#!/usr/bin/env bash
# =============================================================================
# niri-wlsunset.sh —— 护眼/夜间色温（wlsunset）
#
# 生成 ~/.config/niri/sun.kdl（spawn-at-startup 启动 wlsunset），主配置末尾加
# `include optional=true "sun.kdl"`(幂等)。自动日落需经纬度，手动固定只需温度。
# 与 tools.kdl/audio.kdl/dt-settings.kdl 各自独立 include。注册 main.sh WM 子菜单。
#
# 用法: bash niri-wlsunset.sh [on|off|status]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
log() { echo "  [niri-wlsunset] $*"; }
err() { echo "  [niri-wlsunset] 错误: $*" >&2; }

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
MAIN="$NIRI_DIR/config.kdl"
SUN="$NIRI_DIR/sun.kdl"
SUN_INCLUDE='include optional=true "sun.kdl"'
STATE="$NIRI_DIR/.sun-state"
ST_LAT="${SUN_LAT:-39.9}"; ST_LON="${SUN_LON:-116.4}"   # 默认北京
ST_NIGHT="${SUN_NIGHT:-4000}"; ST_DAY="${SUN_DAY:-6500}"

# 状态缓存（手动/自动模式参数）
st_set() { printf '%s\n' "$1" > "$STATE"; }
st_get() { cat "$STATE" 2>/dev/null | head -1; }

ensure_include() {
    grep -q 'sun\.kdl' "$MAIN" 2>/dev/null && return 0
    awk -v inc="$SUN_INCLUDE" '{ print } END { print ""; print "// dt-sun include (niri-wlsunset.sh 管理)"; print inc }' "$MAIN" > "$MAIN.tmp" \
        && mv "$MAIN.tmp" "$MAIN"
    log "已在主配置末尾加入 include sun.kdl"
}

remove_include() {
    awk -v inc="$SUN_INCLUDE" '
        /dt-sun include/ { skip=1; next }
        skip && /^include optional=true "sun.kdl"/ { skip=0; next }
        { print }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    log "已从主配置移除 include sun.kdl"
}

# --- 生成 sun.kdl（spawn-at-startup 启动 wlsunset，自动日落需坐标） ---
gen_sun() {
    st_set auto
    cat > "$SUN" <<KDL
// 由 desktop-toolkit niri-wlsunset.sh 生成；请用工具修改，手改可能被覆盖。
spawn-at-startup "wlsunset -L $ST_LAT -l $ST_LON -t $ST_NIGHT -T $ST_DAY"
KDL
    log "sun.kdl 已生成: wlsunset -L $ST_LAT -l $ST_LON -t $ST_NIGHT -T $ST_DAY"
}

install_pkgs() {
    command -v wlsunset >/dev/null 2>&1 && { log "wlsunset 已装"; return 0; }
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        err "安装 wlsunset 需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    log "安装 wlsunset ..."
    if ! sudo dnf install -y wlsunset; then
        err "安装失败，请手动: sudo dnf install wlsunset"
        return 1
    fi
    log "wlsunset 安装完成"
}

do_on() {
    install_pkgs || return 1
    gen_sun
    ensure_include
    # 立即生效（杀掉旧的再启动新的）
    pkill -x wlsunset 2>/dev/null || true
    nohup wlsunset -L "$ST_LAT" -l "$ST_LON" -t "$ST_NIGHT" -T "$ST_DAY" >/dev/null 2>&1 &
    command -v niri >/dev/null 2>&1 && niri msg action load-config-file 2>/dev/null || true
    log "色温已开启（坐标 $ST_LAT,$ST_LON  夜 $ST_NIGHT K / 日 $ST_DAY K）"
}

do_off() {
    pkill -x wlsunset 2>/dev/null && log "已停止 wlsunset" || log "wlsunset 未在运行"
    rm -f "$SUN"
    remove_include
    st_set off
    command -v niri >/dev/null 2>&1 && niri msg action load-config-file 2>/dev/null || true
    log "已移除 sun.kdl 与 include"
}

sun_status() {
    echo "=== niri 护眼色温 状态 ==="
    command -v wlsunset >/dev/null 2>&1 && echo "  ✅ wlsunset 已装" || echo "  ❌ wlsunset 未装"
    pgrep -x wlsunset >/dev/null 2>&1 && echo "  ✅ wlsunset 运行中" || echo "  ❌ wlsunset 未运行"
    echo "  模式: $(st_get 未设置)   夜温: $ST_NIGHT K   日温: $ST_DAY K   坐标: $ST_LAT,$ST_LON"
    [ -f "$SUN" ] && echo "  ✅ sun.kdl 已生成" || echo "  ❌ sun.kdl 未生成"
    grep -q 'sun\.kdl' "$MAIN" 2>/dev/null && echo "  ✅ 主配置已 include sun.kdl" || echo "  ❌ 未 include"
}

menu() {
    while true; do
        local c
        c=$(dt_menu "niri 护眼色温" "wlsunset 夜间调暖屏幕，避免刺眼。自动模式按经纬度算日出日落：" \
            "on|开启色温|自动日落（按当前参数，默认北京坐标）" \
            "off|关闭|停止进程 + 移除自启" \
            "cfg|设置参数|纬度/经度/夜温/日温" \
            "status|状态|进程/参数/include" \
            "back|← 返回|") || return 0
        case "$c" in
            on) do_on ;;
            off) do_off ;;
            cfg) menu_cfg ;;
            status) sun_status ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

menu_cfg() {
    local c
    c=$(dt_menu "色温参数" "当前: 坐标 $ST_LAT,$ST_LON  夜 $ST_NIGHT K  日 $ST_DAY K" \
        "lat|纬度(北正南负)|如北京 39.9 / 广州 23.1" \
        "lon|经度(东正西负)|如北京 116.4 / 广州 113.3" \
        "night|夜间温度 K|3000-6500(越低越暖)" \
        "day|白天温度 K|4000-6500(越高越接近日光)" \
        "back|← 返回|") || return 0
    case "$c" in
        lat) local v; v=$(dt_ask_text "纬度" "北正南负，如 39.9" "$ST_LAT") || return 0; ST_LAT="$v" ;;
        lon) v=$(dt_ask_text "经度" "东正西负，如 116.4" "$ST_LON") || return 0; ST_LON="$v" ;;
        night) v=$(dt_ask_num "夜间温度" "3000-6500 K（越低越暖）" "$ST_NIGHT" 3000 6500 100) || return 0; ST_NIGHT="$v" ;;
        day) v=$(dt_ask_num "白天温度" "4000-6500 K（越高越接近日光）" "$ST_DAY" 4000 6500 100) || return 0; ST_DAY="$v" ;;
        __quit) exit 0 ;;
        back) return 0 ;;
    esac
    log "已更新参数。如需生效请重新执行1.或2.。"
}

case "${1:-}" in
    on) do_on ;;
    off) do_off ;;
    status) sun_status ;;
    *) menu ;;
esac
