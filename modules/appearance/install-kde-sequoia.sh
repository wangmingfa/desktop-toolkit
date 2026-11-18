#!/usr/bin/env bash
# =============================================================================
# KDE Plasma macOS 16 (经典 Sequoia 风格) 安装器 —— WhiteSur-kde
# 在 KDE Plasma 的宿主机终端运行： bash install-kde-sequoia.sh
# 与 macOS 26 (MacTahoe Liquid KDE) 不同，这套是经典 Big Sur/Sequoia 外观。
# 注意：两套主题会互相覆盖，二选一使用。
# =============================================================================
set -euo pipefail

REPO="vinceliuice/WhiteSur-kde"
BRANCH="master"
SRC_DIR="${SRC_DIR:-$HOME/.local/src/desktop-toolkit-kde}"
DEST="$SRC_DIR/WhiteSur-kde"

echo "==> [1/2] 克隆 $REPO"
mkdir -p "$SRC_DIR"
if [ -d "$DEST/.git" ]; then
    echo "    已存在，跳过克隆"
else
    git clone --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$DEST"
fi

echo "==> [2/2] 运行安装器（安装全部颜色变体 + 圆角模糊窗口）"
cd "$DEST"
if [ -x ./install.sh ]; then
    ./install.sh
else
    echo "错误: 未找到 install.sh" >&2
    exit 1
fi

echo
echo "============================================================"
echo "完成！已安装 macOS 16 经典 (WhiteSur) 到 KDE Plasma。"
echo "在 系统设置 -> 外观 里选择 WhiteSur / WhiteSur-dark 即可应用。"
echo "Kvantum 若未生效：系统设置 -> 颜色 -> Kvantum -> 选 WhiteSur。"
echo "============================================================"
