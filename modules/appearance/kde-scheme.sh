#!/usr/bin/env bash
# =============================================================================
# KDE Plasma macOS 外观方案统一入口
# 支持两套（二选一，会互相覆盖）：
#   macOS 26 (Tahoe 液态玻璃)  -> MacTahoe Liquid KDE
#   macOS 16 (经典 Sequoia)    -> WhiteSur-kde
# 安装后可用对应方案的微调工具；本入口在 main.sh「外观美化 -> KDE 外观美化」。
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

APPEARANCE="$DT_ROOT/modules/appearance"

kde_show_list() {
    "$APPEARANCE/adjust-window.sh" list > /tmp/dt-config-list.txt 2>&1 || true
    if [ "$GUI" = zenity ]; then
        zenity --text-info --title="当前配置" --filename=/tmp/dt-config-list.txt \
            --width=760 --height=640 2>/dev/null || true
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "当前配置" --textbox /tmp/dt-config-list.txt 760 640 2>/dev/null || true
    fi
}

main() {
    while true; do
        local c
        c=$(dt_menu "KDE 外观美化" \
            "KDE Plasma 的 macOS 风格方案。安装前先选版本，两套会互相覆盖（二选一）：" \
            "install26|① 安装 macOS 26 (Tahoe 液态玻璃)|MacTahoe Liquid KDE，当前默认方案" \
            "install16|② 安装 macOS 16 (经典 Sequoia)|WhiteSur-kde" \
            "config|③ 桌面外观配置中心|macOS 26 微调：圆角/透明度/Dock/Logo/窗口动画" \
            "mode-perf|④ 切换到性能模式|关闭液态玻璃，软件渲染流畅（VMware 推荐）" \
            "mode-full|⑤ 切换到完整模式|恢复液态玻璃特效（需硬件加速）" \
            "window-gui|⑥ 窗口调整滑块|单独打开圆角/透明度滑块界面" \
            "logo|⑦ 安装白色 CachyOS Logo|macOS 26 Tahoe 的顶栏 Logo" \
            "list|⑧ 查看当前所有可调项|打印清单" \
            "back|← 返回|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            install26)
                if dt_confirm "安装 macOS 26 (Tahoe Liquid KDE)？需要 sudo，跳过 SDDM/Plymouth。"; then
                    bash "$APPEARANCE/install-theme.sh"
                    dt_info "macOS 26 安装流程已结束。"
                fi ;;
            install16)
                if dt_confirm "安装 macOS 16 经典 (WhiteSur-kde)？需要网络 + git。"; then
                    bash "$APPEARANCE/install-kde-sequoia.sh"
                    dt_info "WhiteSur 安装流程已结束。去 系统设置->外观 选择 WhiteSur 应用。"
                fi ;;
            config)
                [ -x "$APPEARANCE/config-center.sh" ] && "$APPEARANCE/config-center.sh" \
                    || dt_err_gui "缺少 $APPEARANCE/config-center.sh" ;;
            mode-perf|mode-full)
                local mode=$([ "$c" = mode-perf ] && echo perf || echo full)
                if dt_confirm "切换到 $([ "$mode" = perf ] && echo 性能模式 || echo 完整模式)？"; then
                    bash "$APPEARANCE/toggle-glass.sh" "$mode"
                    dt_info "已切换。KWin 配置通常重新登录一次后完全生效。"
                fi ;;
            window-gui)
                "$APPEARANCE/adjust-window.sh" gui ;;
            logo)
                bash "$APPEARANCE/install-logo.sh"
                dt_info "白色 CachyOS Logo 已安装并应用。" ;;
            list) kde_show_list ;;
        esac
    done
}

main "$@"
