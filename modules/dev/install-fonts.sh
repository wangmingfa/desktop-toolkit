#!/usr/bin/env bash
# =============================================================================
# 开发/终端字体安装（Nerd Fonts + 中文字体）
# -----------------------------------------------------------------------------
# 终端(alacritty)与 DMS 顶栏常缺等宽/图标字体(Nerd Fonts)，代码和图标显示不全。
# Nerd Fonts 走 dt_download（GitHub release → 镜像回退），受限网络可用。
# 安装到 ~/.local/share/fonts（用户级，无需 sudo），装完 fc-cache 重建缓存。
#
# 用法: install-fonts.sh [nerd|noto|menu]
#   nerd  安装推荐 Nerd Fonts（JetBrainsMono / Hack / FiraCode）
#   noto  安装 Noto CJK 中文字体（dnf，需 sudo）
#   menu  交互选择（默认）
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

log() { dt_log "$*"; }
err() { dt_err "$*"; }

FONT_DIR="$HOME/.local/share/fonts"
NERD_VERSION="v3.3.0"
NERD_BASE="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_VERSION"

# 推荐 Nerd Fonts: 名称|family 关键词(用于幂等判断)
NERD_FONTS=(
    "JetBrainsMono|JetBrainsMono"
    "Hack|Hack"
    "FiraCode|FiraCode"
)

font_installed() { # family 关键词
    fc-list 2>/dev/null | grep -qi "$1"
}

install_nerd_one() { # name family
    local name="$1" fam="$2"
    if font_installed "$fam"; then
        log "字体 $fam 已安装，跳过"
        return 0
    fi
    mkdir -p "$FONT_DIR"
    local zip="$FONT_DIR/.nerd-$name.zip"
    log "下载 $name Nerd Font（镜像回退）..."
    dt_download "$NERD_BASE/$name.zip" "$zip" || return 1
    # 校验 zip 完整性（截断/坏包直接失败，避免装了半截字体）
    if command -v unzip >/dev/null 2>&1; then
        unzip -tq "$zip" >/dev/null 2>&1 || { err "$name.zip 校验失败(下载不完整)，已清理"; rm -f "$zip"; return 1; }
    fi
    mkdir -p "$FONT_DIR/$name"
    unzip -oq "$zip" -d "$FONT_DIR/$name" 2>/dev/null || { err "解压 $name 失败"; rm -f "$zip"; return 1; }
    rm -f "$zip"
    log "$name Nerd Font 已安装到 $FONT_DIR/$name"
}

install_nerd_all() {
    local n f ok=0
    for entry in "${NERD_FONTS[@]}"; do
        IFS='|' read -r n f <<< "$entry"
        install_nerd_one "$n" "$f" && ok=1 || true
    done
    [ "$ok" = 1 ] && fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
}

install_noto() {
    if fc-list 2>/dev/null | grep -qi "Noto Sans CJK"; then
        log "Noto CJK 已安装"
        return 0
    fi
    # dnf 装 Noto CJK（需 sudo；受限网络走系统源，通常已配镜像）
    if command -v dnf >/dev/null 2>&1; then
        log "安装 Noto Sans CJK（需 sudo）..."
        sudo dnf install -y noto-sans-cjk noto-serif-cjk 2>/dev/null \
            && fc-cache -f >/dev/null 2>&1 && log "Noto CJK 已安装" || err "dnf 安装失败（可手动 sudo dnf install noto-sans-cjk）"
    else
        err "非 dnf 发行版，请手动安装 Noto CJK"
    fi
}

menu() {
    while true; do
        local c
        c=$(dt_menu "字体安装" "终端/顶栏等宽与图标字体（用户级，无需 sudo；中文需 sudo）" \
            "nerd|1. 安装推荐 Nerd Fonts|JetBrainsMono / Hack / FiraCode（镜像下载）" \
            "noto|2. 安装 Noto CJK 中文字体|dnf，需 sudo" \
            "status|3. 查看已装字体|列出 Nerd/CJK 字体" \
            "back|← 返回|") || return 0
        case "$c" in
            nerd) install_nerd_all ;;
            noto) install_noto ;;
            status)
                echo "已装 Nerd/JetBrains/Fira 字体: $(fc-list 2>/dev/null | grep -icE 'nerd|jetbrains|firacode' || true) 条"
                echo "已装 CJK 字体: $(fc-list 2>/dev/null | grep -icE 'cjk|noto sans cjk' || true) 条" ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    nerd) install_nerd_all ;;
    noto) install_noto ;;
    status)
        echo "已装 Nerd/JetBrains/Fira 字体: $(fc-list 2>/dev/null | grep -icE 'nerd|jetbrains|firacode' || true) 条"
        echo "已装 CJK 字体: $(fc-list 2>/dev/null | grep -icE 'cjk|noto sans cjk' || true) 条" ;;
    menu) menu ;;
    *) echo "用法: install-fonts.sh [nerd|noto|status|menu]" >&2; exit 1 ;;
esac
