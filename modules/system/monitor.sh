#!/usr/bin/env bash
# =============================================================================
# monitor.sh —— 系统监控工具（btop / htop / nvtop）
#
# 终端资源监控器一键安装（Fedora 官方源均有）。只装包，不碰配置。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash monitor.sh [status|install <tool>]
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

mo_log() { echo -e "  ${DT_CYAN}[monitor]${DT_NC} $*"; }
mo_err() { echo -e "  ${DT_RED}[monitor] 错误:${DT_NC} $*" >&2; }

mo_has() { command -v "$1" >/dev/null 2>&1; }

mo_install() { # <btop|htop|nvtop>
    local tool="$1"
    if mo_has "$tool"; then mo_log "$tool 已装"; return 0; fi
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        mo_err "安装 $tool 需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    mo_log "安装 $tool ..."
    if ! sudo dnf install -y "$tool"; then
        mo_err "安装 $tool 失败，请手动: sudo dnf install $tool"
        return 1
    fi
    mo_log "$tool 安装完成"
}

mo_status() {
    echo "=== 系统监控工具状态 ==="
    for t in btop htop nvtop; do
        if mo_has "$t"; then echo "  ✅ $t"; else echo "  ❌ $t（未装）"; fi
    done
}

mo_menu() {
    while true; do
        local c
        c=$(dt_menu "系统监控工具" "终端资源监控（btop 更美观 / htop 经典 / nvtop 显卡）：" \
            "btop|① 安装 btop|终端 CPU/内存/磁盘/网络(美观)" \
            "htop|② 安装 htop|经典进程监控" \
            "nvtop|③ 安装 nvtop|显卡监控(需独显)" \
            "all|④ 全部安装|btop + htop + nvtop" \
            "status|⑤ 状态|已装/未装" \
            "back|← 返回|") || return 0
        case "$c" in
            btop) mo_install btop ;;
            htop) mo_install htop ;;
            nvtop) mo_install nvtop ;;
            all) mo_install btop; mo_install htop; mo_install nvtop ;;
            status) mo_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    status) mo_status ;;
    install) [ -n "${2:-}" ] && mo_install "$2" || mo_err "用法: monitor.sh install <btop|htop|nvtop>" ;;
    *) mo_menu ;;
esac
