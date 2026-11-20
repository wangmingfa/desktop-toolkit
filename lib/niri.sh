# =============================================================================
# Niri 系方案共享能力
#   供 modules/wm/niri-*.sh 复用，避免每个方案各自复制一份 dnf 弱网兜底、
#   会话文件修正与收尾横幅。
#
# 依赖（调用方必须已经做了）:
#   1) source lib/common.sh   —— 提供 dt_detect_gui
#   2) source lib/ui.sh       —— 提供 dt_confirm；source 时会设置全局 $GUI
#   3) 定义 log()/err()       —— 本文件的提示走这两个函数
# =============================================================================

# ---------------------------------------------------------------------------
# dnf 下载参数
#   COPR 的大包(dms-cli ~83MB)存 AWS S3，弱网时极易失败——dnf 内部按
#   "30 秒内少于 1000 B/s"判死(low-speed)，这个阈值不暴露、改不了。
#   能做的是：总传输时限放宽(timeout=0)、每次下载重试调高(retries)，
#   再叠加脚本级重跑(见 dnf_install_retry)。仍慢就换网或稍后重跑续装。
#   注意 dnf5 只认 timeout/retries，不认 dnf4 的 transfer_timeout/retrycount。
# ---------------------------------------------------------------------------
DT_DNF_OPTS=(--setopt=timeout="${DT_DNF_TIMEOUT:-0}" --setopt=retries="${DT_DNF_RETRIES:-10}")

# ---------------------------------------------------------------------------
# 收尾横幅用的颜色。stdout 不是 tty(重定向/管道)时退化为空串，
# 避免 ANSI 转义混进日志。
# ---------------------------------------------------------------------------
niri_color_init() {
    if [ -t 1 ]; then
        DT_BOLD=$'\033[1m'
        DT_GREEN=$'\033[0;32m'
        DT_YELLOW=$'\033[0;33m'
        DT_CYAN=$'\033[0;36m'
        DT_NC=$'\033[0m'
    else
        DT_BOLD=""; DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_NC=""
    fi
}

# ---------------------------------------------------------------------------
# 带重试的 dnf 安装：COPR 源下载大包偶发超时/中断，重跑即可续装
# (已装好的包自动跳过)。最多 3 次。
# ---------------------------------------------------------------------------
dnf_install_retry() { # <包名>...
    local attempt
    local -a pkgs=("$@")
    for (( attempt=1; attempt<=3; attempt++ )); do
        [ "$attempt" -gt 1 ] && log "第 ${attempt} 次重试安装（上次下载失败/中断，已装好的会自动跳过）…"
        if sudo dnf install -y "${DT_DNF_OPTS[@]}" "${pkgs[@]}"; then
            return 0
        fi
        err "第 ${attempt} 次安装失败"
    done
    err "安装仍未成功。可稍后重跑续装，或手动执行："
    err "  sudo dnf install ${DT_DNF_OPTS[*]} ${pkgs[*]}"
    return 1
}

# ---------------------------------------------------------------------------
# 可续传兜底：COPR 的大包存在 AWS S3，dnf install【不能断点续传】，弱网下永远卡在
# 几个百分点；而 `dnf download` 支持续传——重复调用会在已下部分上继续。故改为：
#   循环 dnf download(累积) -> rpm2cpio 全量解包校验 -> 用本地 rpm 安装。
# 进度持久化在 DT_DL_DIR，中断/重跑都能续传。src.rpm 不参与安装，跳过。
# 完整性判据必须用 rpm2cpio(解包全量载荷，截断必失败)：rpm -qp 不可靠
# (截断文件仍带完整 rpm 头)，COPR 包未签名 rpm -K 也无输出。
# ---------------------------------------------------------------------------
dnf_install_resumable() { # <包名>...
    local -a pkgs=("$@")
    local dir="${DT_DL_DIR:-/tmp/dt-niri-rpms}"
    local dnf_cmd=dnf
    command -v dnf5 >/dev/null 2>&1 && dnf_cmd=dnf5
    echo
    echo "  ⚠ COPR 大包下载失败，改用可续传下载 + 本地安装"
    echo "    （进度存于 $dir，Ctrl+C 中断后重跑本脚本会继续，不会从头下）"
    mkdir -p "$dir"
    local attempt=0 total=0 bad=0 sz prev=-1 stuck=0 f
    while [ "$attempt" -lt 50 ]; do
        attempt=$((attempt+1))
        # 注意: download 不以 root 跑(实测可行, 且避免 root 文件权限)
        "$dnf_cmd" download --resolve --destdir="$dir" \
            "${DT_DNF_OPTS[@]}" "${pkgs[@]}" >/dev/null 2>&1 || true
        total=0; bad=0
        for f in "$dir"/*.rpm; do
            [ -f "$f" ] || continue
            case "$f" in *.src.rpm) continue ;; esac
            total=$((total+1))
            rpm2cpio "$f" >/dev/null 2>&1 || bad=$((bad+1))
        done
        sz=$(du -sm "$dir" 2>/dev/null | cut -f1)
        log "第 ${attempt} 轮：${total} 个 rpm 中 ${bad} 个未完成（已下载 ${sz}MB）"
        [ "$bad" -eq 0 ] && break
        [ "$sz" = "$prev" ] && stuck=$((stuck+1)) || stuck=0
        prev=$sz
        # 连续两轮零进展 = 网络彻底不通, 别空转
        [ "$stuck" -ge 2 ] && break
    done
    local -a local_rpms=()
    for f in "$dir"/*.rpm; do
        [ -f "$f" ] || continue
        case "$f" in *.src.rpm) continue ;; esac
        local_rpms+=("$f")
    done
    [ "${#local_rpms[@]}" -eq 0 ] && { err "未下载到任何可用 rpm"; return 1; }
    if [ "$bad" -ne 0 ]; then
        err "仍有 ${bad} 个 rpm 未完成下载。请重跑本脚本续传（进度已保留），"
        err "或给机器挂代理后重跑: HTTPS_PROXY=http://127.0.0.1:7890 bash $0"
        return 1
    fi
    echo "==> 从本地 rpm 安装（${#local_rpms[@]} 个；缺的基础包 dnf 会从正常源补）…"
    sudo dnf install -y "${local_rpms[@]}"
}

# ---------------------------------------------------------------------------
# 已有本地 rpm 时直接装(跳过网络)。用于：
#   1) 之前 dnf_install_resumable 已把 rpm 下齐
#   2) 在别处下载好 rpm 拷进本机
# 只装 DT_DL_DIR 里【完整】的非 src 包；返回 0 表示已用本地路径装完。
# ---------------------------------------------------------------------------
dnf_install_from_local() { # <包名>...
    local -a want=("$@")
    local dir="${DT_DL_DIR:-/tmp/dt-niri-rpms}"
    [ -d "$dir" ] || return 1
    local -a local_rpms=() f missing=()
    for f in "$dir"/*.rpm; do
        [ -f "$f" ] || continue
        case "$f" in *.src.rpm) continue ;; esac
        local_rpms+=("$f")
    done
    [ "${#local_rpms[@]}" -eq 0 ] && return 1
    # 确认用户要装的包都在本地(按包名精确匹配 %{NAME})
    for w in "${want[@]}"; do
        local found=0
        for f in "${local_rpms[@]}"; do
            if rpm -qp --qf '%{NAME}\n' "$f" 2>/dev/null | grep -qx "$w"; then
                found=1; break
            fi
        done
        [ "$found" -eq 1 ] || missing+=("$w")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log "本地缺少: ${missing[*]}，需要联网下载"
        return 1
    fi
    echo "==> 用本地 rpm 安装（${#local_rpms[@]} 个，无需再下载）…"
    sudo dnf install -y "${local_rpms[@]}"
}

# ---------------------------------------------------------------------------
# 确保登录界面有 Niri 会话项
#
# 三个硬约束（读 GDM 51 源码 libgdm/gdm-sessions.c 的 key_file_is_relevant 得出）:
#   a) 必须写在【系统级】目录。GDM 只扫 <system_data_dir>/wayland-sessions 与
#      <system_data_dir>/xsessions（collect_sessions 用 g_get_system_data_dirs()
#      拼，不含用户目录）。用户级 ~/.local/share/wayland-sessions 对 greeter 无效。
#   b) 【最关键，且 niri 上游包缺失】必须有 X-GDM-CanRunHeadless=true。
#      GDM 的过滤条件是:
#          only_headless_allowed = (get_systemd_seat() == NULL)
#          if (no_display || hidden || tryexec_failed ||
#              (only_headless_allowed && !can_run_headless))  → 丢弃该会话
#      gdm.service 跑在 system.slice、没有 logind session，所以
#      get_systemd_seat() 恒为 NULL → only_headless_allowed 恒为 TRUE →
#      只放行带该键的会话。Fedora 的 gnome*.desktop 都带，niri 上游的
#      resources/niri.desktop 不带，于是被静默丢弃；丢弃后若只剩一个会话，
#      登录界面连左下角的齿轮都不画出来。
#   c) Exec/TryExec 用绝对路径更稳（g_find_program_in_path 对绝对路径只做
#      access(X_OK)，裸命令名则依赖 PATH）。
#
# 注意: 不要照抄 GNOME 的 X-GDM-SessionRegisters=true——那是"会话程序自己向
# DisplayManager 注册"的声明。判定 strings /usr/bin/<合成器> | grep -c
# DisplayManager，niri 结果为 0（从不注册），照抄会让 GDM 空等；实际登录时
# GDM 走的是 gdm-wayland-session --handle-registration 代为注册。
# ---------------------------------------------------------------------------
niri_ensure_gdm_session() {
    local sys_dir=/usr/share/wayland-sessions
    local sys_file="$sys_dir/niri.desktop"
    local user_file="$HOME/.local/share/wayland-sessions/niri.desktop"

    # 清掉历史上误建的用户级文件: 对 greeter 无效, 还会让旧逻辑误判"已处理"
    rm -f "$user_file"

    # 幂等: 已存在且写法正确则不动
    if [ -f "$sys_file" ] \
        && grep -q '^Exec=/usr/bin/niri-session' "$sys_file" 2>/dev/null \
        && grep -q '^TryExec=/usr/bin/niri-session' "$sys_file" 2>/dev/null \
        && grep -q '^X-GDM-CanRunHeadless=true' "$sys_file" 2>/dev/null; then
        return 0
    fi
    if [ ! -d "$sys_dir" ]; then
        log "无 $sys_dir(非 GDM 显示管理器)，跳过会话项修正"
        return 0
    fi

    if ! sudo tee "$sys_file" >/dev/null <<'EOF'
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor
Exec=/usr/bin/niri-session
TryExec=/usr/bin/niri-session
Type=Application
DesktopNames=niri
X-GDM-CanRunHeadless=true
EOF
    then
        err "写 $sys_file 失败(需要 sudo 密码)。请手动写入同样内容后重跑，"
        err "之后必须 sudo systemctl restart gdm 才生效。"
        return 0
    fi
    log "已修正系统级会话项 $sys_file(绝对路径 + X-GDM-CanRunHeadless=true)"
}

# ---------------------------------------------------------------------------
# 收尾横幅: 绿色完成横幅 + 黄色加粗的"重启 GDM"提示 + 交互代跑
#   niri_finish <完成标题> [额外提示行...]
# GDM 只在【启动时】扫一次会话文件，单纯"注销"不会重新扫描，必须 restart。
# ---------------------------------------------------------------------------
niri_finish_banner() { # 完成标题 [额外提示行...]
    local title="$1"; shift || true
    echo
    echo -e "${DT_GREEN}${DT_BOLD}════════════════════════════════════════════════════════════════${DT_NC}"
    echo -e "${DT_GREEN}${DT_BOLD}✅ 完成！${title}${DT_NC}"
    echo -e "${DT_GREEN}${DT_BOLD}════════════════════════════════════════════════════════════════${DT_NC}"
    echo
    echo -e "${DT_YELLOW}${DT_BOLD}★ 下一步（必做）：重启 GDM，登录界面才会出现 Niri${DT_NC}"
    echo -e "${DT_YELLOW}  GDM 只在【启动时】扫一次会话文件，单纯“注销”不会重新扫描，所以必须重启它。${DT_NC}"
    echo -e "${DT_YELLOW}  手动执行:${DT_NC}"
    echo -e "      ${DT_CYAN}${DT_BOLD}sudo systemctl restart gdm${DT_NC}"
    echo -e "  重启后在登录界面【左下角的齿轮 ⚙️】里选 Niri。"
    echo -e "  也可以不进登录界面，在 TTY 直接跑: ${DT_CYAN}${DT_BOLD}niri-session${DT_NC}"
    if [ "$#" -gt 0 ]; then
        echo
        for line in "$@"; do
            echo "  $line"
        done
    fi
    echo
    # 交互确认后代跑重启，省得用户自己再敲一遍。
    # 只在 stdin 是终端时问，避免非交互环境(管道/CI)卡在 read。
    if [ -t 0 ]; then
        case "${XDG_SESSION_TYPE:-}" in
            wayland|x11) echo -e "  ${DT_YELLOW}提示: 你当前在桌面会话里，重启 GDM 会立即注销本桌面(这是预期行为)。${DT_NC}" ;;
        esac
        echo
        if dt_confirm "要现在重启 GDM 吗？（会立即注销当前桌面，之后在登录界面选 Niri）"; then
            echo -e "  ${DT_CYAN}==> 重启 GDM…（本终端会被关闭）${DT_NC}"
            sudo systemctl restart gdm \
                || echo -e "  ${DT_YELLOW}重启失败，请手动执行: sudo systemctl restart gdm${DT_NC}"
        else
            echo -e "  ${DT_CYAN}已跳过，稍后自己执行上面的命令即可。${DT_NC}"
        fi
    fi
}