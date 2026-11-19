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
            echo "vinceliuice/MacTahoe-gtk-theme main  MacTahoe  vinceliuice/MacTahoe-icon-theme main MacTahoe vinceliuice/MacTahoe-icon-theme" ;;
        macos15)
            echo "vinceliuice/WhiteSur-gtk-theme master WhiteSur  vinceliuice/WhiteSur-icon-theme master WhiteSur vinceliuice/WhiteSur-cursors" ;;
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

# 步骤号 -> 中文说明 (供断点续装提示用)
gn_step_label() { # 1..6
    case "$1" in
        1) echo "安装 GTK 主题" ;;
        2) echo "安装图标主题" ;;
        3) echo "安装光标主题" ;;
        4) echo "应用主题设置 (gsettings)" ;;
        5) echo "安装 GNOME 扩展" ;;
        6) echo "创建桌面启动器" ;;
        *) echo "" ;;
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

# 安装图标主题（icon repo 的 install.sh，默认蓝色 macOS 风格）
gn_install_icons() { # icon_repo_dir
    local dir="$1"
    if [ -x "$dir/install.sh" ]; then
        # WhiteSur 的 -t 不认 blue(合法值 default|purple|...), 但默认即 blue;
        # MacTahoe 的 -t 认 blue。故先试 -t blue, 失败回退为默认(同样蓝色)。
        ( cd "$dir" && ./install.sh -t blue ) || ( cd "$dir" && ./install.sh ) \
            || { echo "图标主题安装失败" >&2; return 1; }
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
    # 回退仓库里可能自带 cursors/ 子目录(如 MacTahoe), 优先用它
    if [ -d "$cdir/cursors" ] && [ -x "$cdir/cursors/install.sh" ]; then
        ( cd "$cdir/cursors" && ./install.sh ) || return 1
    elif [ -x "$cdir/install.sh" ]; then
        ( cd "$cdir" && ./install.sh ) || return 1
    fi
}

# gsettings 统一封装
gn_gs() { gsettings set "$@" 2>/dev/null || { echo "  gsettings 失败: $*" >&2; return 1; }; }

# 剥离主题名的变体后缀，得到基础名（如 WhiteSur-Dark-solid -> WhiteSur）
gn_theme_base() { # theme_name
    local t="$1" prev=""
    while [ "$t" != "$prev" ]; do
        prev="$t"
        t="$(echo "$t" | sed -E 's/-([Ll]ight|[Dd]ark|[Ss]olid|[Hh][Dd]pi|[Xx][Hh][Dd]pi)$//')"
    done
    echo "$t"
}

# 解析实际安装的主题目录名。
# 主题安装器生成的是带变体后缀的目录（WhiteSur-Dark / WhiteSur-Light），
# 基础名（WhiteSur）通常不存在；若把 gsettings 设成不存在的名字，
# user-theme 扩展会回退到默认 Adwaita -> 顶栏/窗口不变。故需解析真实目录。
# 用法: gn_resolve_theme_name <base> [dark|light]  -> 输出真实主题名
gn_resolve_theme_name() { # base [dark|light]
    local base="$1" pref="${2:-dark}" d
    [ -d "$HOME/.themes/$base/gnome-shell" ] && { echo "$base"; return 0; }
    # 目标色普通变体（优先）
    local -a suf
    if [ "$pref" = light ]; then suf=("$HOME/.themes/$base-Light" "$HOME/.themes/$base-light"); else suf=("$HOME/.themes/$base-Dark" "$HOME/.themes/$base-dark"); fi
    for d in "${suf[@]}"; do
        [ -d "$d/gnome-shell" ] && { echo "$(basename "$d")"; return 0; }
    done
    # 任意目标色变体，排除 solid/hdpi/xhdpi
    local pglob; pglob="$HOME/.themes/$base-Dark* $HOME/.themes/$base-dark*"; [ "$pref" = light ] && pglob="$HOME/.themes/$base-Light* $HOME/.themes/$base-light*"
    for d in $pglob; do
        [ -d "$d/gnome-shell" ] || continue
        case "$(basename "$d")" in *solid*|*hdpi*|*xhdpi*) continue ;; esac
        echo "$(basename "$d")"; return 0
    done
    # 任意变体（排除 solid/hdpi/xhdpi）
    for d in "$HOME/.themes/${base}"*; do
        [ -d "$d/gnome-shell" ] || continue
        case "$(basename "$d")" in *solid*|*hdpi*|*xhdpi*) continue ;; esac
        echo "$(basename "$d")"; return 0
    done
    echo "$base"
}

# 切换主题深浅色：同时切换 color-scheme 与实际的 GTK/Shell 主题变体。
# 依据当前 gtk-theme 解析基础名，再解析出对应深/浅变体（存在才切）。
gn_switch_color_scheme() { # dark|light
    local mode="$1"
    local cur base target=""
    cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    [ -z "$cur" ] && return 0
    base="$(gn_theme_base "$cur")"
    target="$(gn_resolve_theme_name "$base" "$mode")"
    gn_gs org.gnome.desktop.interface color-scheme "prefer-$mode" || true
    [ -n "$target" ] && gn_gs org.gnome.desktop.interface gtk-theme "$target" || true
    [ -n "$target" ] && gn_gs org.gnome.shell.extensions.user-theme name "$target" || true
    echo "  主题: $cur -> $target (color-scheme=prefer-$mode)"
}

# 设置窗口按钮布局: left = macOS 红黄绿在左; right = GNOME 默认在右
gn_set_button_layout() { # left|right
    local mode="$1"
    case "$mode" in
        left)  gn_gs org.gnome.desktop.wm.preferences button-layout "close,minimize,maximize:" || true ;;
        right) gn_gs org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close" || true ;;
        *) return 1 ;;
    esac
    echo "  窗口按钮: $(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null)"
}

# 查询当前窗口按钮布局 -> left|right
gn_button_layout() {
    local v l
    v=$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null | tr -d "'")
    l="${v%%:*}"
    case "$l" in *close*) echo "left" ;; *) echo "right" ;; esac
}

# 创建桌面启动器(.desktop): 应用列表 + 桌面, 供一键打开 GNOME 配置中心,
# 避免每次都要去终端敲命令。Terminal=true 让 sudo/安装进度有终端可用。
gn_install_launcher() {
    local script="$GN_ROOT/gnome-config-center.sh"
    local apps="$HOME/.local/share/applications"
    local iconfile="$HOME/.local/share/icons/hicolor/scalable/apps/desktop-toolkit-gnome.svg"
    local desktop="$apps/desktop-toolkit-gnome.desktop"
    [ -x "$script" ] || chmod +x "$script" 2>/dev/null || true

    # 自定义图标: macOS 风格窗口 + 红黄绿按钮
    mkdir -p "$(dirname "$iconfile")"
    cat > "$iconfile" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <rect x="14" y="26" width="100" height="76" rx="14" fill="#1e1e2e" stroke="#313244" stroke-width="2"/>
  <circle cx="30" cy="42" r="5.5" fill="#ff5f57"/>
  <circle cx="45" cy="42" r="5.5" fill="#febc2e"/>
  <circle cx="60" cy="42" r="5.5" fill="#28c840"/>
  <rect x="28" y="60" width="72" height="7" rx="3.5" fill="#45475a"/>
  <rect x="28" y="76" width="56" height="7" rx="3.5" fill="#45475a"/>
</svg>
SVG

    mkdir -p "$apps"
    cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GNOME macOS 美化
Name[zh_CN]=GNOME macOS 美化
GenericName=macOS 外观配置中心
Comment=打开 GNOME macOS 外观配置中心 (macOS 26 Tahoe / macOS 15 经典)
Comment[zh_CN]=打开 GNOME macOS 外观配置中心 (macOS 26 Tahoe / macOS 15 经典)
Exec=$script
Icon=desktop-toolkit-gnome
Terminal=true
Categories=Settings;DesktopSettings;GTK;
Keywords=macos;theme;gnome;美化;主题;
StartupNotify=true
EOF
    chmod +x "$desktop"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps" 2>/dev/null || true
    fi
    echo "  [launcher] 已创建启动器：GNOME macOS 美化"
    echo "  [launcher] 应用列表搜索“GNOME macOS 美化”即可打开；右键可固定到 Dock。"
    echo "  [launcher] 桌面图标(可选): cp \"$desktop\" ~/Desktop/ && gio set ~/Desktop/desktop-toolkit-gnome.desktop metadata::trusted true"
}

# 应用主题到 GNOME 各组件
gn_apply() { # version
    local version="$1"
    local gtk_theme icon_theme cursor_theme
    read -r _ _ gtk_theme _ _ icon_theme cursor_theme < <(gn_version_info "$version")
    local cursor_actual="$cursor_theme"
    # 光标实际安装名可能带 -cursors 后缀差异，自动探测
    local found; found=$(ls -d "$HOME/.local/share/icons/"*[Cc]ursor* 2>/dev/null | head -1 || true)
    [ -n "$found" ] && cursor_actual="$(basename "$found")"
    # GTK/Shell 主题目录实际带变体后缀，须用真实存在的名字（默认深色）
    local theme_actual
    theme_actual="$(gn_resolve_theme_name "$gtk_theme" dark)"

    echo "  [apply] 应用 GTK/图标/光标/Shell 主题…"
    gn_gs org.gnome.desktop.interface gtk-theme   "$theme_actual" || true
    gn_gs org.gnome.desktop.interface icon-theme  "$icon_theme" || true
    gn_gs org.gnome.desktop.interface cursor-theme "$cursor_actual" || true
    # GNOME Shell 主题（需要 user-themes 扩展）
    gn_gs org.gnome.shell.extensions.user-theme name "$theme_actual" || true
    # 深浅色
    gn_gs org.gnome.desktop.interface color-scheme prefer-dark || true
    echo "  [apply] 完成（主题名=$theme_actual；Shell 主题需启用 user-themes 扩展才生效）"
}

# 下载并安装 GNOME 扩展 zip（尽力而为，成功返回 0）
gn_ext_install_zip() { # url name
    local url="$1" name="$2" tmp
    tmp=$(mktemp --suffix="-$name.zip")
    if curl -fsSL -m 60 -o "$tmp" "$url" 2>/dev/null && [ -s "$tmp" ]; then
        if gnome-extensions install "$tmp" 2>/dev/null; then
            rm -f "$tmp"; return 0
        fi
    fi
    rm -f "$tmp"; return 1
}

# 把扩展 UUID 写入 org.gnome.shell enabled-extensions(保留现有)。
# 用于扩展刚装、运行中的 shell 还不认识时, 注销重登后自动启用。
gn_ext_force_enable() { # uuid
    local uuid="$1" cur u joined=""
    local -a list=()
    cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)
    # gsettings 返回形如 ['a@b', 'c@d']; 拆成数组
    while IFS= read -r u; do
        [ -n "$u" ] && list+=("$u")
    done < <(printf '%s' "$cur" | tr -d "[]'" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
    for u in "${list[@]}"; do
        [ "$u" = "$uuid" ] && return 0   # 已在列表
    done
    list+=("$uuid")
    for u in "${list[@]}"; do
        [ -n "$joined" ] && joined="$joined, "
        joined="$joined'$u'"
    done
    gsettings set org.gnome.shell enabled-extensions "[$joined]" 2>/dev/null
}

# 安装 GNOME 扩展（user-themes / dash-to-dock / blur-my-shell）
# user-themes 是 GNOME 自带的系统扩展(gnome-shell-extensions 包)，无需联网下载；
# dash-to-dock / blur-my-shell 需联网从 extensions.gnome.org 下载，尽力而为。
gn_install_extensions() { # version
    local version="$1"
    local ut_dir ut_uuid=""
    echo "  [ext] 安装 GNOME 扩展…"

    # --- user-themes: Shell 主题切换的基础（系统包, 不依赖 extensions.gnome.org）---
    # 不同发行版/版本命名不同: 有 user-themes@...gnome.org, 也有
    # user-theme@...gcampax.github.com (Fedora 45 独立包), 故用 user-them* 匹配单复数
    ut_dir=$(ls -d /usr/share/gnome-shell/extensions/user-them* 2>/dev/null | head -1 || true)
    if [ -z "$ut_dir" ]; then
        echo "  [ext] 安装 gnome-shell-extensions 包（提供 user-themes，需 sudo）…"
        if command -v dnf >/dev/null 2>&1; then
            # Fedora 40+ 把扩展拆成独立包(gnome-shell-extension-user-theme);
            # 老版 Fedora 用聚合包 gnome-shell-extensions。两者都试试。
            sudo dnf install -y gnome-shell-extension-user-theme \
                || sudo dnf install -y gnome-shell-extensions
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y gnome-shell-extensions
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm gnome-shell-extensions
        elif command -v zypper >/dev/null 2>&1; then
            sudo zypper in -y gnome-shell-extensions
        else
            echo "  [ext] 未识别的包管理器，请手动安装 gnome-shell-extensions" >&2
        fi
        ut_dir=$(ls -d /usr/share/gnome-shell/extensions/user-them* 2>/dev/null | head -1 || true)
    fi

    if [ -n "$ut_dir" ]; then
        # 从 metadata.json 取真实 UUID(不同发行版命名不同, 勿硬编码)
        ut_uuid=$(sed -n 's/.*"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ut_dir/metadata.json" 2>/dev/null | head -1 || true)
        [ -z "$ut_uuid" ] && ut_uuid="user-themes@gnome-shell-extensions.gnome.org"
        # user-themes 现在存在(架构可用), 重设 Shell 主题。
        # 此前 gn_apply(第4步)设置时 schema 还不存在会静默失败, 这里补上。
        # 主题目录实际带变体后缀, 用真实存在的名字, 否则顶栏回退默认 Adwaita。
        local gtk_theme theme_actual
        read -r _ _ gtk_theme < <(gn_version_info "$version")
        theme_actual="$(gn_resolve_theme_name "$gtk_theme" dark)"
        gn_gs org.gnome.shell.extensions.user-theme name "$theme_actual" || true
        if gnome-extensions enable "$ut_uuid" 2>/dev/null; then
            echo "  [ext] user-themes 已启用 ✅（Shell 主题已设为 $theme_actual）"
        elif gn_ext_force_enable "$ut_uuid"; then
            echo "  [ext] user-themes 已登记为启用（注销重登一次后生效，Shell 主题=$theme_actual）"
        else
            echo "  [ext] user-themes 已安装，但需注销重登一次才能启用"
        fi
    else
        echo "  [ext] 未找到 user-themes 扩展（包未装成功），Shell 主题暂无法切换" >&2
    fi

    # --- dash-to-dock: macOS 风格 Dock（需联网，尽力而为）---
    if ! gnome-extensions list 2>/dev/null | grep -q dash-to-dock; then
        gn_ext_install_zip "https://extensions.gnome.org/extension-data/307/dash-to-dock.zip" dash-to-dock \
            || echo "  [ext] dash-to-dock 下载失败（网络不通，可稍后到 extensions.gnome.org 手动装）"
    fi
    # --- blur-my-shell: Tahoe 液态玻璃感（仅 macos26，需联网，尽力而为）---
    if [ "$version" = macos26 ] && ! gnome-extensions list 2>/dev/null | grep -q blur; then
        gn_ext_install_zip "https://extensions.gnome.org/extension-data/3193/blur-my-shell.zip" blur-my-shell \
            || echo "  [ext] blur-my-shell 下载失败（网络不通，可稍后到 extensions.gnome.org 手动装）"
    fi
    echo "  [ext] 完成（dash-to-dock / blur-my-shell 需联网，失败可到 extensions.gnome.org 手动装）"
}
