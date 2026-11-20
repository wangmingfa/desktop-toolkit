#!/usr/bin/env bash
# =============================================================================
# Niri + DMS (Dux Modular Shell) 一键安装
#   niri  : 滚动平铺 Wayland 合成器（横向无限卷轴式布局）
#   DMS   : Quickshell 桌面外壳（Dux Modular Shell，原 DankMaterialShell）
#           官方推荐搭配 niri（"DMS Team's choice of Wayland compositor"）
# 用法: bash niri-dms.sh [--terminal alacritty|kitty|ghostty] [--force] [--skip-systemd]
# 说明: 走发行版包管理器(镜像友好) + dms setup headless(非交互)，
#       不依赖 curl|sh install.duxlabs.dev，透明可控、便于断点重跑。
# =============================================================================
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"
# ui.sh 提供 dt_confirm 等交互控件(含 TUI 兜底)，收尾时用来问"是否现在重启 GDM"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/ui.sh"

TERMINAL="alacritty"
FORCE=0
NO_SYSTEMD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --terminal) TERMINAL="${2:-alacritty}"; shift 2 ;;
        --force)    FORCE=1; shift ;;
        --skip-systemd) NO_SYSTEMD=1; shift ;;
        *) echo "用法: niri-dms.sh [--terminal alacritty|kitty|ghostty] [--force] [--skip-systemd]" >&2; exit 1 ;;
    esac
done

log() { echo "  [niri-dms] $*"; }
err() { echo "  [niri-dms] 错误: $*" >&2; }

# 收尾横幅用的颜色。沿用 install.sh 的写法；stdout 不是 tty(输出被重定向/管道)时
# 退化为无色，避免 ANSI 转义混进日志。
if [ -t 1 ]; then
    DT_BOLD=$'\033[1m'
    DT_GREEN=$'\033[0;32m'
    DT_YELLOW=$'\033[0;33m'
    DT_CYAN=$'\033[0;36m'
    DT_NC=$'\033[0m'
else
    DT_BOLD=""; DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_NC=""
fi

# dnf 下载参数：COPR 的大包(dms-cli ~83MB)在网络慢时极易失败——dnf 内部按
# "30 秒内少于 1000 B/s" 判死(low-speed)，这个阈值 dnf 不暴露、改不了。
# 能做的是：把总传输时限放宽(timeout=0 不限时)、把每次下载的重试次数调高(retries)，
# 再叠加本脚本的重跑(见 dnf_install_retry)。仍慢就换网/稍后重跑续装。
DT_DNF_OPTS=(--setopt=timeout="${DT_DNF_TIMEOUT:-0}" --setopt=retries="${DT_DNF_RETRIES:-10}")

echo "══════════════════════════════════════════"
echo " 安装 Niri + DMS (Dux Modular Shell)"
echo "══════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 1) 安装包（发行版自适应）
# ---------------------------------------------------------------------------
# 带重试的 dnf 安装：COPR 源(copr-pulp-prod.s3.amazonaws.com)下载大包偶发超时/中断，
# 重跑即可续装（已装好的包自动跳过）。
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
    err "安装仍未成功。可稍后重跑本脚本续装，或手动执行："
    err "  sudo dnf install ${DT_DNF_OPTS[*]} ${pkgs[*]}"
    return 1
}

# ---------------------------------------------------------------------------
# 可续传兜底：COPR 的大包(dms-cli ~83MB)存在 AWS S3(copr-pulp-prod.s3.amazonaws.com)。
# dnf 按"30 秒内少于 1000 B/s"判死且【不能断点续传】，弱网下永远卡在几个百分点。
# 而 `dnf download` 支持续传——重复调用会在已下部分上继续。故改为：
#   循环 dnf download(累积) -> rpm2cpio 全量解包校验 -> 用本地 rpm 安装。
# 进度持久化在 DT_DL_DIR，中断/重跑都能续传。src.rpm 不参与安装，跳过。
# ---------------------------------------------------------------------------
dnf_install_resumable() { # <包名>...
    local -a pkgs=("$@")
    local dir="${DT_DL_DIR:-/tmp/dt-niridms-rpms}"
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
            # rpm2cpio 会解包整个载荷: 文件截断必失败(比 rpm -qp 可靠)
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

# 已有本地 rpm 时直接装(跳过网络)。用于：
#   1) 之前 dnf_install_resumable 已把 rpm 下齐(如 /tmp/dmsdl 累积完成)
#   2) 在别处下载好 rpm 拷进本机
# 只装 DT_DL_DIR 里【完整】的非 src 包；返回 0 表示已用本地路径装完。
dnf_install_from_local() { # <包名>...
    local -a want=("$@")
    local dir="${DT_DL_DIR:-/tmp/dt-niridms-rpms}"
    [ -d "$dir" ] || return 1
    local -a local_rpms=() f missing=()
    for f in "$dir"/*.rpm; do
        [ -f "$f" ] || continue
        case "$f" in *.src.rpm) continue ;; esac
        local_rpms+=("$f")
    done
    [ "${#local_rpms[@]}" -eq 0 ] && return 1
    # 确认用户要装的包都在本地(按包名前缀匹配 NEVRA)
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
    echo "==> 用本地 rpm 安装（${#local_rpms[@]} 个，无需再从 S3 下载）…"
    sudo dnf install -y "${local_rpms[@]}"
}

install_pkgs() {
    if command -v dnf >/dev/null 2>&1; then
        echo "==> 检测到 Fedora/dnf"
        # DMS 在 COPR duxlabs/dms（旧 avengemedia/* 已迁移到 duxlabs）
        # 幂等：已启用时 enable 是 no-op
        sudo dnf copr enable -y duxlabs/dms 2>/dev/null \
            || log "COPR duxlabs/dms 启用未确认(可手动: sudo dnf copr enable duxlabs/dms)，继续"
        # 优先用已有的本地 rpm(续传产物/外部导入), 跳过慢的 S3 下载
        if dnf_install_from_local niri dms quickshell xwayland-satellite \
            xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
            "$TERMINAL" fuzzel mako waybar playerctl; then
            return 0
        fi
        echo "  安装 niri + dms + 配套(需 sudo 密码；COPR 的 dms-cli 约 83MB)…"
        # 常规安装 -> 失败(通常是 COPR 大包下载被判超时)则走可续传的兜底路径
        dnf_install_retry niri dms quickshell xwayland-satellite \
            xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
            "$TERMINAL" fuzzel mako waybar playerctl \
        || dnf_install_resumable niri dms quickshell xwayland-satellite \
            xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
            "$TERMINAL" fuzzel mako waybar playerctl
    elif command -v pacman >/dev/null 2>&1; then
        echo "==> 检测到 Arch/pacman"
        sudo pacman -S --needed --noconfirm niri dux-shell xwayland-satellite \
            xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
            "$TERMINAL" fuzzel matugen cava qt6-multimedia-ffmpeg
    elif command -v apt-get >/dev/null 2>&1; then
        echo "==> 检测到 Debian/Ubuntu(需 PPA)"
        sudo add-apt-repository -y ppa:duxlabs/dux-repo || true
        sudo add-apt-repository -y ppa:duxlabs/dms || true
        sudo apt-get update
        sudo apt-get install -y niri dms quickshell "$TERMINAL"
    elif command -v zypper >/dev/null 2>&1; then
        echo "==> 检测到 openSUSE/zypper"
        sudo zypper --non-interactive in niri dms quickshell "$TERMINAL"
    else
        err "未识别的包管理器。请手动安装 niri + dms(dux-shell)，或用官方一键安装器："
        err "  curl -fsSL https://install.duxlabs.dev | sh"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# 2) dms setup headless：非交互生成 niri+DMS 配置（不覆盖已有，除非 --force）
#    DMS 拒绝以 root 运行，本脚本以普通用户执行，勿加 sudo。
# ---------------------------------------------------------------------------
setup_dms() {
    command -v dms >/dev/null 2>&1 || { err "未找到 dms 命令（包未装成功）"; return 1; }
    local extra="--skip-existing"; [ "$FORCE" = 1 ] && extra="--force"
    echo "==> 生成 niri + DMS 配置（dms setup headless，非交互）…"
    # shellcheck disable=SC2086  # extra 是受控的单个 flag
    if dms setup headless --compositor niri --terminal "$TERMINAL" $extra; then
        log "dms 配置生成完成"
    else
        err "dms setup headless 失败，可手动运行: dms setup"
    fi
}

# ---------------------------------------------------------------------------
# 3) 绑定 dms 到 niri 会话（systemd --user，DMS 只随 niri 启动）
# ---------------------------------------------------------------------------
bind_systemd() {
    [ "$NO_SYSTEMD" = 1 ] && return 0
    echo "==> 绑定 dms 到 niri 会话（systemctl --user add-wants）…"
    systemctl --user add-wants niri.service dms 2>&1 \
        && log "已绑定：DMS 随 niri 启动/停止" \
        || err "绑定失败，可手动: systemctl --user add-wants niri.service dms"
}

# ---------------------------------------------------------------------------
# 4) 去掉默认 waybar 自启（DMS 自带顶栏，避免出现两条栏）
# ---------------------------------------------------------------------------
strip_waybar() {
    local cfg="$HOME/.config/niri/config.kdl"
    [ -f "$cfg" ] || return 0
    if grep -q 'spawn-at-startup "waybar"' "$cfg" 2>/dev/null; then
        cp -a "$cfg" "$cfg.bak-niridms-$(date +%Y%m%d-%H%M%S)"
        sed -i '/spawn-at-startup "waybar"/d' "$cfg"
        log "已移除默认 waybar 自启（备份在 $cfg.bak-niridms-*）；DMS 自带顶栏"
    fi
}

# ---------------------------------------------------------------------------
# 5) 确保登录界面有 Niri 会话项
#
#    三个硬约束(读 GDM 51 源码 libgdm/gdm-sessions.c 的 key_file_is_relevant 得出):
#    a) 必须写在【系统级】目录。GDM greeter 以 root/gdm 运行, 只扫
#         <system_data_dir>/wayland-sessions、<system_data_dir>/xsessions
#       用户级 ~/.local/share/wayland-sessions 对 greeter 无效(不影响已登录会话)。
#    b) 【最关键、且 niri 上游包缺失】必须有 X-GDM-CanRunHeadless=true。
#       GDM 的过滤条件是:
#           only_headless_allowed = (get_systemd_seat() == NULL)
#           if (no_display || hidden || tryexec_failed ||
#               (only_headless_allowed && !can_run_headless))  → 丢弃该会话
#       gdm.service 跑在 system.slice, 没有 logind session, 所以 get_systemd_seat()
#       恒为 NULL → only_headless_allowed 恒为 TRUE → **只放行带该键的会话**。
#       Fedora 的 gnome.desktop / gnome-classic.desktop 都带这个键, niri 上游的
#       resources/niri.desktop 不带, 于是 niri 被静默丢弃; 且丢弃后若只剩一个会话,
#       登录界面连左下角的会话齿轮都不画出来, 现象就是"完全看不到切换项"。
#    c) Exec / TryExec 用绝对路径更稳(g_find_program_in_path 对绝对路径做
#       access(X_OK), 裸命令名依赖 PATH)。
#
#    注意: 不要照抄 GNOME 的 X-GDM-SessionRegisters=true——那是"会话程序自己向
#    DisplayManager 注册"的声明。strings 验证 niri 二进制 0 处引用 DisplayManager,
#    照抄反而让 GDM 等一个永远不会来的注册。
# ---------------------------------------------------------------------------
ensure_session_file() {
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
        log "无 $sys_dir(非 GDM 显示管理器), 跳过会话项修正"
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
        err "写 $sys_file 失败(需要 sudo 密码)。请手动写入同样内容后重跑, "
        err "或执行: sudo bash $0。之后必须 sudo systemctl restart gdm 才生效。"
        return 0
    fi
    log "已修正系统级会话项 $sys_file(绝对路径 + X-GDM-CanRunHeadless=true)"
}

# 安装是前置条件：失败则不生成配置，明确提示续装，避免看似"完成"实则装了一半
if ! install_pkgs; then
    echo
    echo "============================================================"
    echo "❌ 包安装未成功，已中止（未生成 DMS 配置）。"
    echo "  常见原因：COPR 大包(dms-cli ~83MB)下载太慢被判超时。"
    echo "  请重跑本脚本续装（已装好的包会自动跳过，只重试缺的部分）："
    echo "  bash modules/wm/niri-dms.sh"
    echo "  想给更多重试次数: DT_DNF_RETRIES=20 bash modules/wm/niri-dms.sh"
    echo "============================================================"
    exit 1
fi
setup_dms
bind_systemd
strip_waybar
ensure_session_file

echo
echo -e "${DT_GREEN}${DT_BOLD}════════════════════════════════════════════════════════════════${DT_NC}"
echo -e "${DT_GREEN}${DT_BOLD}✅ 完成！Niri + DMS 已安装。${DT_NC}"
echo -e "${DT_GREEN}${DT_BOLD}════════════════════════════════════════════════════════════════${DT_NC}"
echo
echo -e "${DT_YELLOW}${DT_BOLD}★ 下一步（必做）：重启 GDM，登录界面才会出现 Niri${DT_NC}"
echo -e "${DT_YELLOW}  GDM 只在【启动时】扫一次会话文件，单纯“注销”不会重新扫描，所以必须重启它。${DT_NC}"
echo -e "${DT_YELLOW}  手动执行:${DT_NC}"
echo -e "      ${DT_CYAN}${DT_BOLD}sudo systemctl restart gdm${DT_NC}"
echo -e "  重启后在登录界面【左下角的齿轮 ⚙️】里选 Niri。"
echo -e "  也可以不进登录界面，在 TTY 直接跑: ${DT_CYAN}${DT_BOLD}niri-session${DT_NC}"
echo
echo "  1) 快捷键: Super+T 开终端($TERMINAL) · Super+D 应用启动器 · Super+Shift+E 退出"
echo "  2) DMS 顶栏/设置: 按 Super 打开面板进一步微调"
echo "  3) 若齿轮里仍无 Niri: 检查 /usr/share/wayland-sessions/niri.desktop 是否含"
echo "     X-GDM-CanRunHeadless=true (缺了会被 GDM 静默过滤), 再看 Exec 是否绝对路径"
echo "  4) 双栏(waybar+DMS)残留: 重跑本脚本会自动清理，或删 config.kdl 里 spawn-at-startup \"waybar\""
echo
# 交互确认后代跑重启：用户回答"是"就直接重启 GDM，省得自己再敲一遍。
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
