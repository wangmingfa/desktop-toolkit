#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit / GNOME macOS 美化 公共库
# 由 install.sh 与 gnome-config-center.sh source
# 支持两套方案：
#   macos26  -> MacTahoe-gtk-theme   (macOS 26 Tahoe 液态玻璃)
#   macos15  -> WhiteSur-gtk-theme   (经典 Big Sur / Sequoia 风格)
# =============================================================================

GN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 公共库（镜像加速等）——避免重复 source
if [ -z "${DT_ROOT:-}" ]; then
    source "$GN_ROOT/../../../lib/common.sh"
fi
GN_SRC_DIR="${GN_SRC_DIR:-$HOME/.local/src/desktop-toolkit-gnome}"

# 版本 -> 仓库 / 主题名 映射
gn_version_info() { # macos26|macos15  -> 输出 "gtk_repo gtk_branch gtk_theme icon_repo icon_branch icon_theme cursor_theme"
    case "$1" in
        macos26)
            echo "vinceliuice/MacTahoe-gtk-theme main  MacTahoe  vinceliuice/MacTahoe-icon-theme main MacTahoe MacTahoe-cursor" ;;
        macos15)
            echo "vinceliuice/WhiteSur-gtk-theme master WhiteSur  vinceliuice/WhiteSur-icon-theme master WhiteSur WhiteSur-cursors" ;;
        *) return 1 ;;
    esac
}

gn_version_label() { # macos26|macos15 -> 中文标签
    case "$1" in
        macos26) echo "macOS 26 (Tahoe 液态玻璃)" ;;
        macos15) echo "macOS 15 (经典 Sequoia 风格)" ;;
        *)      echo "未知版本" ;;
    esac
}

# 是否在 GNOME 环境
gn_is_gnome() {
    if command -v gnome-shell >/dev/null 2>&1; then return 0; fi
    case "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}" in
        *GNOME*|*ubuntu*|*gnome*) return 0 ;;
    esac
    return 1
}

# 克隆主题仓库（复用 dt_clone，自动国内镜像回退）
gn_clone() { # repo branch
    local repo="$1" branch="$2"
    local dir="$GN_SRC_DIR/$(basename "$repo")"
    mkdir -p "$GN_SRC_DIR"
    if [ -d "$dir/.git" ]; then
        echo "  [git] $repo 已存在，跳过克隆" >&2
        echo "$dir"; return 0
    fi
    dt_clone "https://github.com/$repo.git" "$dir" "$branch" || return 1
    echo "$dir"
}

# 安装 GTK 主题所需的构建依赖(主要是 sassc)。
# 主题的 install.sh 在缺 sassc 时会走 prepare_deps, 其中用 /dev/tcp 探测
# iana.org:80 校时; 部分网络下该探测失败直接 exit 1。提前装好 sassc 即可
# 让 install_theme_deps 直接跳过整段(含探测)。
gn_ensure_deps() { # 无参数; 返回 0 表示 sassc 可用(或已装好)
    if command -v sassc >/dev/null 2>&1; then
        echo "  [deps] sassc 已安装，跳过依赖检查"
        return 0
    fi
    echo "  [deps] 缺少 sassc，用系统包管理器安装（需要 sudo 密码）…"
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y sassc
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y sassc
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm sassc
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper in -y sassc
    else
        echo "  [deps] 未识别的包管理器，请手动安装 sassc 后重试" >&2
        return 1
    fi
    if command -v sassc >/dev/null 2>&1; then
        echo "  [deps] sassc 安装完成"
    else
        echo "  [deps] sassc 安装失败" >&2
        return 1
    fi
}

# 运行 GTK 主题安装器（install.sh）
gn_install_gtk() { # gtk_repo_dir
    local dir="$1"; shift
    if [ -x "$dir/install.sh" ]; then
        ( cd "$dir" && ./install.sh "$@" ) || { echo "GTK 主题安装失败" >&2; return 1; }
    else
        echo "未找到 $dir/install.sh" >&2; return 1
    fi
}

# 安装图标主题（icon repo 的 install.sh，-t blue 默认）
gn_install_icons() { # icon_repo_dir
    local dir="$1"
    if [ -x "$dir/install.sh" ]; then
        ( cd "$dir" && ./install.sh -t blue ) || { echo "图标主题安装失败" >&2; return 1; }
    else
        echo "未找到 $dir/install.sh" >&2; return 1
    fi
}

# 安装光标主题：优先 icon repo 内的 cursors 目录；否则用独立 cursors 仓库
gn_install_cursors() { # icon_repo_dir cursor_repo
    local icon_dir="$1" cursor_repo="$2"
    if [ -d "$icon_dir/cursors" ] && [ -x "$icon_dir/cursors/install.sh" ]; then
        ( cd "$icon_dir/cursors" && ./install.sh ) && return 0
    fi
    local branch=master
    case "$cursor_repo" in *MacTahoe*) branch=main ;; esac
    local cdir; cdir=$(gn_clone "$cursor_repo" "$branch") || return 1
    if [ -x "$cdir/install.sh" ]; then
        ( cd "$cdir" && ./install.sh ) || return 1
    fi
}

# gsettings 统一封装
gn_gs() { gsettings set "$@" 2>/dev/null || { echo "  gsettings 失败: $*" >&2; return 1; }; }

# 应用主题到 GNOME 各组件
gn_apply() { # version
    local version="$1"
    local gtk_theme icon_theme cursor_theme
    read -r _ _ gtk_theme _ _ icon_theme cursor_theme < <(gn_version_info "$version")
    local cursor_actual="$cursor_theme"
    # 光标实际安装名可能带 -cursors 后缀差异，自动探测
    local found; found=$(ls -d "$HOME/.local/share/icons/"*[Cc]ursor* 2>/dev/null | head -1)
    [ -n "$found" ] && cursor_actual="$(basename "$found")"

    echo "  [apply] 应用 GTK/图标/光标/Shell 主题…"
    gn_gs org.gnome.desktop.interface gtk-theme   "$gtk_theme" || true
    gn_gs org.gnome.desktop.interface icon-theme  "$icon_theme" || true
    gn_gs org.gnome.desktop.interface cursor-theme "$cursor_actual" || true
    # GNOME Shell 主题（需要 user-themes 扩展）
    gn_gs org.gnome.shell.extensions.user-theme name "$gtk_theme" || true
    # 深浅色
    gn_gs org.gnome.desktop.interface color-scheme prefer-dark || true
    echo "  [apply] 完成（Shell 主题需启用 user-themes 扩展才生效）"
}

# 安装 GNOME 扩展（user-themes / dash-to-dock / blur-my-shell）
gn_install_extensions() { # version
    local version="$1"
    echo "  [ext] 安装 GNOME 扩展…"
    # user-themes: 让 Shell 主题可切换
    gn-extensions install "https://extensions.gnome.org/extension-data/19/user-themes.v*.shell-extension.zip" 2>/dev/null \
        || gn-extensions install "https://extensions.gnome.org/extension-data/19/user-themes.zip" 2>/dev/null || true
    # dash-to-dock: macOS 风格 Dock
    gn-extensions install "https://extensions.gnome.org/extension-data/307/dash-to-dock.zip" 2>/dev/null || true
    # blur-my-shell: Tahoe 液态玻璃感（仅 macos26 建议）
    if [ "$version" = macos26 ]; then
        gn-extensions install "https://extensions.gnome.org/extension-data/3193/blur-my-shell.zip" 2>/dev/null || true
    fi
    gn-extensions enable user-themes 2>/dev/null || true
    gn-extensions enable dash-to-dock 2>/dev/null || true
    gn-extensions enable blur-my-shell 2>/dev/null || true
    echo "  [ext] 完成（可到 GNOME Extensions 商店手动补齐依赖）"
}
