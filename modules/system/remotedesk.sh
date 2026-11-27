#!/usr/bin/env bash
# =============================================================================
# remotedesk.sh —— 远程桌面（xrdp RDP / tigervnc VNC）
#
# 安装并启用 RDP(xrdp, 3389) 或 VNC(tigervnc, 5901)，查看状态，关闭。
# 涉及安全：开放远程端口有风险，明确提示用后关闭。Wayland 会话远程桌面
# 支持有限，RDP 走 Xorg 会话（需装 Xorg GNOME 会话）。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash remotedesk.sh [xrdp|vnc|status|off]
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

rd_log() { echo -e "  ${DT_CYAN}[remotedesk]${DT_NC} $*"; }
rd_err() { echo -e "  ${DT_RED}[remotedesk] 错误:${DT_NC} $*" >&2; }

rd_need_sudo() {
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        rd_err "操作需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    return 0
}

rd_firewall() { # <port> —— 开放防火墙端口（幂等）
    sudo firewall-cmd --permanent --add-port="$1/tcp" >/dev/null 2>&1 && \
        sudo firewall-cmd --reload >/dev/null 2>&1
}

rd_xrdp() { # 安装并启用 RDP
    rd_need_sudo || return 1
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  ${DT_YELLOW}⚠ 远程桌面有安全风险：开放 RDP 端口后局域网内任何设备可尝试连接。${DT_NC}"
    dt_confirm "安装并启用 xrdp（RDP 端口 3389）？\n需 sudo 密码 + 防火墙开放 3389。\n\n继续？" || return 0
    rd_log "安装 xrdp ..."
    sudo dnf install -y xrdp || { rd_err "安装失败"; return 1; }
    sudo systemctl enable --now xrdp 2>/dev/null || rd_err "xrdp 服务启动失败"
    rd_firewall 3389
    rd_log "✅ xrdp 已启用。远程客户端连 ${ip:-本机IP}:3389（RDP）。"
    rd_log "Wayland 会话支持有限；若连不上需装 Xorg GNOME 会话（sudo dnf install gnome-session-xsession）。"
}

rd_vnc() { # 安装 VNC + 提示配置
    rd_need_sudo || return 1
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  ${DT_YELLOW}⚠ VNC 需设置独立密码（vncpasswd），开放 5901 端口。${DT_NC}"
    dt_confirm "安装 tigervnc-server（VNC 端口 5901）？\n需 sudo 密码 + 防火墙开放 5901。\n\n继续？" || return 0
    rd_log "安装 tigervnc-server ..."
    sudo dnf install -y tigervnc-server || { rd_err "安装失败"; return 1; }
    rd_firewall 5901
    rd_log "✅ tigervnc 已装。请在一个终端里完成配置："
    rd_log "  1) vncpasswd            # 设 VNC 密码"
    rd_log "  2) vncserver            # 启动（首次会提示配置，默认 :1 = 5901）"
    rd_log "  远程客户端连 ${ip:-本机IP}:5901（VNC）。"
}

rd_status() {
    echo -e "  ${DT_BOLD}═══ 远程桌面状态 ═══${DT_NC}"
    local xrdp_st vnc_st
    # is-active 对 inactive 输出 "inactive" 且退出非零；用 || true 保留输出, 别追加 echo
    xrdp_st=$(systemctl is-active xrdp 2>/dev/null || true)
    vnc_st=$(systemctl is-active vncserver@:1 2>/dev/null || true)
    echo "  RDP (xrdp, 3389):  ${xrdp_st:-inactive}"
    echo "  VNC (vncserver@:1): ${vnc_st:-inactive}"
    echo "  本机 IP: $(hostname -I 2>/dev/null | awk '{print $1}')"
}

rd_off() {
    rd_need_sudo || return 1
    dt_confirm "关闭远程桌面（停用 xrdp + vncserver@:1）？\n需 sudo 密码。\n\n继续？" || return 0
    sudo systemctl disable --now xrdp 2>/dev/null; sudo systemctl disable --now vncserver@:1 2>/dev/null
    sudo firewall-cmd --permanent --remove-port=3389/tcp >/dev/null 2>&1
    sudo firewall-cmd --permanent --remove-port=5901/tcp >/dev/null 2>&1
    sudo firewall-cmd --reload >/dev/null 2>&1
    rd_log "已关闭远程桌面并移除防火墙端口（3389/5901）"
}

rd_menu() {
    while true; do
        local c
        c=$(dt_menu "远程桌面" "xrdp RDP / tigervnc VNC（开放端口有风险，用后关闭）：" \
            "xrdp|安装启用 RDP|xrdp 端口 3389（需 sudo + 防火墙）" \
            "vnc|安装 VNC|tigervnc 端口 5901（需 sudo + vncpasswd）" \
            "status|查看状态|RDP/VNC 服务 + 本机 IP" \
            "off|关闭远程|停服务 + 移除防火墙端口" \
            "back|← 返回|") || return 0
        case "$c" in
            xrdp) rd_xrdp ;;
            vnc) rd_vnc ;;
            status) rd_status ;;
            off) rd_off ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    xrdp) rd_xrdp ;;
    vnc) rd_vnc ;;
    status) rd_status ;;
    off) rd_off ;;
    *) rd_menu ;;
esac
