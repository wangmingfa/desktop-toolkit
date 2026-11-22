#!/usr/bin/env bash
# =============================================================================
# journal.sh —— 系统日志查看（journalctl / systemd-analyze）
#
# 查看错误/系统/服务/内核日志，清理旧日志，启动耗时分析。systemd 自带无需装；
# 清理需 sudo。放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash journal.sh [err|boot|svc|kernel|clean|blame]
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

jn_log() { echo -e "  ${DT_CYAN}[journal]${DT_NC} $*"; }
jn_err() { echo -e "  ${DT_RED}[journal] 错误:${DT_NC} $*" >&2; }

# journalctl 输出直接到 stdout（查看操作，不捕获）
jn_err_log() { journalctl -p err -n 50 --no-pager 2>/dev/null || jn_err "读取失败"; }
jn_boot() { journalctl -b -n 80 --no-pager 2>/dev/null || jn_err "读取失败"; }
jn_kernel() { journalctl -k -n 30 --no-pager 2>/dev/null || jn_err "读取失败"; }

jn_svc() { # 某服务日志
    local svc="${1:-}"
    [ -n "$svc" ] || svc=$(dt_ask_text "服务日志" "服务名（如 dms/pipewire/wireplumber/NetworkManager）" "dms") || return 0
    [ -n "$svc" ] || return 0
    echo -e "  ${DT_BOLD}═══ $svc 日志（最近 50 条）═══${DT_NC}"
    journalctl -u "$svc" -n 50 --no-pager 2>/dev/null || jn_err "无 $svc 日志（服务可能未运行/不存在）"
}

jn_clean() { # 清理旧日志
    local days
    days=$(dt_ask_text "清理日志" "保留最近几天（回车=7）" "7") || return 0
    [ -n "$days" ] || days=7
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        jn_err "清理需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    local before
    before=$(journalctl --disk-usage 2>/dev/null | tail -1 || echo "?")
    dt_confirm "清理日志（保留最近 ${days} 天）？\n当前占用: $before\n\n继续？" || return 0
    sudo journalctl --vacuum-time="${days}d" 2>&1 | tail -3
}

jn_blame() { # 启动耗时
    echo -e "  ${DT_BOLD}═══ 启动耗时 Top 12（systemd-analyze blame）═══${DT_NC}"
    systemd-analyze blame 2>/dev/null | head -12 || jn_err "读取失败"
}

jn_menu() {
    while true; do
        local c
        c=$(dt_menu "系统日志查看" "journalctl 日志 + 启动分析（systemd 自带）：" \
            "err|1. 错误日志|最近 50 条错误/严重（-p err）" \
            "boot|2. 本次启动日志|最近 80 条" \
            "svc|3. 某服务日志|输入服务名查最近 50 条" \
            "kernel|4. 内核日志|最近 30 条内核消息" \
            "blame|5. 启动耗时|systemd-analyze blame Top 12" \
            "clean|6. 清理旧日志|保留最近 N 天（需 sudo）" \
            "back|← 返回|") || return 0
        case "$c" in
            err) jn_err_log ;;
            boot) jn_boot ;;
            svc) jn_svc ;;
            kernel) jn_kernel ;;
            blame) jn_blame ;;
            clean) jn_clean ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    err) jn_err_log ;;
    boot) jn_boot ;;
    svc) jn_svc "${2:-}" ;;
    kernel) jn_kernel ;;
    blame) jn_blame ;;
    clean) jn_clean ;;
    *) jn_menu ;;
esac
