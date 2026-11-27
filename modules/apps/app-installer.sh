#!/usr/bin/env bash
# =============================================================================
# app-installer.sh —— 常用应用安装器（浏览器/通信/办公/媒体/容器）
#
# 发行版感知（Fedora/Arch/Debian），运行时探测源里是否有、是否已装。
# 只装包，不碰配置。注册 main.sh 应用子菜单。
#
# 用法: bash app-installer.sh [matrix|install <id>]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
log() { echo "  [app-installer] $*"; }
err() { echo "  [app-installer] 错误: $*" >&2; }

app_distro() {
    . /etc/os-release 2>/dev/null || true
    case "${ID:-}" in
        fedora) echo fedora ;;
        arch) echo arch ;;
        debian) echo debian ;;
        ubuntu) echo ubuntu ;;
        *) echo other ;;
    esac
}

# 每行 id|显示名|类别|Fedora|Arch|Debian|备注；类别 browser/office/media/container
# 包名 "THIRD" 表示该发行版需第三方源（不自动装）
app_catalog() {
    cat <<'EOF'
chromium|Chromium|browser|chromium|chromium|chromium|
firefox|Firefox|browser|firefox|firefox|firefox-esr|
code|VS Code|browser|code|code|code|
telegram|Telegram|browser|telegram-desktop|telegram-desktop|telegram-desktop|
libreoffice|LibreOffice|office|libreoffice|libreoffice|libreoffice|
vlc|VLC|office|vlc|vlc|vlc|
gimp|GIMP|office|gimp|gimp|gimp|
blender|Blender|office|blender|blender|blender|
kdenlive|Kdenlive|office|kdenlive|kdenlive|kdenlive|
obs|OBS Studio|office|obs-studio|obs-studio|obs-studio|
audacity|Audacity|office|audacity|audacity|audacity|
podman|Podman|container|podman|podman|podman|
docker|Docker|container|THIRD|docker|docker|Fedora 需 docker-ce 第三方源|
EOF
}

app_field() { # <id> <col>
    app_catalog | awk -F'|' -v id="$1" -v c="$2" '$1==id {print $c}'
}

app_pkg() { # <id> → 当前发行版包名；空=不受支持
    local id="$1" distro col
    distro=$(app_distro)
    case "$distro" in
        fedora) col=4 ;; arch) col=5 ;; debian|ubuntu) col=6 ;; *) echo ""; return 0 ;;
    esac
    app_field "$id" "$col"
}

app_available() { # <id> → 0 可自动装
    local id="$1" pkg distro
    pkg=$(app_pkg "$id") || return 1
    [ -z "$pkg" ] && return 1
    [ "$pkg" = THIRD ] && return 1
    distro=$(app_distro)
    case "$distro" in
        fedora) dnf repoquery --available "$pkg" >/dev/null 2>&1 ;;
        arch) pacman -Si "$pkg" >/dev/null 2>&1 ;;
        debian|ubuntu) apt-cache show "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

app_installed() { # <id> → 0 已装
    local id="$1" pkg distro
    pkg=$(app_pkg "$id") || return 1
    [ -z "$pkg" ] && return 1
    [ "$pkg" = THIRD ] && return 1
    distro=$(app_distro)
    case "$distro" in
        fedora) rpm -q "$pkg" >/dev/null 2>&1 ;;
        arch) pacman -Q "$pkg" >/dev/null 2>&1 ;;
        debian|ubuntu) dpkg -s "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

app_install() { # <id>
    local id="$1" pkg distro
    pkg=$(app_pkg "$id"); distro=$(app_distro)
    case "$distro" in
        fedora) log "dnf 安装 $pkg ..."; sudo dnf install -y "$pkg" ;;
        arch) log "pacman 安装 $pkg ..."; sudo pacman -S --noconfirm --needed "$pkg" ;;
        debian|ubuntu) log "apt 安装 $pkg ..."; sudo apt install -y "$pkg" ;;
        *) err "不支持的发行版: $distro"; return 1 ;;
    esac
}

app_install_one() { # <id>
    local id="$1" name cat note pkg distro
    name=$(app_field "$id" 2); cat=$(app_field "$id" 3); note=$(app_field "$id" 7)
    pkg=$(app_pkg "$id"); distro=$(app_distro)

    if ! app_available "$id"; then
        local why
        if [ "$pkg" = THIRD ]; then
            why="当前发行版($distro)官方源没有此包，需第三方源（详见备注）。"
        elif [ -z "$pkg" ]; then
            why="当前发行版($distro)不受本工具支持。"
        else
            why="当前发行版($distro)源里没有此包。"
        fi
        dt_info "$name\n无法自动安装。\n$why\n\n备注: ${note:-无}"
        return 0
    fi

    if app_installed "$id"; then
        dt_confirm "$name 已安装。\n\n要重新安装/升级吗？" || return 0
    fi

    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        dt_info "$name\n安装需 sudo 密码，但当前不是交互终端。\n\n请在一个终端里运行:\n  bash $DT_ROOT/modules/apps/app-installer.sh"
        return 0
    fi

    dt_confirm "安装 $name（包 $pkg）？\n需要 sudo 密码。\n\n继续？" || return 0
    log "安装 $name ..."
    if app_install "$id"; then
        log "✅ $name 安装完成"
    else
        err "$name 安装失败。请手动: sudo dnf install $pkg"
    fi
}

app_matrix() {
    local distro
    distro=$(app_distro)
    local txt
    txt=$(printf '当前发行版: %s\n\n  %-14s %-8s %-18s %s\n' "$distro" "名称" "类别" "当前包" "状态")
    local id name cat pkg st
    while IFS='|' read -r id name cat _ _ _ _; do
        pkg=$(app_pkg "$id")
        if app_installed "$id"; then st="已装"
        elif app_available "$id"; then st="可装"
        else st="源里没有"; fi
        txt+=$'\n'"$(printf '  %-14s %-8s %-18s %s' "$name" "$cat" "${pkg:-—}" "$st")"
    done < <(app_catalog)
    dt_info "常用应用 支持矩阵" "$txt"
}

app_pick() { # <类别>
    local cls="$1"
    local -a rows=()
    local id name cat note state
    while IFS='|' read -r id name cat _ _ _ note; do
        [ "$cat" != "$cls" ] && continue
        if app_installed "$id"; then state="已装"
        elif app_available "$id"; then state="可装"
        else state="⚠源里没有"; fi
        [ -n "$note" ] && state="$state · $note"
        rows+=("$id|$name|$state")
    done < <(app_catalog)
    rows+=("back|← 返回|")
    local title
    case "$cls" in
        browser) title="浏览器 / 通信" ;;
        office) title="办公 / 媒体" ;;
        container) title="容器" ;;
    esac
    local c
    c=$(dt_menu "$title" "选择要安装的项（先确认，需要 sudo 密码）" "${rows[@]}") || return 0
    [ "$c" = back ] && return 0
    app_install_one "$c"
}

app_menu() {
    while true; do
        local distro c
        distro=$(app_distro)
        c=$(dt_menu "常用应用安装器" \
            "当前发行版: $distro；安装前探测源里是否有。" \
            "browser|浏览器/通信|Chromium/Firefox/VS Code/Telegram" \
            "office|办公/媒体|LibreOffice/VLC/GIMP/Blender/Kdenlive/OBS/Audacity" \
            "container|容器|Podman/Docker" \
            "matrix|支持矩阵|各应用在当前发行版的包名与状态" \
            "back|← 返回|") || return 0
        case "$c" in
            browser) app_pick browser ;;
            office) app_pick office ;;
            container) app_pick container ;;
            matrix) app_matrix ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    matrix) app_matrix ;;
    install) [ -n "${2:-}" ] && app_install_one "$2" || err "用法: app-installer.sh install <id>" ;;
    *) app_menu ;;
esac
