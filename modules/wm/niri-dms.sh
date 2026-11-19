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

install_pkgs() {
    if command -v dnf >/dev/null 2>&1; then
        echo "==> 检测到 Fedora/dnf"
        # DMS 在 COPR duxlabs/dms（旧 avengemedia/* 已迁移到 duxlabs）
        # 幂等：已启用时 enable 是 no-op
        sudo dnf copr enable -y duxlabs/dms 2>/dev/null \
            || log "COPR duxlabs/dms 启用未确认(可手动: sudo dnf copr enable duxlabs/dms)，继续"
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
# 5) 确保登录界面有 Niri 会话项（系统包未提供时建用户级）
# ---------------------------------------------------------------------------
ensure_session_file() {
    [ -f /usr/share/wayland-sessions/niri.desktop ] && return 0
    [ -f "$HOME/.local/share/wayland-sessions/niri.desktop" ] && return 0
    mkdir -p "$HOME/.local/share/wayland-sessions"
    cat > "$HOME/.local/share/wayland-sessions/niri.desktop" <<'EOF'
[Desktop Entry]
Name=Niri
Comment=Scrollable tiling Wayland compositor
Exec=niri-session
Type=Application
DesktopName=niri
EOF
    log "已创建用户级 Niri 登录项：~/.local/share/wayland-sessions/niri.desktop"
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
echo "============================================================"
echo "✅ 完成！Niri + DMS 已安装。"
echo "  1) 注销，登录界面选 Niri 会话；或用 TTY 运行: niri-session"
echo "  2) 快捷键: Super+T 开终端($TERMINAL) · Super+D 应用启动器 · Super+Shift+E 退出"
echo "  3) DMS 顶栏/设置: 按 Super 打开面板进一步微调"
echo "  4) 若 Niri 登录项未出现: 检查 /usr/share/wayland-sessions/niri.desktop"
echo "  5) 双栏(waybar+DMS)残留: 重跑本脚本会自动清理，或删 config.kdl 里 spawn-at-startup \"waybar\""
echo "============================================================"
