#!/usr/bin/env bash
# =============================================================================
# speedtest.sh —— 网络测速（speedtest-cli）
#
# 测下行/上行/延迟。受限网络可能偏慢或超时，加 --timeout 限制。
# 注册 main.sh 网络子菜单。
#
# 用法: bash speedtest.sh [run|install|status]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
log() { echo "  [speedtest] $*"; }
err() { echo "  [speedtest] 错误: $*" >&2; }

sp_has() { command -v speedtest-cli >/dev/null 2>&1; }

sp_install() {
    if sp_has; then log "speedtest-cli 已装"; return 0; fi
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        err "安装需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    log "安装 speedtest-cli ..."
    sudo dnf install -y speedtest-cli || { err "安装失败"; return 1; }
    log "安装完成"
}

sp_run() {
    if ! sp_has; then
        err "speedtest-cli 未装。先安装: bash $(basename "$0") install"
        return 1
    fi
    log "开始测速（受限网络可能慢，超时 30 秒/请求）..."
    speedtest-cli --simple --timeout 30 2>/dev/null || speedtest-cli --timeout 30 2>/dev/null \
        || { err "测速失败（网络受限或服务器不可达）。可稍后重试。"; return 1; }
}

sp_status() {
    echo "=== 网络测速状态 ==="
    sp_has && echo "  ✅ speedtest-cli 已装" || echo "  ❌ speedtest-cli 未装"
}

sp_menu() {
    while true; do
        local c
        c=$(dt_menu "网络测速" "speedtest-cli 测下行/上行/延迟：" \
            "run|1. 测速|Ping/Download/Upload（约 30 秒）" \
            "install|2. 安装 speedtest-cli|需 sudo" \
            "status|3. 状态|已装/未装" \
            "back|← 返回|") || return 0
        case "$c" in
            run) sp_run ;;
            install) sp_install ;;
            status) sp_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    run) sp_run ;;
    install) sp_install ;;
    status) sp_status ;;
    *) sp_menu ;;
esac
