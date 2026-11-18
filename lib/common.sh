#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit / 公共函数库
# 所有模块 source 本文件即可获得：仓库根目录、DBUS 环境、备份、日志
# =============================================================================

# 仓库根目录 (本文件位于 <repo>/lib/common.sh)
DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 当前用户 UID / DBUS 会话地址 (脚本可能运行在容器里，需显式指向宿主会话)
DT_UID="$(id -u)"
DT_DBUS_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${DT_UID}/bus XDG_RUNTIME_DIR=/run/user/${DT_UID}"

dt_log() { echo "[desktop-toolkit] $*"; }
dt_err() { echo "[desktop-toolkit] 错误: $*" >&2; }

# 带时间戳备份一个配置文件： dt_backup ~/.config/kwinrc
dt_backup() {
    local f="$1"
    [ -f "$f" ] || return 0
    local bak="${f}.bak-dt-$(date +%Y%m%d-%H%M%S)"
    cp -a "$f" "$bak" && dt_log "已备份: $bak"
}

# 检测 GUI 工具：容器里是 zenity，宿主机 KDE 上是 kdialog
dt_detect_gui() {
    if command -v zenity >/dev/null 2>&1; then
        echo zenity
    elif command -v kdialog >/dev/null 2>&1; then
        echo kdialog
    else
        echo none
    fi
}
