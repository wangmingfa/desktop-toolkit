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
# niri.sh 提供 dnf 弱网兜底 / 会话文件修正 / 收尾横幅(Niri + Noctalia 两个方案共用)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/niri.sh"
# 保持本方案历史的下载目录名，续传进度不丢
export DT_DL_DIR="${DT_DL_DIR:-/tmp/dt-niridms-rpms}"

TERMINAL="alacritty"
FORCE=0
NO_SYSTEMD=0
UNINSTALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --terminal) TERMINAL="${2:-alacritty}"; shift 2 ;;
        --force)    FORCE=1; shift ;;
        --skip-systemd) NO_SYSTEMD=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        *) echo "用法: niri-dms.sh [--terminal alacritty|kitty|ghostty] [--force] [--skip-systemd] [--uninstall]" >&2; exit 1 ;;
    esac
done

log() { echo "  [niri-dms] $*"; }
err() { echo "  [niri-dms] 错误: $*" >&2; }

# ---------------------------------------------------------------------------
# 卸载: 移除 DMS 配置与服务, 保留 niri 本体与用户数据
#   在主流程 install_pkgs 之前调用并 exit, 避免卸载时又去装包。
# ---------------------------------------------------------------------------
uninstall_dms() {
    local cfg="$HOME/.config/niri/config.kdl"
    echo "==> 卸载 Niri + DMS 配置…"

    # 1) 停用 systemd 用户服务(niri-dms.sh 的 bind_systemd 用 add-wants 绑定)
    systemctl --user disable dms 2>/dev/null && log "已停用 dms 用户服务" || true
    systemctl --user daemon-reload 2>/dev/null || true

    # 2) 移除 config.kdl 里的 dms include 行(备份后清理)
    if [ -f "$cfg" ]; then
        cp -a "$cfg" "$cfg.bak-uninstall-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        sed -i -E '/^[[:space:]]*include[[:space:]]+optional=true[[:space:]]+"dms\//d' "$cfg"
        log "已从 $cfg 移除 dms include 行（备份为 $cfg.bak-uninstall-*）"
    fi

    # 3) 删除 DMS 生成的配置目录
    if [ -d "$HOME/.config/niri/dms" ]; then
        log "已删除 $HOME/.config/niri/dms"
        rm -rf "$HOME/.config/niri/dms"
    fi

    # 4) 卸载包(保留 niri 本体: 它可继续给 Noctalia 等方案当宿主)
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf remove -y dms quickshell 2>/dev/null \
            && log "已卸载 dms/quickshell 包" \
            || err "卸载 dms 包失败, 可手动: sudo dnf remove dms"
    else
        log "未检测到 dnf, 跳过 dms 包卸载"
    fi

    echo
    echo "  DMS 配置已移除。niri 本体保留(登录界面仍可选 Niri 会话)。"
    echo "  想连 niri 一起移除: sudo dnf remove niri"
}

niri_color_init

echo "══════════════════════════════════════════"
echo " 安装 Niri + DMS (Dux Modular Shell)"
echo "══════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 1) 安装包（发行版自适应）
#    dnf 弱网兜底(重试/可续传下载/本地 rpm 复用)见 lib/niri.sh
# ---------------------------------------------------------------------------
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
#    会话文件的三个硬约束(系统级目录 / X-GDM-CanRunHeadless=true / Exec 绝对路径)
#    已抽到 lib/niri.sh 的 niri_ensure_dm_session，此处不再重复。

# --uninstall 在任何安装动作之前处理并退出, 避免"卸载时又去装包"
if [ "$UNINSTALL" = 1 ]; then
    uninstall_dms
    exit 0
fi

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
niri_ensure_dm_session

# 收尾横幅 + 交互代跑"重启 GDM"见 lib/niri.sh 的 niri_finish_banner
niri_finish_banner "Niri + DMS 已安装。" \
    "1) 快捷键: Super+T 开终端($TERMINAL) · Super+D 应用启动器 · Super+Shift+E 退出" \
    "2) DMS 顶栏/设置: 按 Super 打开面板进一步微调" \
    "3) 若登录界面仍无 Niri: 检查 /usr/share/wayland-sessions/niri.desktop 是否含 X-GDM-CanRunHeadless=true" \
    "4) 双栏(waybar+DMS)残留: 重跑本脚本会自动清理，或删 config.kdl 里 spawn-at-startup \"waybar\""
