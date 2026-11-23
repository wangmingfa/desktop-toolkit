#!/usr/bin/env bash
# =============================================================================
# GNOME macOS 外观配置中心
# 交互式选择 macOS 版本(26 Tahoe / 16 经典)、安装、切换深浅色、查看状态。
# 需在 GNOME 桌面的终端中运行；GUI 自适应 zenity / kdialog。
# =============================================================================
set -euo pipefail

GN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$GN_DIR/../../../lib/common.sh"
source "$GN_DIR/../../../lib/ui.sh"
source "$GN_DIR/lib-gnome.sh"

gn_current() {
    echo "当前 GTK 主题  : $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo '?')"
    echo "当前图标主题  : $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo '?')"
    echo "当前光标主题  : $(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || echo '?')"
    echo "当前 Shell 主题: $(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null || echo '(未启用 user-themes)')"
    echo "当前颜色方案  : $(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo '?')"
    echo "当前窗口按钮  : $(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null || echo '?')"
}

main() {
    while true; do
        local c
        c=$(dt_menu "GNOME macOS 外观配置中心" \
            "选择要执行的操作（本模块支持 macOS 26 Tahoe 与 macOS 15 经典两套）：" \
            "install26|1. 安装 macOS 26 (Tahoe 液态玻璃)|最新液态玻璃风格 (MacTahoe-gtk-theme)" \
            "install15|2. 安装 macOS 15 (经典 Sequoia 风格)|经典大苏尔/索诺玛风格 (WhiteSur-gtk-theme)" \
            "installfluent|3. 安装 Windows 11 (Fluent 风格)|非 macOS 圆角/Mica 质感 (Fluent-gtk-theme)" \
            "status|4. 查看当前应用的主题|gsettings 当前值" \
            "dark|5. 切换深色模式|prefer-dark" \
            "light|6. 切换浅色模式|prefer-light" \
            "ext|7. 安装/启用 GNOME 扩展|user-themes / dash-to-dock / blur-my-shell（自动配置）" \
            "buttons|8. 窗口按钮位置|macOS 红黄绿在左 / GNOME 默认在右" \
            "back|← 返回|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            install26|install15|installfluent)
                local v
                case "$c" in
                    install26) v=macos26 ;;
                    install15) v=macos15 ;;
                    installfluent) v=fluent ;;
                esac
                if dt_confirm "安装 $(gn_version_label "$v") 风格到 GNOME？（需要网络 + git，安装过程几分钟）"; then
                    bash "$GN_DIR/install.sh" "$v"
                    dt_info "$(gn_version_label "$v") 安装流程结束。\n若 Shell 未变，启用 user-themes 扩展后注销重登。"
                fi ;;
            status)
                dt_info "$(gn_current)" ;;
            dark)  gn_switch_color_scheme dark;  dt_info "已切换到深色模式" ;;
            light) gn_switch_color_scheme light; dt_info "已切换到浅色模式" ;;
            ext)
                if dt_confirm "安装并启用 user-themes / dash-to-dock / blur-my-shell？"; then
                    gn_install_extensions "${LAST_VER:-macos26}"
                    dt_info "扩展安装完成"
                fi ;;
            buttons)
                local bl choice
                bl=$(gn_button_layout)
                choice=$(dt_menu "窗口按钮位置" \
                    "当前: $([ "$bl" = left ] && echo '左侧 (macOS 红黄绿)' || echo '右侧 (GNOME 默认)')" \
                    "left|左侧 (macOS)|红黄绿 close,minimize,maximize 在左上角" \
                    "right|右侧 (GNOME)|appmenu:minimize,maximize,close 在右上角" \
                    "back|← 返回|") || continue
                [ "$choice" = __quit ] && exit 0
                [ -z "$choice" ] || [ "$choice" = back ] && continue
                gn_set_button_layout "$choice"
                dt_info "窗口按钮已设为$([ "$choice" = left ] && echo '左侧 (macOS 红黄绿)' || echo '右侧 (GNOME 默认)')。\n已打开的窗口需重开或注销重登后生效。"
                ;;
        esac
    done
}

main "$@"
