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
gn_version_info() { # macos26|macos15|fluent  -> 输出 "gtk_repo gtk_branch gtk_theme icon_repo icon_branch icon_theme cursor_theme"
    case "$1" in
        macos26)
            echo "vinceliuice/MacTahoe-gtk-theme main  MacTahoe  vinceliuice/MacTahoe-icon-theme main MacTahoe vinceliuice/MacTahoe-icon-theme" ;;
        macos15)
            echo "vinceliuice/WhiteSur-gtk-theme master WhiteSur  vinceliuice/WhiteSur-icon-theme master WhiteSur vinceliuice/WhiteSur-cursors" ;;
        fluent)
            # Windows 11 Fluent 风格; 光标源暂缺(验证未达), 留空则由 gn_install_cursors 跳过
            echo "vinceliuice/Fluent-gtk-theme master Fluent  vinceliuice/Fluent-icon-theme master Fluent  " ;;
        *) return 1 ;;
    esac
}

gn_version_label() { # macos26|macos15|fluent -> 中文标签
    case "$1" in
        macos26) echo "macOS 26 (Tahoe 液态玻璃)" ;;
        macos15) echo "macOS 15 (经典 Sequoia 风格)" ;;
        fluent)  echo "Windows 11 (Fluent 风格)" ;;
        *)       echo "未知版本" ;;
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

# 运行 GTK 主题安装器（install.sh）。参数按版本区分：
#  - WhiteSur/MacTahoe: -l = 本地安装(→~/.themes)
#  - Fluent: -l 语义是 --libadwaita(不同!), 且非 root 默认装 $XDG_DATA_HOME/themes(若已设),
#    故显式 -d ~/.themes 强制与其它主题一致, 否则 gn_resolve_theme_name 会找不到主题目录。
gn_install_gtk() { # gtk_repo_dir version
    local dir="$1" version="$2"
    local -a args=()
    case "$version" in
        fluent) args=(-d "$HOME/.themes") ;;
        *)      args=(-l) ;;
    esac
    if [ -x "$dir/install.sh" ]; then
        ( cd "$dir" && ./install.sh "${args[@]}" ) || { echo "GTK 主题安装失败" >&2; return 1; }
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
    # 优先用 icon 仓库自带的 cursors 子目录(如 Fluent-icon-theme/cursors)
    if [ -d "$icon_dir/cursors" ] && [ -x "$icon_dir/cursors/install.sh" ]; then
        ( cd "$icon_dir/cursors" && ./install.sh ) && return 0
    fi
    if [ -z "$cursor_repo" ]; then
        echo "  [cursor] 无光标源（该风格未提供），保留当前光标主题" >&2
        return 0
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
# 注意: 有的主题(Fluent)会同时生成"基础目录"(Fluent)且它对应默认=浅色,
# 故**目标色变体优先于基础名**, 避免深色偏好被误设成浅色基础版。
# 用法: gn_resolve_theme_name <base> [dark|light]  -> 输出真实主题名
gn_resolve_theme_name() { # base [dark|light]
    local base="$1" pref="${2:-dark}" d
    # 目标色普通变体（优先）
    local -a suf
    if [ "$pref" = light ]; then suf=("$HOME/.themes/$base-Light" "$HOME/.themes/$base-light"); else suf=("$HOME/.themes/$base-Dark" "$HOME/.themes/$base-dark"); fi
    for d in "${suf[@]}"; do
        [ -d "$d/gnome-shell" ] && { echo "$(basename "$d")"; return 0; }
    done
    # 基础名精确存在（仅当目标色变体缺失时用，如 Fluent 的基础目录是浅色）
    [ -d "$HOME/.themes/$base/gnome-shell" ] && { echo "$base"; return 0; }
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

# 解析实际存在的图标主题名：图标安装器可能只生成变体目录(如 xxx-dark)，
# 把不存在的基础名写进 gsettings 会让图标回退默认，故先探测真实目录。
gn_resolve_icon_name() { # base [dark|light]
    local base="$1" pref="${2:-dark}" d root
    for d in "$HOME/.local/share/icons/$base" "$HOME/.icons/$base" "/usr/share/icons/$base"; do
        [ -d "$d" ] && { echo "$base"; return 0; }
    done
    local -a cands=()
    if [ "$pref" = light ]; then cands=("$base-Light" "$base-light"); else cands=("$base-Dark" "$base-dark"); fi
    for d in "${cands[@]}"; do
        for root in "$HOME/.local/share/icons" "$HOME/.icons"; do
            [ -d "$root/$d" ] && { echo "$d"; return 0; }
        done
    done
    # 任意变体（排除 htop 之类同名干扰）
    for root in "$HOME/.local/share/icons" "$HOME/.icons"; do
        for d in "$root/$base"*; do
            [ -d "$d" ] || continue
            case "$(basename "$d")" in *htop*|*cursor*|*Cursor*) continue ;; esac
            echo "$(basename "$d")"; return 0
        done
    done
    echo "$base"
}

# 解析实际安装的光标主题名（仓库名与实际目录名常有 -cursors 后缀差异）
gn_resolve_cursor_name() { # 期望名(可带 owner 前缀)
    local want="${1##*/}" d
    for d in "$HOME/.local/share/icons/$want" "$HOME/.icons/$want" "/usr/share/icons/$want"; do
        [ -d "$d" ] && { echo "$want"; return 0; }
    done
    d=$(ls -d "$HOME/.local/share/icons/"*"$want"* 2>/dev/null | head -1 || true)
    [ -z "$d" ] && d=$(ls -d "$HOME/.local/share/icons/"*[Cc]ursor* 2>/dev/null | head -1 || true)
    [ -n "$d" ] && { basename "$d"; return 0; }
    echo "$want"
}

# 切换主题深浅色：同时切换 color-scheme 与实际的 GTK/Shell 主题变体。
# 依据当前 gtk-theme 解析基础名，再解析出对应深/浅变体（存在才切）。
gn_switch_color_scheme() { # dark|light
    local mode="$1"
    local cur base target=""
    cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'" || true)
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
    # 图标/光标实际安装名可能与基础名不同，解析真实目录名，避免写进不存在的名字
    local icon_actual cursor_actual
    icon_actual="$(gn_resolve_icon_name "$icon_theme" dark)"
    cursor_actual="$(gn_resolve_cursor_name "$cursor_theme")"
    # GTK/Shell 主题目录实际带变体后缀，须用真实存在的名字（默认深色）
    local theme_actual
    theme_actual="$(gn_resolve_theme_name "$gtk_theme" dark)"

    echo "  [apply] 应用 GTK/图标/光标/Shell 主题…"
    gn_gs org.gnome.desktop.interface gtk-theme   "$theme_actual" || true
    gn_gs org.gnome.desktop.interface icon-theme  "$icon_actual" || true
    gn_gs org.gnome.desktop.interface cursor-theme "$cursor_actual" || true
    # GNOME Shell 主题（需要 user-themes 扩展）
    gn_gs org.gnome.shell.extensions.user-theme name "$theme_actual" || true
    # 深浅色
    gn_gs org.gnome.desktop.interface color-scheme prefer-dark || true
    echo "  [apply] 完成（GTK=$theme_actual 图标=$icon_actual 光标=$cursor_actual）"
}

# ---------------------------------------------------------------------------
# GNOME 扩展：安装 / 启用 / 配置（extensions.gnome.org，尽力而为）
#
# 约定（踩过的坑）：
#  - 下载地址必须按"当前 Shell 版本"向 EGO API 现问，别硬编码 pk/zip 路径
#    （旧代码写死的 .../extension-data/307/dash-to-dock.zip 早已 404）。
#  - 装完必须 enable，否则 Dash 永远不出现；运行中的 Shell 不认识新扩展时，
#    写 org.gnome.shell enabled-extensions 兜底（注销重登生效），
#    并清掉 disabled-extensions 里的同名项（disabled 优先于 enabled）。
#  - 用户目录安装的扩展 schema 在扩展自己的 schemas/ 下，gsettings 默认看不到，
#    需 GSETTINGS_SCHEMA_DIR 指向它（gnome-extensions install 已顺带编译），
#    拿不到 schema 时退回 dconf 按路径写。
# ---------------------------------------------------------------------------

# 当前 GNOME Shell 主版本号（如 51）
gn_shell_major() {
    local v
    v=$(gnome-shell --version 2>/dev/null | awk '{print $3}' || true)
    echo "${v%%.*}"
}

# 扩展是否已安装（用户目录 / 系统目录 / gnome-extensions 列表）
gn_ext_installed() { # uuid
    local uuid="$1" list
    [ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ] && return 0
    [ -d "/usr/share/gnome-shell/extensions/$uuid" ] && return 0
    list=$(gnome-extensions list 2>/dev/null || true)
    case "$list" in *"$uuid"*) return 0 ;; esac
    return 1
}

# 已安装扩展的目录（用户级优先）
gn_ext_dir() { # uuid
    local uuid="$1" d
    for d in "$HOME/.local/share/gnome-shell/extensions/$uuid" \
             "/usr/share/gnome-shell/extensions/$uuid"; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}

# 向 EGO 问"与当前 Shell 版本匹配"的下载地址；取不到返回 1
gn_ext_download_url() { # uuid
    local uuid="$1" major json url
    major=$(gn_shell_major)
    json=$(curl -fsSL --max-time 20 \
        "https://extensions.gnome.org/extension-info/?uuid=$uuid${major:+&shell_version=$major}" 2>/dev/null || true)
    url=$(printf '%s' "$json" \
        | sed -n 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1 || true)
    case "$url" in
        /download-extension/*) echo "https://extensions.gnome.org$url" ;;
        "") return 1 ;;
        *) echo "$url" ;;
    esac
}

# 从 extensions.gnome.org 安装扩展（已装则跳过）
gn_ext_install_ego() { # uuid
    local uuid="$1" url tmp
    if gn_ext_installed "$uuid"; then
        echo "  [ext] $uuid 已安装，跳过下载"
        return 0
    fi
    url=$(gn_ext_download_url "$uuid" || true)
    if [ -z "$url" ]; then
        echo "  [ext] $uuid：取不到与 GNOME $(gn_shell_major) 匹配的下载地址（网络不通或该扩展不支持此版本）" >&2
        return 1
    fi
    tmp=$(mktemp --suffix="-$uuid.zip")
    if ! curl -fsSL --max-time 120 -o "$tmp" "$url" 2>/dev/null || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        echo "  [ext] $uuid 下载失败（$url）" >&2
        return 1
    fi
    if gnome-extensions install --force "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "  [ext] $uuid 已安装 ✅"
        return 0
    fi
    rm -f "$tmp"
    echo "  [ext] $uuid 安装失败（$url）" >&2
    return 1
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

# 从 org.gnome.shell disabled-extensions 里移除 uuid（disabled 优先于 enabled，
# 用户以前手动关过的扩展不清掉就永远起不来）
gn_ext_force_unblock() { # uuid
    local uuid="$1" cur u joined=""
    cur=$(gsettings get org.gnome.shell disabled-extensions 2>/dev/null || true)
    case "$cur" in *"$uuid"*) ;; *) return 0 ;; esac
    while IFS= read -r u; do
        [ -n "$u" ] || continue
        [ "$u" = "$uuid" ] && continue
        [ -n "$joined" ] && joined="$joined, "
        joined="$joined'$u'"
    done < <(printf '%s' "$cur" | tr -d "[]'" | tr ',' '\n' | sed 's/^ *//; s/ *$//' || true)
    gsettings set org.gnome.shell disabled-extensions "[$joined]" 2>/dev/null || true
}

# 启用扩展：先走运行中 Shell 的 D-Bus，失败则登记为启用（注销重登生效）
gn_ext_enable() { # uuid
    local uuid="$1"
    if ! gn_ext_installed "$uuid"; then
        echo "  [ext] $uuid 未安装，无法启用" >&2
        return 1
    fi
    gn_ext_force_unblock "$uuid"
    if gnome-extensions enable "$uuid" 2>/dev/null; then
        echo "  [ext] $uuid 已启用 ✅"
        return 0
    fi
    if gn_ext_force_enable "$uuid"; then
        echo "  [ext] $uuid 已登记启用（注销重登一次后生效）"
        return 0
    fi
    echo "  [ext] $uuid 启用失败" >&2
    return 1
}

# 扩展是否已被本会话加载（gnome-extensions list --enabled）
gn_ext_enabled() { # uuid
    local uuid="$1" list
    list=$(gnome-extensions list --enabled 2>/dev/null || true)
    case "$list" in *"$uuid"*) return 0 ;; esac
    return 1
}

# 让 gsettings 看到扩展自带的 schema（设置 GN_EXT_SCHEMA_DIR，后续 gn_ext_set 用）
gn_ext_use_schemas() { # uuid
    local dir
    dir=$(gn_ext_dir "$1" || true)
    [ -n "$dir" ] || return 1
    [ -d "$dir/schemas" ] || { GN_EXT_SCHEMA_DIR="" ; return 1; }
    if command -v glib-compile-schemas >/dev/null 2>&1; then
        glib-compile-schemas "$dir/schemas" 2>/dev/null || true
    fi
    GN_EXT_SCHEMA_DIR="$dir/schemas"
    export GN_EXT_SCHEMA_DIR
}

# 写扩展设置：优先 GSETTINGS_SCHEMA_DIR+gsettings（能校验键名/枚举），
# 无 schema 时退回 dconf 按路径写（不依赖 schema 文件）
gn_ext_set() { # schema key value
    local schema="$1" key="$2" value="$3" path
    if [ -n "${GN_EXT_SCHEMA_DIR:-}" ] && [ -d "$GN_EXT_SCHEMA_DIR" ] \
        && GSETTINGS_SCHEMA_DIR="$GN_EXT_SCHEMA_DIR" gsettings set "$schema" "$key" "$value" 2>/dev/null; then
        return 0
    fi
    path="/$(printf '%s' "$schema" | tr '.' '/')/"
    case "$value" in
        true|false) ;;
        ''|*[!0-9.]*) value="'$value'" ;;
    esac
    if command -v dconf >/dev/null 2>&1; then
        dconf write "$path$key" "$value" 2>/dev/null && return 0
    fi
    echo "  [ext] 写设置失败: $schema $key=$value" >&2
    return 1
}

# dash-to-dock 观感：macos = 底部悬浮 + 自动隐藏 + 点击最小化 + 圆点指示
#                    windows = 常驻底部居中任务栏（Fluent/Win11 风格用）
#
# ⚠ 别开 unity-backlit-items（Dock 图标高亮）：dash-to-dock 110 在重建图标时
#   RunningIndicatorBase.update() 拿不到图标容器子节点，直接抛
#   "Expected type string for argument 'style'" → 图标建到一半中断，
#   Dock 上只剩一个图标（固定应用"看起来全丢"）。custom-theme-shrink 同理保持默认。
gn_dtd_apply_style() { # macos|windows
    local style="${1:-macos}" s=org.gnome.shell.extensions.dash-to-dock
    gn_ext_set "$s" dock-position BOTTOM || true
    case "$style" in
        windows)
            gn_ext_set "$s" dock-fixed true || true
            gn_ext_set "$s" autohide false || true
            gn_ext_set "$s" intellihide false || true
            gn_ext_set "$s" dash-max-icon-size 40 || true
            ;;
        *)
            gn_ext_set "$s" dock-fixed false || true
            gn_ext_set "$s" autohide true || true
            gn_ext_set "$s" intellihide true || true
            gn_ext_set "$s" intellihide-mode FOCUS_APPLICATION_WINDOWS || true
            gn_ext_set "$s" dash-max-icon-size 48 || true
            gn_ext_set "$s" transparency-mode FIXED || true
            gn_ext_set "$s" background-opacity 0.6 || true
            # macOS 风格不抢 Super+1..9（交给工作区切换）
            gn_ext_set "$s" hot-keys false || true
            ;;
    esac
    gn_ext_set "$s" extend-height false || true
    gn_ext_set "$s" always-center-icons true || true
    gn_ext_set "$s" running-indicator-style DOTS || true
    gn_ext_set "$s" click-action minimize || true
    gn_ext_set "$s" scroll-action cycle-windows || true
    gn_ext_set "$s" show-apps-at-top true || true
    gn_ext_set "$s" show-trash true || true
    gn_ext_set "$s" show-mounts false || true
    gn_ext_set "$s" multi-monitor true || true
    gn_ext_set "$s" force-straight-corner false || true
    gn_ext_set "$s" animation-time 0.2 || true
    # 显式关掉会触发渲染 bug 的两项（也用于修复早期版本写进去的 true）
    gn_ext_set "$s" unity-backlit-items false || true
    gn_ext_set "$s" custom-theme-shrink false || true
    gn_ext_set "$s" apply-glossy-effect false || true
}

# 安装 + 配置 + 启用 dash-to-dock（macOS 风格 Dock）
gn_setup_dash_to_dock() { # macos|windows
    local style="${1:-macos}" uuid=dash-to-dock@micxgx.gmail.com label="macOS Dock 风格"
    [ "$style" = windows ] && label="Windows 任务栏风格"
    echo "  [ext] 配置 dash-to-dock（$label）…"
    if ! gn_ext_install_ego "$uuid"; then
        echo "  [ext] dash-to-dock 不可用（网络/兼容性），已跳过 Dock 配置" >&2
        return 1
    fi
    # Ubuntu Dock 与 dash-to-dock 抢同一位置，先禁用
    if gn_ext_installed ubuntu-dock@ubuntu.com; then
        gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true
        echo "  [ext] 已禁用 ubuntu-dock（避免与 dash-to-dock 冲突）"
    fi
    gn_ext_use_schemas "$uuid" || true
    gn_dtd_apply_style "$style"
    GN_EXT_SCHEMA_DIR=""
    gn_ext_enable "$uuid"
}

# 安装 + 启用 blur-my-shell（Tahoe 液态玻璃感）
gn_setup_blur_my_shell() {
    local uuid=blur-my-shell@aunetx
    echo "  [ext] 配置 blur-my-shell（顶栏/Dock 毛玻璃）…"
    if ! gn_ext_install_ego "$uuid"; then
        echo "  [ext] blur-my-shell 不可用（网络/兼容性），已跳过毛玻璃配置" >&2
        return 1
    fi
    gn_ext_use_schemas "$uuid" || true
    # 默认 pipeline 已经是合适的模糊；这里只确保"顶栏 + Dock + 概览"开启
    gn_ext_set "org.gnome.shell.extensions.blur-my-shell.panel" static-blur true || true
    gn_ext_set "org.gnome.shell.extensions.blur-my-shell.dash-to-dock" blur true || true
    gn_ext_set "org.gnome.shell.extensions.blur-my-shell.overview" blur true || true
    GN_EXT_SCHEMA_DIR=""
    gn_ext_enable "$uuid"
}
# ---------------------------------------------------------------------------
# 安装 GNOME 扩展（全部自动启用 + 关键设置自动写入）
#   user-themes    : Shell 主题切换基础，系统包提供，不联网
#   dash-to-dock   : macOS 风格 Dock（装完自动 enable + macOS 观感配置）
#   blur-my-shell  : 顶栏/Dock 毛玻璃（仅 macos26 液态玻璃风格）
# ---------------------------------------------------------------------------
gn_install_extensions() { # version
    local version="$1"
    local ut_dir ut_uuid="" gtk_theme theme_actual dock_style=macos
    echo "  [ext] 安装并启用 GNOME 扩展…"
    [ "$version" = fluent ] && dock_style=windows

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
                || sudo dnf install -y gnome-shell-extensions || true
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y gnome-shell-extensions || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm gnome-shell-extensions || true
        elif command -v zypper >/dev/null 2>&1; then
            sudo zypper in -y gnome-shell-extensions || true
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
        read -r _ _ gtk_theme < <(gn_version_info "$version")
        theme_actual="$(gn_resolve_theme_name "$gtk_theme" dark)"
        gn_gs org.gnome.shell.extensions.user-theme name "$theme_actual" || true
        gn_ext_enable "$ut_uuid" || true
    else
        echo "  [ext] 未找到 user-themes 扩展（包未装成功），Shell 主题暂无法切换" >&2
    fi

    # --- dash-to-dock: macOS Dock / Windows 任务栏（装完自动启用）---
    gn_setup_dash_to_dock "$dock_style" || true

    # --- blur-my-shell: Tahoe 液态玻璃感（仅 macos26）---
    if [ "$version" = macos26 ]; then
        gn_setup_blur_my_shell || true
    fi

    # --- 汇总：哪些本次生效、哪些要注销重登 ---
    local uuid pending=""
    for uuid in "$ut_uuid" dash-to-dock@micxgx.gmail.com; do
        [ -n "$uuid" ] || continue
        gn_ext_enabled "$uuid" || pending="$pending $uuid"
    done
    if [ "$version" = macos26 ]; then
        gn_ext_enabled blur-my-shell@aunetx || pending="$pending blur-my-shell@aunetx"
    fi
    if [ -n "$pending" ]; then
        echo "  [ext] 已登记但需注销重登才加载：${pending# }"
    else
        echo "  [ext] 扩展全部已启用 ✅"
    fi
}

# ---------------------------------------------------------------------------
# 主题/扩展生效校验：读回 gsettings 检查是否真的用上了本次安装的产物。
# 只做提示，不中断安装（返回 0）。
# ---------------------------------------------------------------------------
gn_verify_themes() { # version
    local version="$1"
    local gtk_theme icon_theme cursor_theme
    read -r _ _ gtk_theme _ _ icon_theme cursor_theme < <(gn_version_info "$version")
    local bad=0 cur dir want
    echo "  [check] 校验主题生效情况…"

    # GTK: 值必须存在且目录真实存在
    cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    if [ -n "$cur" ] && { [ -d "$HOME/.themes/$cur" ] || [ -d "$HOME/.local/share/themes/$cur" ] || [ -d "/usr/share/themes/$cur" ]; }; then
        echo "  [check] ✅ GTK 主题: $cur"
    else
        echo "  [check] ⚠ GTK 主题未生效（当前='${cur:-空}'，期望 $gtk_theme 的深色变体）"; bad=$((bad+1))
    fi

    # 图标
    cur=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)
    dir=""
    for d in "$HOME/.local/share/icons/$cur" "$HOME/.icons/$cur" "/usr/share/icons/$cur"; do
        [ -d "$d" ] && { dir="$d"; break; }
    done
    if [ -n "$dir" ]; then
        echo "  [check] ✅ 图标主题: $cur"
    else
        echo "  [check] ⚠ 图标主题目录不存在（当前='${cur:-空}'，期望 $icon_theme）"; bad=$((bad+1))
    fi

    # 光标
    cur=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'" || true)
    dir=""
    for d in "$HOME/.local/share/icons/$cur" "$HOME/.icons/$cur" "/usr/share/icons/$cur"; do
        [ -d "$d" ] && { dir="$d"; break; }
    done
    if [ -n "$dir" ]; then
        echo "  [check] ✅ 光标主题: $cur"
    else
        echo "  [check] ⚠ 光标主题目录不存在（当前='${cur:-空}'，期望 $cursor_theme）"; bad=$((bad+1))
    fi

    # Shell 主题（依赖 user-themes 扩展；schema 不存在时该键读不到）
    local schemas
    schemas=$(gsettings list-schemas 2>/dev/null || true)
    if [[ "$schemas" == *org.gnome.shell.extensions.user-theme* ]]; then
        cur=$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | tr -d "'" || true)
        if [ -n "$cur" ] && { [ -d "$HOME/.themes/$cur" ] || [ -d "/usr/share/themes/$cur" ]; }; then
            echo "  [check] ✅ Shell 主题: $cur"
        else
            # 当前值是无效主题名（目录不存在；旧版本曾写入过错误字符串）→ 自动修正
            want="$(gn_resolve_theme_name "$gtk_theme" dark)"
            if { [ -d "$HOME/.themes/$want" ] || [ -d "/usr/share/themes/$want" ]; } \
                && gn_gs org.gnome.shell.extensions.user-theme name "$want"; then
                echo "  [check] 🔧 Shell 主题值无效，已修正为: $want"
            else
                echo "  [check] ⚠ Shell 主题未生效（当前='${cur:-空}'），注销重登后再看一次"; bad=$((bad+1))
            fi
        fi
    else
        echo "  [check] ⚠ user-themes 扩展未安装，Shell 主题无法切换（顶栏会保持默认）"; bad=$((bad+1))
    fi

    # Dock / 毛玻璃扩展是否被会话加载
    local uuid
    for uuid in dash-to-dock@micxgx.gmail.com; do
        gn_ext_installed "$uuid" || { echo "  [check] ⚠ 未安装 $uuid"; bad=$((bad+1)); continue; }
        if gn_ext_enabled "$uuid"; then
            echo "  [check] ✅ 扩展已启用: $uuid"
        else
            echo "  [check] ⚠ 扩展已装但未加载: $uuid（注销重登生效）"; bad=$((bad+1))
        fi
    done
    if [ "$version" = macos26 ]; then
        uuid=blur-my-shell@aunetx
        if gn_ext_installed "$uuid"; then
            gn_ext_enabled "$uuid" \
                && echo "  [check] ✅ 扩展已启用: $uuid" \
                || { echo "  [check] ⚠ 扩展已装但未加载: $uuid（注销重登生效）"; bad=$((bad+1)); }
        else
            echo "  [check] ⚠ 未安装 $uuid（毛玻璃效果不可用）"; bad=$((bad+1))
        fi
    fi

    if [ "$bad" -eq 0 ]; then
        echo "  [check] 全部生效 ✅"
    else
        echo "  [check] 有 $bad 项待生效：注销重登一次通常即可（Shell 主题/扩展只在会话启动时加载）"
    fi
    return 0
}
