#!/usr/bin/env bash
# =============================================================================
# syssvc.sh —— 系统服务管理（systemctl 系统级）
#
# 列出运行中/失败服务、启停/启用禁用系统服务（需 sudo）。与 autostart.sh
# （用户服务）互补。放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash syssvc.sh [list|failed|op <svc> <start|stop|restart|enable|disable>|status <svc>]
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

sv_log() { echo -e "  ${DT_CYAN}[syssvc]${DT_NC} $*"; }
sv_err() { echo -e "  ${DT_RED}[syssvc] 错误:${DT_NC} $*" >&2; }

sv_need_sudo() {
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        sv_err "操作需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    return 0
}

sv_list() {
    echo -e "  ${DT_BOLD}═══ 运行中系统服务（前 20）═══${DT_NC}"
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null \
        | grep -E '^[a-z0-9@_.-]+\.service' | head -20 \
        || sv_err "读取失败"
}

sv_failed() {
    echo -e "  ${DT_BOLD}═══ 失败/加载失败服务 ═══${DT_NC}"
    local out
    out=$(systemctl --failed --no-pager 2>/dev/null || true)
    printf '%s\n' "$out" | grep -E '^[a-z0-9@_.-]+\.service|loaded' | head -15
}

sv_op() { # <svc> <start|stop|restart|enable|disable>
    local svc="${1:-}" op="${2:-}"
    [ -n "$svc" ] || svc=$(dt_ask_text "服务名" "系统服务名（如 gdm/NetworkManager/sshd）" "") || return 0
    [ -n "$svc" ] || return 0
    case "$svc" in *.service|*.socket|*.timer) ;; *) svc="$svc.service" ;; esac
    [ -n "$op" ] || op=$(dt_menu "操作" "对 $svc 执行：" \
        "start|① 启动|立即运行" \
        "stop|② 停止|立即停止" \
        "restart|③ 重启|停止再启动" \
        "enable|④ 开机自启|enable（下次开机启用）" \
        "disable|⑤ 取消自启|disable（下次开机停用）" \
        "status|⑥ 查看状态|") || return 0
    if [ "$op" = status ]; then
        systemctl status "$svc" --no-pager 2>/dev/null | head -12 || sv_err "查看失败"
        return 0
    fi
    sv_need_sudo || return 1
    dt_confirm "对 $svc 执行 $op？\n需 sudo 密码。\n\n继续？" || return 0
    if sudo systemctl "$op" "$svc"; then
        sv_log "✅ $op $svc 完成"
    else
        sv_err "$op $svc 失败（检查服务名/权限/依赖）"
    fi
}

sv_status() { # <svc>
    local svc="${1:-}"
    [ -n "$svc" ] || svc=$(dt_ask_text "服务名" "系统服务名" "") || return 0
    [ -n "$svc" ] || return 0
    case "$svc" in *.service|*.socket|*.timer) ;; *) svc="$svc.service" ;; esac
    systemctl status "$svc" --no-pager 2>/dev/null | head -12 || sv_err "查看失败"
}

sv_menu() {
    while true; do
        local c
        c=$(dt_menu "系统服务管理" "systemctl 系统级服务（与用户级 autostart 互补）：" \
            "list|① 运行中服务|列出前 20 个 running" \
            "op|② 启停服务|输入服务名 + start/stop/restart/enable/disable" \
            "failed|③ 失败服务|列出 failed/加载失败" \
            "status|④ 状态|输入服务名看状态" \
            "back|← 返回|") || return 0
        case "$c" in
            list) sv_list ;;
            op) sv_op ;;
            failed) sv_failed ;;
            status) sv_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    list) sv_list ;;
    failed) sv_failed ;;
    op) sv_op "${2:-}" "${3:-}" ;;
    status) sv_status "${2:-}" ;;
    *) sv_menu ;;
esac
