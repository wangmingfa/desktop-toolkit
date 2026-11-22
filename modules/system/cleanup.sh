#!/usr/bin/env bash
# =============================================================================
# cleanup.sh —— 系统清理维护（dnf 缓存 / journal 日志 / 旧内核）
#
# 保守实现：每项先只读显示可释放空间，执行前逐项 dt_confirm 确认。
# 旧内核只保留最新 2 个，删除更老的（不删当前运行内核）。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash cleanup.sh [show|dnf|journal|kernels]
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

cl_log() { echo -e "  ${DT_CYAN}[cleanup]${DT_NC} $*"; }
cl_err() { echo -e "  ${DT_RED}[cleanup] 错误:${DT_NC} $*" >&2; }

# 捕获输出后再处理（pipefail 下避免上游 SIGPIPE 误判）
cl_out() { local o; o=$("$@" 2>/dev/null) || true; printf '%s' "$o"; }

cl_has_sudo() { sudo -n true 2>/dev/null; }
cl_sudo_warn() {
    if ! cl_has_sudo && [ ! -t 0 ]; then
        cl_err "需 sudo 密码，但当前不是交互终端。请在一个终端里运行本脚本。"
        return 1
    fi
    return 0
}

cl_dnf_size() { # dnf 缓存大小（先无 sudo 试，失败再 sudo）
    local s
    s=$(du -sh /var/cache/dnf 2>/dev/null | awk '{print $1}')
    [ -n "$s" ] || s=$(cl_out sudo du -sh /var/cache/dnf 2>/dev/null | awk '{print $1}')
    echo "${s:-?}"
}

cl_journal_size() {
    cl_out journalctl --disk-usage | grep -oE '[0-9.]+[MG]' | head -1
}

cl_kernels() { # 已装 kernel-core 列表（新→旧）
    cl_out rpm -q kernel-core --qf '%{INSTALLTIME} %{VERSION}-%{RELEASE}\n' \
        | sort -rn | awk '{print $2}'
}

cl_show() {
    echo -e "  ${DT_BOLD}可清理空间（只读）${DT_NC}"
    echo
    echo -e "  ${DT_CYAN}dnf 缓存:${DT_NC}   $(cl_dnf_size)"
    echo -e "  ${DT_CYAN}journal 日志:${DT_NC} $(cl_journal_size)"
    local -a ks
    mapfile -t ks < <(cl_kernels)
    echo -e "  ${DT_CYAN}旧内核:${DT_NC}   共 ${#ks[@]} 个，可清 $(( ${#ks[@]} > 2 ? ${#ks[@]} - 2 : 0 )) 个（保留最新 2 个）"
}

cl_dnf_clean() {
    cl_sudo_warn || return 1
    dt_confirm "清理 dnf 缓存（/var/cache/dnf，当前 $(cl_dnf_size)）？" || return 0
    cl_log "清理 dnf 缓存 ..."
    sudo dnf clean all 2>/dev/null && cl_log "dnf 缓存已清理" || cl_err "dnf 清理失败"
}

cl_journal_clean() {
    cl_sudo_warn || return 1
    dt_confirm "清理 journal 日志到 100M（当前 $(cl_journal_size)）？" || return 0
    cl_log "清理 journal 日志（vacuum 100M）..."
    sudo journalctl --vacuum-size=100M >/dev/null 2>&1 && cl_log "journal 已清理到 100M" || cl_err "journal 清理失败"
}

cl_kernels_clean() {
    cl_sudo_warn || return 1
    local -a ks
    mapfile -t ks < <(cl_kernels)
    if [ "${#ks[@]}" -le 2 ]; then
        cl_log "旧内核不多（${#ks[@]} 个），无需清理"
        return 0
    fi
    local running old
    running=$(uname -r)
    echo "  当前运行内核: $running"
    echo "  已装内核(新→旧): ${ks[*]}"
    dt_confirm "清理旧内核（保留最新 2 个，删除 ${#ks[@]} - 2 = $(( ${#ks[@]} - 2 )) 个）？" || return 0
    local i
    for (( i=2; i<${#ks[@]}; i++ )); do
        local k="${ks[$i]}"
        # 绝不删当前运行内核
        case "$k" in *"$running"*) cl_log "跳过运行内核 $k"; continue ;; esac
        cl_log "删除旧内核 $k ..."
        sudo dnf remove -y "kernel-core-$k" 2>/dev/null || cl_err "删除 $k 失败"
    done
    cl_log "旧内核清理完成"
}

cl_menu() {
    while true; do
        local c
        c=$(dt_menu "系统清理维护" "保守清理：每项先确认。可释放空间：" \
            "show|1. 查看可清理空间|dnf 缓存/journal/旧内核（只读）" \
            "dnf|2. 清理 dnf 缓存|dnf clean all" \
            "journal|3. 清理 journal 日志|vacuum 到 100M" \
            "kernels|4. 清理旧内核|保留最新 2 个" \
            "all|5. 全部清理|依次确认 2.3.4." \
            "back|← 返回|") || return 0
        case "$c" in
            show) cl_show ;;
            dnf) cl_dnf_clean ;;
            journal) cl_journal_clean ;;
            kernels) cl_kernels_clean ;;
            all) cl_dnf_clean; cl_journal_clean; cl_kernels_clean ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    show) cl_show ;;
    dnf) cl_dnf_clean ;;
    journal) cl_journal_clean ;;
    kernels) cl_kernels_clean ;;
    *) cl_menu ;;
esac
