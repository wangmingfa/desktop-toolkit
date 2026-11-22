#!/usr/bin/env bash
# =============================================================================
# netmanager.sh —— 网络连接管理（nmcli）
#
# 查看网络状态/连接列表、Wi-Fi 开关、连接/断开已有连接。nmcli 已装。
# 注册 main.sh 网络子菜单。
#
# 用法: bash netmanager.sh [status|list|wifi <on|off>|up <连接名>|down <连接名>]
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

nm_log() { echo -e "  ${DT_CYAN}[netmanager]${DT_NC} $*"; }
nm_err() { echo -e "  ${DT_RED}[netmanager] 错误:${DT_NC} $*" >&2; }

nm_status() {
    echo -e "  ${DT_BOLD}═══ 网络状态 ═══${DT_NC}"
    nmcli general status 2>/dev/null | sed 's/^/  /' || nm_err "读取失败"
    echo
    echo -e "  ${DT_BOLD}═══ 活动连接 ═══${DT_NC}"
    nmcli -t -f TYPE,NAME,STATE,DEVICE connection show --active 2>/dev/null | sed 's/:/  /g;s/^/  /' || nm_err "无活动连接"
}

nm_list() {
    echo -e "  ${DT_BOLD}═══ 已保存的连接 ═══${DT_NC}"
    nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null | sed 's/:/  /g;s/^/  /' || nm_err "无连接"
}

nm_wifi() { # <on|off>
    local state="$1"
    nm_log "Wi-Fi $state ..."
    if nmcli radio wifi "$state" 2>/dev/null; then
        nm_log "Wi-Fi 已$state"
    else
        nm_err "Wi-Fi $state 失败（可能需要权限）"
    fi
}

nm_up() { # <连接名>
    local conn="${1:-}"
    [ -n "$conn" ] || conn=$(dt_ask_text "连接" "已保存的连接名（nm_list 查看）" "") || return 0
    [ -n "$conn" ] || return 0
    nm_log "连接 $conn ..."
    if nmcli connection up "$conn" 2>&1 | tail -1; then
        nm_log "已连接"
    else
        nm_err "连接失败（检查密码/网络可用）"
    fi
}

nm_down() { # <连接名>
    local conn="${1:-}"
    [ -n "$conn" ] || conn=$(dt_ask_text "断开" "要断开的连接名" "") || return 0
    [ -n "$conn" ] || return 0
    if nmcli connection down "$conn" 2>/dev/null; then
        nm_log "已断开 $conn"
    else
        nm_err "断开失败"
    fi
}

nm_scan() { # 扫描 Wi-Fi 并选择连接（需已保存或输入密码）
    if ! nmcli -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null | grep -q SSID; then
        nm_err "Wi-Fi 扫描失败（可能未启用/无网卡）"
        return 1
    fi
    local -a rows=()
    local ssid sig inuse
    while IFS=: read -r inuse ssid sig _; do
        [ -z "$ssid" ] && continue
        rows+=("$ssid|$(printf '%-32s %s%%' "$ssid" "$sig")|${inuse:-\*}")
    done < <(nmcli -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null)
    rows+=("back|← 返回|")
    local c
    c=$(dt_menu "Wi-Fi 网络" "选择要连接的网络（若未保存会提示密码）：" "${rows[@]}") || return 0
    [ "$c" = back ] && return 0
    nm_log "连接 $c ..."
    if nmcli --ask device wifi connect "$c" 2>&1 | tail -2; then
        nm_log "已连接 $c"
    else
        nm_err "连接失败（密码错/未启用）"
    fi
}

nm_menu() {
    while true; do
        local c
        c=$(dt_menu "网络连接管理" "nmcli 查看/连接网络（nmcli 已装）：" \
            "status|1. 网络状态|general status + 活动连接" \
            "list|2. 已保存连接|nmcli connection show" \
            "scan|3. 扫描 Wi-Fi 连接|选择网络连接（可输密码）" \
            "wifi-on|4. Wi-Fi 开|nmcli radio wifi on" \
            "wifi-off|5. Wi-Fi 关|nmcli radio wifi off" \
            "up|6. 连接已有|输入连接名 up" \
            "down|7. 断开|输入连接名 down" \
            "back|← 返回|") || return 0
        case "$c" in
            status) nm_status ;;
            list) nm_list ;;
            scan) nm_scan ;;
            wifi-on) nm_wifi on ;;
            wifi-off) nm_wifi off ;;
            up) nm_up ;;
            down) nm_down ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    status) nm_status ;;
    list) nm_list ;;
    wifi) nm_wifi "${2:-}" ;;
    up) nm_up "${2:-}" ;;
    down) nm_down "${2:-}" ;;
    scan) nm_scan ;;
    *) nm_menu ;;
esac
