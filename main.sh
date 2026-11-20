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
source "$DT_ROOT/modules/appearance/gnome/lib-gnome.sh"

APPEARANCE="$DT_ROOT/modules/appearance"

# ---------------------------------------------------------------------------
# 子菜单：外观美化
# ---------------------------------------------------------------------------
sub_appearance() {
    while true; do
        local c
        c=$(dt_menu "外观美化" "桌面环境与 macOS 版本方案（KDE / GNOME 均支持 macOS 26 与 15）：" \
            "kde|① KDE 外观美化|macOS 26 Tahoe / 15 经典 安装切换 + 微调工具|gui" \
            "gnome|② GNOME 外观美化|macOS 26 / 15 方案（适用于 GNOME 系统）|gui" \
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
                else
                    cat /tmp/dt-config-list.txt   # TUI: 直接终端打印
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
                    "status|③ 查看状态|") || return 0
                bash "$DT_ROOT/modules/network/github-mirror.sh" "$action"
                dt_info "完成。查看/修改: 换 GH_PROXY 前缀后重跑 on。"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：窗口管理器 / 桌面方案
# ---------------------------------------------------------------------------
sub_wm() {
    while true; do
        local c
        c=$(dt_menu "窗口管理器 / 桌面方案" "平铺 Wayland 合成器与桌面外壳方案：" \
            "niri-dms|① 一键安装 Niri + DMS|滚动平铺 Niri + Dux Modular Shell(DMS) 桌面外壳" \
            "niri-noctalia|② 一键配置 Niri + Noctalia|Noctalia 桌面外壳(需已装 niri；Fedora 45+ 默认源)" \
            "niri-shell-switch|③ 切换桌面外壳(DMS ↔ Noctalia)|两个外壳同时开会抢顶栏, 这里关掉一个开另一个" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            niri-dms)
                if dt_confirm "一键安装 Niri + DMS（Dux Modular Shell）？\n需要网络 + sudo 密码，安装几分钟。"; then
                    bash "$DT_ROOT/modules/wm/niri-dms.sh"
                    dt_info "Niri + DMS 安装流程结束。注销后登录界面选 Niri 会话。"
                fi ;;
            niri-noctalia)
                if dt_confirm "为当前 niri 配置 Noctalia 桌面外壳？\n需要 sudo 密码安装 noctalia（Fedora 45+ 默认源）。"; then
                    bash "$DT_ROOT/modules/wm/niri-noctalia.sh"
                    dt_info "Niri + Noctalia 配置完成。注销后登录界面选 Niri 会话。"
                fi ;;
            niri-shell-switch)
                bash "$DT_ROOT/modules/wm/niri-shell-switch.sh"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：系统诊断（自动扫描 modules/system/ 下的脚本）
#   新增诊断工具只需往该目录丢一个 .sh，这里会自动出现（不需要改 main.sh）。
# ---------------------------------------------------------------------------
sub_system() {
    local dir="$DT_ROOT/modules/system"
    # 目录不存在时 find 返回非零，pipefail 下必须容错，否则 set -e 直接退出
    local -a files=() f
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        files+=("$f")
    done
    [ "${#files[@]}" -eq 0 ] && { sub_placeholder system system; return 0; }

    while true; do
        local -a rows=()
        for f in "${files[@]}"; do
            rows+=("$(basename "$f" .sh)|$(basename "$f")")
        done
        local c
        c=$(dt_menu "系统诊断" "诊断环境并按需一键修复：" \
            "${rows[@]}" "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        for f in "${files[@]}"; do
            [ "$(basename "$f" .sh)" = "$c" ] && bash "$f"
        done
    done
}

# ---------------------------------------------------------------------------
# 子菜单：系统配置 / 开发 / 备份（预留分类，后续往对应目录加脚本即可）
# ---------------------------------------------------------------------------
sub_placeholder() { # title
    local title="$1" dir="$2"
    # pipefail 下 find 对不存在的占位目录会返回非零，须容错，否则 set -e 直接退出
    local count
    count=$(find "$DT_ROOT/modules/$dir" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l) || true
    dt_info "$title\n\n该分类目前有 ${count} 个脚本。\n把新脚本放进 modules/$dir/ 后，这里会自动出现（后续可扩展自动扫描）。"
}

# ---------------------------------------------------------------------------
# 启动时检测 GNOME 安装进度: 有未完成步骤则直接在终端列出, 可一键恢复,
# 避免还要进 GUI 菜单逐层选择后才看到"可以恢复"。
# ---------------------------------------------------------------------------
dt_resume_gnome() {
    local -a pending=()          # 交替存放: version next_step
    local f ver next i idx gui_opt choice

    # 重新扫描(嵌套函数, 便于安装后再次调用)
    gn_scan_pending() {
        pending=()
        for f in "$GN_SRC_DIR"/.install-state-*; do
            [ -f "$f" ] || continue
            ver=$(sed -n 's/^version=//p' "$f" | head -1)
            next=$(sed -n 's/^next_step=//p' "$f" | head -1)
            case "$ver" in macos26|macos15|fluent) ;; *) continue ;; esac
            case "$next" in [2-6]) ;; *) continue ;; esac   # 只列真正未完成的
            pending+=("$ver" "$next")
        done
    }
    gn_scan_pending
    [ "${#pending[@]}" -eq 0 ] && return 0

    echo
    echo "──────────────────────────────────────────────"
    echo "发现未完成的安装进度："
    i=1
    for (( idx=0; idx<${#pending[@]}; idx+=2 )); do
        ver="${pending[idx]}"; next="${pending[idx+1]}"
        echo "  [$i] $(gn_version_label "$ver")  —— 第 $next/6 步（$(gn_step_label "$next")）"
        i=$((i+1))
    done
    gui_opt=$i
    echo "  [$gui_opt] 进入 GUI 菜单"
    echo "──────────────────────────────────────────────"
    read -r -p "选择操作（回车 = $gui_opt 进入 GUI 菜单）: " choice || true
    choice="${choice:-$gui_opt}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$gui_opt" ]; then
        ver="${pending[$(( (choice-1)*2 ))]}"
        next="${pending[$(( (choice-1)*2 + 1 ))]}"
        echo
        echo "==> 继续 $(gn_version_label "$ver") 安装：从步骤 $next/6（$(gn_step_label "$next")）"
        # 用户已在终端确认, 传给 install.sh 跳过其内部重复的"继续?"询问
        # || true: 安装失败也不能让 main.sh(set -e) 直接退出, 回提示让用户再选
        GN_FORCE_RESUME=1 bash "$DT_ROOT/modules/appearance/gnome/install.sh" "$ver" || true
        echo
        # 安装结束后重新检测: 已全部完成则直接结束, 不再弹 GUI 菜单
        gn_scan_pending
        if [ "${#pending[@]}" -eq 0 ]; then
            exit 0
        fi
        # 还有另一版本未完成 -> 继续在终端列
        dt_resume_gnome
        return 0
    fi
    return 0   # 无效输入或选择进 GUI 菜单
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
main() {
    dt_resume_gnome
    # TUI 模式提示（GUI=none 时 dt_menu 自动退化为文本菜单，不再需要 zenity/kdialog）
    if [ "$GUI" = none ]; then
        echo "未检测到 zenity / kdialog，已进入命令行(TUI)模式："
        echo "  - 需要 GUI 的选项已自动隐藏（如外观美化）"
        echo "  - 所有交互在终端完成"
        echo
    fi
    while true; do
        local c
        c=$(dt_menu "desktop-toolkit" "选择要执行的分类（脚本集中管理，拉下来即可用）：" \
            "appearance|① 外观美化|macOS 美化 / 主题 / 配置中心 / 性能模式|gui" \
            "wm|② 窗口管理器 / 桌面方案|Niri + DMS 等平铺 Wayland 方案" \
            "system|③ 系统诊断|会话/显示管理器/依赖体检（自动扫描 modules/system/）" \
            "network|④ 网络工具|代理 / 网络相关脚本（待扩展）" \
            "dev|⑤ 开发环境|开发工具与环境配置（待扩展）" \
            "backup|⑥ 备份与恢复|配置备份/还原（待扩展）" \
            "about|⑦ 关于 / 使用说明|查看仓库结构与用法" \
            "exit|⑧ 退出|") || exit 0
        case "$c" in
            exit) exit 0 ;;
            appearance) sub_appearance ;;
            wm) sub_wm ;;
            network) sub_network ;;
            system) sub_system ;;
            dev|backup) sub_placeholder "$c" "$c" ;;
            about)
                dt_info "desktop-toolkit\n\n仓库目录：$DT_ROOT\n\n用法：\n1) git clone 本仓库\n2) cd desktop-toolkit && ./main.sh\n3) 菜单选择对应分类，选中即开始\n\n脚本按分类放在 modules/ 下，公共库在 lib/，资源在 assets/。" ;;
        esac
    done
}

main "$@"
