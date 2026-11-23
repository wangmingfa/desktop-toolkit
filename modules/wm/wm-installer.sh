#!/usr/bin/env bash
# =============================================================================
# WM / 桌面环境 安装器
#   列出常见窗口管理器与桌面环境（KDE/GNOME/sway/i3/Hyprland/...），
#   发行版感知地安装（Fedora/Arch/Debian/Ubuntu）。
#   只做"安装 + 提示切换会话"，不碰用户现有配置（GNOME/niri 不受影响）。
#   用法: bash modules/wm/wm-installer.sh
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
source "$DT_ROOT/lib/niri.sh"   # dnf_install_retry / niri_dm_unit / niri_restart_dm
log() { echo "  [wm-installer] $*"; }
err() { echo "  [wm-installer] 错误: $*" >&2; }
niri_color_init

# ---------------------------------------------------------------------------
# 发行版探测（/etc/os-release 的 ID）
# ---------------------------------------------------------------------------
wm_distro() {
    . /etc/os-release 2>/dev/null || true
    case "${ID:-}" in
        fedora) echo fedora ;;
        arch) echo arch ;;
        debian) echo debian ;;
        ubuntu) echo ubuntu ;;
        *) echo other ;;
    esac
}

# ---------------------------------------------------------------------------
# 目录（catalog）：每行 id|显示名|类别|Fedora|Arch|Debian/Ubuntu|会话类型|备注
#   类别: DE=桌面环境(组/元包), WM=平铺窗口管理器, FLOAT=堆叠/浮动
#   包名 "COPR" 表示该发行版官方源没有（需第三方源或源码编译），菜单标"⚠源里没有"
#   各发行版包名经实测核对（Fedora 45 dnf repoquery / group list；Arch/Debian 用通用名）
# ---------------------------------------------------------------------------
wm_catalog() {
    cat <<'EOF'
kde|KDE Plasma|DE|kde-desktop|plasma-meta|kde-plasma-desktop|wayland|
gnome|GNOME|DE|gnome-desktop|gnome|gnome|wayland|
xfce|Xfce|DE|xfce-desktop|xfce4|xfce4|x11|
mate|MATE|DE|mate-desktop|mate|mate-desktop|x11|
cinnamon|Cinnamon|DE|cinnamon-desktop|cinnamon|cinnamon-desktop|x11|
lxqt|LXQt|DE|lxqt-desktop|lxqt|lxqt|x11|
sway|sway|WM|sway|sway|sway|wayland|
i3|i3|WM|i3|i3|i3|x11|
hyprland|Hyprland|WM|COPR|hyprland|COPR|wayland|Fedora 需 COPR solopasha/hyprland; Debian 需编译|
river|river|WM|river|river|river|wayland|
bspwm|bspwm|WM|bspwm|bspwm|bspwm|x11|
awesome|awesome|WM|awesome|awesome|awesome|x11|
xmonad|xmonad|WM|xmonad|xmonad|xmonad|x11|
qtile|qtile|WM|qtile|qtile|qtile|x11|
openbox|openbox|FLOAT|openbox|openbox|openbox|x11|
fluxbox|fluxbox|FLOAT|fluxbox|fluxbox|fluxbox|x11|
wayfire|wayfire|FLOAT|wayfire|wayfire|wayfire|wayland|
labwc|labwc|FLOAT|labwc|labwc|labwc|wayland|
herbstluftwm|herbstluftwm|FLOAT|herbstluftwm|herbstluftwm|herbstluftwm|x11|
dwm|dwm|FLOAT|COPR|dwm|dwm|x11|Fedora 需源码编译|
leftwm|leftwm|FLOAT|COPR|leftwm|COPR|x11|Fedora/Debian 需 COPR|
EOF
}

wm_field() { # <id> <col> —— 从 catalog 取字段(列号 1-8)
    wm_catalog | awk -F'|' -v id="$1" -v c="$2" '$1==id {print $c}'
}

wm_pkg() { # <id> —— 当前发行版对应的包/组名；空=不受支持
    local id="$1" distro col
    distro=$(wm_distro)
    case "$distro" in
        fedora) col=4 ;;
        arch) col=5 ;;
        debian|ubuntu) col=6 ;;
        *) echo ""; return 0 ;;
    esac
    wm_field "$id" "$col"
}

# 源里有没有（可自动装？）：0=可装 / 1=不可装（源里没有或需 COPR/编译）
wm_pkg_available() {
    local id="$1" pkg distro cls
    pkg=$(wm_pkg "$id") || return 1
    [ -z "$pkg" ] && return 1
    [ "$pkg" = COPR ] && return 1
    distro=$(wm_distro)
    cls=$(wm_field "$id" 3)
    case "$distro" in
        fedora)
            if [ "$cls" = DE ]; then
                dnf group info "$pkg" >/dev/null 2>&1
            else
                dnf repoquery --available "$pkg" >/dev/null 2>&1
            fi ;;
        arch) pacman -Si "$pkg" >/dev/null 2>&1 ;;
        debian|ubuntu) apt-cache show "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# 是否已装：0=已装 / 1=未装（DE 用核心会话包判断，WM 用主包）
wm_installed() {
    local id="$1" pkg distro
    pkg=$(wm_pkg "$id") || return 1
    [ -z "$pkg" ] && return 1
    [ "$pkg" = COPR ] && return 1
    distro=$(wm_distro)
    case "$distro" in
        fedora)
            case "$id" in
                kde) rpm -q plasma-workspace >/dev/null 2>&1 ;;
                gnome) rpm -q gnome-shell >/dev/null 2>&1 ;;
                xfce) rpm -q xfce4-session >/dev/null 2>&1 ;;
                mate) rpm -q mate-session-manager >/dev/null 2>&1 ;;
                cinnamon) rpm -q cinnamon-session >/dev/null 2>&1 ;;
                lxqt) rpm -q lxqt-session >/dev/null 2>&1 ;;
                *) rpm -q "$pkg" >/dev/null 2>&1 ;;
            esac ;;
        arch) pacman -Q "$pkg" >/dev/null 2>&1 ;;
        debian|ubuntu) dpkg -s "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 安装（按发行版分派）。DE 在 Fedora 走组安装(带重试)，WM 走 dnf_install_retry。
# ---------------------------------------------------------------------------
wm_install() { # <id> —— 返回 0/1
    local id="$1" pkg distro cls
    pkg=$(wm_pkg "$id"); cls=$(wm_field "$id" 3); distro=$(wm_distro)
    case "$distro" in
        fedora)
            if [ "$cls" = DE ]; then
                local attempt
                for (( attempt=1; attempt<=3; attempt++ )); do
                    [ "$attempt" -gt 1 ] && log "第 ${attempt} 次重试安装桌面环境组（已装好的会跳过）…"
                    if sudo dnf group install -y "$pkg"; then return 0; fi
                    err "第 ${attempt} 次组安装失败"
                done
                err "组安装仍未成功。可稍后重跑续装，或手动: sudo dnf group install $pkg"
                return 1
            else
                dnf_install_retry "$pkg"
            fi ;;
        arch)
            log "pacman 安装 $pkg ..."
            sudo pacman -S --noconfirm --needed "$pkg" ;;
        debian|ubuntu)
            log "apt 安装 $pkg ..."
            sudo apt install -y "$pkg" ;;
        *)
            err "不支持的发行版: $distro"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 安装单项：确认 + 安装 + 收尾
# ---------------------------------------------------------------------------
wm_install_one() { # <id>
    local id="$1" name cat sess note pkg distro why
    name=$(wm_field "$id" 2); cat=$(wm_field "$id" 3)
    sess=$(wm_field "$id" 7); note=$(wm_field "$id" 8)
    distro=$(wm_distro); pkg=$(wm_pkg "$id")

    if ! wm_pkg_available "$id"; then
        if [ "$pkg" = COPR ]; then
            why="当前发行版($distro)官方源没有此包，需第三方源(COPR/PPA)或源码编译。"
        elif [ -z "$pkg" ]; then
            why="当前发行版($distro)不受本工具支持。"
        else
            why="当前发行版($distro)源里没有此包。"
        fi
        dt_info "$name\n无法自动安装。\n$why\n\n备注: ${note:-无}\n\n如需安装请按备注手动处理。"
        return 0
    fi

    if wm_installed "$id"; then
        dt_confirm "$name 已安装。\n\n要重新安装/升级吗？" || return 0
    fi

    # 非交互 shell + sudo 需密码：提前提示，避免 sudo 卡住
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        dt_info "$name\n安装需要 sudo 密码，但当前不是交互终端（无法输入密码）。\n\n请在一个终端里运行:\n  bash $DT_ROOT/modules/wm/wm-installer.sh"
        return 0
    fi

    if [ "$cat" = DE ]; then
        dt_confirm "安装 $name 桌面环境（组/元包 $pkg）。\n下载量大，弱网可能需 10 分钟以上，中断后可重跑续装。\n\n继续？" || return 0
    else
        dt_confirm "安装 $name（包 $pkg，$sess 会话）。\n需要 sudo 密码。\n\n继续？" || return 0
    fi

    log "安装 $name ..."
    if wm_install "$id"; then
        wm_finish "$id"
    else
        err "$name 安装失败。可重跑本脚本续装，或手动安装: $pkg"
    fi
}

# ---------------------------------------------------------------------------
# 收尾：绿色完成 + 切换方法 + 重启 DM 代跑（DM 只在启动时扫会话文件）
# ---------------------------------------------------------------------------
wm_finish() { # <id>
    local id="$1" name sess dm_unit
    name=$(wm_field "$id" 2); sess=$(wm_field "$id" 7)
    dm_unit=$(niri_dm_unit 2>/dev/null || true)
    echo
    echo -e "${DT_GREEN:-}${DT_BOLD:-}✅ 安装完成：${name}${DT_NC:-}"
    echo
    echo -e "  ${DT_BOLD:-}切换方法${DT_NC:-}：注销当前会话，在登录界面【会话切换】选 ${name}。"
    echo "    - GDM：登录框左下角齿轮 ⚙️"
    echo "    - SDDM：登录框右下角"
    echo "    - 部分 DM：登录框上方/侧面会话菜单"
    if [ -n "$dm_unit" ]; then
        echo
        echo -e "  ${DT_YELLOW:-}如果登录界面看不到 ${name} 会话（$sess）：${DT_NC:-}"
        echo "    ${dm_unit} 只在【启动时】扫一次会话文件，单纯注销不会重新扫描。"
        echo "    手动执行: sudo systemctl restart ${dm_unit}"
    fi
    echo
    if [ -t 0 ]; then
        if dt_confirm "现在重启显示管理器吗？（会注销当前桌面，之后在登录界面选 ${name}）"; then
            niri_restart_dm || err "重启失败，请手动执行: sudo systemctl restart ${dm_unit}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 支持矩阵（只读）
# ---------------------------------------------------------------------------
wm_show_matrix() {
    local distro
    distro=$(wm_distro)
    local txt
    txt=$(printf '当前发行版: %s\n\n  %-14s %-6s %-8s %-16s %s\n' "$distro" "名称" "类别" "会话" "当前包" "状态")
    local id name cat sess pkg st
    while IFS='|' read -r id name cat _ _ _ sess _; do
        pkg=$(wm_pkg "$id")
        if wm_installed "$id"; then st="已装"
        elif wm_pkg_available "$id"; then st="可装"
        else st="源里没有"; fi
        txt+=$'\n'"$(printf '  %-14s %-6s %-8s %-16s %s' "$name" "$cat" "$sess" "${pkg:-—}" "$st")"
    done < <(wm_catalog)
    dt_info "WM / 桌面环境 支持矩阵\n\n$txt"
}

# ---------------------------------------------------------------------------
# 分组选择子菜单
# ---------------------------------------------------------------------------
wm_pick() { # <类别: de|wm|float>
    local cls="$1"
    local -a rows=()
    local id name cat sess note state
    while IFS='|' read -r id name cat _ _ _ sess note; do
        [ "${cat,,}" != "$cls" ] && continue
        if wm_installed "$id"; then state="已装"
        elif wm_pkg_available "$id"; then state="$sess"
        else state="⚠源里没有"; fi
        [ -n "$note" ] && state="$state · $note"
        rows+=("$id|$name|$state")
    done < <(wm_catalog)
    rows+=("back|← 返回|")
    local title
    case "$cls" in
        de) title="桌面环境" ;;
        wm) title="平铺窗口管理器" ;;
        float) title="堆叠/浮动窗口管理器" ;;
    esac
    local c
    c=$(dt_menu "$title" "选择要安装的项（先确认，需要 sudo 密码）" "${rows[@]}") || return 0
    [ "$c" = back ] && return 0
    wm_install_one "$c"
}

# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------
wm_menu() {
    while true; do
        local distro c
        distro=$(wm_distro)
        c=$(dt_menu "WM / 桌面环境 安装器" \
            "当前发行版: $distro；安装前会探测源里是否有对应包。" \
            "de|1. 桌面环境|KDE/GNOME/Xfce/MATE/Cinnamon/LXQt（依赖多、下载大）" \
            "wm|2. 平铺窗口管理器|sway/i3/Hyprland/river/bspwm/awesome/xmonad/qtile" \
            "float|3. 堆叠/浮动窗口管理器|openbox/fluxbox/wayfire/labwc/herbstluftwm/dwm/leftwm" \
            "matrix|4. 查看支持矩阵|各 WM/DE 在当前发行版的包名与状态" \
            "back|← 返回|") || return 0
        case "$c" in
            de) wm_pick de ;;
            wm) wm_pick wm ;;
            float) wm_pick float ;;
            matrix) wm_show_matrix ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

# 直接跑
wm_menu
