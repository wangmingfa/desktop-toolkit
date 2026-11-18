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
}

main() {
    while true; do
        local c
        c=$(dt_menu "GNOME macOS 外观配置中心" \
            "选择要执行的操作（本模块支持 macOS 26 Tahoe 与 macOS 16 经典两套）：" \
            "install26|① 安装 macOS 26 (Tahoe 液态玻璃)|最新液态玻璃风格 (MacTahoe-gtk-theme)" \
            "install16|② 安装 macOS 16 (经典 Sequoia 风格)|经典大苏尔/索诺玛风格 (WhiteSur-gtk-theme)" \
            "status|③ 查看当前应用的主题|gsettings 当前值" \
            "dark|④ 切换深色模式|prefer-dark" \
            "light|⑤ 切换浅色模式|prefer-light" \
            "ext|⑥ 安装 GNOME 扩展|user-themes / dash-to-dock / blur-my-shell" \
            "back|← 返回|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            install26|install16)
                local v=$([ "$c" = install26 ] && echo macos26 || echo macos16)
                if dt_confirm "安装 $(gn_version_label "$v") 风格到 GNOME？（需要网络 + git，安装过程几分钟）"; then
                    bash "$GN_DIR/install.sh" "$v"
                    dt_info "$(gn_version_label "$v") 安装流程结束。\n若 Shell 未变，启用 user-themes 扩展后注销重登。"
                fi ;;
            status)
                dt_info "$(gn_current)" ;;
            dark)  gn_gs org.gnome.desktop.interface color-scheme prefer-dark;  dt_info "已切换到深色模式" ;;
            light) gn_gs org.gnome.desktop.interface color-scheme prefer-light; dt_info "已切换到浅色模式" ;;
            ext)
                if dt_confirm "安装并启用 user-themes / dash-to-dock / blur-my-shell？"; then
                    gn_install_extensions "${LAST_VER:-macos26}"
                    dt_info "扩展安装完成"
                fi ;;
        esac
    done
}

main "$@"
