#!/usr/bin/env bash
# =============================================================================
# 安装纯白色 CachyOS 顶部栏 Logo 到 macOS Tahoe 主题图标目录
# 主题需先安装（见 install-theme.sh）。本脚本可重复运行。
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSETS="$DT_ROOT/assets"

for theme in MacTahoeLiquidKde-Icons MacTahoeLiquidKde-Icons-dark; do
    dest="$HOME/.local/share/icons/$theme/places/scalable"
    mkdir -p "$dest"
    cp -f "$ASSETS/cachyos-logo-symbolic.svg" "$dest/cachyos-logo-symbolic.svg"
    echo "已安装: $dest/cachyos-logo-symbolic.svg"
done

# 应用为顶部菜单图标
SRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
[ -f "$SRC" ] && cp -a "$SRC" "${SRC}.bak-dt-logo"
bash "$DT_ROOT/modules/appearance/adjust-window.sh" logo cachy

echo "完成。若图标未刷新，注销重登一次即可。"
