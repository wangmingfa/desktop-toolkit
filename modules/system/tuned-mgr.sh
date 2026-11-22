#!/usr/bin/env bash
# =============================================================================
# tuned-mgr.sh —— tuned 电源/性能方案管理
#
# 安装 tuned + 服务（需 sudo），查看/切换/推荐性能方案（balanced/desktop/
# server/throughput-performance 等）。放进 modules/system/ 由 sub_system 扫描。
#
# 用法: bash tuned-mgr.sh [install|active|recommend|set <方案>|list]
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

tu_log() { echo -e "  ${DT_CYAN}[tuned]${DT_NC} $*"; }
tu_err() { echo -e "  ${DT_RED}[tuned] 错误:${DT_NC} $*" >&2; }
tu_has() { command -v tuned-adm >/dev/null 2>&1; }

tu_need_sudo() {
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        tu_err "操作需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    return 0
}

tu_install() {
    if tu_has && systemctl is-active tuned >/dev/null 2>&1; then
        tu_log "tuned 已装且运行中"
        return 0
    fi
    tu_need_sudo || return 1
    tu_log "安装 tuned 并启用服务 ..."
    sudo dnf install -y tuned || { tu_err "安装失败"; return 1; }
    sudo systemctl enable --now tuned 2>/dev/null || tu_err "服务启用失败"
    tu_log "完成。当前方案: $(tuned-adm active 2>/dev/null | awk -F': ' '{print $2}')"
}

tu_active() {
    echo -e "  ${DT_BOLD}═══ tuned 当前方案 ═══${DT_NC}"
    tuned-adm active 2>/dev/null | sed 's/^/  /' || tu_err "tuned 未装/未运行"
}

tu_recommend() {
    echo -e "  ${DT_BOLD}═══ tuned 推荐方案 ═══${DT_NC}"
    tuned-adm recommend 2>/dev/null | sed 's/^/  /' || tu_err "读取失败"
}

tu_set() { # <方案>
    local profile="${1:-}"
    [ -n "$profile" ] || profile=$(dt_ask_text "方案" "tuned-adm list 查看（如 balanced/desktop/server/throughput-performance）" "") || return 0
    [ -n "$profile" ] || return 0
    tu_need_sudo || return 1
    dt_confirm "切换到 tuned 方案 $profile ?\n需 sudo 密码。\n\n继续？" || return 0
    if sudo tuned-adm profile "$profile" 2>&1 | tail -2; then
        tu_log "✅ 已切换到 $profile"
    else
        tu_err "切换失败（方案名错/服务未运行）"
    fi
}

tu_list() {
    echo -e "  ${DT_BOLD}═══ tuned 可用方案 ═══${DT_NC}"
    tuned-adm list 2>/dev/null | sed 's/^/  /' || tu_err "tuned 未装"
}

tu_menu() {
    while true; do
        local c
        c=$(dt_menu "tuned 性能调优" "电源/性能自动调优方案管理：" \
            "install|1. 安装 tuned+服务|需 sudo，装完自动启用" \
            "active|2. 当前方案|tuned-adm active" \
            "recommend|3. 推荐方案|tuned-adm recommend" \
            "set|4. 切换方案|输入方案名（list 查看）" \
            "list|5. 可用方案|tuned-adm list" \
            "back|← 返回|") || return 0
        case "$c" in
            install) tu_install ;;
            active) tu_active ;;
            recommend) tu_recommend ;;
            set) tu_set ;;
            list) tu_list ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    install) tu_install ;;
    active) tu_active ;;
    recommend) tu_recommend ;;
    set) tu_set "${2:-}" ;;
    list) tu_list ;;
    *) tu_menu ;;
esac
