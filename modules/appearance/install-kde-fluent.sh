#!/usr/bin/env bash
# =============================================================================
# KDE Plasma Windows 11 (Fluent 风格) 安装器 —— Fluent-kde
# 在 KDE Plasma 的宿主机终端运行： bash install-kde-fluent.sh
# 非 macOS 风格：Windows 11 Fluent 圆角/Mica 质感（aurorae/Kvantum/plasma/color-schemes）。
# 注意：与 macOS 两套主题会互相覆盖，二选一使用。
# =============================================================================
set -euo pipefail

# 公共库：提供 dt_clone（国内镜像回退）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

REPO="vinceliuice/Fluent-kde"
BRANCH="main"   # Fluent-kde 默认分支是 main（与 WhiteSur-kde 的 master 不同）
SRC_DIR="${SRC_DIR:-$HOME/.local/src/desktop-toolkit-kde}"
DEST="$SRC_DIR/Fluent-kde"

echo "==> [1/2] 克隆 $REPO"
mkdir -p "$SRC_DIR"
if [ -d "$DEST/.git" ]; then
    echo "    已存在，跳过克隆"
else
    dt_clone "https://github.com/$REPO.git" "$DEST" "$BRANCH"
fi

echo "==> [2/2] 运行安装器（安装全部颜色变体 + 深/浅色）"
cd "$DEST"
if [ -x ./install.sh ]; then
    ./install.sh
else
    echo "错误: 未找到 install.sh" >&2
    exit 1
fi

echo
echo "============================================================"
echo "完成！已安装 Windows 11 (Fluent) 到 KDE Plasma。"
echo "在 系统设置 -> 外观 里选择 Fluent / Fluent-dark 即可应用。"
echo "Kvantum 若未生效：系统设置 -> 颜色 -> Kvantum -> 选 Fluent。"
echo "============================================================"
