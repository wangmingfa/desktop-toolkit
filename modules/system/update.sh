#!/usr/bin/env bash
# =============================================================================
# update.sh —— 系统更新管理（检查 / 列出 / 升级）
#
# Fedora dnf/dnf5。检查更新只读；升级需 sudo（大下载，弱网中断可重跑续装）。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash update.sh [check|upgrade|status]
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

up_log() { echo -e "  ${DT_CYAN}[update]${DT_NC} $*"; }
up_err() { echo -e "  ${DT_RED}[update] 错误:${DT_NC} $*" >&2; }

up_dnf() { command -v dnf5 >/dev/null 2>&1 && echo dnf5 || echo dnf; }

# 可用更新数（dnf check-update 有更新时退出码 100, pipefail 下需容错）
up_count() {
    local out c
    out=$(sudo -n dnf check-update 2>/dev/null || dnf check-update 2>/dev/null || true)
    c=$(printf '%s\n' "$out" | grep -cE '^[a-z0-9._-]+[[:space:]]+[0-9]' || true)
    printf '%s' "${c:-0}"
}

up_check() { # 列出待更新（只读）
    local n
    n=$(up_count)
    if [ "$n" -eq 0 ]; then
        echo -e "  ${DT_GREEN}✅${DT_NC} 系统已是最新（无可用更新）"
        return 0
    fi
    echo -e "  ${DT_YELLOW}有 ${n} 个可用更新：${DT_NC}"
    dnf check-update 2>/dev/null | grep -E '^[a-z0-9._-]+[[:space:]]+[0-9]' | awk '{printf "    %-30s %s -> %s\n", $1, $2, $3}' | head -20
}

up_upgrade() {
    local n
    n=$(up_count)
    if [ "$n" -eq 0 ]; then up_log "无可用更新"; return 0; fi
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        up_err "升级需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    dt_confirm "升级 ${n} 个包？\n下载量可能较大，弱网中断后重跑可续装。\n\n继续？" || return 0
    up_log "dnf upgrade（${n} 个包）..."
    sudo "$(up_dnf)" upgrade -y || { up_err "升级失败（可能中断，重跑续装）"; return 1; }
    up_log "✅ 升级完成"
}

up_status() {
    echo "=== 系统更新状态 ==="
    echo "  可用更新: $(up_count) 个"
    echo "  包管理器: $(up_dnf)"
}

up_menu() {
    while true; do
        local c
        c=$(dt_menu "系统更新管理" "检查 / 升级 Fedora 系统包（dnf）：" \
            "check|1. 检查更新|只读列出待更新包" \
            "upgrade|2. 升级全部|dnf upgrade（需 sudo，大下载）" \
            "status|3. 状态|可用更新数 / 包管理器" \
            "back|← 返回|") || return 0
        case "$c" in
            check) up_check ;;
            upgrade) up_upgrade ;;
            status) up_status ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    check) up_check ;;
    upgrade) up_upgrade ;;
    status) up_status ;;
    *) up_menu ;;
esac
