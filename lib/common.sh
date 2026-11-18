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

# =============================================================================
# 国内网络 / GitHub 镜像加速
#   涉及 GitHub 的资源（主题/图标/光标仓库）在部分网络下慢或不可达，
#   可用国内镜像加速。通过环境变量控制，方便复用：
#     DT_MIRROR=auto|ghproxy|gitclone|off   (默认 auto: 先直连, 失败自动走镜像)
#     GH_PROXY=<https://xxx>                (ghproxy 镜像前缀, 可换)
#   注意: ghproxy 类镜像站地址会变动, 失效时改 GH_PROXY 即可。
# =============================================================================
DT_MIRROR="${DT_MIRROR:-auto}"
GH_PROXY="${GH_PROXY:-https://mirror.ghproxy.com}"

# 把 github 完整 URL 按当前镜像改写
dt_github() { # https://github.com/owner/repo(.git)
    local url="$1"
    case "$DT_MIRROR" in
        ghproxy) echo "$GH_PROXY/$url" ;;
        gitclone) echo "https://gitclone.com/$url" ;;
        *) echo "$url" ;;  # auto/off 原样返回(内部由 dt_clone 决定回退)
    esac
}

# 浅克隆仓库，带镜像回退：dt_clone <github_url> <dest> [branch]
dt_clone() {
    local url="$1" dest="$2" branch="${3:-}"
    local -a candidates=()
    case "$DT_MIRROR" in
        off)      candidates=("$url") ;;
        ghproxy)  candidates=("$(dt_github "$url")") ;;
        gitclone) candidates=("$(dt_github "$url")") ;;
        auto)     candidates=("$url" "$GH_PROXY/$url" "https://gitclone.com/$url") ;;
    esac
    rm -rf "$dest" 2>/dev/null || true
    local m
    for m in "${candidates[@]}"; do
        echo "  [git] 尝试: $m"
        # 强制 HTTP/1.1: 规避部分代理/镜像对 HTTP/2 流的重置
        if [ -n "$branch" ]; then
            git -c http.version=HTTP/1.1 clone --depth 1 -b "$branch" "$m" "$dest" >/dev/null 2>&1 && return 0
        else
            git -c http.version=HTTP/1.1 clone --depth 1 "$m" "$dest" >/dev/null 2>&1 && return 0
        fi
    done
    echo "  [git] 克隆失败(已尝试 ${#candidates[@]} 个源): $url" >&2
    return 1
}
