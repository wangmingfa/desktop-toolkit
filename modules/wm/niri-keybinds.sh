#!/usr/bin/env bash
# =============================================================================
# niri-keybinds.sh —— niri 快捷键可视化配置
#
# 生成 ~/.config/niri/dt-keybinds.kdl，主配置末尾加
# `include optional=true "dt-keybinds.kdl"`(幂等)。与 niri-tools 的 tools.kdl、
# niri-config 的 dt-settings.kdl、niri-wlsunset 的 sun.kdl 各自独立 include，
# 互不干扰。
#
# 预设绑定按"开关"管理：关闭 = 把主配置里对应行注释掉（加 `// [dt-keybinds]` 前缀），
# 开启 = 去掉前缀。注释行不会触发 niri 解析错误，也不改本模块管理的 dt-keybinds.kdl。
#
# 自定义绑定：内置常见 action 列表 + 自定义 spawn 命令，写到 dt-keybinds.kdl。
#
# 依赖: lib/common.sh、lib/ui.sh。
# 用法: bash niri-keybinds.sh [browse|presets|custom|export-html|status|uninstall]
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_GREEN=${DT_GREEN:-$'\033[0;32m'}
    DT_YELLOW=${DT_YELLOW:-$'\033[0;33m'}
    DT_CYAN=${DT_CYAN:-$'\033[0;36m'}
    DT_BOLD=${DT_BOLD:-$'\033[1m'}
    DT_NC=${DT_NC:-$'\033[0m'}
else
    DT_GREEN=${DT_GREEN:-""}; DT_YELLOW=${DT_YELLOW:-""}
    DT_CYAN=${DT_CYAN:-""}; DT_BOLD=${DT_BOLD:-""}; DT_NC=${DT_NC:-""}
fi

log() { echo "  [niri-keybinds] $*"; }
err() { echo "  [niri-keybinds] 错误: $*" >&2; }

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
MAIN="$NIRI_DIR/config.kdl"
KEYB="$NIRI_DIR/dt-keybinds.kdl"
KEYB_INCLUDE='include optional=true "dt-keybinds.kdl"'
STATE="$NIRI_DIR/.dt-keybinds.conf"
ORIG="${MAIN}.orig-dt"
MARK='[dt-keybinds]'

# ---------------------------------------------------------------------------
# 状态读写（key=value；value 可能含 ##，取到行尾）
# ---------------------------------------------------------------------------
st_get() { # key [default]
    local line
    [ -f "$STATE" ] || { printf '%s' "${2:-}"; return 0; }
    while IFS= read -r line; do
        case "$line" in
            "$1="*) printf '%s' "${line#*=}"; return 0 ;;
        esac
    done < "$STATE"
    printf '%s' "${2:-}"
}
st_set() { # key value
    local tmp
    mkdir -p "$NIRI_DIR"
    tmp=$(mktemp)
    [ -f "$STATE" ] && {
        while IFS= read -r line; do
            case "$line" in "$1="*) ;; *) printf '%s\n' "$line" >> "$tmp" ;; esac
        done < "$STATE"
    }
    printf '%s=%s\n' "$1" "$2" >> "$tmp"
    mv "$tmp" "$STATE"
}
st_unset() { # key
    local tmp
    [ -f "$STATE" ] || return 0
    tmp=$(mktemp)
    while IFS= read -r line; do
        case "$line" in "$1="*) ;; *) printf '%s\n' "$line" >> "$tmp" ;; esac
    done < "$STATE"
    mv "$tmp" "$STATE"
}

# ---------------------------------------------------------------------------
# 预设绑定表（key##label##action##overlay##default##cat##scope）
# ---------------------------------------------------------------------------
presets() {
    cat <<'EOF'
overview##总览切换##toggle-overview##null##enabled##窗口
alttab##Alt-Tab 窗口切换##alt-tab-overlay##null##enabled##窗口
close##关闭窗口##close-window##null##enabled##窗口
focus-up##焦点上移##focus-window-up##null##disabled##焦点
focus-down##焦点下移##focus-window-down##null##enabled##焦点
focus-left##焦点左移##focus-column-left##null##enabled##焦点
focus-right##焦点右移##focus-column-right##null##enabled##焦点
move-up##移动上移##move-window-up##null##disabled##移动
move-down##移动下移##move-window-down##null##disabled##移动
move-left##移动左移##move-column-left##null##disabled##移动
move-right##移动右移##move-column-right##null##disabled##移动
zoom-in##窗口放大##zoom-window +1##null##disabled##窗口
zoom-out##窗口缩小##zoom-window -1##null##disabled##窗口
fullscreen##全屏切换##toggle-fullscreen##null##enabled##窗口
maximize##最大化##toggle-maximized##null##disabled##窗口
screenshot##全屏截图##screenshot##null##disabled##工具
screenshot-ui##截图界面##screenshot-ui-open##null##disabled##工具
ws-switch##切换工作区##focus-workspace##null##disabled##工作区
lock##锁屏##spawn##swaylock##disabled##系统
terminal##终端##spawn##$TERMINAL##enabled##系统
EOF
}

# 预设的 overlay title（key -> title），null 表示不显示
preset_title() {
    case "$1" in
        terminal) echo "Open Terminal" ;;
        lock) echo "Lock Screen" ;;
        overview) echo "Overview" ;;
        alttab) echo "Alt-Tab" ;;
        *) echo "null" ;;
    esac
}

# 预设表查询：按 key 取整行（key##label##action##overlay##default##cat）
preset_row() { # key -> 整行
    local line
    while IFS= read -r line; do
        case "$line" in
            "$1"##*) printf '%s' "$line"; return 0 ;;
        esac
    done < <(presets)
    return 1
}
preset_field() { # key field_index(1-based): 1=key 2=label 3=action 4=overlay 5=default 6=cat
    local row
    row="$(preset_row "$1")" || return 1
    local -a f=()
    # 用 tr 转换 ## 为制表符，再 read
    IFS=$'\t' read -ra f <<< "$(printf '%s' "$row" | tr '##' '\t')"
    printf '%s' "${f[$(( $2 - 1 ))]:-}"
}

# ---------------------------------------------------------------------------
# KDL 生成（预设来自预设表 + 状态文件；自定义全来自状态文件）
# ---------------------------------------------------------------------------
gen_keybinds() {
    {
        printf '// 由 desktop-toolkit niri-keybinds.sh 生成；请用工具修改，手改可能被覆盖。\n'
        printf 'binds {\n'
        # 预设
        local line row key val action overlay def scope bindkey title
        while IFS= read -r row; do
            key="${row%%##*}"
            action="$(preset_field "$key" 3)"
            overlay="$(preset_field "$key" 4)"
            def="$(preset_field "$key" 5)"
            [ "$def" = enabled ] || continue
            val="$(st_get "preset:$key" disabled)"
            [ "$val" = enabled ] || continue
            bindkey="$(st_get "preset:$key##key" "Super+Space")"
            title="$(preset_title "$key")"
            if [ "$action" = "spawn" ]; then
                local cmd
                cmd="$(st_get "preset:$key##cmd" "${overlay:-swaylock}")"
                [ "$cmd" = null ] && cmd="swaylock"
                printf '    %s hotkey-overlay-title=%s { spawn %s; }\n' \
                    "$bindkey" "$title" "$(kdl_escape "$cmd")"
            else
                printf '    %s { %s; }\n' "$bindkey" "$action"
            fi
        done < <(presets)
        # 自定义
        while IFS= read -r line; do
            case "$line" in
                custom:*=*)
                    val="${line#*=}"; key="${line%%=*}"
                    [ "${val%%##*}" = enabled ] || continue
                    bindkey="$(st_get "${key}##key")"
                    action="$(st_get "${key}##act")"
                    local args
                    args="$(st_get "${key}##args")"
                    [ -n "$bindkey" ] && [ -n "$action" ] || continue
                    if [ -n "$args" ]; then
                        printf '    %s { %s %s; }\n' "$bindkey" "$action" "$args"
                    else
                        printf '    %s { %s; }\n' "$bindkey" "$action"
                    fi
                    ;;
            esac
        done < "$STATE" 2>/dev/null
        printf '}\n'
    } > "$KEYB.tmp"
}

# KDL 字符串转义（双引号与反斜杠）
kdl_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# 解析 binds（输出 file<TAB>scope<TAB>key<TAB>action<TAB>args<TAB>raw）
# ---------------------------------------------------------------------------
parse_binds() { # file...
    awk '
    function emit() {
        if (bindkey != "") {
            line = rawline
            sub(/^[ \t]+/, "", line)
            sub(/\/\/[^\n]*$/, "", line)
            gsub(/[ \t]+/, " ", line)
            sub(/^[ \t]+|[ \t]+$/, "", line)
            print file "\t" scope "\t" bindkey "\t" act "\t" args "\t" line
        }
        bindkey = ""; act = ""; args = ""
    }
    FNR == 1 { emit(); file = FILENAME; inbinds = 0; next }
    # binds 块开始（先匹配，避免被 bind key 规则误判）
    /^[ \t]*binds[ \t]*\{/ { inbinds = 1; next }
    # binds 块结束
    /^[ \t]*\}/ { if (inbinds) inbinds = 0; next }
    # bind key 行（只在 binds 块内处理）
    inbinds && /^[ \t]*[A-Za-z_][A-Za-z0-9+]*[ \t]*\{/ {
        emit()
        line = $0
        n = split(line, parts, "{")
        bindkey = parts[1]
        gsub(/[ \t]+/, "", bindkey)
        rest = parts[2]
        sub(/\};?/, "", rest)
        sub(/^[ \t]+|[ \t]+$/, "", rest)
        # 取 action 名（第一个 token）
        act = rest
        sub(/[ \t;].*$/, "", act)
        sub(/^[ \t]+/, "", act)
        # 参数 = action 后紧跟的部分
        if (match(rest, / [A-Za-z0-9_+-]+/)) {
            args = substr(rest, RSTART + 1, RLENGTH)
            sub(/[ \t].*$/, "", args)
            sub(/[ \t]+$/, "", args)
        }
        rawline = $0
        next
    }
    END { emit() }
    ' "$@"
}

# ---------------------------------------------------------------------------
# include 管理
# ---------------------------------------------------------------------------
ensure_include() {
    [ -f "$MAIN" ] || { err "主配置 $MAIN 不存在"; return 1; }
    grep -q 'dt-keybinds\.kdl' "$MAIN" 2>/dev/null && return 0
    backup_main_once
    awk -v inc="$KEYB_INCLUDE" '
        { print }
        END { print ""; print "// dt-keybinds include (niri-keybinds.sh 管理)"; print inc }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    log "已在主配置末尾加入 include dt-keybinds.kdl"
}
remove_include() {
    [ -f "$MAIN" ] || return 0
    awk -v inc="$KEYB_INCLUDE" '
        /dt-keybinds include/ { skip = 1; next }
        skip && $0 == inc { skip = 0; next }
        { print }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    log "已从主配置移除 include"
}
backup_main_once() {
    [ -f "$ORIG" ] && return 0
    [ -f "$MAIN" ] && cp "$MAIN" "$ORIG"
}

# ---------------------------------------------------------------------------
# 校验 + 写盘 + 热重载
# ---------------------------------------------------------------------------
niri_validate() { # file
    command -v niri >/dev/null 2>&1 || return 0
    niri validate -c "$1" >/tmp/dt-nk-verify.$$ 2>&1
}
do_reload() {
    niri msg action reload-config >/dev/null 2>&1 && log "已触发热重载" || log "热重载未成功（请手动: niri msg action reload-config）"
}
apply() {
    gen_keybinds
    if [ ! -s "$KEYB.tmp" ]; then log "生成内容为空"; return 0; fi
    if ! niri_validate "$KEYB.tmp"; then
        err "生成的片段无效，未写入："
        sed 's/^/    /' /tmp/dt-nk-verify.$$ >&2 2>/dev/null
        rm -f "$KEYB.tmp" /tmp/dt-nk-verify.$$
        return 1
    fi
    cp "$KEYB.tmp" "$KEYB"; rm -f "$KEYB.tmp"
    ensure_include || return 1
    if ! niri_validate "$MAIN"; then
        err "合并后主配置校验失败，已回滚："
        sed 's/^/    /' /tmp/dt-nk-verify.$$ >&2 2>/dev/null
        remove_include
        return 1
    fi
    do_reload
    return 0
}

# ---------------------------------------------------------------------------
# 注释/恢复（关/开预设：把主配置里对应行注释掉 / 去掉注释前缀）
# ---------------------------------------------------------------------------
comment_line() { # key action bindkey
    [ -f "$MAIN" ] || return 0
    local awk_pat="$1" awk_act="$2" awk_key="$3"
    awk -v key="$awk_key" -v act="$awk_act" -v pat="$awk_pat" -v mark="$MARK" '
        {
            if (index($0, mark) > 0) { print; next }
            line = $0
            sub(/\/\/[^\n]*$/, "", line)
            # 去掉行首空格和注释前缀后匹配
            gsub(/^[ \t]+/, "", line)
            if (line ~ key ".*" act) {
                print "    // " mark " " $0
                next
            }
            print
        }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
}
restore_line() { # 恢复所有被本模块注释的行
    [ -f "$MAIN" ] || return 0
    local n=0
    awk -v mark="$MARK" '
        {
            line = $0
            if (match(line, /^[ \t]*\/\/[ \t]*\[[^\]]*\][ \t]*/)) {
                rest = substr(line, RSTART + RLENGTH)
                sub(/^\/\/[ \t]*\[dt-keybinds\][ \t]*/, "", rest)
                if (rest ~ /^[A-Za-z_][A-Za-z0-9+]*[ \t]*\{/) {
                    print rest
                    next
                }
            }
            print
        }
    ' "$MAIN" > "$MAIN.tmp"
    if ! cmp -s "$MAIN.tmp" "$MAIN"; then mv "$MAIN.tmp" "$MAIN"; fi
    rm -f "$MAIN.tmp"
}
disabled_count() {
    [ -f "$MAIN" ] || { echo 0; return 0; }
    grep -c "\[dt-keybinds\]" "$MAIN" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 冲突检测：某键位是否已被其它 bind 占用
# ---------------------------------------------------------------------------
key_conflict() { # bindkey
    local k="$1" f
    for f in "$MAIN" "$KEYB"; do
        [ -f "$f" ] || continue
        grep -q "^[ \t]*$k[ \t]*{" "$f" 2>/dev/null && {
            echo "$f"; return 0
        }
    done
    return 1
}

# ---------------------------------------------------------------------------
# 预设开关
# ---------------------------------------------------------------------------
toggle_preset() { # key action
    local key="$1" action="${2:-}"
    [ -z "$action" ] && action="$(preset_field "$key" 3)"
    local cur
    cur="$(st_get "preset:$key" disabled)"
    if [ "$cur" = enabled ]; then
        # 当前启用 → 关闭：注释主配置里对应行
        st_set "preset:$key" disabled
        local bindkey
        bindkey="$(st_get "preset:$key##key")"
        [ -n "$bindkey" ] && comment_line "$bindkey" "$action" "$bindkey"
        log "已关闭 $key（$action）"
        apply
    else
        # 当前关闭 → 询问键位后启用
        ask_and_enable_preset "$key" "$action"
    fi
}

ask_and_enable_preset() { # key action
    local key="$1" action="$2"
    local defkey
    defkey="$(st_get "preset:$key##key" "Super+Space")"
    if [ "$action" = "spawn" ]; then
        # spawn 预设：命令来自预设表第 4 字段（overlay 位放的是命令）
        local cmd
        cmd="$(preset_field "$key" 4)"
        [ "$cmd" = null ] || [ -z "$cmd" ] && cmd="swaylock"
        st_set "preset:$key##cmd" "$cmd"
    fi
    local bindkey
    bindkey=$(dt_ask_text "绑定键位" "为 $key（$action）设置快捷键（如 Super+Space / Mod+O / Alt+Up）" "$defkey") || return 0
    [ -n "$bindkey" ] || bindkey="$defkey"
    # 冲突检测
    local conf
    if conf=$(key_conflict "$bindkey"); then
        if ! dt_confirm "键位 $bindkey 已占用（在 $conf）。\n仍要用它吗？"; then
            return 0
        fi
    fi
    st_set "preset:$key" enabled
    st_set "preset:$key##key" "$bindkey"
    # 先恢复所有被注释行（把同键的旧行恢复），再写 dt-keybinds.kdl
    restore_line
    apply
}

# ---------------------------------------------------------------------------
# 预设菜单
# ---------------------------------------------------------------------------
preset_menu() {
    local -a rows=() row key label action def
    while IFS= read -r row; do
        key="${row%%##*}"
        label="$(preset_field "$key" 2)"
        action="$(preset_field "$key" 3)"
        def="$(preset_field "$key" 5)"
        cur="$(st_get "preset:$key" "$def")"
        if [ "$cur" = enabled ]; then
            local bindkey
            bindkey="$(st_get "preset:$key##key" "Super+Space")"
            rows+=("$key|[✓] $label|键位: $bindkey → $action（点击关闭）")
        else
            rows+=("$key|[ ] $label|默认: $action（点击开启）")
        fi
    done < <(presets)
    rows+=("back|← 返回|")
    while true; do
        local c
        c=$(dt_menu "niri 预设快捷键" "按分类管理内置快捷键（关闭 = 注释主配置里对应行；开启 = 恢复并写入）：" \
            "${rows[@]}") || return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            back) return 0 ;;
            *)
                local action
                action="$(preset_field "$c" 3)"
                toggle_preset "$c" "$action"
                # 刷新列表
                rows=()
                while IFS= read -r row; do
                    key="${row%%##*}"
                    label="$(preset_field "$key" 2)"
                    action="$(preset_field "$key" 3)"
                    def="$(preset_field "$key" 5)"
                    cur="$(st_get "preset:$key" "$def")"
                    if [ "$cur" = enabled ]; then
                        bindkey="$(st_get "preset:$key##key" "Super+Space")"
                        rows+=("$key|[✓] $label|键位: $bindkey → $action（点击关闭）")
                    else
                        rows+=("$key|[ ] $label|默认: $action（点击开启）")
                    fi
                done < <(presets)
                rows+=("back|← 返回|")
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 自定义绑定
# ---------------------------------------------------------------------------
custom_menu() {
    while true; do
        local c
        c=$(dt_menu "自定义快捷键" "添加/管理本模块创建的自定义绑定（写入 dt-keybinds.kdl）：" \
            "add|1. 添加绑定|内置 action 或自定义命令" \
            "del|2. 删除绑定|从 dt-keybinds.kdl 移除" \
            "back|← 返回|" \
        ) || return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            add) custom_add ;;
            del) custom_del ;;
            back) return 0 ;;
        esac
    done
}

custom_add() {
    local c
    c=$(dt_menu "选择动作类型" "常用内置动作或自定义命令：" \
        "spawn|1. 启动程序|spawn \"命令\"（如 nautilus、firefox）" \
        "spawn-sh|2. 启动 Shell 命令|spawn-sh \"sh -c 命令\"" \
        "focus-ws|3. 切换工作区|focus-workspace N" \
        "close-w|4. 关闭窗口|close-window" \
        "overview|5. 总览切换|toggle-overview" \
        "alt-tab|6. Alt-Tab|alt-tab-overlay" \
        "back|← 返回|" \
    ) || return 0
    [ "$c" = __quit ] && exit 0
    [ "$c" = back ] && return 0

    local idx
    idx=$(date +%s%N | md5sum | cut -c1-6)
    local id="custom:$idx"

    local bindkey
    bindkey=$(dt_ask_text "绑定键位" "快捷键（如 Super+Alt+T）" "") || return 0
    [ -n "$bindkey" ] || { err "键位不能为空"; return 0; }

    local act args=""
    case "$c" in
        spawn)
            local cmd
            cmd=$(dt_ask_text "启动命令" "要启动的程序（如 firefox、nautilus）" "") || return 0
            [ -n "$cmd" ] || return 0
            act="spawn"; args="$(kdl_escape "$cmd")"
            ;;
        spawn-sh)
            local shcmd
            shcmd=$(dt_ask_text "Shell 命令" "要执行的 shell 命令（会经 sh -c）" "") || return 0
            [ -n "$shcmd" ] || return 0
            act="spawn-sh"; args="$(kdl_escape "$shcmd")"
            ;;
        focus-ws)
            local n
            n=$(dt_ask_num "工作区号" "要切换到的工作区编号" "1" 1 20 1) || return 0
            [ -n "$n" ] || return 0
            act="focus-workspace"; args="$n"
            ;;
        close-w) act="close-window" ;;
        overview) act="toggle-overview" ;;
        alt-tab) act="alt-tab-overlay" ;;
    esac

    # 冲突检测
    local conf
    if conf=$(key_conflict "$bindkey"); then
        if ! dt_confirm "键位 $bindkey 已占用（在 $conf）。\n仍要添加吗？"; then
            return 0
        fi
    fi

    st_set "$id" "enabled##$act##root"
    st_set "$id##key" "$bindkey"
    st_set "$id##act" "$act"
    st_set "$id##args" "$args"
    st_set "$id##scope" "root"
    log "已添加: $bindkey → $act ${args}"
    apply
}

custom_del() {
    local -a rows=() line val key
    [ -f "$STATE" ] || { log "没有自定义绑定"; return 0; }
    while IFS= read -r line; do
        case "$line" in
            custom:*=*)
                val="${line#*=}"
                [ "${val%%##*}" = enabled ] || continue
                key="${line%%=*}"
                local k a
                k="$(st_get "${key}##key")"
                a="$(st_get "${key}##act")"
                [ -n "$k" ] && [ -n "$a" ] && rows+=("$key|$k → $a|")
                ;;
        esac
    done < "$STATE"
    if [ "${#rows[@]}" -eq 0 ]; then
        log "没有可删除的自定义绑定"
        return 0
    fi
    local c
    c=$(dt_menu "删除自定义绑定" "选择要移除的绑定（移除后其键位释放）：" "${rows[@]}" "back|← 返回|") || return 0
    [ "$c" = __quit ] && exit 0
    [ "$c" = back ] && return 0
    st_unset "$c"
    # 同时清掉附属字段
    local f
    for f in key act args scope; do
        st_unset "$c##$f"
    done
    log "已删除: $c"
    apply
}

# ---------------------------------------------------------------------------
# 浏览 / 搜索
# ---------------------------------------------------------------------------
browse_menu() {
    local c
    c=$(dt_menu "浏览快捷键" "查看当前生效的所有快捷键，或按关键词搜索：" \
        "all|1. 显示全部绑定|扫描主配置 + dt-keybinds.kdl" \
        "search|2. 搜索绑定|按关键词（动作名/键位）" \
        "export|3. 导出 HTML 快捷键表|保存为网页便于查阅" \
        "back|← 返回|" \
    ) || return 0
    [ "$c" = __quit ] && exit 0
    case "$c" in
        all) show_binds "" ;;
        search)
            local kw
            kw=$(dt_ask_text "搜索关键词" "输入动作名（如 focus）、键位（如 Super）或中文说明" "") || return 0
            [ -n "$kw" ] || return 0
            show_binds "$kw"
            ;;
        export) export_html ;;
        back) return 0 ;;
    esac
}

# 收集所有配置文件
all_config_files() {
    local f
    for f in "$MAIN" "$KEYB"; do
        [ -f "$f" ] && echo "$f"
    done
    # 也扫描 dms/binds.kdl 等（用户可能手动 include）
    find "$NIRI_DIR" -name '*.kdl' -type f 2>/dev/null | sort
}

show_binds() { # keyword
    local kw="${1:-}" kwlower=""
    [ -n "$kw" ] && kwlower=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
    local tmp
    tmp=$(mktemp)
    parse_binds $(all_config_files) > "$tmp" 2>/dev/null || true
    local total=0 matched=0
    while IFS=$'\t' read -r f sc k act args raw; do
        [ -z "${k:-}" ] && continue
        total=$((total+1))
        local hit=0
        if [ -n "$kw" ]; then
            local combined
            combined=$(printf '%s' "$k $act $args $raw" | tr '[:upper:]' '[:lower:]')
            case "$combined" in
                *"$kwlower"*) hit=1 ;;
            esac
        else
            hit=1
        fi
        if [ "$hit" -eq 1 ]; then
            matched=$((matched+1))
            local disabled=0 state=""
            if [ -f "$MAIN" ] && grep -q "\[dt-keybinds\]" "$MAIN" 2>/dev/null; then
                grep "\[dt-keybinds\]" "$MAIN" 2>/dev/null | grep -q "$k" && disabled=1
            fi
            [ "$disabled" -eq 1 ] && state=" ${DT_YELLOW}[已禁用]${DT_NC}"
            printf '  %-24s %-14s %-28s %s%s\n' \
                "$act" "${args:-}" "$k" "$raw" "$state"
        fi
    done < "$tmp"
    rm -f "$tmp"
    echo
    echo -e "  ${DT_BOLD}共 $total 条绑定，匹配 $matched 条${DT_NC}"
}

# ---------------------------------------------------------------------------
# 导出 HTML
# ---------------------------------------------------------------------------
export_html() {
    local out="${1:-$HOME/Downloads/niri-keybinds.html}"
    local tmp
    tmp=$(mktemp)
    parse_binds $(all_config_files) > "$tmp" 2>/dev/null || true

    local total=0
    {
        cat <<HTML
<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>niri 快捷键总表</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans",sans-serif;
     margin:0;padding:24px;background:#fafafa;color:#222;}
h1{font-size:22px;margin:0 0 6px;}
.meta{color:#777;font-size:13px;margin-bottom:18px;}
table{border-collapse:collapse;width:100%;background:#fff;box-shadow:0 1px 4px rgba(0,0,0,.08);
     border-radius:8px;overflow:hidden;}
th{background:#2b2b2b;color:#fff;text-align:left;padding:10px 14px;font-size:13px;
   font-weight:500;letter-spacing:.02em;}
td{padding:9px 14px;border-bottom:1px solid #eee;font-size:14px;vertical-align:top;}
tr:last-child td{border-bottom:none;}
tr:hover td{background:#f5f9ff;}
code{background:#f0f0f0;padding:2px 6px;border-radius:4px;font-size:13px;
     font-family:"SF Mono",Monaco,Consolas,monospace;}
.off{color:#aaa;}
.off td{color:#999;background:#fafafa;}
.src{color:#888;font-size:12px;}
</style></head><body>
<h1>niri 快捷键总表</h1>
<div class="meta">由 desktop-toolkit niri-keybinds.sh 生成 &nbsp;·&nbsp;
$(date '+%Y-%m-%d %H:%M')</div>
<table><thead><tr>
<th>动作</th><th>参数</th><th>键位</th><th>作用域</th><th>来源</th>
</tr></thead><tbody>
HTML
        while IFS=$'\t' read -r f sc k act args raw; do
            [ -z "${k:-}" ] && continue
            total=$((total+1))
            local off="" src=""
            src=$(basename "$f")
            if grep -q "\[dt-keybinds\]" "$MAIN" 2>/dev/null && \
               grep -q "$k" <(grep "\[dt-keybinds\]" "$MAIN" 2>/dev/null); then
                off="off"
            fi
            printf '<tr class="%s"><td><code>%s</code></td><td>%s</td><td><code>%s</code></td><td>%s</td><td class="src">%s</td></tr>\n' \
                "$off" "$act" "${args:-—}" "$k" "$sc" "$src"
        done < "$tmp"
        printf '</tbody></table>\n'
        printf '<div class="meta" style="margin-top:14px;">共 %d 条绑定</div>\n' "$total"
        printf '</body></html>\n'
    } > "$out"
    rm -f "$tmp"
    log "已导出: $out（$total 条绑定）"
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$out" >/dev/null 2>&1 &
    fi
}

# ---------------------------------------------------------------------------
# 状态总览
# ---------------------------------------------------------------------------
status_all() {
    echo -e "${DT_BOLD}═══ niri 快捷键状态 ═══${DT_NC}"
    local n
    n=$(disabled_count)
    echo -e "  主配置被注释的行: ${DT_YELLOW}$n${DT_NC}（用本工具可恢复）"
    if [ -f "$STATE" ]; then
        local enabled=0 custom=0
        while IFS= read -r line; do
            case "$line" in
                preset:*=*) [ "${line#*=%%##*}" = enabled ] && enabled=$((enabled+1)) ;;
                custom:*=*) [ "${line#*=%%##*}" = enabled ] && custom=$((custom+1)) ;;
            esac
        done < "$STATE"
        echo -e "  已启用预设: $enabled"
        echo -e "  自定义绑定: $custom"
    else
        echo "  暂无状态（未配置过）"
    fi
    echo -e "  主配置: $MAIN"
    echo -e "  本模块文件: $KEYB"
}

# ---------------------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------------------
uninstall() {
    remove_include
    rm -f "$KEYB" "$STATE"
    restore_line
    log "已卸载：移除 include + 删除 $KEYB/$STATE，恢复被注释的行"
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        local c
        c=$(dt_menu "niri 快捷键可视化配置" "预设开关 / 自定义绑定 / 浏览搜索 / 导出 HTML 快捷键表：" \
            "browse|1. 浏览与搜索|显示当前所有快捷键，支持关键词过滤" \
            "presets|2. 预设快捷键|按分类启用/关闭内置快捷键（可改键位）" \
            "custom|3. 自定义绑定|添加/删除自定义快捷键（写入 dt-keybinds.kdl）" \
            "export|4. 导出 HTML 快捷键表|生成网页版快捷键总表便于查阅" \
            "status|5. 状态总览|显示已启用预设 / 被注释行数" \
            "uninstall|6. 卸载|移除 include + 删除本模块文件" \
            "back|← 返回|" \
        ) || return 0
        case "$c" in
            browse) browse_menu ;;
            presets) preset_menu ;;
            custom) custom_menu ;;
            export) export_html ;;
            status) status_all ;;
            uninstall)
                if dt_confirm "确定卸载 niri 快捷键配置？\n会移除 include 与 dt-keybinds.kdl，并恢复被注释的行。"; then
                    uninstall
                fi ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    browse) browse_menu ;;
    presets) preset_menu ;;
    custom) custom_menu ;;
    export-html) export_html ;;
    status) status_all ;;
    uninstall) uninstall ;;
    "") main_menu ;;
    *) echo "用法: bash $0 [browse|presets|custom|export-html|status|uninstall]"; exit 1 ;;
esac