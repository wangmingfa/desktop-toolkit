#!/usr/bin/env bash
# =============================================================================
# bluetooth.sh —— 蓝牙管理（开关 / 扫描 / 配对设备连接）
#
# 基于 bluez 的 bluetoothctl（Fedora 官方源）。无蓝牙硬件时只读提示。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash bluetooth.sh [status|on|off|scan]
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

bt_log() { echo -e "  ${DT_CYAN}[bluetooth]${DT_NC} $*"; }
bt_err() { echo -e "  ${DT_RED}[bluetooth] 错误:${DT_NC} $*" >&2; }

bt_has() { command -v bluetoothctl >/dev/null 2>&1; }
bt_powered() { bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; }
bt_hw() { # 有无蓝牙适配器（rfkill 或 sysfs 判断）
    [ -d /sys/class/bluetooth ] && ls /sys/class/bluetooth | grep -q . && return 0
    rfkill list 2>/dev/null | grep -qi bluetooth && return 0
    return 1
}

bt_status() {
    if ! bt_has; then
        echo -e "  ${DT_YELLOW}bluetoothctl 未安装。${DT_NC}"
        echo "  安装: sudo dnf install -y bluez"
        return 1
    fi
    if ! bt_hw; then
        echo -e "  ${DT_YELLOW}未检测到蓝牙适配器（可能无蓝牙硬件）。${DT_NC}"
        return 1
    fi
    local svc powered
    svc=$(systemctl is-active bluetooth 2>/dev/null || echo inactive)
    bt_powered && powered="开" || powered="关"
    echo -e "  ${DT_BOLD}蓝牙服务:${DT_NC} $svc   ${DT_BOLD}适配器:${DT_NC} $powered"
    echo
    echo "  已配对设备:"
    if bluetoothctl devices 2>/dev/null | grep -q .; then
        bluetoothctl devices 2>/dev/null | sed 's/^/    /'
    else
        echo "    （无）"
    fi
}

bt_on() {
    bt_has || { bt_err "bluetoothctl 未安装"; return 1; }
    sudo systemctl start bluetooth 2>/dev/null
    bluetoothctl power on 2>/dev/null
    bt_powered && bt_log "蓝牙已开启" || bt_err "开启失败"
}

bt_off() {
    bluetoothctl power off 2>/dev/null
    bt_powered && bt_err "关闭失败" || bt_log "蓝牙已关闭"
}

bt_scan() { # 扫描 12 秒
    bt_powered || { bt_err "蓝牙未开启"; return 1; }
    bt_log "扫描 12 秒（新设备会显示在下方）..."
    bluetoothctl --timeout 12 scan on 2>/dev/null | grep -E "Device|NEW|discovered" | head -20
    bt_log "扫描结束"
}

bt_devices() { bluetoothctl devices 2>/dev/null | sed 's/^Device /  /'; }

bt_connect() { # <mac>
    local mac="$1"
    bluetoothctl connect "$mac" 2>/dev/null | grep -qi "Connection successful" \
        && bt_log "已连接 $mac" || bt_err "连接失败 $mac（可能需要先配对）"
}

bt_menu() {
    while true; do
        local c
        c=$(dt_menu "蓝牙管理" "蓝牙开关 / 扫描 / 连接配对设备：" \
            "status|1. 查看状态|服务/适配器/已配对设备" \
            "on|2. 开启蓝牙|启动服务 + 适配器上电" \
            "off|3. 关闭蓝牙|适配器下电" \
            "scan|4. 扫描附近设备|12 秒（需蓝牙开启）" \
            "back|← 返回|") || return 0
        case "$c" in
            status) bt_status ;;
            on) bt_on ;;
            off) bt_off ;;
            scan) bt_scan ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    status) bt_status ;;
    on) bt_on ;;
    off) bt_off ;;
    scan) bt_scan ;;
    *) bt_menu ;;
esac
