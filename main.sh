#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit —— 桌面/系统脚本工具箱统一入口
# 用法： git clone <repo> ~/code/desktop-toolkit && cd ~/code/desktop-toolkit && ./main.sh
#   ./main.sh [--gui|--tui]   默认 gui（自动探测 zenity/kdialog，都没有则 TUI 兜底）；
#                             --tui 强制文本菜单模式（子模块一并继承）。
# 运行后全部用菜单选择，不需要记任何命令。
# =============================================================================
set -euo pipefail

# 解析运行模式参数：gui(默认, 自动探测) / tui(强制文本菜单)
# 必须在 source ui.sh 之前处理，并 export——模块都是 bash 子进程，靠环境变量继承。
DT_MODE=gui
for _arg in "$@"; do
    case "$_arg" in
        --gui) DT_MODE=gui ;;
        --tui) DT_MODE=tui ;;
        *) echo "未知参数: $_arg（可用: --gui | --tui，默认 --gui）" >&2; exit 1 ;;
    esac
done
if [ "$DT_MODE" = tui ]; then
    export GUI=none
fi

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
source "$DT_ROOT/modules/appearance/gnome/lib-gnome.sh"
dt_quit_clear   # 清上次残留的退出标志（模块内退出会写它）

APPEARANCE="$DT_ROOT/modules/appearance"

# ---------------------------------------------------------------------------
# 子菜单：外观美化
# ---------------------------------------------------------------------------
sub_appearance() {
    while true; do
        dt_quit_pending && exit 0
        local c
        c=$(dt_menu "外观美化" "桌面环境与 macOS 版本方案（KDE / GNOME 均支持 macOS 26 与 15）：" \
            "kde|KDE 外观美化|macOS 26 Tahoe / 15 经典 安装切换 + 微调工具|gui" \
            "gnome|GNOME 外观美化|macOS 26 / 15 方案（适用于 GNOME 系统）|gui" \
            "wbtn|窗口按钮布局|GTK/Electron 关闭按钮位置（macOS 左 / Windows 右）" \
            "fcitx5-style|fcitx5 输入法外观|中文输入法主题切换/下载/字体" \
            "mako-style|mako 通知样式|透明/圆角/位置（DMS 环境 mako 被屏蔽则提示）" \
            "font-manager|字体管理|已装字体列表 + Nerd Font 编程字体" \
            "list|查看当前所有配置|打印可调项清单" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            kde)
                bash "$APPEARANCE/kde-scheme.sh" ;;
            gnome)
                bash "$APPEARANCE/gnome/gnome-config-center.sh" ;;
            wbtn)
                bash "$APPEARANCE/window-buttons.sh" ;;
            fcitx5-style)
                bash "$APPEARANCE/fcitx5-style.sh" ;;
            mako-style)
                bash "$APPEARANCE/mako-style.sh" ;;
            font-manager)
                bash "$APPEARANCE/font-manager.sh" ;;
            list)
                bash "$APPEARANCE/adjust-window.sh" list > /tmp/dt-config-list.txt 2>&1 || true
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
        dt_quit_pending && exit 0
        local c
        c=$(dt_menu "网络工具" "网络相关脚本：" \
            "mirror|GitHub 国内镜像一键配置|对大陆网络下 github 慢/不通的场景" \
            "proxy|代理一键配置|git/dnf/pip/npm/cargo 代理 + no_proxy（受限网络）" \
            "speedtest|网络测速|speedtest-cli 测下行/上行/延迟" \
            "netmanager|网络连接管理|nmcli 状态/连接/Wi-Fi 开关" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            mirror)
                local action
                action=$(dt_menu "GitHub 镜像" "当前配置：" \
                    "on|启用镜像|把 github.com 重写到国内镜像（全局 git）" \
                    "off|关闭镜像|移除重写" \
                    "status|查看状态|") || return 0
                [ "$action" = __quit ] && exit 0
                bash "$DT_ROOT/modules/network/github-mirror.sh" "$action"
                dt_info "完成。查看/修改: 换 GH_PROXY 前缀后重跑 on。"
                ;;
            proxy)
                local action url
                action=$(dt_menu "代理配置" "为各工具配置/移除代理(URL 默认 http://127.0.0.1:7890)：" \
                    "on|配置代理|写入 git/dnf/pip/npm/cargo + 环境变量" \
                    "off|移除代理|清除上述全部代理" \
                    "status|查看状态|") || return 0
                [ "$action" = __quit ] && exit 0
                if [ "$action" = on ]; then
                    url=$(dt_ask_text "代理地址" "代理 URL（含协议）" "http://127.0.0.1:7890") || url="http://127.0.0.1:7890"
                    [ -n "$url" ] || url="http://127.0.0.1:7890"
                fi
                bash "$DT_ROOT/modules/network/proxy-setup.sh" "$action" "${url:-}"
                ;;
            speedtest)
                bash "$DT_ROOT/modules/network/speedtest.sh" ;;
            netmanager)
                bash "$DT_ROOT/modules/network/netmanager.sh" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：窗口管理器 / 桌面方案
# ---------------------------------------------------------------------------
sub_wm() {
    while true; do
        dt_quit_pending && exit 0
        local c
        c=$(dt_menu "窗口管理器 / 桌面方案" "平铺 Wayland 合成器与桌面外壳方案：" \
            "niri-dms|一键安装 niri + DMS|滚动平铺 niri + Dux Modular Shell(DMS) 桌面外壳" \
            "niri-noctalia|一键配置 niri + Noctalia|Noctalia 桌面外壳(需已装 niri；Fedora 45+ 默认源)" \
            "niri-shell-switch|切换桌面外壳(DMS ↔ Noctalia)|两个外壳同时开会抢顶栏, 这里关掉一个开另一个" \
            "niri-config|niri 可视化配置|常用配置菜单化: 布局/边框/阴影/输入/光标/显示器输出" \
            "niri-tools|niri 日常工具|截图/录屏/剪贴板历史 + 快捷键(Print/Super+P/Super+V)" \
            "niri-wallpaper|niri 壁纸/锁屏|原生 background-image 壁纸 + swaylock 锁屏样式" \
            "dms-theme|DMS 顶栏主题|dms matugen 生成 Material 主题(顶栏+niri+gtk+终端)" \
            "wm-installer|WM / 桌面环境安装器|KDE/GNOME/sway/i3/Hyprland 等常见 WM/DE, 发行版感知安装" \
            "niri-audio|niri 音频控制|音量/静音/媒体键快捷键(pamixer + playerctl)" \
            "wlsunset|niri 护眼色温|夜间屏幕调暖(wlsunset, 自动日落)" \
            "dms-topbar|DMS 顶栏监控|CPU/内存/磁盘/温度/网速/电池 组件开关" \
            "de-installer|一键安装 KDE/GNOME|依赖级清单(必须+可选, 逐项勾选)" \
            "niri-keybinds|niri 快捷键可视化配置|预设开关/自定义绑定/浏览搜索/导出 HTML" \
            "niri-ime|niri 输入法(fcitx5)|中文/日文/韩文输入法一键配置(拼音引擎+环境+自启动)" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            niri-dms)
                if dt_confirm "一键安装 niri + DMS（Dux Modular Shell）？\n需要网络 + sudo 密码，安装几分钟。"; then
                    bash "$DT_ROOT/modules/wm/niri-dms.sh"
                    dt_info "niri + DMS 安装流程结束。注销后登录界面选 niri 会话。"
                fi ;;
            niri-noctalia)
                if dt_confirm "为当前 niri 配置 Noctalia 桌面外壳？\n需要 sudo 密码安装 noctalia（Fedora 45+ 默认源）。"; then
                    bash "$DT_ROOT/modules/wm/niri-noctalia.sh"
                    dt_info "niri + Noctalia 配置完成。注销后登录界面选 niri 会话。"
                fi ;;
            niri-shell-switch)
                bash "$DT_ROOT/modules/wm/niri-shell-switch.sh"
                ;;
            niri-config)
                bash "$DT_ROOT/modules/wm/niri-config.sh"
                ;;
            niri-tools)
                bash "$DT_ROOT/modules/wm/niri-tools.sh"
                ;;
            niri-wallpaper)
                bash "$DT_ROOT/modules/wm/niri-wallpaper.sh"
                ;;
            dms-theme)
                bash "$DT_ROOT/modules/wm/niri-dms-theme.sh"
                ;;
            dms-topbar)
                bash "$DT_ROOT/modules/wm/dms-topbar.sh"
                ;;
            de-installer)
                bash "$DT_ROOT/modules/wm/de-installer.sh"
                ;;
            wm-installer)
                bash "$DT_ROOT/modules/wm/wm-installer.sh"
                ;;
            niri-audio)
                bash "$DT_ROOT/modules/wm/niri-audio.sh"
                ;;
            wlsunset)
                bash "$DT_ROOT/modules/wm/niri-wlsunset.sh"
                ;;
            niri-keybinds)
                bash "$DT_ROOT/modules/wm/niri-keybinds.sh"
                ;;
            niri-ime)
                bash "$DT_ROOT/modules/wm/niri-ime.sh"
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
        dt_quit_pending && exit 0
        local -a rows=()
        for f in "${files[@]}"; do
            rows+=("$(basename "$f" .sh)|$(basename "$f")")
        done
        local c
        c=$(dt_menu "系统诊断" "诊断环境并按需一键修复：" \
            "${rows[@]}" "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        for f in "${files[@]}"; do
            [ "$(basename "$f" .sh)" = "$c" ] && bash "$f"
        done
    done
}

# ---------------------------------------------------------------------------
# 子菜单：应用安装
# ---------------------------------------------------------------------------
sub_apps() {
    while true; do
        dt_quit_pending && exit 0
        local c
        c=$(dt_menu "应用安装" "应用级一键安装（镜像下载，适配受限网络）：" \
            "uu-remote|UU 远程 Linux 被控端|社区开源实现，官方客户端远程控制本机" \
            "wowtype|WowType 输入法|fcitx5 插件，镜像下载 + fcitx5 一键配置" \
            "app-installer|常用应用安装器|Chromium/Firefox/VLC/LibreOffice/Podman 等, 发行版感知" \
            "flatpak-mgr|Flatpak 应用管理|隔离运行 GUI 应用(装/卸/更新)" \
            "windows-games|Windows 游戏运行环境|Wine/Lutris/Steam 平台(勾选装)" \
            "qemu-installer|QEMU/KVM 虚拟机|QEMU+libvirt+UEFI+建虚拟机(装完直接加VM)" \
            "shells|Shell 安装器|fish/nushell/zsh 等(勾选装 / 切换 / 设默认)" \
            "lazyvim|LazyVim 一键安装|Neovim IDE 配置(依赖预检 / 可选件勾选装)" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            uu-remote)
                bash "$DT_ROOT/modules/apps/uu-remote.sh" ;;
            wowtype)
                bash "$DT_ROOT/modules/apps/wowtype.sh" ;;
            app-installer)
                bash "$DT_ROOT/modules/apps/app-installer.sh" ;;
            flatpak-mgr)
                bash "$DT_ROOT/modules/apps/flatpak-mgr.sh" ;;
            windows-games)
                bash "$DT_ROOT/modules/apps/windows-games.sh" ;;
            qemu-installer)
                bash "$DT_ROOT/modules/apps/qemu-installer.sh" ;;
            shells)
                bash "$DT_ROOT/modules/apps/shells.sh" ;;
            lazyvim)
                bash "$DT_ROOT/modules/apps/lazyvim.sh" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：开发环境
# ---------------------------------------------------------------------------
sub_dev() {
    while true; do
        dt_quit_pending && exit 0
        local c
        c=$(dt_menu "开发环境" "git 配置与常用开发工具：" \
            "setup|开发环境配置|git 身份/默认分支 + 工具安装（需 sudo）" \
            "fonts|字体安装|Nerd Fonts / 中文 CJK（终端/顶栏图标）" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            setup) bash "$DT_ROOT/modules/dev/setup-dev.sh" ;;
            fonts) bash "$DT_ROOT/modules/dev/install-fonts.sh" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 子菜单：备份与恢复
# ---------------------------------------------------------------------------
sub_backup() {
    while true; do
        dt_quit_pending && exit 0
        local c
        c=$(dt_menu "备份与恢复" "用户级配置备份/恢复（无需 sudo）：" \
            "backup|配置备份|打包 fcitx5/uuremote/niri/git 等配置" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            backup) bash "$DT_ROOT/modules/backup/backup-config.sh" ;;
        esac
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
        if [ "$DT_MODE" = tui ]; then
            echo "已按 --tui 强制进入命令行模式："
        else
            echo "未检测到 zenity / kdialog，已进入命令行(TUI)模式："
        fi
        echo "  - 需要 GUI 的选项已自动隐藏（如外观美化）"
        echo "  - 所有交互在终端完成"
        echo
    fi
    while true; do
        local c
        c=$(dt_menu "desktop-toolkit" "选择要执行的分类（脚本集中管理，拉下来即可用）：" \
            "appearance|外观美化|macOS 美化 / 主题 / 配置中心 / 性能模式|gui" \
            "wm|窗口管理器 / 桌面方案|niri + DMS 等平铺 Wayland 方案" \
            "system|系统诊断|会话/显示管理器/依赖体检（自动扫描 modules/system/）" \
            "network|网络工具|GitHub 镜像 / 代理配置 / 网络相关脚本" \
            "apps|应用安装|UU 远程 等应用一键安装（受限网络镜像）" \
            "dev|开发环境|开发工具与环境配置（待扩展）" \
            "backup|备份与恢复|配置备份/还原（待扩展）" \
            "about|关于 / 使用说明|查看仓库结构与用法") || exit 0
        case "$c" in
            __quit) exit 0 ;;
            appearance) sub_appearance ;;
            wm) sub_wm ;;
            network) sub_network ;;
            system) sub_system ;;
            apps) sub_apps ;;
            dev) sub_dev ;;
            backup) sub_backup ;;
            about)
                dt_info "desktop-toolkit\n\n仓库目录：$DT_ROOT\n\n用法：\n1) git clone 本仓库\n2) cd desktop-toolkit && ./main.sh\n3) 菜单选择对应分类，选中即开始\n\n脚本按分类放在 modules/ 下，公共库在 lib/，资源在 assets/。" ;;
        esac
    done
}

main "$@"
