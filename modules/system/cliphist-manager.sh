#!/usr/bin/env bash
# =============================================================================
# cliphist-manager.sh —— 剪贴板历史管理（cliphist）
#
# niri-tools 已绑 Super+V 查看剪贴板(fuzzel 菜单)，但缺 cliphist store 常驻
# （不常驻则历史为空）。本模块补: 安装 cliphist、启动历史记录服务
# (spawn-at-startup "cliphist store", 独立 cliphist.kdl include)、查看/清理/状态。
# 放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash cliphist-manager.sh [status|view|wipe|install|store-on]
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

ch_log() { echo -e "  ${DT_CYAN}[cliphist]${DT_NC} $*"; }
ch_err() { echo -e "  ${DT_RED}[cliphist] 错误:${DT_NC} $*" >&2; }

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
MAIN="$NIRI_DIR/config.kdl"
CLIP="$NIRI_DIR/cliphist.kdl"
CLIP_INCLUDE='include optional=true "cliphist.kdl"'

ch_has() { command -v cliphist >/dev/null 2>&1; }

# --- include 管理(awk -v 幂等) ---
ensure_include() {
    grep -q 'cliphist\.kdl' "$MAIN" 2>/dev/null && return 0
    awk -v inc="$CLIP_INCLUDE" '{ print } END { print ""; print "// dt-cliphist include (cliphist-manager.sh 管理)"; print inc }' "$MAIN" > "$MAIN.tmp" \
        && mv "$MAIN.tmp" "$MAIN"
    ch_log "已在主配置末尾加入 include cliphist.kdl"
}

remove_include() {
    [ -f "$MAIN" ] || return 0
    awk -v inc="$CLIP_INCLUDE" '
        /dt-cliphist include/ { skip=1; next }
        skip && /^include optional=true "cliphist.kdl"/ { skip=0; next }
        { print }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    ch_log "已从主配置移除 include cliphist.kdl"
}

ch_install() {
    if ch_has; then ch_log "cliphist 已装"; return 0; fi
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        ch_err "安装需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    ch_log "安装 cliphist（+wl-clipboard 依赖）..."
    sudo dnf install -y cliphist wl-clipboard || { ch_err "安装失败"; return 1; }
    ch_log "安装完成"
}

# 启动历史记录：spawn-at-startup + 立即启动（setsid 后台）
ch_store_on() {
    ch_has || ch_install || return 1
    mkdir -p "$NIRI_DIR"
    cat > "$CLIP" <<'KDL'
// 由 desktop-toolkit cliphist-manager.sh 生成；请用工具修改，手改可能被覆盖。
spawn-at-startup "cliphist store"
KDL
    ensure_include
    if ! pgrep -x cliphist >/dev/null 2>&1; then
        setsid cliphist store >/dev/null 2>&1 &
        ch_log "已启动 cliphist store"
    else
        ch_log "cliphist store 已在运行"
    fi
    command -v niri >/dev/null 2>&1 && timeout 5 niri msg reload-config 2>/dev/null || true
    ch_log "历史记录已开启（niri 启动时自动加载）"
}

ch_store_off() {
    pkill -x cliphist 2>/dev/null && ch_log "已停止 cliphist" || ch_log "cliphist 未运行"
    rm -f "$CLIP"
    remove_include
    command -v niri >/dev/null 2>&1 && timeout 5 niri msg reload-config 2>/dev/null || true
    ch_log "历史记录已关闭"
}

ch_view() { # fuzzel 选择历史项并复制回剪贴板
    ch_has || { ch_err "cliphist 未装，先安装"; return 1; }
    local sel
    sel=$(cliphist list 2>/dev/null | fuzzel --dmenu --no-run 2>/dev/null) || return 0
    [ -n "$sel" ] || return 0
    local id
    id=$(printf '%s' "$sel" | cut -f1)
    if cliphist decode "$id" 2>/dev/null | wl-copy 2>/dev/null; then
        ch_log "已复制回剪贴板"
    else
        ch_err "复制失败（需 wl-copy）"
    fi
}

ch_wipe() {
    ch_has || { ch_err "cliphist 未装"; return 1; }
    dt_confirm "清空全部剪贴板历史？" || return 0
    cliphist wipe 2>/dev/null && ch_log "已清空剪贴板历史" || ch_err "清空失败"
}

ch_status() {
    echo "=== 剪贴板历史状态 ==="
    ch_has && echo "  ✅ cliphist 已装" || echo "  ❌ cliphist 未装"
    pgrep -x cliphist >/dev/null 2>&1 && echo "  ✅ cliphist store 运行中" || echo "  ❌ cliphist store 未运行"
    local n
    if ch_has; then n=$(cliphist list 2>/dev/null | wc -l || true); else n=0; fi
    echo "  历史条数: $n"
    [ -f "$CLIP" ] && echo "  ✅ cliphist.kdl 已生成" || echo "  ❌ cliphist.kdl 未生成"
    grep -q 'cliphist\.kdl' "$MAIN" 2>/dev/null && echo "  ✅ 已 include" || echo "  ❌ 未 include"
    command -v fuzzel >/dev/null 2>&1 && echo "  ✅ fuzzel（选择菜单）" || echo "  ❌ fuzzel 未装"
}

ch_menu() {
    while true; do
        local c
        c=$(dt_menu "剪贴板历史管理" "cliphist 历史（niri-tools 的 Super+V 用于查看）：" \
            "install|1. 安装 cliphist|cliphist + wl-clipboard（需 sudo）" \
            "store-on|2. 启动历史记录|spawn-at-startup cliphist store + 立即启动" \
            "view|3. 查看/复制|fuzzel 选择历史项复制回剪贴板" \
            "wipe|4. 清空历史|cliphist wipe" \
            "store-off|5. 关闭历史记录|停 store + 移除自启" \
            "status|6. 状态|工具/store/条数/include" \
            "back|← 返回|") || return 0
        case "$c" in
            install) ch_install ;;
            store-on) ch_store_on ;;
            view) ch_view ;;
            wipe) ch_wipe ;;
            store-off) ch_store_off ;;
            status) ch_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    status) ch_status ;;
    view) ch_view ;;
    wipe) ch_wipe ;;
    install) ch_install ;;
    store-on) ch_store_on ;;
    store-off) ch_store_off ;;
    *) ch_menu ;;
esac
