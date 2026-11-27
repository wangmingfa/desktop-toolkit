#!/usr/bin/env bash
# =============================================================================
# 窗口按钮布局调整（GTK / Electron 客户端装饰）
# -----------------------------------------------------------------------------
# 统一改 org.gnome.desktop.wm.preferences button-layout，作用于所有带客户端
# 装饰(CSD)的 GTK/Electron 应用（Capy / 浏览器 / 设置等）。
#
# 背景(踩坑): Capy 侧栏折叠后其"展开按钮"出现在左上角；若窗口按钮也在左边
# (macOS 风格, close,minimize,maximize:)，关闭按钮正好压在展开按钮上。
# 彻底解决只能把按钮移到右边——没有"既左又避开"的布局。
#
# 用法: window-buttons.sh [left|right|status|menu]
#   left    macOS 风格: close,minimize,maximize:  (关闭在最左)
#   right   Windows 风格: :minimize,maximize,close (关闭在最右)
#   status  打印当前布局
#   无参数  打开交互菜单(GUI/TUI 自适应)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/ui.sh"

log() { dt_log "$*"; }
err() { dt_err "$*"; }

SCHEMA="org.gnome.desktop.wm.preferences"
GKEY="button-layout"

# 预设
LAYOUT_MACOS="close,minimize,maximize:"       # 左 macOS
LAYOUT_WIN=":minimize,maximize,close"         # 右 Windows (关闭最右)
LAYOUT_GENOME="appmenu:minimize,maximize,close"  # GNOME 默认

# 允许的按钮 token（含 appmenu，用于自定义校验）
TOKENS="close,minimize,maximize,appmenu"

# ---------------------------------------------------------------------------
# 读取/校验
# ---------------------------------------------------------------------------
get_layout() {
    gsettings get "$SCHEMA" "$GKEY" 2>/dev/null | sed "s/^'//; s/'$//" || true
}

schema_ok() {
    gsettings get "$SCHEMA" "$GKEY" >/dev/null 2>&1
}

# 校验 button-layout 格式: 一个冒号, 左侧/右侧各为逗号分隔的合法 token 且不重复
valid_layout() {
    local v="$1"
    local left right tok t
    [ -n "$v" ] || return 1
    [[ "$v" == *":"* ]] || return 1
    left="${v%%:*}"
    right="${v#*:}"
    # 冒号只能有一个
    [[ "$right" != *":"* ]] || return 1
    local -a seen=()
    for side in "$left" "$right"; do
        [ -n "$side" ] || continue
        IFS=',' read -ra toks <<< "$side"
        for t in "${toks[@]}"; do
            [ -n "$t" ] || return 1
            case ",$TOKENS," in
                *",$t,"*) ;;
                *) return 1 ;;
            esac
            for s in "${seen[@]}"; do [ "$s" = "$t" ] && return 1; done
            seen+=("$t")
        done
    done
    return 0
}

# ---------------------------------------------------------------------------
# 应用
# ---------------------------------------------------------------------------
apply_layout() { # value desc
    local v="$1" desc="${2:-}"
    if ! valid_layout "$v"; then
        err "无效布局 \"$v\"（格式: 左列表:右列表，token ∈ $TOKENS）"
        return 1
    fi
    gsettings set "$SCHEMA" "$GKEY" "$v" || { err "设置失败"; return 1; }
    local now
    now=$(get_layout)
    [ "$now" = "$v" ] || { err "设置后校验失败（当前 $now）"; return 1; }
    log "已应用: ${desc:+$desc }($v)"
    dt_info "窗口按钮布局已改为：\n  $v\n\n${desc:+$desc\n}\nGTK / Electron 应用需重启才生效（Capy 关掉重开）。"
}

apply_macos() {
    dt_confirm "设为 macOS 左边风格（$LAYOUT_MACOS）？\n\n⚠ 注意：若在使用 Capy 等应用，折叠侧栏后的\"展开按钮\"会被左上角关闭按钮遮挡（Capy 布局 bug），建议改用右边风格。" || return 0
    apply_layout "$LAYOUT_MACOS" "macOS 左边（关闭在最左）"
}

apply_win() {
    apply_layout "$LAYOUT_WIN" "Windows 右边（关闭在最右）"
}

apply_custom() {
    local v
    v=$(dt_ask_text "自定义按钮布局" "格式: 左列表:右列表，token ∈ close,minimize,maximize（可含 appmenu）" "$(get_layout)") || return 0
    [ -n "$v" ] || return 0
    apply_layout "$v" "自定义"
}

# ---------------------------------------------------------------------------
# 交互菜单
# ---------------------------------------------------------------------------
menu() {
    while true; do
        local cur
        cur=$(get_layout)
        local c
        c=$(dt_menu "窗口按钮布局" "当前：$cur（作用于所有 GTK/Electron 客户端装饰窗口）" \
            "macos|macOS 左边风格|close,minimize,maximize: 关闭在左（Capy 会重叠，慎用）" \
            "win|Windows 右边风格|:minimize,maximize,close 关闭在最右（推荐，避 Capy 重叠）" \
            "gnome|GNOME 默认|appmenu:minimize,maximize,close" \
            "custom|自定义布局|输入完整 button-layout 值" \
            "status|查看当前|打印当前值" \
            "back|← 返回|") || return 0
        case "$c" in
            macos) apply_macos ;;
            win) apply_win ;;
            gnome) apply_layout "$LAYOUT_GENOME" "GNOME 默认" ;;
            custom) apply_custom ;;
            status) echo "当前 button-layout: $(get_layout)" ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------
if ! schema_ok; then
    echo "错误: 当前环境无 org.gnome.desktop.wm.preferences 模式（非 GNOME/GTK 环境），无法调整窗口按钮布局。" >&2
    exit 1
fi

case "${1:-menu}" in
    left) apply_macos ;;
    right) apply_win ;;
    status) echo "当前 button-layout: $(get_layout)" ;;
    menu) menu ;;
    *) echo "用法: window-buttons.sh [left|right|status|menu]" >&2; exit 1 ;;
esac
