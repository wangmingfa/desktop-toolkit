#!/usr/bin/env bash
# =============================================================================
# GNOME macOS 美化安装器
# 用法:
#   ./install.sh macos26   安装 macOS 26 (Tahoe 液态玻璃)
#   ./install.sh macos15   安装 macOS 15 (经典 Sequoia 风格)
#   ./install.sh           不带参数则显示用法
# 在 GNOME 桌面的终端中运行；需已装 git。
# =============================================================================
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-gnome.sh"

VERSION="${1:-}"

case "$VERSION" in
    macos26|macos15) ;;
    *)
        cat <<'EOF'
用法: ./install.sh <macos26|macos15>

  macos26  安装 macOS 26 (Tahoe 液态玻璃)  -> MacTahoe-gtk-theme
  macos15  安装 macOS 15 (经典 Sequoia 风格) -> WhiteSur-gtk-theme

示例:
  ./install.sh macos26
EOF
        exit 1 ;;
esac

echo "════════════════════════════════════════════"
echo " 安装: $(gn_version_label "$VERSION")  (GNOME)"
echo "════════════════════════════════════════════"

if ! gn_is_gnome; then
    echo "警告: 当前未检测到 GNOME 会话。请确认在 GNOME 桌面的终端中运行。"
    echo "      (若已安装 gnome-shell 只是桌面未用，可忽略)"
fi

read -r GTK_REPO GTK_BRANCH GTK_THEME ICON_REPO ICON_BRANCH ICON_THEME CURSOR_REPO < <(gn_version_info "$VERSION")

echo "==> [1/5] 安装 GTK 主题 ($GTK_REPO)"
GTK_DIR=$(gn_clone "$GTK_REPO" "$GTK_BRANCH")
# 缺 sassc 时 WhiteSur 会走 prepare_deps 的网络探测(连 iana.org),
# 本网络下探测失败直接退出；先装好 sassc 可完全跳过探测。
gn_ensure_deps || true
gn_install_gtk "$GTK_DIR" -l

echo "==> [2/5] 安装图标主题 ($ICON_REPO)"
ICON_DIR=$(gn_clone "$ICON_REPO" "$ICON_BRANCH")
gn_install_icons "$ICON_DIR"

echo "==> [3/5] 安装光标主题"
gn_install_cursors "$ICON_DIR" "$CURSOR_REPO" || echo "  (光标主题可选，可稍后手动安装)"

echo "==> [4/5] 应用主题设置 (gsettings)"
gn_apply "$VERSION"

echo "==> [5/5] 安装 GNOME 扩展 (user-themes / dash-to-dock / blur-my-shell)"
gn_install_extensions "$VERSION"

echo
echo "============================================================"
echo "完成！已应用 $(gn_version_label "$VERSION") 风格。"
echo "若 Shell/顶栏未变化："
echo "  1) 安装并启用 user-themes 扩展（GNOME Extensions 商店搜 'User Themes'）"
echo "  2) 在 设置->外观 里把 Shell 主题选为 $GTK_THEME"
echo "  3) 注销重登一次"
echo "手动重跑: $0 $VERSION"
echo "============================================================"
