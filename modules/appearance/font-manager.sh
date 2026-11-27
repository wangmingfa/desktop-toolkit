#!/usr/bin/env bash
# =============================================================================
# font-manager.sh —— 字体管理（列表 / 安装 Nerd Font）
#
# 列出已装字体（fc-list），安装 Nerd Font 编程字体（dt_download 走镜像下载
# release zip → ~/.local/share/fonts → fc-cache）。无需 sudo（用户级字体）。
# 注册 main.sh 外观子菜单。
#
# 用法: bash font-manager.sh [list|nerd <family>|install <family>]
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_BOLD=$'\033[1m'; DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'
    DT_CYAN=$'\033[0;36m'; DT_RED=$'\033[0;31m'; DT_NC=$'\033[0m'
else
    DT_BOLD=""; DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_NC=""
fi

fm_log() { echo -e "  ${DT_CYAN}[font]${DT_NC} $*"; }
fm_err() { echo -e "  ${DT_RED}[font] 错误:${DT_NC} $*" >&2; }

# Nerd Font 家族 → release URL（v3.3.0，dt_download 走镜像）
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0"

fm_family_url() {
    case "$1" in
        JetBrainsMono) echo "$FONT_URL/JetBrainsMono.zip" ;;
        FiraCode) echo "$FONT_URL/FiraCode.zip" ;;
        Hack) echo "$FONT_URL/Hack.zip" ;;
        UbuntuMono) echo "$FONT_URL/UbuntuMono.zip" ;;
        Noto) echo "$FONT_URL/Noto.zip" ;;
        *) echo "" ;;
    esac
}

fm_list() {
    echo -e "  ${DT_BOLD}═══ 已装字体家族（前 30）═══${DT_NC}"
    fc-list : family 2>/dev/null | sort -u | head -30 | sed 's/^/  /' || fm_err "fc-list 失败"
}

fm_nerd() { # <family>
    local family="${1:-}"
    [ -n "$family" ] || family=$(dt_menu "Nerd Font" "选择要下载的编程字体（用户级，不需 sudo）：" \
        "JetBrainsMono|JetBrainsMono Nerd Font|编程常用(等宽+图标)" \
        "FiraCode|FiraCode Nerd Font|开源等宽" \
        "Hack|Hack Nerd Font|经典等宽" \
        "UbuntuMono|UbuntuMono Nerd Font|Ubuntu 风格" \
        "Noto|Noto Nerd Font|Noto 无衬线" \
        "back|← 返回|") || return 0
    [ "$family" = __quit ] && exit 0
    [ "$family" = back ] && return 0
    local url dest
    url=$(fm_family_url "$family")
    [ -n "$url" ] || { fm_err "未知字体: $family"; return 1; }
    dest="$HOME/.local/share/fonts/nerd-$family"
    mkdir -p "$dest"
    fm_log "下载 $family（$url，受限网络走镜像）..."
    if dt_download "$url" "$dest/$family.zip"; then
        fm_log "解压 + 刷新字体缓存..."
        if unzip -o "$dest/$family.zip" -d "$dest" >/dev/null 2>&1; then
            rm -f "$dest/$family.zip"
            fc-cache -f >/dev/null 2>&1
            fm_log "✅ $family 安装完成（$dest）。终端/应用选字体即可。"
        else
            fm_err "解压失败（需 unzip，可 sudo dnf install unzip）"
        fi
    else
        fm_err "下载失败（网络受限已尝试镜像）。可稍后重试或换字体。"
    fi
}

fm_menu() {
    while true; do
        local c
        c=$(dt_menu "字体管理" "已装字体列表 + Nerd Font 编程字体（用户级）：" \
            "list|列出已装字体|fc-list 家族前 30" \
            "nerd|安装 Nerd Font|下载到 ~/.local/share/fonts(镜像)" \
            "back|← 返回|") || return 0
        case "$c" in
            list) fm_list ;;
            nerd) fm_nerd ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    list) fm_list ;;
    nerd) fm_nerd "${2:-}" ;;
    install) fm_nerd "${2:-}" ;;
    *) fm_menu ;;
esac
