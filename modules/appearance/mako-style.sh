#!/usr/bin/env bash
# =============================================================================
# mako-style.sh —— mako 通知样式（透明/圆角/位置/字体）
#
# 生成 ~/.config/mako/config。注意：DMS 桌面外壳会屏蔽 mako 服务（DMS 自带
# 通知中心，mako 抢通知总线名会导致 DMS 顶栏起不来），本模块会检测 mako 状态，
# 若被屏蔽则明确提示"样式不会生效"（不会自动解除屏蔽，避免破坏 DMS）。
# 注册 main.sh 外观子菜单。
#
# 用法: bash mako-style.sh [status|apply <预设>]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
log() { echo "  [mako-style] $*"; }
err() { echo "  [mako-style] 错误: $*" >&2; }

MAKO_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/mako/config"
MK_STATE="$MAKO_CONF"

mako_masked() { # mako 是否被 systemd 屏蔽（DMS 环境常见）；systemctl 对 masked 返回非零，用 $() 收集
    local s
    s=$(systemctl --user is-enabled mako.service 2>/dev/null || true)
    [ "$s" = masked ]
}

mako_active() {
    local s
    s=$(systemctl --user is-active mako.service 2>/dev/null || true)
    [ "$s" = active ]
}

gen_config() { # <预设: translucent|compact|default>
    local preset="$1"
    mkdir -p "$(dirname "$MAKO_CONF")"
    case "$preset" in
        translucent)
            cat > "$MAKO_CONF" <<'CONF'
font=Noto Sans CJK SC 11
background-color=#000000D9
text-color=#FFFFFF
border-color=#00000000
border-size=2
border-radius=12
width=380
height=140
margin=16
padding=14
default-timeout=6000
anchor=top-right
layer=overlay
CONF
            ;;
        compact)
            cat > "$MAKO_CONF" <<'CONF'
font=Noto Sans CJK SC 10
background-color=#1E1E2ED9
text-color=#CDD6F4
border-color=#89B4FACC
border-size=1
border-radius=8
width=320
height=100
margin=10
padding=10
default-timeout=5000
anchor=top-right
CONF
            ;;
        default)
            rm -f "$MAKO_CONF"
            log "已移除 mako 配置（恢复默认）"
            return 0
            ;;
    esac
    log "已写入 mako 配置（预设: $preset）"
}

apply_preset() { # <预设>
    local preset="$1"
    if mako_masked; then
        log "⚠ 当前 mako 服务被 systemd 屏蔽（常见于 DMS 桌面外壳，DMS 自带通知中心）。"
        log "  已写入配置但【不会生效】。若要 mako 通知，需先解除屏蔽："
        log "    systemctl --user unmask mako.service"
        log "  （注意：DMS 环境下解除屏蔽可能让 DMS 顶栏的通知起不来，请知情后再动。）"
    fi
    gen_config "$preset"
    # 若 mako 在跑则热重载
    if mako_active; then
        command -v makoctl >/dev/null 2>&1 && makoctl reload 2>/dev/null || true
        log "已热重载 mako"
    fi
}

mako_status() {
    echo "=== mako 通知样式状态 ==="
    if mako_masked; then
        echo "  ⚠ mako.service 被 systemd 屏蔽（DMS 环境常见，样式不会生效）"
    elif mako_active; then
        echo "  ✅ mako 运行中"
    else
        echo "  ❌ mako 未运行"
    fi
    [ -f "$MAKO_CONF" ] && echo "  ✅ mako 配置存在: $MAKO_CONF" || echo "  ❌ mako 配置不存在（默认样式）"
    echo "  当前预设: $(grep -q 'border-radius=12' "$MAKO_CONF" 2>/dev/null && echo translucent || (grep -q 'border-radius=8' "$MAKO_CONF" 2>/dev/null && echo compact || echo 默认))"
}

menu() {
    while true; do
        local c
        c=$(dt_menu "mako 通知样式" "透明/圆角/位置。当前环境 mako 状态见下：" \
            "translucent|1. 透明圆角|黑色半透明 + 大圆角(12px) + 右上角" \
            "compact|2. 紧凑深色|猫猫配色 + 小圆角(8px) + 短超时" \
            "default|3. 恢复默认|删除 mako 配置" \
            "status|4. 状态|mako 服务/配置/预设" \
            "back|← 返回|") || return 0
        case "$c" in
            translucent) apply_preset translucent ;;
            compact) apply_preset compact ;;
            default) apply_preset default ;;
            status) mako_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    status) mako_status ;;
    apply) [ -n "${2:-}" ] && apply_preset "$2" || err "用法: mako-style.sh apply <translucent|compact|default>" ;;
    *) menu ;;
esac
