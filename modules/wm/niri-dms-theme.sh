#!/usr/bin/env bash
# =============================================================================
# DMS 顶栏/全局主题美化（dms matugen 生成 Material 主题）
# -----------------------------------------------------------------------------
# DMS 用 dms matugen generate 从"主色 hex 或壁纸图"生成 Material 主题并同步
# 到 DMS 顶栏 + niri colors.kdl + gtk/fcitx5/终端等(dms matugen check 探测)。
# 这是 DMS 官方主题机制(顶栏 QML 颜色即来自生成的色板)。
#
# 用法: niri-dms-theme.sh [hex|image|dark|light|status|menu]
#   hex <color>    按主色生成(dark/light 由 --mode)
#   image <path>   从壁纸图生成
#   dark|light     切换模式后重新生成(需 --value 已在状态缓存, 实际以 hex 为主)
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

log() { dt_log "$*"; }
err() { dt_err "$*"; }

# 当前主题状态(上次生成的 kind/value/mode)，供 dark/light 复用
DMS_STATE="$HOME/.config/dms/.dt-theme"
WALL="$HOME/.config/niri/wallpaper.kdl"

st_get() { # key default
    [ -f "$DMS_STATE" ] || { echo "$2"; return; }
    awk -v k="$1" '$1==k {print $2; exit}' "$DMS_STATE" 2>/dev/null || echo "$2"
}
st_set() { # key value
    local k="$1" v="$2" f="$DMS_STATE"
    mkdir -p "$(dirname "$f")"
    if [ -f "$f" ]; then
        awk -v k="$k" -v v="$v" 'BEGIN{f=0} $1==k{print k" "v; f=1; next} {print} END{if(!f)print k" "v}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
        printf '%s %s\n' "$k" "$v" > "$f"
    fi
}

wallpaper_path() {
    [ -f "$WALL" ] && sed -n 's/.*background-image "\([^"]*\)".*/\1/p' "$WALL" | head -1
}

gen_theme() { # kind value mode
    local kind="$1" value="$2" mode="${3:-dark}"
    [ -n "$value" ] || { err "缺少主题源(主色/壁纸)"; return 1; }
    command -v dms >/dev/null 2>&1 || { err "未找到 dms"; return 1; }
    log "生成 DMS Material 主题: $kind $value ($mode) ... 可能耗时几十秒"
    if dms matugen generate --kind "$kind" --value "$value" --mode "$mode" --spec dms; then
        st_set kind "$kind"; st_set value "$value"; st_set mode "$mode"
        log "✅ DMS 主题已应用(顶栏 + niri colors + gtk/fcitx5/终端)"
    else
        err "matugen 生成失败(可检查 dms matugen check / 是否装了 matugen)"
        return 1
    fi
}

apply_hex() {
    local mode="${1:-dark}"
    local v
    v=$(dt_ask_text "主色" "输入主色 hex(如 7c9bff) 或留空用上次" "$(st_get value '')") || return 0
    [ -n "$v" ] || return 0
    # 规范化 hex(允许无 #)
    [[ "$v" =~ ^[0-9a-fA-F]{6}$ ]] && v="#$v"
    gen_theme hex "$v" "$mode"
}

apply_image() {
    local img="$1" mode="${2:-dark}"
    [ -z "$img" ] && img=$(wallpaper_path)
    if [ -z "$img" ] || [ ! -f "$img" ]; then
        img=$(dt_ask_text "壁纸路径" "输入壁纸图(需已设置 niri 壁纸)" "") || return 0
    fi
    [ -f "$img" ] || { err "壁纸不存在: $img"; return 0; }
    gen_theme image "$img" "$mode"
}

apply_mode() { # dark|light
    local mode="$1" kind value
    kind=$(st_get kind hex); value=$(st_get value '')
    [ -n "$value" ] || { err "尚未生成过主题，请先按主色或壁纸生成"; return 0; }
    gen_theme "$kind" "$value" "$mode"
}

status() {
    echo "=== DMS 主题 ==="
    echo "  上次: $(st_get kind '') $(st_get value '') / $(st_get mode '')"
    echo "=== 探测(可同步的应用) ==="
    # 收集到变量再显示: 避免 head 提前关闭导致 python3 SIGPIPE(set -o pipefail 下误判)
    local apps
    apps=$(dms matugen check 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); [print("  " + ("✅" if x["detected"] else "  ") + " " + x["id"]) for x in d]' 2>/dev/null) || apps="  (matugen check 不可用)"
    echo "$apps" | head -12
}

menu() {
    while true; do
        local c
        c=$(dt_menu "DMS 顶栏主题" "dms matugen 生成 Material 主题(顶栏+niri+gtk+终端)" \
            "hex|1. 按主色生成|输入 hex 主色(深色默认)" \
            "image|2. 从壁纸生成|用当前 niri 壁纸图" \
            "light|3. 浅色模式|重新生成 light" \
            "dark|4. 深色模式|重新生成 dark" \
            "status|5. 查看状态|上次主题 + 可同步应用" \
            "back|← 返回|") || return 0
        case "$c" in
            hex) apply_hex dark ;;
            image) apply_image ;;
            light) apply_mode light ;;
            dark) apply_mode dark ;;
            status) status ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    hex) apply_hex "${2:-dark}" ;;
    image) apply_image "${2:-}" ;;
    dark) apply_mode dark ;;
    light) apply_mode light ;;
    status) status ;;
    menu) menu ;;
    *) echo "用法: niri-dms-theme.sh [hex|image|dark|light|status|menu]" >&2; exit 1 ;;
esac
