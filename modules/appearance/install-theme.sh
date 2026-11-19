#!/usr/bin/env bash
# ============================================================
# 在宿主机 CachyOS 的终端中运行：  bash ~/setup-macos-tahoe-host.sh
#
# 效果：把 KDE Plasma 6 打造成 macOS Tahoe（液态玻璃）风格
#   - 全套组件：顶部菜单栏 + 底部 Dock + 控制中心 + 红绿灯窗口按钮
#               + 图标 + 光标 + 壁纸 + SF 字体 + GTK/Qt 主题 + 圆角/玻璃特效
#   - 自动明暗：06:00 浅色 / 18:00 深色（systemd 用户定时器）
#   - 不含登录界面(SDDM)与开机动画(Plymouth)，不改 GRUB/initramfs
# 撤销：见脚本末尾提示
# ============================================================
set -euo pipefail

# 公共库：提供 dt_clone（国内镜像回退）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

REPO_DIR="$HOME/macos-tahoe-liquid-kde"

echo "==> [1/3] 安装缺少的构建依赖 (cmake / extra-cmake-modules)"
sudo pacman -S --needed cmake extra-cmake-modules

echo "==> [2/3] 获取主题仓库 (宿主机已开 FlClash TUN，克隆应该很快)"
if git -C "$REPO_DIR" rev-parse HEAD >/dev/null 2>&1; then
  echo "    仓库已存在且完好，跳过克隆"
else
  echo "    清理残留并重新克隆（自动国内镜像回退：直连 -> ghproxy -> gitclone）"
  dt_clone "https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git" "$REPO_DIR" || {
    echo "克隆失败。可设 DT_MIRROR=ghproxy 或换 GH_PROXY 后重跑；已开代理的可检查节点。" >&2
    exit 1
  }
fi
cd "$REPO_DIR"

echo "==> [3/3] 应用主题：全套 / 自动明暗 / 排除 SDDM 与 Plymouth"
sudo ./src/scripts/installer_backend.py install \
  --auto --no-sddm --no-plymouth

# GTK 4.14 兼容修复（@media/@import 与 color-mix），否则 GTK4 窗口会全透明
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fix-gtk-theme.sh" fix || true

echo
echo "============================================================"
echo "完成。KWin / Plasma 会自动重启生效。"
echo
echo "手动切换明暗： ~/.local/bin/mac-tahoe-theme-switch  (带 --light / --dark / --auto)"
echo "重新配置组件： cd ~/macos-tahoe-liquid-kde && ./installer  (中文图形界面)"
echo "完全撤销主题： cd ~/macos-tahoe-liquid-kde && sudo ./src/scripts/installer_backend.py uninstall"
echo "============================================================"
