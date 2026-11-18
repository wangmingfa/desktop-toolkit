#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit / 交互控件库
# 自适应：容器用 zenity，宿主机 KDE 用 kdialog
# 使用前先 source common.sh（提供 dt_detect_gui）
# =============================================================================

GUI="$(dt_detect_gui)"

dt_menu() { # title text "key|label|desc" ...
    local title="$1" text="$2"; shift 2
    if [ "$GUI" = zenity ]; then
        local args=() row key label desc
        for row in "$@"; do
            IFS='|' read -r key label desc <<< "$row"
            args+=("$key" "$label" "$desc")
        done
        zenity --list --title="$title" --text="$text" --width=560 --height=560 \
            --column="编号" --column="选项" --column="说明" \
            --print-column=1 "${args[@]}" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        local args=() row key label desc
        for row in "$@"; do
            IFS='|' read -r key label desc <<< "$row"
            [ -n "$desc" ] && args+=("$key" "$label — $desc") || args+=("$key" "$label")
        done
        kdialog --title "$title" --menu "$text" "${args[@]}" 2>/dev/null
    fi
}

dt_ask_num() { # title text value min max step
    if [ "$GUI" = zenity ]; then
        zenity --scale --title="$1" --text="$2" --value="$3" \
            --min-value="$4" --max-value="$5" --step="$6" --width=480 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "$1" --inputbox "$2 ($4-$5)" "$3" 2>/dev/null
    fi
}

dt_ask_text() { # title text default_value
    if [ "$GUI" = zenity ]; then
        zenity --entry --title="$1" --text="$2" --entry-text="${3:-}" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "$1" --inputbox "$2" "${3:-}" 2>/dev/null
    fi
}

dt_confirm() {
    if [ "$GUI" = zenity ]; then
        zenity --question --title="确认" --text="$1" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "确认" --yesno "$1" 2>/dev/null
    fi
}

dt_info() {
    if [ "$GUI" = zenity ]; then
        zenity --info --title="完成" --text="$1" 2>/dev/null || true
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "完成" --msgbox "$1" 2>/dev/null || true
    fi
}

dt_err_gui() {
    if [ "$GUI" = zenity ]; then
        zenity --error --title="错误" --text="$1" 2>/dev/null || true
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "错误" --error "$1" 2>/dev/null || true
    fi
}
