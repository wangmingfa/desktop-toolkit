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
        c=$(dt_menu "外观美化" "桌面环境与 macOS 版本方案（KDE / GNOME 均支持 macOS 26 与 15）：" \
            "kde|① KDE 外观美化|macOS 26 Tahoe / 15 经典 安装切换 + 微调工具" \
            "gnome|② GNOME 外观美化|macOS 26 / 15 方案（适用于 GNOME 系统）" \
            "list|③ 查看当前所有配置|打印可调项清单" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            kde)
                bash "$APPEARANCE/kde-scheme.sh" ;;
            gnome)
                bash "$APPEARANCE/gnome/gnome-config-center.sh" ;;
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
# 子菜单：网络工具
# ---------------------------------------------------------------------------
sub_network() {
    while true; do
        local c
        c=$(dt_menu "网络工具" "网络相关脚本：" \
            "mirror|① GitHub 国内镜像一键配置|对大陆网络下 github 慢/不通的场景" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            mirror)
                local action
                action=$(dt_menu "GitHub 镜像" "当前配置：" \
                    "on|① 启用镜像|把 github.com 重写到国内镜像（全局 git）" \
                    "off|② 关闭镜像|移除重写" \
                    "status|③ 查看状态|") || continue
                bash "$DT_ROOT/modules/network/github-mirror.sh" "$action"
                dt_info "完成。查看/修改: 换 GH_PROXY 前缀后重跑 on。"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：系统配置 / 开发 / 备份（预留分类，后续往对应目录加脚本即可）
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
            network) sub_network ;;
            system|dev|backup) sub_placeholder "$c" "$c" ;;
            about)
                dt_info "desktop-toolkit\n\n仓库目录：$DT_ROOT\n\n用法：\n1) git clone 本仓库\n2) cd desktop-toolkit && ./main.sh\n3) 菜单选择对应分类，选中即开始\n\n脚本按分类放在 modules/ 下，公共库在 lib/，资源在 assets/。" ;;
        esac
    done
}

main "$@"
