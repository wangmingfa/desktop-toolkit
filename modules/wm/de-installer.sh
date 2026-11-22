#!/usr/bin/env bash
# =============================================================================
# de-installer.sh —— 一键安装 KDE/GNOME 桌面环境（依赖级清单，逐包可选）
#
# 与 wm-installer 的"整组 dnf group install"不同：本模块列出每个依赖的
# 作用 + 必须/可选分类，可选依赖默认全勾选、可逐项去掉勾选，再一次性安装。
# 只装包，不碰用户现有配置（niri 会话不受影响；装完注销登录界面选会话）。
#
# 用法: bash de-installer.sh [gnome|kde|help <gnome|kde>|list <gnome|kde>]
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_BOLD=$'\033[1m'; DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'
    DT_CYAN=$'\033[0;36m'; DT_RED=$'\033[0;31m'; DT_NC=$'\033[0m'
else
    DT_BOLD=""; DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_NC=""
fi

de_log() { echo -e "  ${DT_CYAN}[de-installer]${DT_NC} $*"; }
de_err() { echo -e "  ${DT_RED}[de-installer] 错误:${DT_NC} $*" >&2; }

# ---------------------------------------------------------------------------
# 依赖目录：de|id|required(1必/0选)|package|作用
# ---------------------------------------------------------------------------
de_catalog() {
    cat <<'EOF'
gnome|gnome-shell|1|gnome-shell|GNOME 桌面外壳（顶栏/概览/应用网格）
gnome|gnome-session|1|gnome-session|会话管理器（登录后启动 GNOME）
gnome|gdm|1|gdm|显示管理器（登录界面，选 GNOME 会话）
gnome|gnome-control-center|1|gnome-control-center|设置中心（外观/显示/网络/用户）
gnome|gnome-console|1|gnome-console|终端（GNOME Console）
gnome|nautilus|1|nautilus|文件管理器
gnome|gnome-text-editor|1|gnome-text-editor|文本编辑器
gnome|xorg-x11-server-Xwayland|1|xorg-x11-server-Xwayland|X11 兼容层（Wayland 下运行 X 应用）
gnome|pipewire|1|pipewire|音频服务（Wayland 音频后端）
gnome|wireplumber|1|wireplumber|音频会话管理
gnome|gvfs|1|gvfs|虚拟文件系统（挂载/回收站/网络）
gnome|gnome-tweaks|0|gnome-tweaks|高级设置（主题/字体/扩展微调）
gnome|gnome-software|0|gnome-software|软件中心（GUI 安装/更新应用）
gnome|gnome-extensions-app|0|gnome-extensions-app|扩展管理 GUI
gnome|gnome-classic-session|0|gnome-classic-session|经典会话（GNOME Flashback）
gnome|gdm-settings|0|gdm-settings|GDM 登录界面设置
gnome|gnome-calendar|0|gnome-calendar|日历
gnome|gnome-weather|0|gnome-weather|天气
gnome|gnome-clocks|0|gnome-clocks|时钟/世界时间
gnome|gnome-maps|0|gnome-maps|地图
gnome|gnome-calculator|0|gnome-calculator|计算器
gnome|gnome-disk-utility|0|gnome-disk-utility|磁盘工具（分区/格式化/健康）
gnome|gnome-system-monitor|0|gnome-system-monitor|系统监视器（CPU/内存/进程）
gnome|evince|0|evince|PDF/文档阅读器
gnome|eog|0|eog|图片查看器
gnome|file-roller|0|file-roller|归档管理器（压缩/解压）
gnome|gnome-terminal|0|gnome-terminal|传统终端（GNOME Terminal）
gnome|gnome-browser-connector|0|gnome-browser-connector|浏览器集成（Shell 与浏览器通讯）
kde|plasma-workspace|1|plasma-workspace|Plasma 桌面核心（外壳/面板/窗口管理）
kde|plasma-desktop|1|plasma-desktop|Plasma 桌面基础（默认应用/桌面行为）
kde|sddm|1|sddm|显示管理器（KDE 登录界面）
kde|konsole|1|konsole|终端（KDE Konsole）
kde|dolphin|1|dolphin|文件管理器
kde|systemsettings|1|systemsettings|系统设置（外观/网络/输入法/硬件）
kde|breeze|1|breeze|默认主题/窗口装饰（Breeze）
kde|xorg-x11-server-Xwayland|1|xorg-x11-server-Xwayland|X11 兼容层（Wayland 下运行 X 应用）
kde|pipewire|1|pipewire|音频服务（Wayland 音频后端）
kde|wireplumber|1|wireplumber|音频会话管理
kde|kate|0|kate|文本编辑器（KDE Kate）
kde|gwenview|0|gwenview|图片查看器
kde|okular|0|okular|PDF/文档阅读器
kde|ark|0|ark|归档管理器（压缩/解压）
kde|kcalc|0|kcalc|计算器
kde|plasma-nm|0|plasma-nm|网络管理小程序（Wi-Fi/以太网托盘）
kde|plasma-pa|0|plasma-pa|音量小程序（托盘音量）
kde|bluedevil|0|bluedevil|蓝牙管理（托盘蓝牙）
kde|kde-print-manager|0|kde-print-manager|打印管理（打印机配置）
kde|kde-gtk-config|0|kde-gtk-config|GTK 应用外观适配 KDE 主题
kde|kmail|0|kmail|邮件客户端（KMail）
kde|kcharselect|0|kcharselect|字符选择器
EOF
}

# 取目录字段：de_field <de> <id> <col>
de_field() {
    de_catalog | awk -F'|' -v d="$1" -v i="$2" -v c="$3" '$1==d && $2==i {print $c; exit}'
}
de_has() { # de_field 非空判断
    [ -n "$(de_field "$1" "$2" "$3")" ]
}
de_count() { # de_count <de> <req> → 数量
    de_catalog | awk -F'|' -v d="$1" -v r="$2" '$1==d && $3==r {n++} END {print n+0}'
}
de_installed() { # 核心包是否已装（判断整个 DE 是否已装）
    case "$1" in
        gnome) rpm -q gnome-shell >/dev/null 2>&1 ;;
        kde) rpm -q plasma-workspace >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 安装（must = 全部必须包 + 勾选的可选包）
# ---------------------------------------------------------------------------
de_do_install() { # <de> <可选 id...>
    local de="$1"; shift
    local -a pkgs=() optids=()
    local id req pkg
    # 必须包（全部）
    while IFS='|' read -r d i r p _; do
        [ "$d" = "$de" ] && [ "$r" = 1 ] && pkgs+=("$p")
    done < <(de_catalog)
    # 勾选的可选包
    for id in "$@"; do
        pkg=$(de_field "$de" "$id" 4)
        [ -n "$pkg" ] && pkgs+=("$pkg") && optids+=("$id")
    done
    local nopt=${#optids[@]} nreq ntotal
    nreq=$(de_count "$de" 1); ntotal=${#pkgs[@]}
    de_log "将安装 ${ntotal} 个包（${nreq} 必须 + ${nopt} 可选）..."
    [ "$nopt" -eq 0 ] && de_log "未勾选任何可选依赖，只装必须包。"
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        de_err "安装需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    dt_confirm "安装 $de 的 ${ntotal} 个包？\n需要 sudo 密码，下载量可能较大（弱网中断重跑可续装）。\n\n继续？" || return 0
    de_log "dnf install -y ${#pkgs[@]} 个包 ..."
    if sudo dnf install -y "${pkgs[@]}"; then
        de_log "✅ $de 依赖安装完成。注销后登录界面选择 $de 会话。"
        if [ "$de" = kde ]; then
            de_log "KDE 登录界面默认由 SDDM 提供；如当前用 GDM 可在登录界面切换会话。"
        fi
    else
        de_err "安装失败（可能中断，重跑续装）。手动: sudo dnf install -y ${pkgs[*]}"
    fi
}

# ---------------------------------------------------------------------------
# 勾选菜单（ui.sh 无多选：自建"点击切换 + 确认安装"）
# ---------------------------------------------------------------------------
de_in_sel() { # de_in_sel <id> <sel...>
    local x
    for x in "${@:2}"; do [ "$x" = "$1" ] && return 0; done
    return 1
}

de_menu_select() { # <gnome|kde>
    local de="$1"
    local -a sel=()
    local id req
    # 可选依赖默认全勾选（一键安装；用户可去掉勾选）
    while IFS='|' read -r d i r _; do
        [ "$d" = "$de" ] && [ "$r" = 0 ] && sel+=("$i")
    done < <(de_catalog)

    local nreq nopt
    nreq=$(de_count "$de" 1); nopt=$(de_count "$de" 0)
    if de_installed "$de"; then
        de_log "$de 核心已安装。可补装可选依赖或重装。"
    fi

    while true; do
        local -a rows=()
        local pkg purpose d i r
        while IFS='|' read -r d i r pkg purpose; do
            [ "$d" = "$de" ] || continue
            local ins=""
            rpm -q "$pkg" >/dev/null 2>&1 && ins=" ✓已装"
            if [ "$r" = 1 ]; then
                rows+=("req-$i|[*] $pkg|${purpose}${ins}（必须）")
            elif de_in_sel "$i" "${sel[@]}"; then
                rows+=("$i|[x] $pkg|${purpose}${ins}")
            else
                rows+=("$i|[ ] $pkg|${purpose}${ins}")
            fi
        done < <(de_catalog)
        rows+=("__install|▶ 安装所选|已勾选 ${#sel[@]} 可选 + $nreq 必须，需 sudo" "back|← 返回|")

        local c
        c=$(dt_menu "$de 依赖选择（*必须不可取消 / [x]可选勾选，点击切换）" \
            "共 $nreq 必须 + $nopt 可选；可选默认全勾，点击取消。" \
            "${rows[@]}") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            __install) de_do_install "$de" "${sel[@]}"; return 0 ;;
            req-*) : ;;  # 必须依赖不可取消
            *)
                if de_in_sel "$c" "${sel[@]}"; then
                    local -a news=(); local x
                    for x in "${sel[@]}"; do [ "$x" != "$c" ] && news+=("$x"); done
                    sel=("${news[@]}")
                else
                    sel+=("$c")
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 依赖说明（只读，列出全部依赖的作用 + 必须/可选）
# ---------------------------------------------------------------------------
de_help() { # <gnome|kde>
    local de="$1"
    local -a lines=()
    local d i r pkg purpose ins
    while IFS='|' read -r d i r pkg purpose; do
        [ "$d" = "$de" ] || continue
        ins=""; rpm -q "$pkg" >/dev/null 2>&1 && ins="（已装）"
        local tag
        if [ "$r" = 1 ]; then tag="必须"; else tag="可选"; fi
        lines+=("$(printf '  %-9s %-28s %s' "$tag" "$pkg" "${purpose}${ins}")")
    done < <(de_catalog)
    local title
    case "$de" in
        gnome) title="GNOME 依赖清单（$(de_count "$de" 1) 必须 + $(de_count "$de" 0) 可选）" ;;
        kde) title="KDE Plasma 依赖清单（$(de_count "$de" 1) 必须 + $(de_count "$de" 0) 可选）" ;;
    esac
    dt_info "$title\n$(printf '%s\n' "${lines[@]}")"
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
de_menu() {
    while true; do
        local c
        c=$(dt_menu "一键安装 KDE / GNOME" "依赖级清单安装（必须+可选，逐项勾选）：" \
            "gnome|1. 安装 GNOME|${DT_GREEN}11 必须 + 17 可选${DT_NC}，GNOME Shell 桌面" \
            "kde|2. 安装 KDE Plasma|${DT_GREEN}10 必须 + 11 可选${DT_NC}，Plasma 桌面" \
            "help-gnome|3. GNOME 依赖说明|列出全部依赖作用（必须/可选）" \
            "help-kde|4. KDE 依赖说明|列出全部依赖作用（必须/可选）" \
            "back|← 返回|") || return 0
        case "$c" in
            gnome) de_menu_select gnome ;;
            kde) de_menu_select kde ;;
            help-gnome) de_help gnome ;;
            help-kde) de_help kde ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    gnome|kde) de_menu_select "$1" ;;
    help) [ -n "${2:-}" ] && de_help "$2" || de_err "用法: de-installer.sh help <gnome|kde>" ;;
    list)
        # 打印目录（机器可读，便于查看清单）
        de_catalog | awk -F'|' -v d="${2:-}" '$1==d || d=="" {printf "%s|%s|%s|%s|%s\n", $1,$2,$3,$4,$5}' ;;
    *) de_menu ;;
esac
