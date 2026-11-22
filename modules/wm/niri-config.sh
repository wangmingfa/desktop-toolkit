#!/usr/bin/env bash
# =============================================================================
# niri-config.sh — Niri 可视化配置（TUI / GUI 自适应）
#
# 背景: niri 配置项太多记不住。本工具把常用项做成菜单, 改完自动生成 KDL、
#   `niri validate` 校验、失败回滚、并触发热重载。
#
# 写入策略(关键): 本工具【独占】~/.config/niri/dt-settings.kdl, 在主配置
#   config.kdl 末尾加一行 `include optional=true "dt-settings.kdl"`。
#     - niri 的 include 是"合并"语义、且"末尾优先", 所以本工具设的项会生效;
#     - 主配置里用户自己的其它设置不受影响(只覆盖本工具启用过的项);
#     - 只写"用户显式改过"的项, 没碰过的项不写, 不会静默覆盖主配置。
#   touchpad/mouse 是 niri 的"非合并段"(整块替换), 故本工具一旦调整就
#   完整重建该块, 并在首次调整时从主配置尽力播种现有值。
#
# 用法:  bash niri-config.sh            # 交互菜单(TUI/GUI 自适应)
#        bash niri-config.sh --show     # 打印当前设置与校验结果
#        bash niri-config.sh --uninstall# 移除 include + 本工具生成的文件
#
# 依赖: lib/common.sh、lib/ui.sh(dt_menu/dt_ask_* 自适应 zenity/kdialog/TUI)。
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 颜色(非 tty 退化为空串; 用 :- 兜底避免 set -u 下未绑定)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_BAD=$'\033[0;31m'
    C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'; C_NC=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_BAD=""; C_CYAN=""; C_BOLD=""; C_NC=""
fi

log() { echo "  [niri-config] $*"; }
err() { echo "  [niri-config] 错误: $*" >&2; }

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
MAIN="$NIRI_DIR/config.kdl"
SETTINGS="$NIRI_DIR/dt-settings.kdl"
STATE="$NIRI_DIR/.dt-settings.conf"
DEFAULT_CONFIG="/usr/share/doc/niri/default-config.kdl"

# ---------------------------------------------------------------------------
# 状态读写(仅存"显式设置"的项; key=value, value 到行尾)
# ---------------------------------------------------------------------------
state_get() { # key [default]
    local key="$1" def="${2:-}" line
    if [ -f "$STATE" ]; then
        while IFS= read -r line; do
            case "$line" in "$key="*) printf '%s' "${line#*=}"; return 0 ;; esac
        done < "$STATE"
    fi
    printf '%s' "$def"
}
state_has() { # key
    local key="$1" line
    [ -f "$STATE" ] || return 1
    while IFS= read -r line; do
        case "$line" in "$key="*) return 0 ;; esac
    done < "$STATE"
    return 1
}
state_set() { # key value
    local key="$1" val="$2" line tmp
    mkdir -p "$NIRI_DIR"
    tmp=$(mktemp)
    [ -f "$STATE" ] && { while IFS= read -r line; do case "$line" in "$key="*) ;; *) printf '%s\n' "$line" ;; esac; done < "$STATE" > "$tmp"; }
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$STATE"
}
state_unset() { # key
    local key="$1" line tmp
    [ -f "$STATE" ] || return 0
    tmp=$(mktemp)
    while IFS= read -r line; do case "$line" in "$key="*) ;; *) printf '%s\n' "$line" ;; esac; done < "$STATE" > "$tmp"
    mv "$tmp" "$STATE"
}
onoff() { [ "${1:-0}" = 1 ] && echo 开 || echo 关; }

# ---------------------------------------------------------------------------
# niri 版本(年龄门槛: blur 需 >= 26.04; optional include 需 >= 26.04)
# ---------------------------------------------------------------------------
niri_ver() { niri --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true; }
niri_ge_2604() {
    local v; v=$(niri_ver)
    [ -n "$v" ] || return 1
    local a=${v%.*} b=${v#*.}
    a=$((10#$a)); b=$((10#$b))
    [ "$a" -gt 26 ] || { [ "$a" -eq 26 ] && [ "$b" -ge 4 ]; }
}

# ---------------------------------------------------------------------------
# KDL 片段生成
# ---------------------------------------------------------------------------
gen_layout() {
    local body; body=$(mktemp)
    state_has gaps && printf '    gaps %s\n' "$(state_get gaps)" >> "$body"
    state_has center_focused && printf '    center-focused-column "%s"\n' "$(state_get center_focused)" >> "$body"
    state_has default_column_display && printf '    default-column-display "%s"\n' "$(state_get default_column_display)" >> "$body"
    state_has background_color && [ -n "$(state_get background_color)" ] && printf '    background-color "%s"\n' "$(state_get background_color)" >> "$body"

    if state_has focus_ring_on || state_has focus_ring_width || state_has focus_ring_active || state_has focus_ring_inactive; then
        printf '    focus-ring {\n' >> "$body"
        printf '        %s\n' "$( [ "$(state_get focus_ring_on 1)" = 1 ] && echo on || echo off )" >> "$body"
        state_has focus_ring_width && printf '        width %s\n' "$(state_get focus_ring_width)" >> "$body"
        state_has focus_ring_active && printf '        active-color "%s"\n' "$(state_get focus_ring_active)" >> "$body"
        state_has focus_ring_inactive && printf '        inactive-color "%s"\n' "$(state_get focus_ring_inactive)" >> "$body"
        printf '    }\n' >> "$body"
    fi
    if state_has border_on || state_has border_width || state_has border_active || state_has border_inactive; then
        printf '    border {\n' >> "$body"
        printf '        %s\n' "$( [ "$(state_get border_on 0)" = 1 ] && echo on || echo off )" >> "$body"
        state_has border_width && printf '        width %s\n' "$(state_get border_width)" >> "$body"
        state_has border_active && printf '        active-color "%s"\n' "$(state_get border_active)" >> "$body"
        state_has border_inactive && printf '        inactive-color "%s"\n' "$(state_get border_inactive)" >> "$body"
        printf '    }\n' >> "$body"
    fi
    if state_has shadow_on || state_has shadow_softness || state_has shadow_spread || state_has shadow_color; then
        printf '    shadow {\n' >> "$body"
        printf '        %s\n' "$( [ "$(state_get shadow_on 0)" = 1 ] && echo on || echo off )" >> "$body"
        state_has shadow_softness && printf '        softness %s\n' "$(state_get shadow_softness)" >> "$body"
        state_has shadow_spread && printf '        spread %s\n' "$(state_get shadow_spread)" >> "$body"
        if state_has shadow_offset_x || state_has shadow_offset_y; then
            printf '        offset x=%s y=%s\n' "$(state_get shadow_offset_x 0)" "$(state_get shadow_offset_y 5)" >> "$body"
        fi
        state_has shadow_color && printf '        color "%s"\n' "$(state_get shadow_color)" >> "$body"
        printf '    }\n' >> "$body"
    fi

    if [ -s "$body" ]; then printf 'layout {\n'; cat "$body"; printf '}\n\n'; fi
    rm -f "$body"
}

gen_keyboard() {
    local body; body=$(mktemp)
    if { state_has kb_layout && [ -n "$(state_get kb_layout)" ]; } \
        || { state_has kb_variant && [ -n "$(state_get kb_variant)" ]; } \
        || { state_has kb_options && [ -n "$(state_get kb_options)" ]; }; then
        printf '        xkb {\n' >> "$body"
        state_has kb_layout && [ -n "$(state_get kb_layout)" ] && printf '            layout "%s"\n' "$(state_get kb_layout)" >> "$body"
        state_has kb_variant && [ -n "$(state_get kb_variant)" ] && printf '            variant "%s"\n' "$(state_get kb_variant)" >> "$body"
        state_has kb_options && [ -n "$(state_get kb_options)" ] && printf '            options "%s"\n' "$(state_get kb_options)" >> "$body"
        printf '        }\n' >> "$body"
    fi
    state_has kb_repeat_delay && printf '        repeat-delay %s\n' "$(state_get kb_repeat_delay)" >> "$body"
    state_has kb_repeat_rate && printf '        repeat-rate %s\n' "$(state_get kb_repeat_rate)" >> "$body"
    [ "$(state_get kb_numlock 0)" = 1 ] && state_has kb_numlock && printf '        numlock\n' >> "$body"
    if [ -s "$body" ]; then printf '    keyboard {\n'; cat "$body"; printf '    }\n'; fi
    rm -f "$body"
}

gen_touchpad() {
    state_has tp_seeded || return 0
    printf '    touchpad {\n'
    [ "$(state_get tp_tap 1)" = 1 ] && printf '        tap\n'
    [ "$(state_get tp_natural 1)" = 1 ] && printf '        natural-scroll\n'
    [ "$(state_get tp_dwt 0)" = 1 ] && printf '        dwt\n'
    [ "$(state_get tp_left_handed 0)" = 1 ] && printf '        left-handed\n'
    state_has tp_accel_speed && printf '        accel-speed %s\n' "$(state_get tp_accel_speed)"
    state_has tp_accel_profile && printf '        accel-profile "%s"\n' "$(state_get tp_accel_profile)"
    state_has tp_scroll_method && printf '        scroll-method "%s"\n' "$(state_get tp_scroll_method)"
    state_has tp_click_method && printf '        click-method "%s"\n' "$(state_get tp_click_method)"
    printf '    }\n'
}

gen_mouse() {
    state_has mouse_seeded || return 0
    printf '    mouse {\n'
    [ "$(state_get mouse_natural 0)" = 1 ] && printf '        natural-scroll\n'
    [ "$(state_get mouse_left_handed 0)" = 1 ] && printf '        left-handed\n'
    state_has mouse_accel_speed && printf '        accel-speed %s\n' "$(state_get mouse_accel_speed)"
    state_has mouse_accel_profile && printf '        accel-profile "%s"\n' "$(state_get mouse_accel_profile)"
    printf '    }\n'
}

gen_focus_follows() {
    # focus-follows-mouse 是 input{} 里的通用合并段(非整块替换)。
    # niri 没有显式 off 语法(实测 26.04 报非法)，所以 off=不生成该行；
    # 若主配置 config.kdl 里已写 focus-follows-mouse，需手动注释那行才真正关闭。
    case "$(state_get ffm_mode off)" in
        always) printf '    focus-follows-mouse\n' ;;
        0)      printf '    focus-follows-mouse max-scroll-amount="0%%"\n' ;;
        10)     printf '    focus-follows-mouse max-scroll-amount="10%%"\n' ;;
    esac
}

gen_anim() {
    # 动画是顶层 animation{} 块; 预设覆盖窗口移动/开关/工作区切换的 spring。
    # default=不生成(沿用主配置/默认); off=高刚度近似"无动画"。
    local style dr st
    style=$(state_get anim default)
    [ "$style" = default ] && return 0
    case "$style" in
        fluid)  dr=0.85; st=400 ;;
        snappy) dr=0.70; st=800 ;;
        off)    dr=1.00; st=10000 ;;
        *) return 0 ;;
    esac
    printf 'animation {\n'
    local blk
    for blk in window-movement window-open window-close workspace-switch; do
        printf '    %s {\n' "$blk"
        printf '        spring damping-ratio=%s stiffness=%s epsilon=0.0001\n' "$dr" "$st"
        printf '    }\n'
    done
    printf '}\n\n'
}

gen_input() {
    local body; body=$(mktemp)
    # gen_keyboard/gen_touchpad 直接写 stdout, 先收集到 body
    { gen_keyboard; gen_touchpad; gen_mouse; gen_focus_follows; } > "$body"
    if [ -s "$body" ]; then printf 'input {\n'; cat "$body"; printf '}\n\n'; fi
    rm -f "$body"
}

gen_misc() {
    local cur; cur=$(mktemp)
    { state_has cursor_theme && [ -n "$(state_get cursor_theme)" ] && printf '    xcursor-theme "%s"\n' "$(state_get cursor_theme)"; } >> "$cur"
    { state_has cursor_size && [ -n "$(state_get cursor_size)" ] && printf '    xcursor-size %s\n' "$(state_get cursor_size)"; } >> "$cur"
    [ "$(state_get cursor_hide_typing 0)" = 1 ] && state_has cursor_hide_typing && printf '    hide-when-typing\n' >> "$cur"
    if [ -s "$cur" ]; then printf 'cursor {\n'; cat "$cur"; printf '}\n'; fi
    rm -f "$cur"

    local ov; ov=$(mktemp)
    state_has overview_zoom && [ -n "$(state_get overview_zoom)" ] && printf '    zoom %s\n' "$(state_get overview_zoom)" >> "$ov"
    state_has overview_backdrop && [ -n "$(state_get overview_backdrop)" ] && printf '    backdrop-color "%s"\n' "$(state_get overview_backdrop)" >> "$ov"
    if [ -s "$ov" ]; then printf 'overview {\n'; cat "$ov"; printf '}\n'; fi
    rm -f "$ov"

    if niri_ge_2604 && { state_has blur_off || state_has blur_passes || state_has blur_offset || state_has blur_noise || state_has blur_saturation; }; then
        printf 'blur {\n'
        [ "$(state_get blur_off 0)" = 1 ] && printf '    off\n'
        state_has blur_passes && printf '    passes %s\n' "$(state_get blur_passes)"
        state_has blur_offset && printf '    offset %s\n' "$(state_get blur_offset)"
        state_has blur_noise && printf '    noise %s\n' "$(state_get blur_noise)"
        state_has blur_saturation && printf '    saturation %s\n' "$(state_get blur_saturation)"
        printf '}\n'
    fi

    [ "$(state_get prefer_no_csd 0)" = 1 ] && state_has prefer_no_csd && printf 'prefer-no-csd\n'
    [ "$(state_get clipboard_disable_primary 0)" = 1 ] && state_has clipboard_disable_primary && printf 'clipboard {\n    disable-primary\n}\n'
    [ "$(state_get hotkey_skip 0)" = 1 ] && state_has hotkey_skip && printf 'hotkey-overlay {\n    skip-at-startup\n}\n'
    state_has screenshot_path && [ -n "$(state_get screenshot_path)" ] && printf 'screenshot-path "%s"\n' "$(state_get screenshot_path)"
}

gen_spawn_at_startup() {
    # 开机自启(顶层, 合并): 单条命令; 多条可由用户手动加或后续扩展
    local s; s=$(state_get spawn '')
    [ -n "$s" ] && printf 'spawn-at-startup "%s"\n' "$s"
}

gen_environment() {
    # 环境变量(顶层, 合并): 存 "KEY value"
    local e; e=$(state_get env_var '')
    [ -n "$e" ] || return 0
    printf 'environment { %s }\n' "$e"
}

gen_notifications() {
    # 通知(顶层): 超时(ms)
    state_has notify_timeout_ms && printf 'notifications { timeout-ms %s }\n' "$(state_get notify_timeout_ms)"
}

gen_workspaces() {
    # 工作区命名(顶层, 合并): 给 1-6 号工作区设 name
    local body n
    body=$(mktemp)
    for n in 1 2 3 4 5 6; do
        local nm; nm=$(state_get "ws_name_$n" '')
        [ -n "$nm" ] && printf '    "%s" { name "%s" }\n' "$n" "$nm" >> "$body"
    done
    if [ -s "$body" ]; then printf 'workspaces {\n'; cat "$body"; printf '}\n\n'; fi
    rm -f "$body"
}

gen_idle() {
    # 空闲/电源(顶层): DPMS 关屏超时(0=不设)
    state_has idle_dpms_ms && [ "$(state_get idle_dpms_ms 0)" != 0 ] && printf 'idle { dpms-timeout-ms %s }\n' "$(state_get idle_dpms_ms)"
}

gen_window_rule() {
    # 窗口规则(顶层): 一条规则(目标 app-id + 浮窗/最大化/无边框/固定工作区)
    local appid; appid=$(state_get wr_appid '')
    [ -n "$appid" ] || return 0
    local body; body=$(mktemp)
    printf 'window-rule {\n    match app-id="%s"\n' "$appid" >> "$body"
    [ "$(state_get wr_float 0)" = 1 ] && printf '    is-floating true\n' >> "$body"
    [ "$(state_get wr_max 0)" = 1 ] && printf '    open-maximized true\n' >> "$body"
    [ "$(state_get wr_border 0)" = 1 ] && printf '    border off\n' >> "$body"
    local ws; ws=$(state_get wr_ws '')
    [ -n "$ws" ] && printf '    open-on-workspace "%s"\n' "$ws" >> "$body"
    printf '}\n\n' >> "$body"
    cat "$body"; rm -f "$body"
}

gen_gestures() {
    # 触摸手势(顶层): 默认开; 只在显式关闭时生成 enabled false
    local ws ov body
    ws=$(state_get gesture_ws_swipe on)
    ov=$(state_get gesture_ov_swipe on)
    if state_has gesture_ws_swipe || state_has gesture_ov_swipe; then
        body=$(mktemp)
        [ "$ws" = off ] && printf '    workspace-switch swipe { enabled false }\n' >> "$body"
        [ "$ov" = off ] && printf '    open-overview swipe { enabled false }\n' >> "$body"
        if [ -s "$body" ]; then printf 'gestures {\n'; cat "$body"; printf '}\n\n'; fi
        rm -f "$body"
    fi
}

gen_outputs() {
    [ -f "$STATE" ] || return 0
    local line name n
    local -a names=()
    declare -A seen=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^out\.(.+)\.(scale|transform|off)= ]]; then
            name="${BASH_REMATCH[1]}"
            if [ -z "${seen[$name]:-}" ]; then seen[$name]=1; names+=("$name"); fi
        fi
    done < "$STATE"
    for n in "${names[@]}"; do
        printf 'output "%s" {\n' "$n"
        [ "$(state_get "out.$n.off" 0)" = 1 ] && printf '    off\n'
        state_has "out.$n.scale" && printf '    scale %s\n' "$(state_get "out.$n.scale")"
        state_has "out.$n.transform" && printf '    transform "%s"\n' "$(state_get "out.$n.transform")"
        printf '}\n\n'
    done
}

gen_all() { # <outfile>
    local out="$1"; : > "$out"
    printf '// 由 desktop-toolkit niri-config.sh 生成；请用工具修改，手改可能被覆盖。\n' >> "$out"
    { gen_layout; gen_anim; gen_input; gen_misc; gen_outputs; gen_spawn_at_startup; gen_environment; gen_notifications; gen_workspaces; gen_idle; gen_window_rule; gen_gestures; } >> "$out"
}

# ---------------------------------------------------------------------------
# 主配置: include 行 + 完整配置校验 + 写盘 + 热重载
# ---------------------------------------------------------------------------
niri_validate() { # <configfile>
    command -v niri >/dev/null 2>&1 || return 0   # 没装 niri 就不校验
    niri validate -c "$1" >/tmp/dt-nc-verify.$$ 2>&1
}

ensure_main_exists() {
    [ -f "$MAIN" ] && return 0
    err "未找到主配置 $MAIN"
    if [ -f "$DEFAULT_CONFIG" ]; then
        if dt_confirm "是否用 niri 默认配置初始化 $MAIN？"; then
            mkdir -p "$NIRI_DIR"
            cp "$DEFAULT_CONFIG" "$MAIN"
            log "已用默认配置初始化主配置"
            return 0
        fi
    fi
    return 1
}

# 固定路径一次性备份(勿用时间戳备份, 见 AGENTS.md 9.2): 首次改动时存原始配置
backup_main_once() {
    [ -f "$MAIN.orig-dt" ] && return 0
    [ -f "$MAIN" ] && cp "$MAIN" "$MAIN.orig-dt"
}

ensure_include() {
    [ -f "$MAIN" ] || return 1
    grep -q 'dt-settings\.kdl' "$MAIN" 2>/dev/null && return 0
    backup_main_once
    local inc
    if niri_ge_2604; then inc='include optional=true "dt-settings.kdl"'; else inc='include "dt-settings.kdl"'; fi
    {
        printf '\n// desktop-toolkit niri 可视化配置（勿删此行；用 niri-config.sh --uninstall 移除）\n'
        printf '%s\n' "$inc"
    } >> "$MAIN"
    log "已在主配置末尾加入 include"
}

remove_include() {
    [ -f "$MAIN" ] || return 0
    local tmp; tmp=$(mktemp)
    awk '
        /desktop-toolkit niri 可视化配置/ { next }
        /include.*dt-settings\.kdl/ { next }
        { print }
    ' "$MAIN" > "$tmp"
    if ! cmp -s "$tmp" "$MAIN"; then
        backup_main_once
        cp "$tmp" "$MAIN"
        log "已从主配置移除 include"
    fi
    rm -f "$tmp"
}

do_reload() { niri msg action reload-config >/dev/null 2>&1 || true; }

apply() {
    ensure_main_exists || return 1
    local frag; frag=$(mktemp)
    gen_all "$frag"

    if ! niri_validate "$frag"; then
        err "生成的配置片段无效，未写入（你的配置未被改动）："
        sed 's/^/    /' /tmp/dt-nc-verify.$$ >&2
        rm -f "$frag" /tmp/dt-nc-verify.$$
        return 1
    fi
    rm -f /tmp/dt-nc-verify.$$

    local bak=""; [ -f "$SETTINGS" ] && { bak=$(mktemp); cp "$SETTINGS" "$bak"; }
    cp "$frag" "$SETTINGS"; rm -f "$frag"
    ensure_include || { err "无法写入 include，回滚"; [ -n "$bak" ] && cp "$bak" "$SETTINGS"; rm -f "$bak"; return 1; }

    if ! niri_validate "$MAIN"; then
        err "合并后主配置校验失败，已回滚（你的配置未被改动）："
        sed 's/^/    /' /tmp/dt-nc-verify.$$ >&2
        if [ -n "$bak" ]; then cp "$bak" "$SETTINGS"; else printf '// 空\n' > "$SETTINGS"; fi
        rm -f "$bak" /tmp/dt-nc-verify.$$
        return 1
    fi
    rm -f /tmp/dt-nc-verify.$$ "$bak"
    do_reload
    log "已保存并生效（$SETTINGS）"
}

# ---------------------------------------------------------------------------
# 输入组件(统一走 lib/ui.sh, GUI/TUI 自适应)
# ---------------------------------------------------------------------------
num_int_set() { # key label default min max
    local key="$1" label="$2" def="$3" min="$4" max="$5"
    local cur v; cur=$(state_get "$key" "$def")
    v=$(dt_ask_num "$label" "" "$cur" "$min" "$max" "1") || return 2
    [ -n "$v" ] || return 2
    [[ "$v" =~ ^[0-9]+$ ]] || { err "请输入整数"; return 1; }
    { [ "$v" -ge "$min" ] && [ "$v" -le "$max" ]; } || { err "范围 $min~$max"; return 1; }
    state_set "$key" "$v"
}
float_set() { # key label default min max
    local key="$1" label="$2" def="$3" min="$4" max="$5"
    local cur v; cur=$(state_get "$key" "$def")
    v=$(dt_ask_text "$label" "范围 $min ~ $max" "$cur") || return 2
    [ -n "$v" ] || return 2
    [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { err "请输入数字"; return 1; }
    awk -v x="$v" -v lo="$min" -v hi="$max" 'BEGIN{ exit !(x+0>=lo+0 && x+0<=hi+0) }' \
        || { err "范围 $min ~ $max"; return 1; }
    state_set "$key" "$v"
}
text_set() { # key label default
    local key="$1" label="$2" def="$3"
    local cur v; cur=$(state_get "$key" "$def")
    v=$(dt_ask_text "$label" "" "$cur") || return 2
    if [[ "$v" == *['"\\']* || "$v" == *$'\n'* ]]; then
        err "不能包含双引号/反斜杠/换行"; return 1
    fi
    state_set "$key" "$v"
}
enum_set() { # key label default "v1|v2|..."
    local key="$1" label="$2" def="$3" vals="$4"
    local cur v; cur=$(state_get "$key" "$def")
    local -a rows=()
    local IFS='|'
    for v in $vals; do rows+=("$v|$v|"); done
    unset IFS
    local sel; sel=$(dt_menu "$label" "当前: $cur" "${rows[@]}") || return 2
    [ -n "$sel" ] || return 2
    state_set "$key" "$sel"
}
toggle_set() { # key label default
    local key="$1" label="$2" def="$3"
    local cur sel; cur=$(state_get "$key" "$def")
    sel=$(dt_menu "$label" "当前: $(onoff "$cur")" "1|开启|" "0|关闭|") || return 2
    [ -n "$sel" ] || return 2
    state_set "$key" "$sel"
}

# 应用一次(改了才调); 失败不打断菜单
save() { apply || true; }

# ---------------------------------------------------------------------------
# 从主配置尽力播种 touchpad/mouse(非合并段需要完整块)
# ---------------------------------------------------------------------------
extract_block() { # <file> <blockname>
    awk -v name="$2" '
        $0 ~ ("^[[:space:]]*" name "[[:space:]]*\\{") && !inb {
            inb=1; depth=0
            s=$0; depth += gsub(/\{/,"{") - gsub(/\}/,"}")
            if (depth<=0) inb=0
            next
        }
        inb {
            s=$0; depth += gsub(/\{/,"{") - gsub(/\}/,"}")
            if (depth<=0) { inb=0; next }
            print s
        }
    ' "$1"
}

seed_touchpad() {
    [ -f "$STATE" ] && state_has tp_seeded && return 0
    local b; b=$(extract_block "$MAIN" touchpad)
    # 无活跃块时用 niri 默认(tap/natural-scroll 开, 其余默认)
    local tap=1 nat=1 dwt=0 sp=0.0 prof=adaptive sm=two-finger cm=button-areas lh=0
    if [ -n "$b" ]; then
        echo "$b" | grep -qE '^[[:space:]]*tap([[:space:]]|$)' && tap=1 || tap=0
        echo "$b" | grep -qE '^[[:space:]]*natural-scroll([[:space:]]|$)' && nat=1 || nat=0
        echo "$b" | grep -qE '^[[:space:]]*dwt([[:space:]]|$)' && dwt=1 || dwt=0
        echo "$b" | grep -qE '^[[:space:]]*left-handed([[:space:]]|$)' && lh=1 || lh=0
        sp=$(echo "$b" | sed -n 's/^[[:space:]]*accel-speed[[:space:]]\+\([-0-9.]\+\).*/\1/p' | head -1); sp=${sp:-0.0}
        prof=$(echo "$b" | sed -n 's/^[[:space:]]*accel-profile[[:space:]]\+"\([^"]*\)".*/\1/p' | head -1); prof=${prof:-adaptive}
        sm=$(echo "$b" | sed -n 's/^[[:space:]]*scroll-method[[:space:]]\+"\([^"]*\)".*/\1/p' | head -1); sm=${sm:-two-finger}
        cm=$(echo "$b" | sed -n 's/^[[:space:]]*click-method[[:space:]]\+"\([^"]*\)".*/\1/p' | head -1); cm=${cm:-button-areas}
    fi
    state_set tp_tap "$tap"; state_set tp_natural "$nat"; state_set tp_dwt "$dwt"
    state_set tp_left_handed "$lh"; state_set tp_accel_speed "$sp"
    state_set tp_accel_profile "$prof"; state_set tp_scroll_method "$sm"; state_set tp_click_method "$cm"
    state_set tp_seeded 1
}

seed_mouse() {
    [ -f "$STATE" ] && state_has mouse_seeded && return 0
    local b; b=$(extract_block "$MAIN" mouse)
    local nat=0 lh=0 sp=0.0 prof=adaptive
    if [ -n "$b" ]; then
        echo "$b" | grep -qE '^[[:space:]]*natural-scroll([[:space:]]|$)' && nat=1 || nat=0
        echo "$b" | grep -qE '^[[:space:]]*left-handed([[:space:]]|$)' && lh=1 || lh=0
        sp=$(echo "$b" | sed -n 's/^[[:space:]]*accel-speed[[:space:]]\+\([-0-9.]\+\).*/\1/p' | head -1); sp=${sp:-0.0}
        prof=$(echo "$b" | sed -n 's/^[[:space:]]*accel-profile[[:space:]]\+"\([^"]*\)".*/\1/p' | head -1); prof=${prof:-adaptive}
    fi
    state_set mouse_natural "$nat"; state_set mouse_left_handed "$lh"
    state_set mouse_accel_speed "$sp"; state_set mouse_accel_profile "$prof"
    state_set mouse_seeded 1
}

seed_focus_follows() {
    state_has ffm_mode && return 0
    # 仅用于菜单"当前"显示: 从主配置 input{} 尽力解析当前有效值
    local b; b=$(extract_block "$MAIN" input)
    local m=off
    if [ -n "$b" ]; then
        if echo "$b" | grep -qE '^[[:space:]]*focus-follows-mouse[[:space:]]+max-scroll-amount="0%"'; then
            m=0
        elif echo "$b" | grep -qE '^[[:space:]]*focus-follows-mouse[[:space:]]+max-scroll-amount="10%"'; then
            m=10
        elif echo "$b" | grep -qE '^[[:space:]]*focus-follows-mouse([[:space:]]|$)'; then
            m=always
        fi
    fi
    state_set ffm_mode "$m"
}

seed_anim() {
    state_has anim && return 0
    # 仅用于菜单"当前"显示: 从主配置 animation{window-movement{spring...}} 尽力解析
    local b; b=$(extract_block "$MAIN" animation)
    local s=default
    if [ -n "$b" ]; then
        local st; st=$(echo "$b" | sed -n 's/.*stiffness=\([0-9]*\).*/\1/p' | head -1)
        case "$st" in
            400) s=fluid ;; 800) s=snappy ;; 10000) s=off ;;
        esac
    fi
    state_set anim "$s"
}

anim_label() {
    case "$(state_get anim default)" in
        fluid) echo 流畅 ;; snappy) echo 快速 ;; off) echo 关闭 ;; *) echo 默认 ;;
    esac
}

# ---------------------------------------------------------------------------
# 子菜单: 布局
# ---------------------------------------------------------------------------
menu_focus_ring() {
    while true; do
        local c
        c=$(dt_menu "焦点环 focus-ring" "只绘制在当前窗口周围：" \
            "on|① 启用/停用|当前: $(onoff "$(state_get focus_ring_on 1)")" \
            "w|② 宽度|当前: $(state_get focus_ring_width 4) px" \
            "a|③ 活动色|当前: $(state_get focus_ring_active '#7fc8ff')" \
            "i|④ 非活动色|当前: $(state_get focus_ring_inactive '#505050')" \
            "back|← 返回|") || return 0
        case "$c" in
            on) toggle_set focus_ring_on "启用焦点环？" 1 && save ;;
            w) num_int_set focus_ring_width "焦点环宽度(px)" 4 0 32 && save ;;
            a) text_set focus_ring_active "活动色(#rrggbb 或颜色名)" "#7fc8ff" && save ;;
            i) text_set focus_ring_inactive "非活动色" "#505050" && save ;;
            back) return 0 ;;
        esac
    done
}
menu_border() {
    while true; do
        local c
        c=$(dt_menu "窗口边框 border" "绘制在所有窗口周围（会占用窗口尺寸）：" \
            "on|① 启用/停用|当前: $(onoff "$(state_get border_on 0)")" \
            "w|② 宽度|当前: $(state_get border_width 4) px" \
            "a|③ 活动色|当前: $(state_get border_active '#ffc87f')" \
            "i|④ 非活动色|当前: $(state_get border_inactive '#505050')" \
            "back|← 返回|") || return 0
        case "$c" in
            on) toggle_set border_on "启用边框？" 0 && save ;;
            w) num_int_set border_width "边框宽度(px)" 4 0 32 && save ;;
            a) text_set border_active "活动色" "#ffc87f" && save ;;
            i) text_set border_inactive "非活动色" "#505050" && save ;;
            back) return 0 ;;
        esac
    done
}
menu_shadow() {
    while true; do
        local c
        c=$(dt_menu "窗口阴影 shadow" "窗口后面的阴影：" \
            "on|① 启用/停用|当前: $(onoff "$(state_get shadow_on 0)")" \
            "so|② 柔和度 softness|当前: $(state_get shadow_softness 30)" \
            "sp|③ 扩散 spread|当前: $(state_get shadow_spread 5)" \
            "ox|④ 水平偏移|当前: $(state_get shadow_offset_x 0)" \
            "oy|⑤ 垂直偏移|当前: $(state_get shadow_offset_y 5)" \
            "col|⑥ 颜色|当前: $(state_get shadow_color '#00000070')" \
            "back|← 返回|") || return 0
        case "$c" in
            on) toggle_set shadow_on "启用阴影？" 0 && save ;;
            so) num_int_set shadow_softness "阴影柔和度(px)" 30 0 120 && save ;;
            sp) num_int_set shadow_spread "阴影扩散(px)" 5 -20 40 && save ;;
            ox) num_int_set shadow_offset_x "水平偏移(px)" 0 -60 60 && save ;;
            oy) num_int_set shadow_offset_y "垂直偏移(px)" 5 -60 60 && save ;;
            col) text_set shadow_color "阴影颜色(#rrggbbaa)" "#00000070" && save ;;
            back) return 0 ;;
        esac
    done
}
menu_layout() {
    while true; do
        local c
        c=$(dt_menu "布局与外观" "间距 / 居中 / 边框 / 焦点环 / 阴影 / 背景 / 窗口装饰 / 动画：" \
            "gaps|① 窗口间距|当前: $(state_get gaps 16) px" \
            "center|② 焦点列居中|当前: $(state_get center_focused never)" \
            "disp|③ 新列显示模式|当前: $(state_get default_column_display normal)" \
            "bg|④ 工作区背景色|当前: $(state_get background_color 未设置)" \
            "focus|⑤ 焦点环 focus-ring|宽 $(state_get focus_ring_width 4)px $(onoff "$(state_get focus_ring_on 1)")" \
            "border|⑥ 窗口边框 border|宽 $(state_get border_width 4)px $(onoff "$(state_get border_on 0)")" \
            "shadow|⑦ 窗口阴影 shadow|$(onoff "$(state_get shadow_on 0)")" \
            "csd|⑧ 窗口按钮/装饰 prefer-no-csd|当前: $( [ "$(state_get prefer_no_csd 0)" = 1 ] && echo '隐藏(无边框)' || echo '显示(应用自绘)' )" \
            "anim|⑨ 动画控制 animation|当前: $(anim_label)" \
            "back|← 返回|") || return 0
        case "$c" in
            gaps) num_int_set gaps "窗口间距(px)" 16 0 64 && save ;;
            center) enum_set center_focused "焦点列居中策略" never "never|always|on-overflow" && save ;;
            disp) enum_set default_column_display "新列显示模式" normal "normal|tabbed" && save ;;
            bg) text_set background_color "工作区背景色(留空=不改)" "" && save ;;
            focus) menu_focus_ring ;;
            border) menu_border ;;
            shadow) menu_shadow ;;
            csd) toggle_set prefer_no_csd "隐藏窗口按钮和标题栏？(开启后应用自绘的 关闭/最大化/最小化 按钮会消失，窗口变无边框)" 0 && save ;;
            anim) enum_set anim "动画控制(窗口移动/开关/工作区切换)" default "default|fluid|snappy|off" && save ;;
            back) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单: 输入
# ---------------------------------------------------------------------------
menu_keyboard() {
    while true; do
        local c
        c=$(dt_menu "键盘 keyboard" "布局 / 变体 / 选项 / 重复 / 数字锁：" \
            "layout|① 布局 layout|当前: $(state_get kb_layout 继承系统)" \
            "variant|② 变体 variant|当前: $(state_get kb_variant 未设置)" \
            "options|③ 选项 options|当前: $(state_get kb_options 未设置)" \
            "delay|④ 重复延迟 repeat-delay|当前: $(state_get kb_repeat_delay 600) ms" \
            "rate|⑤ 重复速率 repeat-rate|当前: $(state_get kb_repeat_rate 25)/s" \
            "num|⑥ 数字锁 numlock|当前: $(onoff "$(state_get kb_numlock 0)")" \
            "back|← 返回|") || return 0
        case "$c" in
            layout) text_set kb_layout "键盘布局(如 us / us,ru / de)" "" && save ;;
            variant) text_set kb_variant "布局变体(如 colemak_dh)" "" && save ;;
            options) text_set kb_options "xkb 选项(如 grp:win_space_toggle,ctrl:nocaps)" "" && save ;;
            delay) num_int_set kb_repeat_delay "重复延迟(ms)" 600 100 2000 && save ;;
            rate) num_int_set kb_repeat_rate "重复速率(次/秒)" 25 1 200 && save ;;
            num) toggle_set kb_numlock "启动时开启数字锁？" 0 && save ;;
            back) return 0 ;;
        esac
    done
}
menu_touchpad() {
    seed_touchpad
    while true; do
        local c
        c=$(dt_menu "触摸板 touchpad" "首次调整会完整接管该配置块（其余项已从主配置播种）：" \
            "tap|① 点按(轻触) tap|当前: $(onoff "$(state_get tp_tap 1)")" \
            "nat|② 自然滚动 natural-scroll|当前: $(onoff "$(state_get tp_natural 1)")" \
            "dwt|③ 打字时禁用 dwt|当前: $(onoff "$(state_get tp_dwt 0)")" \
            "lh|④ 左手模式|当前: $(onoff "$(state_get tp_left_handed 0)")" \
            "sp|⑤ 加速速度 accel-speed|当前: $(state_get tp_accel_speed 0.0)" \
            "prof|⑥ 加速方式 accel-profile|当前: $(state_get tp_accel_profile adaptive)" \
            "sm|⑦ 滚动方式 scroll-method|当前: $(state_get tp_scroll_method two-finger)" \
            "cm|⑧ 点击方式 click-method|当前: $(state_get tp_click_method button-areas)" \
            "back|← 返回|") || return 0
        case "$c" in
            tap) toggle_set tp_tap "启用轻触点按？" 1 && save ;;
            nat) toggle_set tp_natural "启用自然滚动？" 1 && save ;;
            dwt) toggle_set tp_dwt "打字时禁用触摸板？" 0 && save ;;
            lh) toggle_set tp_left_handed "左手模式？" 0 && save ;;
            sp) float_set tp_accel_speed "加速速度" 0.0 -1.0 1.0 && save ;;
            prof) enum_set tp_accel_profile "加速方式" adaptive "adaptive|flat" && save ;;
            sm) enum_set tp_scroll_method "滚动方式" two-finger "no-scroll|two-finger|edge|on-button-down" && save ;;
            cm) enum_set tp_click_method "点击方式" button-areas "button-areas|clickfinger" && save ;;
            back) return 0 ;;
        esac
    done
}
menu_mouse() {
    seed_mouse
    while true; do
        local c
        c=$(dt_menu "鼠标 mouse" "首次调整会完整接管该配置块：" \
            "nat|① 自然滚动 natural-scroll|当前: $(onoff "$(state_get mouse_natural 0)")" \
            "lh|② 左手模式|当前: $(onoff "$(state_get mouse_left_handed 0)")" \
            "sp|③ 加速速度 accel-speed|当前: $(state_get mouse_accel_speed 0.0)" \
            "prof|④ 加速方式 accel-profile|当前: $(state_get mouse_accel_profile adaptive)" \
            "back|← 返回|") || return 0
        case "$c" in
            nat) toggle_set mouse_natural "启用自然滚动？" 0 && save ;;
            lh) toggle_set mouse_left_handed "左手模式？" 0 && save ;;
            sp) float_set mouse_accel_speed "加速速度" 0.0 -1.0 1.0 && save ;;
            prof) enum_set mouse_accel_profile "加速方式" adaptive "adaptive|flat" && save ;;
            back) return 0 ;;
        esac
    done
}
menu_focus_follows() {
    seed_focus_follows
    while true; do
        local c cur; cur=$(state_get ffm_mode off)
        local lbl; case "$cur" in
            always) lbl="始终跟随(移到窗口即聚焦)" ;;
            0) lbl="仅完全可见时(滚动≤0%)" ;;
            10) lbl="滚动≤10%屏幕宽" ;;
            *) lbl="关闭" ;;
        esac
        c=$(dt_menu "焦点跟随鼠标 focus-follows-mouse" \
            "鼠标移到窗口上自动聚焦。当前: $lbl（关闭=不生成该行; 若主配置已写需手动注释）" \
            "off|① 关闭|不启用" \
            "always|② 始终跟随|移到任何窗口立即聚焦" \
            "0|③ 仅完全可见时|窗口已完整显示、不滚动视图才聚焦(最稳)" \
            "10|④ 允许少量滚动|滚动量≤10%屏幕宽才聚焦" \
            "back|← 返回|") || return 0
        case "$c" in
            off|always|0|10) state_set ffm_mode "$c"; save ;;
            back) return 0 ;;
        esac
    done
}
menu_gestures() {
    while true; do
        local c ws ov
        ws=$(state_get gesture_ws_swipe on); ov=$(state_get gesture_ov_swipe on)
        [ "$ws" = off ] && ws_disp=关 || ws_disp=开
        [ "$ov" = off ] && ov_disp=关 || ov_disp=开
        c=$(dt_menu "触摸手势" "触摸板手势开关(默认开，可单独禁用)：" \
            "ws|① 三指切换工作区|当前: $ws_disp" \
            "ov|② 三指开概览|当前: $ov_disp" \
            "back|← 返回|") || return 0
        case "$c" in
            ws) toggle_gset gesture_ws_swipe "工作区切换手势" && save ;;
            ov) toggle_gset gesture_ov_swipe "开概览手势" && save ;;
            back) return 0 ;;
        esac
    done
}

toggle_gset() { # key label —— on/off 字符串开关
    local k="$1" label="$2" cur
    cur=$(state_get "$k" on)
    if [ "$cur" = off ]; then
        state_set "$k" on
        dt_info "手势" "$label：已开启"
    else
        state_set "$k" off
        dt_info "手势" "$label：已关闭"
    fi
}

menu_input() {
    while true; do
        local c
        c=$(dt_menu "输入与焦点" "键盘 / 触摸板 / 鼠标 / 焦点跟随 / 手势：" \
            "kb|① 键盘|布局/变体/选项/重复/数字锁" \
            "tp|② 触摸板|点按/自然滚动/打字禁用/加速/滚动方式" \
            "mouse|③ 鼠标|自然滚动/加速/左手" \
            "ffm|④ 焦点跟随鼠标|鼠标移到窗口自动聚焦" \
            "gest|⑤ 触摸手势|工作区切换/概览 手势开关" \
            "back|← 返回|") || return 0
        case "$c" in
            kb) menu_keyboard ;;
            tp) menu_touchpad ;;
            mouse) menu_mouse ;;
            ffm) menu_focus_follows ;;
            gest) menu_gestures ;;
            back) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单: 光标与杂项
# ---------------------------------------------------------------------------
menu_blur() {
    while true; do
        local c
        c=$(dt_menu "模糊 blur" "背景模糊参数（需 niri >= 26.04）：" \
            "off|① 全部关闭/允许|当前: $( [ "$(state_get blur_off 0)" = 1 ] && echo 关闭 || echo 允许 )" \
            "passes|② 模糊轮数 passes|当前: $(state_get blur_passes 3)" \
            "offset|③ 偏移 offset|当前: $(state_get blur_offset 3.0)" \
            "noise|④ 噪点 noise|当前: $(state_get blur_noise 0.02)" \
            "sat|⑤ 饱和度 saturation|当前: $(state_get blur_saturation 1.5)" \
            "back|← 返回|") || return 0
        case "$c" in
            off) toggle_set blur_off "关闭全部模糊？" 0 && save ;;
            passes) num_int_set blur_passes "模糊轮数(1-8)" 3 1 8 && save ;;
            offset) float_set blur_offset "偏移(1-6)" 3.0 0.0 6.0 && save ;;
            noise) float_set blur_noise "噪点(0-0.2)" 0.02 0.0 0.2 && save ;;
            sat) float_set blur_saturation "饱和度(0-3)" 1.5 0.0 3.0 && save ;;
            back) return 0 ;;
        esac
    done
}
menu_misc() {
    while true; do
        local -a rows=(
            "ct|① 光标主题|当前: $(state_get cursor_theme 继承)"
            "cs|② 光标大小|当前: $(state_get cursor_size 继承)"
            "hit|③ 打字时隐藏光标|当前: $(onoff "$(state_get cursor_hide_typing 0)")"
            "sp|④ 截图保存路径|当前: $(state_get screenshot_path 未设置)"
            "oz|⑤ 概览缩放 zoom|当前: $(state_get overview_zoom 未设置)"
            "ob|⑥ 概览背景色|当前: $(state_get overview_backdrop 未设置)"
            "hs|⑦ 跳过启动快捷键提示|当前: $(onoff "$(state_get hotkey_skip 0)")"
            "cl|⑧ 禁用中键主选区|当前: $(onoff "$(state_get clipboard_disable_primary 0)")"
        )
        niri_ge_2604 && rows+=("blur|⑨ 背景模糊 blur|参数调整")
        rows+=("back|← 返回|")
        local c
        c=$(dt_menu "光标与杂项" "光标 / 截图 / 概览 / 模糊：" "${rows[@]}") || return 0
        case "$c" in
            ct) text_set cursor_theme "光标主题名(如 Adwaita / breeze_cursors)" "" && save ;;
            cs) num_int_set cursor_size "光标大小(px)" 24 8 128 && save ;;
            hit) toggle_set cursor_hide_typing "打字时隐藏光标？" 0 && save ;;
            sp) text_set screenshot_path "截图路径(支持 ~ 和 %Y 等)" "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png" && save ;;
            oz) float_set overview_zoom "概览缩放(0-0.75)" 0.5 0.0 0.75 && save ;;
            ob) text_set overview_backdrop "概览背景色" "#262626" && save ;;
            hs) toggle_set hotkey_skip "启动时跳过快捷键提示？" 0 && save ;;
            cl) toggle_set clipboard_disable_primary "禁用中键主选区粘贴？" 0 && save ;;
            blur) menu_blur ;;
            back) return 0 ;;
        esac
    done
}

# 子菜单: 系统与开机(自启/环境变量/通知)
# ---------------------------------------------------------------------------
menu_ws_names() {
    while true; do
        local rows=() n
        for n in 1 2 3 4 5 6; do
            local cur; cur=$(state_get "ws_name_$n" '')
            rows+=("$n|工作区 $n|当前: ${cur:-未命名}")
        done
        rows+=("back|← 返回|")
        local c
        c=$(dt_menu "工作区命名" "给 1-6 号工作区设名称（留空=清除）" "${rows[@]}") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            [1-6])
                local v
                v=$(dt_ask_text "工作区 $c 名称" "输入名称(留空=恢复默认)" "$(state_get "ws_name_$c" '')") || continue
                if [ -n "$v" ]; then state_set "ws_name_$c" "$v"; else state_set "ws_name_$c" ""; fi
                save ;;
        esac
    done
}

menu_system() {
    while true; do
        local c
        c=$(dt_menu "系统与开机" "开机自启 / 环境变量 / 通知 / 工作区 / 电源：" \
            "spawn|① 开机自启 spawn-at-startup|当前: $(state_get spawn 未设置)" \
            "env|② 环境变量 environment|当前: $(state_get env_var 未设置)" \
            "notify|③ 通知超时 notifications|当前: $(state_get notify_timeout_ms 未设置) ms" \
            "ws|④ 工作区命名 workspace|给 1-6 号工作区设名称" \
            "idle|⑤ 空闲 DPMS 关屏 idle|当前: $(state_get idle_dpms_ms 未设置) ms" \
            "back|← 返回|") || return 0
        case "$c" in
            spawn) text_set spawn "开机自启命令(如: cliphist serve / 壁纸, 留空清除)" "" && save ;;
            env) text_set env_var "环境变量(格式: KEY value, 如: QT_QPA_PLATFORM wayland)" "" && save ;;
            notify) num_int_set notify_timeout_ms "通知超时(ms, 0=常驻)" 5000 0 60000 && save ;;
            ws) menu_ws_names ;;
            idle) num_int_set idle_dpms_ms "DPMS 关屏超时(ms, 0=不设)" 300000 0 3600000 && save ;;
            back) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单: 窗口规则(window-rule)
# ---------------------------------------------------------------------------
menu_window_rule() {
    while true; do
        local c
        c=$(dt_menu "窗口规则" "给某应用设置规则(浮窗/最大化/无边框/固定工作区)：" \
            "appid|① 目标应用 app-id|当前: $(state_get wr_appid 未设置)" \
            "float|② 浮窗|$(onoff "$(state_get wr_float 0)")" \
            "max|③ 最大化|$(onoff "$(state_get wr_max 0)")" \
            "border|④ 无边框|$(onoff "$(state_get wr_border 0)")" \
            "ws|⑤ 固定工作区|当前: $(state_get wr_ws 未设置)" \
            "back|← 返回|") || return 0
        case "$c" in
            appid) text_set wr_appid "目标应用 app-id(如 firefox / code; 留空=清除规则)" "" && save ;;
            float) toggle_set wr_float "让该应用浮窗？" 0 && save ;;
            max) toggle_set wr_max "让该应用打开时最大化？" 0 && save ;;
            border) toggle_set wr_border "无边框(去掉窗口边框)？" 0 && save ;;
            ws) text_set wr_ws "固定工作区(留空=不固定)" "" && save ;;
            back) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单: 显示器输出
# ---------------------------------------------------------------------------
list_outputs() {
    local names=""
    names=$(niri msg outputs 2>/dev/null | sed -n 's/^Output "\(.*\)".*/\1/p' | sort -u || true)
    [ -z "$names" ] && names=$(niri msg outputs 2>/dev/null | sed -n 's/^Output \([^ ]*\).*/\1/p' | sort -u || true)
    printf '%s' "$names"
}
menu_output_cfg() { # <name>
    local n="$1"
    while true; do
        local c
        c=$(dt_menu "输出: $n" "该显示器的缩放 / 旋转 / 开关：" \
            "scale|① 缩放 scale|当前: $(state_get "out.$n.scale" 未设置)" \
            "transform|② 旋转 transform|当前: $(state_get "out.$n.transform" normal)" \
            "off|③ 开关|当前: $( [ "$(state_get "out.$n.off" 0)" = 1 ] && echo 关闭 || echo 开启 )" \
            "back|← 返回|") || return 0
        case "$c" in
            scale) float_set "out.$n.scale" "缩放(如 1.0 / 1.25 / 2.0)" 1.0 0.5 4.0 && save ;;
            transform) enum_set "out.$n.transform" "旋转" normal "normal|90|180|270" && save ;;
            off) toggle_set "out.$n.off" "关闭该显示器？" 0 && save ;;
            back) return 0 ;;
        esac
    done
}
menu_output() {
    while true; do
        local -a rows=() n
        local names; names=$(list_outputs)
        if [ -n "$names" ]; then
            while IFS= read -r n; do [ -n "$n" ] && rows+=("$n|$n|缩放/旋转/开关"); done <<< "$names"
        fi
        rows+=("manual|手动输入显示器名|(先运行 niri msg outputs 查名字)")
        rows+=("back|← 返回|")
        local c
        c=$(dt_menu "显示器输出" "检测到的输出(在 niri 会话内可见)：" "${rows[@]}") || return 0
        case "$c" in
            back) return 0 ;;
            manual)
                local name; name=$(dt_ask_text "显示器名" "如 eDP-1 / HDMI-A-1" "eDP-1") || continue
                [ -n "$name" ] && menu_output_cfg "$name"
                ;;
            *) menu_output_cfg "$c" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 查看 / 重置 / 卸载
# ---------------------------------------------------------------------------
show_current() {
    echo
    echo -e "${C_BOLD}═══ 当前由本工具管理的设置 ═══${C_NC}"
    if [ -f "$STATE" ] && [ -s "$STATE" ]; then
        sed 's/^/  /' "$STATE"
    else
        echo "  （尚未设置任何项，全部继承主配置/默认）"
    fi
    echo
    echo -e "${C_BOLD}include 状态${C_NC}: $(grep -q 'dt-settings\.kdl' "$MAIN" 2>/dev/null && echo '已加入' || echo '未加入')"
    echo -e "${C_BOLD}生成文件${C_NC}: $SETTINGS ($([ -f "$SETTINGS" ] && echo 存在 || echo 不存在))"
    if command -v niri >/dev/null 2>&1 && [ -f "$MAIN" ]; then
        if niri validate -c "$MAIN" >/tmp/dt-nc-v.$$ 2>&1; then
            echo -e "${C_OK}主配置校验: 通过${C_NC}"
        else
            echo -e "${C_BAD}主配置校验: 失败${C_NC}"; sed 's/^/  /' /tmp/dt-nc-v.$$
        fi
        rm -f /tmp/dt-nc-v.$$
    fi
}

reset_all() {
    dt_confirm "确定移除本工具的所有设置？\n（会清空 dt-settings.kdl，但保留主配置里你自己的设置）" || return 0
    rm -f "$STATE" "$SETTINGS"
    # 重新生成空片段(保证 include 指向的文件存在)，并保留 include
    if [ -f "$MAIN" ] && grep -q 'dt-settings\.kdl' "$MAIN" 2>/dev/null; then
        printf '// 由 desktop-toolkit niri-config.sh 生成；请用工具修改，手改可能被覆盖。\n' > "$SETTINGS"
    fi
    do_reload
    log "已重置本工具的设置"
}

uninstall_all() {
    remove_include
    rm -f "$SETTINGS" "$STATE"
    log "已移除 include、dt-settings.kdl 与状态文件（主配置其余内容保持不变）"
}

# ---------------------------------------------------------------------------
# 搜索: 全量配置项目录(关键词|显示名|所属分类|要打开的菜单函数)
#   功能越多越记不清某项在哪个菜单，搜索按关键词定位后直接跳进对应子菜单。
#   关键词含中文名/配置键/英文，便于任意片段命中; 匹配用字面量(grep -F)防误正则。
# ---------------------------------------------------------------------------
CATALOG=(
    "窗口间距 gaps 间距 窗口 距离|窗口间距|布局与外观|menu_layout"
    "焦点列居中 center-focused-column 居中 列 位置|焦点列居中|布局与外观|menu_layout"
    "新列显示模式 default-column-display 显示 列 标签 tabbed normal|新列显示模式|布局与外观|menu_layout"
    "工作区背景色 background-color 背景 颜色 workspace|工作区背景色|布局与外观|menu_layout"
    "焦点环 focus-ring 聚焦 边框 宽度 颜色 活动 非活动|焦点环|布局与外观|menu_focus_ring"
    "窗口边框 border 边框 宽度 颜色|窗口边框|布局与外观|menu_border"
    "窗口阴影 shadow 阴影 柔和度 扩散 偏移 颜色|窗口阴影|布局与外观|menu_shadow"
    "窗口按钮 窗口装饰 标题栏 无边框 prefer-no-csd 关闭 最大化 最小化 客户端装饰 csd|窗口按钮/装饰|布局与外观|menu_layout"
    "动画 animation 窗口移动 开关 工作区 切换 spring 曲线 流畅 快速 关闭|动画控制|布局与外观|menu_layout"
    "键盘 keyboard 布局 变体 选项 重复 delay rate 数字锁 numlock|键盘|输入与焦点|menu_keyboard"
    "触摸板 touchpad 点按 轻触 tap 自然滚动 加速 滚动方式 左手|触摸板|输入与焦点|menu_touchpad"
    "鼠标 mouse 自然滚动 加速 左手|鼠标|输入与焦点|menu_mouse"
    "焦点跟随鼠标 focus-follows-mouse 悬停 hover 自动聚焦 跟随|焦点跟随鼠标|输入与焦点|menu_focus_follows"
    "光标主题 cursor-theme xcursor 图标|光标主题|光标与杂项|menu_misc"
    "光标大小 cursor-size 光标 大小|光标大小|光标与杂项|menu_misc"
    "打字隐藏光标 hide-when-typing 光标 隐藏 输入|打字时隐藏光标|光标与杂项|menu_misc"
    "截图路径 screenshot-path 截图 screenshot|截图保存路径|光标与杂项|menu_misc"
    "概览缩放 overview zoom 缩放 概览|概览缩放|光标与杂项|menu_misc"
    "概览背景色 overview backdrop 背景 概览|概览背景色|光标与杂项|menu_misc"
    "跳过快捷键提示 hotkey-overlay 快捷键 提示 启动|跳过快捷键提示|光标与杂项|menu_misc"
    "中键主选区 clipboard disable-primary 中键 主选区 剪贴板|禁用中键主选区|光标与杂项|menu_misc"
    "背景模糊 blur 模糊 高斯 背景 透明|背景模糊|光标与杂项|menu_blur"
    "显示器输出 output 缩放 scale 旋转 transform 开关 显示器|显示器输出|显示器输出|menu_output"
    "开机自启 spawn-at-startup 自启 启动 命令|开机自启|系统与开机|menu_system"
    "环境变量 environment 环境 KEY|环境变量|系统与开机|menu_system"
    "通知 notifications timeout 超时 提示|通知超时|系统与开机|menu_system"
    "工作区 workspace 命名 名称 数量|工作区命名|系统与开机|menu_ws_names"
    "空闲 idle 电源 关屏 dpms 超时|空闲 DPMS 关屏|系统与开机|menu_system"
    "窗口规则 window-rule 浮窗 最大化 无边框 固定工作区 app-id|窗口规则|窗口规则|menu_window_rule"
    "手势 gestures 触摸 三指 切换 概览 swipe|触摸手势|输入与焦点|menu_gestures"
)

menu_search() {
    local q
    q=$(dt_ask_text "搜索配置项" "输入关键词(中文/英文/配置键)，如: 间距 / gaps / 模糊 / 焦点 / 鼠标" "") || return 0
    [ -n "$q" ] || return 0
    local -a matched=() rows=()
    local entry kw disp cat fn
    local i=0
    for entry in "${CATALOG[@]}"; do
        IFS='|' read -r kw disp cat fn <<< "$entry"
        if printf '%s' "$kw" | grep -qiF "$q"; then
            matched+=("$entry")
            rows+=("$i|$disp|$cat")
            i=$((i+1))
        fi
    done
    if [ "${#matched[@]}" -eq 0 ]; then
        err "未找到匹配 \"$q\" 的配置项"
        return 0
    fi
    rows+=("back|← 返回|")
    local sel
    sel=$(dt_menu "搜索结果" "匹配 ${#matched[@]} 项，选择后进入对应菜单：" "${rows[@]}") || return 0
    [ "$sel" = back ] && return 0
    [[ "$sel" =~ ^[0-9]+$ ]] || return 0
    [ "$sel" -lt "${#matched[@]}" ] || return 0
    IFS='|' read -r kw disp cat fn <<< "${matched[$sel]}"
    "$fn"
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        local c
        c=$(dt_menu "Niri 可视化配置" "改完自动生成 KDL + 校验 + 热重载；只影响你显式设置过的项：" \
            "search|① 搜索配置项|按关键词找到对应菜单(支持中文/英文/配置键)" \
            "layout|② 布局与外观|间距/居中/边框/焦点环/阴影/背景/窗口装饰" \
            "input|③ 输入与焦点|键盘/触摸板/鼠标/焦点跟随" \
            "misc|④ 光标与杂项|光标/截图/装饰/概览/模糊" \
            "output|⑤ 显示器输出|缩放/旋转/开关（每台显示器）" \
            "system|⑥ 系统与开机|开机自启/环境变量/通知/工作区/电源" \
            "winrule|⑦ 窗口规则|浮窗/最大化/无边框/固定工作区(按应用)" \
            "view|⑧ 查看当前配置|已设置项 + 校验结果" \
            "reset|⑨ 全部重置|清空本工具的所有设置" \
            "back|← 退出|") || return 0
        case "$c" in
            search) menu_search ;;
            layout) menu_layout ;;
            input) menu_input ;;
            misc) menu_misc ;;
            output) menu_output ;;
            system) menu_system ;;
            winrule) menu_window_rule ;;
            view) show_current ;;
            reset) reset_all ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    --show) show_current ;;
    --dump) local_tmp=$(mktemp); gen_all "$local_tmp"; cat "$local_tmp"; rm -f "$local_tmp" ;;
    --uninstall) uninstall_all ;;
    "") main_menu ;;
    *) echo "用法: bash $0 [--show|--dump|--uninstall]"; exit 1 ;;
esac
