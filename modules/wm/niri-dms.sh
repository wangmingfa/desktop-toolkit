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

echo "══════════════════════════════════════════"
echo " 安装 Niri + DMS (Dux Modular Shell)"
echo "══════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 1) 安装包（发行版自适应）
# ---------------------------------------------------------------------------
install_pkgs() {
    if command -v dnf >/dev/null 2>&1; then
        echo "==> 检测到 Fedora/dnf"
        # DMS 在 COPR duxlabs/dms（旧 avengemedia/* 已迁移到 duxlabs）
        # 幂等：已启用时 enable 是 no-op
        sudo dnf copr enable -y duxlabs/dms 2>/dev/null \
            || log "COPR duxlabs/dms 启用未确认(可手动: sudo dnf copr enable duxlabs/dms)，继续"
        echo "  安装 niri + dms + 配套(需 sudo 密码)…"
        sudo dnf install -y niri dms quickshell xwayland-satellite \
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

install_pkgs
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
