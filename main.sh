#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit —— 桌面/系统脚本工具箱统一入口
# 用法： git clone <repo> ~/code/desktop-toolkit && cd ~/code/desktop-toolkit && ./main.sh
# 运行后全部用菜单选择，不需要记任何命令。
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

APPEARANCE="$DT_ROOT/modules/appearance"

# ---------------------------------------------------------------------------
# 子菜单：外观美化
# ---------------------------------------------------------------------------
sub_appearance() {
    while true; do
        local c
        c=$(dt_menu "外观美化" "macOS Tahoe 风格的桌面美化与实时调节：" \
            "config|① 桌面外观配置中心|最常用：圆角/透明度/Dock/Logo/窗口动画 等全部集中在这里" \
            "install|② 安装 macOS Tahoe 主题|首次部署用：拉取主题仓库并安装（跳过 SDDM/Plymouth）" \
            "mode-perf|③ 切换到性能模式|关闭液态玻璃，软件渲染流畅（VMware 推荐）" \
            "mode-full|④ 切换到完整模式|恢复液态玻璃特效（需硬件加速）" \
            "window-gui|⑤ 窗口调整滑块|单独打开圆角/透明度滑块界面" \
            "logo|⑥ 安装白色 CachyOS Logo|把 logo 资源装进主题图标目录并应用" \
            "list|⑦ 查看当前所有配置|打印可调项清单" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            config)
                [ -x "$APPEARANCE/config-center.sh" ] && "$APPEARANCE/config-center.sh" \
                    || dt_err_gui "缺少 $APPEARANCE/config-center.sh" ;;
            install)
                if dt_confirm "将安装 macOS Tahoe Liquid KDE 主题（需要 sudo，跳过 SDDM/Plymouth）。继续？"; then
                    bash "$APPEARANCE/install-theme.sh"
                    dt_info "主题安装流程已结束。"
                fi ;;
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
            list)
                "$APPEARANCE/adjust-window.sh" list > /tmp/dt-config-list.txt 2>&1 || true
                if [ "$GUI" = zenity ]; then
                    zenity --text-info --title="当前配置" --filename=/tmp/dt-config-list.txt \
                        --width=760 --height=640 2>/dev/null || true
                elif [ "$GUI" = kdialog ]; then
                    kdialog --title "当前配置" --textbox /tmp/dt-config-list.txt 760 640 2>/dev/null || true
                fi ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：系统配置 / 网络 / 开发 / 备份（预留分类，后续往对应目录加脚本即可）
# ---------------------------------------------------------------------------
sub_placeholder() { # title
    local title="$1" dir="$2"
    local count; count=$(find "$DT_ROOT/modules/$dir" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l)
    dt_info "$title\n\n该分类目前有 ${count} 个脚本。\n把新脚本放进 modules/$dir/ 后，这里会自动出现（后续可扩展自动扫描）。"
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
main() {
    if [ "$GUI" = none ]; then
        echo "未检测到 zenity / kdialog，无法打开图形菜单。"
        echo "请安装其一后重试：sudo pacman -S zenity   (或 kdialog)"
        exit 1
    fi
    while true; do
        local c
        c=$(dt_menu "desktop-toolkit" "选择要执行的分类（脚本集中管理，拉下来即可用）：" \
            "appearance|① 外观美化|macOS 美化 / 主题 / 配置中心 / 性能模式" \
            "system|② 系统配置|系统优化与服务配置（待扩展）" \
            "network|③ 网络工具|代理 / 网络相关脚本（待扩展）" \
            "dev|④ 开发环境|开发工具与环境配置（待扩展）" \
            "backup|⑤ 备份与恢复|配置备份/还原（待扩展）" \
            "about|⑥ 关于 / 使用说明|查看仓库结构与用法" \
            "exit|⑦ 退出|") || exit 0
        case "$c" in
            exit) exit 0 ;;
            appearance) sub_appearance ;;
            system|network|dev|backup) sub_placeholder "$c" "$c" ;;
            about)
                dt_info "desktop-toolkit\n\n仓库目录：$DT_ROOT\n\n用法：\n1) git clone 本仓库\n2) cd desktop-toolkit && ./main.sh\n3) 菜单选择对应分类，选中即开始\n\n脚本按分类放在 modules/ 下，公共库在 lib/，资源在 assets/。" ;;
        esac
    done
}

main "$@"
