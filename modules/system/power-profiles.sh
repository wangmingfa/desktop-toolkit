#!/usr/bin/env bash
# =============================================================================
# power-profiles.sh —— 电源模式切换（performance / balanced / power-saver）
#
# 基于 power-profiles-daemon（Fedora 官方源），笔记本/可切换硬件的实用工具。
# 只切换系统电源模式，不动用户配置。放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash power-profiles.sh [status|perf|balanced|saver]
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

pp_log() { echo -e "  ${DT_CYAN}[power-profiles]${DT_NC} $*"; }
pp_err() { echo -e "  ${DT_RED}[power-profiles] 错误:${DT_NC} $*" >&2; }

pp_ctl() { command -v powerprofilesctl >/dev/null 2>&1; }
pp_label() { # 模式 → 中文名
    case "${1:-}" in
        performance) echo "性能" ;; balanced) echo "平衡" ;;
        power-saver) echo "节能" ;; *) echo "${1:-未知}" ;;
    esac
}

pp_current() { # stdout 输出当前模式
    powerprofilesctl get 2>/dev/null | tr -d '\n'
}

pp_install() { # 安装 daemon + 启用服务
    if pp_ctl; then pp_log "power-profiles-daemon 已安装"; return 0; fi
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        pp_err "安装需 sudo 密码，但当前不是交互终端。请在一个终端里运行本脚本。"
        return 1
    fi
    pp_log "安装 power-profiles-daemon ..."
    if ! sudo dnf install -y power-profiles-daemon; then
        pp_err "安装失败，请手动: sudo dnf install power-profiles-daemon"
        return 1
    fi
    pp_log "启用 power-profiles-daemon 服务 ..."
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null \
        || sudo systemctl start power-profiles-daemon 2>/dev/null \
        || pp_log "服务启动提示：可手动执行 systemctl enable --now power-profiles-daemon"
    pp_log "安装完成"
}

pp_set() { # <mode> —— 切换
    local mode="$1"
    pp_ctl || { pp_log "power-profiles-daemon 未安装，先安装"; pp_install || return 1; }
    if powerprofilesctl set "$mode" 2>/dev/null; then
        pp_log "已切换到: $(pp_label "$mode")（$(pp_current)）"
    else
        pp_err "切换失败。可用模式: $(powerprofilesctl list 2>/dev/null | sed 's/^\* //' | grep -oE '^[a-z-]+' | tr '\n' ' ')"
        return 1
    fi
}

pp_status() { # 只读状态
    if ! pp_ctl; then
        echo -e "  ${DT_YELLOW}power-profiles-daemon 未安装。${DT_NC}"
        echo "  安装: bash $(basename "$0") install"
        return 1
    fi
    local cur
    cur=$(pp_current)
    echo -e "  ${DT_BOLD}当前电源模式:${DT_NC} ${DT_GREEN}$(pp_label "$cur")${DT_NC} ($cur)"
    echo
    echo "  可用模式:"
    powerprofilesctl list 2>/dev/null | sed 's/^\*/  ●/; s/^/    /' | sed 's/:.*$/  /'
}

pp_menu() {
    while true; do
        local cur
        cur=$(pp_current)
        local c
        c=$(dt_menu "电源模式" \
            "基于 power-profiles-daemon。当前: $(pp_label "$cur") ($cur)" \
            "perf|1. 性能 performance|高性能（性能/散热优先）" \
            "balanced|2. 平衡 balanced|默认（功耗与性能平衡）" \
            "saver|3. 节能 power-saver|省电（电池优先）" \
            "install|4. 安装/修复 power-profiles-daemon|未装时自动安装+启用服务" \
            "status|5. 查看状态|当前模式 + 可用模式" \
            "back|← 返回|") || return 0
        case "$c" in
            perf) pp_set performance ;;
            balanced) pp_set balanced ;;
            saver) pp_set power-saver ;;
            install) pp_install ;;
            status) pp_status ;;
            back) return 0 ;;
        esac
    done
}

# 命令行参数：直接执行对应动作（便于脚本/快捷键调用）
case "${1:-}" in
    status) pp_status ;;
    perf) pp_set performance ;;
    balanced) pp_set balanced ;;
    saver) pp_set power-saver ;;
    install) pp_install ;;
    *) pp_menu ;;
esac
