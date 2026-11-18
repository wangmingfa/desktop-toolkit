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

REPO_DIR="$HOME/macos-tahoe-liquid-kde"

echo "==> [1/3] 安装缺少的构建依赖 (cmake / extra-cmake-modules)"
sudo pacman -S --needed cmake extra-cmake-modules

echo "==> [2/3] 获取主题仓库 (宿主机已开 FlClash TUN，克隆应该很快)"
if git -C "$REPO_DIR" rev-parse HEAD >/dev/null 2>&1; then
  echo "    仓库已存在且完好，跳过克隆"
else
  echo "    清理残留并重新克隆 (强制 HTTP/1.1，避免 HTTP/2 流被代理重置)"
  rm -rf "$REPO_DIR"
  ok=0
  for i in 1 2 3; do
    echo "    ---- 克隆尝试 $i/3 ----"
    if git -c http.version=HTTP/1.1 clone --depth 1 \
         https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git \
         "$REPO_DIR"; then
      ok=1
      break
    fi
    rm -rf "$REPO_DIR"
  done
  if [ "$ok" -ne 1 ]; then
    echo "克隆连续失败 3 次。请检查 FlClash 节点后重跑本脚本。" >&2
    exit 1
  fi
fi
cd "$REPO_DIR"

echo "==> [3/3] 应用主题：全套 / 自动明暗 / 排除 SDDM 与 Plymouth"
sudo ./src/scripts/installer_backend.py install \
  --auto --no-sddm --no-plymouth

echo
echo "============================================================"
echo "完成。KWin / Plasma 会自动重启生效。"
echo
echo "手动切换明暗： ~/.local/bin/mac-tahoe-theme-switch  (带 --light / --dark / --auto)"
echo "重新配置组件： cd ~/macos-tahoe-liquid-kde && ./installer  (中文图形界面)"
echo "完全撤销主题： cd ~/macos-tahoe-liquid-kde && sudo ./src/scripts/installer_backend.py uninstall"
echo "============================================================"
