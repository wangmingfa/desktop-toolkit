#!/usr/bin/env bash
# =============================================================================
# sysinfo.sh —— 系统信息 + 存储分析（inxi / duf / ncdu）
#
# 硬件/系统摘要、磁盘使用、交互式目录分析。工具未装时自动提示安装。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash sysinfo.sh [sys|disks|install]
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

si_log() { echo -e "  ${DT_CYAN}[sysinfo]${DT_NC} $*"; }
si_err() { echo -e "  ${DT_RED}[sysinfo] 错误:${DT_NC} $*" >&2; }

si_has() { command -v "$1" >/dev/null 2>&1; }

si_sysinfo() { # 硬件/系统摘要（inxi 或 /proc 回退）
    if si_has inxi; then
        inxi -Fxxxz 2>/dev/null
    else
        echo -e "  ${DT_YELLOW}inxi 未装，用 /proc 基础信息（装 inxi 更全: bash $(basename "$0") install）${DT_NC}"
        echo
        echo -e "  ${DT_BOLD}发行版:${DT_NC} $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
        echo -e "  ${DT_BOLD}内核:${DT_NC}   $(uname -r)"
        echo -e "  ${DT_BOLD}主机:${DT_NC}   $(hostname)"
        echo -e "  ${DT_BOLD}CPU:${DT_NC}    $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
        echo -e "  ${DT_BOLD}内存:${DT_NC}   $(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
        echo -e "  ${DT_BOLD}会话:${DT_NC}   ${XDG_SESSION_TYPE:-未知} / ${XDG_CURRENT_DESKTOP:-未知}"
    fi
}

si_disks() { # 磁盘使用（duf 或 df 回退）
    if si_has duf; then
        duf 2>/dev/null
    else
        echo -e "  ${DT_YELLOW}duf 未装，用 df 回退（装 duf 更直观: bash $(basename "$0") install）${DT_NC}"
        df -h 2>/dev/null | grep -vE '^tmpfs|^devtmpfs' | head -12
    fi
}

si_dirscan() { # 交互式目录分析（需 ncdu + 交互终端）
    if ! si_has ncdu; then
        si_err "ncdu 未装。先安装: bash $(basename "$0") install"
        return 1
    fi
    if [ ! -t 0 ]; then
        si_err "ncdu 需要交互终端。请在一个终端里运行。"
        return 1
    fi
    local dir
    dir=$(dt_ask_text "目录分析" "输入要分析的目录（回车=根目录 /）" "/") || return 0
    [ -n "$dir" ] || dir="/"
    ncdu "$dir"
}

si_install() {
    local -a need=()
    for t in inxi duf ncdu; do si_has "$t" || need+=("$t"); done
    [ "${#need[@]}" -eq 0 ] && { si_log "工具已装齐"; return 0; }
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        si_err "安装 ${need[*]} 需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    si_log "安装 ${need[*]} ..."
    sudo dnf install -y "${need[@]}" || { si_err "安装失败"; return 1; }
    si_log "安装完成"
}

si_status() {
    echo "=== 系统信息工具状态 ==="
    for t in inxi duf ncdu; do
        si_has "$t" && echo "  ✅ $t" || echo "  ❌ $t（未装）"
    done
}

si_menu() {
    while true; do
        local c
        c=$(dt_menu "系统信息 + 存储分析" "硬件摘要 / 磁盘使用 / 目录分析：" \
            "sys|1. 系统摘要|发行版/内核/CPU/内存/会话(inxi)" \
            "disks|2. 磁盘使用|duf 直观显示各挂载点使用" \
            "dir|3. 目录分析|ncdu 交互式找大文件(需终端)" \
            "install|4. 安装工具|inxi/duf/ncdu（需 sudo）" \
            "status|5. 状态|已装/未装" \
            "back|← 返回|") || return 0
        case "$c" in
            sys) si_sysinfo ;;
            disks) si_disks ;;
            dir) si_dirscan ;;
            install) si_install ;;
            status) si_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    sys) si_sysinfo ;;
    disks) si_disks ;;
    install) si_install ;;
    status) si_status ;;
    *) si_menu ;;
esac
