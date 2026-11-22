#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit / 交互控件库
# 自适应：容器用 zenity，宿主机 KDE 用 kdialog
# 使用前先 source common.sh（提供 dt_detect_gui）
# =============================================================================

GUI="${GUI:-$(dt_detect_gui)}"

# 全局退出标志：dt_menu 追加"退出程序"项，选中即写标志并返回 __quit；
# 各菜单循环加 __quit) exit 0 实现从任意层级直接退出；main.sh 子菜单循环顶
# 再查标志，让"模块内退出"连带退出主程序（模块是子进程，exit 杀不到父进程）。
DT_QUIT_FLAG="${DT_QUIT_FLAG:-${TMPDIR:-/tmp}/dt_quit_flag}"
dt_quit_set() { touch "$DT_QUIT_FLAG"; }
dt_quit_clear() { rm -f "$DT_QUIT_FLAG"; }
dt_quit_pending() { [ -f "$DT_QUIT_FLAG" ]; }

# dt_menu：GUI 用 zenity/kdialog；GUI=none 时退化为文本菜单(TUI)。
# 行格式: "key|label|desc[|gui]" —— 第 4 字段为 gui 表示"需要 GUI 环境"，
# 在 TUI(GUI=none)下自动隐藏该行。
dt_menu() { # title text "key|label|desc[|gui]" ...
    local title="$1" text="$2"; shift 2
    local -a rows=()
    local row key label desc needgui
    for row in "$@"; do
        IFS='|' read -r key label desc needgui <<< "$row"
        [ "$GUI" = none ] && [ "$needgui" = gui ] && continue   # TUI 隐藏 GUI 专属项
        rows+=("$row")
    done
    # 统一追加"退出程序"：任何菜单都能直接退出（选中→写标志+返回 __quit，
    # 各菜单循环 __quit) exit 0 处理；主菜单不再需要单独 exit 项）。
    rows+=("__quit|退出程序|直接退出本程序")
    if [ "$GUI" = zenity ]; then
        local args=()
        for row in "${rows[@]}"; do
            IFS='|' read -r key label desc _ <<< "$row"
            args+=("$key" "$label" "$desc")
        done
        local sel
        sel=$(zenity --list --title="$title" --text="$text" --width=760 --height=640 \
            --column="编号" --column="选项" --column="说明" \
            --print-column=1 "${args[@]}" 2>/dev/null) || return 1
        [ "$sel" = __quit ] && dt_quit_set
        echo "$sel"
    elif [ "$GUI" = kdialog ]; then
        local args=()
        for row in "${rows[@]}"; do
            IFS='|' read -r key label desc _ <<< "$row"
            [ -n "$desc" ] && args+=("$key" "$label — $desc") || args+=("$key" "$label")
        done
        local sel
        sel=$(kdialog --title "$title" --geometry 760x640 --menu "$text" "${args[@]}" 2>/dev/null) || return 1
        [ "$sel" = __quit ] && dt_quit_set
        echo "$sel"
    else
        # TUI：编号文本菜单。菜单/提示走 stderr（dt_menu 常被 $( ) 捕获返回值，
        # stdout 只输出所选 key；否则菜单文本会被命令替换吞掉，用户看不到）。
        echo >&2
        echo "──────────────── $title ────────────────" >&2
        [ -n "$text" ] && echo "$text" >&2
        local i=0 choice
        for row in "${rows[@]}"; do
            IFS='|' read -r key label desc _ <<< "$row"
            i=$((i+1))
            if [ -n "$desc" ]; then
                printf '  %2d) %-28s %s\n' "$i" "$label" "($desc)" >&2
            else
                printf '  %2d) %s\n' "$i" "$label" >&2
            fi
        done
        [ "$i" -eq 0 ] && { echo "  （无可用选项，本菜单在 TUI 模式下为空）" >&2; return 0; }
        printf '请选择 [1-%d]（回车取消）: ' "$i" >&2
        # 回车/无效/EOF 均视为"取消"(返回非零)，与 GUI 分支 zenity 取消一致；
        # 调用方用 || return 0 / || exit 0 处理回退或退出，避免无输入时菜单死循环。
        read -r choice || return 1
        [[ "$choice" =~ ^[0-9]+$ ]] || return 1
        [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ] || return 1
        IFS='|' read -r key _ _ _ <<< "${rows[$((choice-1))]}"
        [ "$key" = __quit ] && dt_quit_set
        echo "$key"
    fi
}

dt_ask_num() { # title text value min max step
    if [ "$GUI" = zenity ]; then
        zenity --scale --title="$1" --text="$2" --value="$3" \
            --min-value="$4" --max-value="$5" --step="$6" --width=480 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "$1" --inputbox "$2 ($4-$5)" "$3" 2>/dev/null
    else
        local v
        printf '%s [%s]（%s-%s）: ' "$1" "$3" "$4" "$5" >&2
        read -r v || return 0
        [ -n "$v" ] || v="$3"
        echo "$v"
    fi
}

dt_ask_text() { # title text default_value
    if [ "$GUI" = zenity ]; then
        zenity --entry --title="$1" --text="$2" --entry-text="${3:-}" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "$1" --inputbox "$2" "${3:-}" 2>/dev/null
    else
        local v
        printf '%s' "$1" >&2
        [ -n "${3:-}" ] && printf ' [%s]' "$3" >&2
        printf ': ' >&2
        read -r v || return 0
        [ -n "$v" ] || v="${3:-}"
        echo "$v"
    fi
}

dt_confirm() {
    if [ "$GUI" = zenity ]; then
        zenity --question --title="确认" --text="$(printf '%b' "$1")" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "确认" --yesno "$(printf '%b' "$1")" 2>/dev/null
    else
        local ans
        printf '%b [y/N] ' "$1" >&2
        read -r ans || return 1
        case "${ans:-}" in y|Y|yes|YES|是) return 0 ;; *) return 1 ;; esac
    fi
}

dt_info() {
    if [ "$GUI" = zenity ]; then
        zenity --info --title="完成" --text="$(printf '%b' "$1")" 2>/dev/null || true
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "完成" --msgbox "$(printf '%b' "$1")" 2>/dev/null || true
    else
        printf '%b\n' "$1"
    fi
}

dt_err_gui() {
    if [ "$GUI" = zenity ]; then
        zenity --error --title="错误" --text="$1" 2>/dev/null || true
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "错误" --error "$1" 2>/dev/null || true
    else
        echo "错误: $1" >&2
    fi
}
