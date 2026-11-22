#!/usr/bin/env bash
# =============================================================================
# flatpak-mgr.sh —— Flatpak 应用管理（安装/卸载/更新/清理）
#
# 安装 flatpak + Flathub 源（需 sudo），列已装/搜装/卸载/更新/清理应用。
# 装应用是用户级（不需 sudo）。受限网络 Flathub 可能慢/失败。
# 注册 main.sh 应用子菜单。
#
# 用法: bash flatpak-mgr.sh [list|search <词>|install <appid>|uninstall <appid>|update|clean|init]
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

fp_log() { echo -e "  ${DT_CYAN}[flatpak]${DT_NC} $*"; }
fp_err() { echo -e "  ${DT_RED}[flatpak] 错误:${DT_NC} $*" >&2; }

fp_has() { command -v flatpak >/dev/null 2>&1; }

fp_init() { # 装 flatpak + Flathub 源
    if ! fp_has; then
        if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
            fp_err "装 flatpak 需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
            return 1
        fi
        fp_log "安装 flatpak ..."
        sudo dnf install -y flatpak || { fp_err "安装失败"; return 1; }
    fi
    if ! flatpak remotes 2>/dev/null | grep -q flathub; then
        fp_log "添加 Flathub 源（受限网络可能慢/失败）..."
        flatpak remote-add --if-not-exists --user flathub \
            https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || \
            fp_err "Flathub 源添加失败（网络受限）。可稍后重试。"
    fi
    fp_log "Flatpak 就绪"
}

fp_list() {
    fp_has || { fp_err "flatpak 未装，先运行 init"; return 1; }
    echo -e "  ${DT_BOLD}═══ 已装 Flatpak 应用 ═══${DT_NC}"
    flatpak list --app --columns=application,version 2>/dev/null | sed 's/^/  /' || fp_err "无已装应用"
}

fp_search_install() { # <词>
    fp_has || { fp_err "flatpak 未装，先运行 init"; return 1; }
    local term="${1:-}"
    [ -n "$term" ] || term=$(dt_ask_text "搜索应用" "搜索词（如 firefox/obs/telegram）" "") || return 0
    [ -n "$term" ] || return 0
    fp_log "搜索 '$term' ..."
    local -a rows=()
    local appid name ver
    while read -r appid name ver _; do
        [ -n "$appid" ] && rows+=("$appid|$name|$ver")
    done < <(flatpak search "$term" 2>/dev/null | awk '{print $1, $2, $3}' | head -15)
    [ "${#rows[@]}" -eq 0 ] && { fp_err "无结果（Flathub 未同步/网络受限）"; return 1; }
    rows+=("back|← 取消|")
    local c
    c=$(dt_menu "搜索结果" "选择要安装的应用（用户级，不需 sudo）：" "${rows[@]}") || return 0
    [ "$c" = back ] && return 0
    dt_confirm "安装 $c ?\n（用户级安装，下载可能较大）" || return 0
    if flatpak install -y --user flathub "$c" 2>&1 | tail -2; then
        fp_log "✅ 已安装 $c"
    else
        fp_err "安装失败（网络受限/未在 Flathub）"
    fi
}

fp_uninstall() { # <appid>
    fp_has || { fp_err "flatpak 未装"; return 1; }
    local appid="${1:-}"
    [ -n "$appid" ] || appid=$(dt_ask_text "卸载" "应用 ID（fp_list 查看）" "") || return 0
    [ -n "$appid" ] || return 0
    dt_confirm "卸载 $appid ?" || return 0
    if flatpak uninstall -y "$appid" 2>&1 | tail -1; then
        fp_log "✅ 已卸载 $appid"
    else
        fp_err "卸载失败"
    fi
}

fp_update() {
    fp_has || { fp_err "flatpak 未装"; return 1; }
    fp_log "更新应用（用户级）..."
    flatpak update -y 2>&1 | tail -3 || fp_err "更新失败（网络受限）"
}

fp_clean() {
    fp_has || { fp_err "flatpak 未装"; return 1; }
    local unused
    unused=$(flatpak uninstall --unused 2>&1 | tail -2)
    fp_log "清理完成：$unused"
}

fp_menu() {
    while true; do
        local c
        c=$(dt_menu "Flatpak 应用管理" "隔离运行 GUI 应用（装应用用户级，不需 sudo）：" \
            "init|1. 安装 Flatpak+Flathub|flatpak 包需 sudo，Flathub 源用户级" \
            "list|2. 已装应用|flatpak list" \
            "search|3. 搜索并安装|按词搜 Flathub，选一个装" \
            "uninstall|4. 卸载|输入应用 ID" \
            "update|5. 更新|flatpak update -y" \
            "clean|6. 清理|移除未使用的运行时" \
            "back|← 返回|") || return 0
        case "$c" in
            init) fp_init ;;
            list) fp_list ;;
            search) fp_search_install ;;
            uninstall) fp_uninstall ;;
            update) fp_update ;;
            clean) fp_clean ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    init) fp_init ;;
    list) fp_list ;;
    search) fp_search_install "${2:-}" ;;
    install) fp_search_install "${2:-}" ;;
    uninstall) fp_uninstall "${2:-}" ;;
    update) fp_update ;;
    clean) fp_clean ;;
    *) fp_menu ;;
esac
