#!/usr/bin/env bash
# =============================================================================
# autostart.sh —— 自启动管理（systemd 用户服务 + niri spawn）
#
# 列出/启用/停用 systemd 用户自启动服务（DMS/cliphist/备份等），并列出
# niri 配置里的 spawn-at-startup。放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash autostart.sh [list|enable <服务>|disable <服务>]
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

au_log() { echo -e "  ${DT_CYAN}[autostart]${DT_NC} $*"; }
au_err() { echo -e "  ${DT_RED}[autostart] 错误:${DT_NC} $*" >&2; }

au_list() { # 列出 systemd 用户自启动 + niri spawn
    echo -e "  ${DT_BOLD}═══ systemd 用户自启动服务（enabled）═══${DT_NC}"
    local out
    out=$(systemctl --user list-unit-files --state=enabled --no-pager 2>/dev/null || true)
    if printf '%s\n' "$out" | grep -qE '\.service'; then
        printf '%s\n' "$out" | grep -E '\.service' | sed 's/^/  /' | head -20
    else
        echo "    （无 enabled 用户服务）"
    fi
    echo
    echo -e "  ${DT_BOLD}═══ niri spawn-at-startup ═══${DT_NC}"
    local niri_dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
    local spawns
    spawns=$(grep -h 'spawn-at-startup' "$niri_dir"/*.kdl 2>/dev/null || true)
    if [ -n "$spawns" ]; then
        printf '%s\n' "$spawns" | sed 's/^/  /'
    else
        echo "    （无 spawn-at-startup）"
    fi
}

au_enable() { # <服务> —— enable --now
    local svc="${1:-}"
    [ -n "$svc" ] || svc=$(dt_ask_text "启用服务" "systemd 用户服务名（如 cliphist / backup-config.timer）" "") || return 0
    [ -n "$svc" ] || return 0
    case "$svc" in *.service|*.timer|*.socket) ;; *) svc="$svc.service" ;; esac
    if systemctl --user enable --now "$svc" 2>/dev/null; then
        au_log "已启用并启动: $svc"
    else
        au_err "启用失败: $svc（检查服务名/是否存在）"
    fi
}

au_disable() { # <服务> —— disable --now
    local svc="${1:-}"
    [ -n "$svc" ] || svc=$(dt_ask_text "停用服务" "systemd 用户服务名（当前启用的）" "") || return 0
    [ -n "$svc" ] || return 0
    case "$svc" in *.service|*.timer|*.socket) ;; *) svc="$svc.service" ;; esac
    if systemctl --user disable --now "$svc" 2>/dev/null; then
        au_log "已停用: $svc"
    else
        au_err "停用失败: $svc"
    fi
}

au_menu() {
    while true; do
        local c
        c=$(dt_menu "自启动管理" "systemd 用户服务 + niri spawn-at-startup：" \
            "list|1. 列出自启动|enabled 用户服务 + niri spawn" \
            "enable|2. 启用服务|输入服务名 enable --now" \
            "disable|3. 停用服务|输入服务名 disable --now" \
            "back|← 返回|") || return 0
        case "$c" in
            list) au_list ;;
            enable) au_enable ;;
            disable) au_disable ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    list) au_list ;;
    enable) au_enable "${2:-}" ;;
    disable) au_disable "${2:-}" ;;
    *) au_menu ;;
esac
