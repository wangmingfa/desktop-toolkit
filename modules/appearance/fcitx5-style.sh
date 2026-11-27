#!/usr/bin/env bash
# =============================================================================
# fcitx5-style.sh —— 中文输入法 fcitx5 外观（主题切换 / 第三方主题下载 / 字体）
#
# fcitx5 主题放在 /usr/share/fcitx5/themes（系统）或 ~/.local/share/fcitx5/themes（用户）。
# 切换 = 写 ~/.config/fcitx5/conf/classicui.conf 的 Theme=，再 reload fcitx5。
# 第三方主题用 dt_clone 走镜像下载（受限网络）。注册 main.sh 外观子菜单。
#
# 用法: bash fcitx5-style.sh [status|list|set <主题>|reload]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
log() { echo "  [fcitx5-style] $*"; }
err() { echo "  [fcitx5-style] 错误: $*" >&2; }

FC5_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5/conf/classicui.conf"
FC5_USR="$HOME/.local/share/fcitx5/themes"

fc5_list_themes() { # 可用主题（系统+用户，去重）
    { ls /usr/share/fcitx5/themes 2>/dev/null; ls "$FC5_USR" 2>/dev/null; } | grep -v '^$' | sort -u
}

fc5_current() {
    grep -E '^Theme=' "$FC5_CONF" 2>/dev/null | head -1 | cut -d= -f2
}

fc5_set_theme() { # <主题名>
    local name="$1"
    fc5_list_themes | grep -qx "$name" || { err "主题 $name 不存在"; return 1; }
    mkdir -p "$(dirname "$FC5_CONF")"
    # 幂等：有 Theme= 则替换，否则追加（awk 避免 sed 引号问题）
    if grep -qE '^Theme=' "$FC5_CONF" 2>/dev/null; then
        awk -v t="$name" '/^Theme=/{print "Theme="t; next} {print}' "$FC5_CONF" > "$FC5_CONF.tmp" && mv "$FC5_CONF.tmp" "$FC5_CONF"
    else
        printf 'Theme=%s\n' "$name" >> "$FC5_CONF"
    fi
    log "已设置主题: $name"
    fc5_reload
}

fc5_reload() {
    # 重启 fcitx5 让主题生效（fcitx5-ctl reload 对主题不总有效，重启更稳）
    if pgrep -x fcitx5 >/dev/null 2>&1; then
        fcitx5-ctl reload 2>/dev/null || true
        log "已请求 fcitx5 重载（如未生效，重新登录或手动重启 fcitx5）"
    else
        log "fcitx5 未在运行，主题将在下次启动生效"
    fi
}

fc5_install_repo() { # <github_url> —— 克隆仓库，找含 theme.conf 的目录装到用户主题目录
    local url="$1"
    local tmp repo
    tmp=$(mktemp -d)
    log "下载主题仓库（镜像回退）: $url"
    if ! dt_clone "$url" "$tmp/repo" >/dev/null 2>&1; then
        err "克隆失败（网络受限时已尝试镜像）。可稍后重试。"
        rm -rf "$tmp"; return 1
    fi
    # 找含 theme.conf 的主题目录（仓库根或子目录）
    local -a dirs=()
    mapfile -t dirs < <(find "$tmp/repo" -name theme.conf 2>/dev/null | xargs -r -n1 dirname)
    if [ "${#dirs[@]}" -eq 0 ]; then
        err "仓库里没找到 theme.conf（可能不是 fcitx5 主题仓库）"
        rm -rf "$tmp"; return 1
    fi
    mkdir -p "$FC5_USR"
    local d name
    for d in "${dirs[@]}"; do
        name=$(basename "$d")
        rm -rf "$FC5_USR/$name"
        cp -r "$d" "$FC5_USR/$name"
        log "已安装主题: $name"
    done
    rm -rf "$tmp"
    log "安装完成。可到菜单1.切换。"
}

fc5_status() {
    echo "=== fcitx5 外观状态 ==="
    pgrep -x fcitx5 >/dev/null 2>&1 && echo "  ✅ fcitx5 运行中" || echo "  ❌ fcitx5 未运行"
    echo "  当前主题: $(fc5_current 未设置)"
    echo "  可用主题:"
    fc5_list_themes | sed 's/^/    /'
}

fc5_menu() {
    while true; do
        local c
        c=$(dt_menu "fcitx5 输入法外观" "中文输入法主题/字体（当前: $(fc5_current 未设置)）：" \
            "set|切换主题|列出可用主题选择" \
            "dl|下载第三方主题|material-color/nord/gruvbox（镜像下载）" \
            "font|字体/大小|编辑 classicui.conf 的 Font" \
            "status|状态|当前主题/可用主题/运行状态" \
            "reload|重载 fcitx5|让主题生效" \
            "back|← 返回|") || return 0
        case "$c" in
            set) menu_set ;;
            dl) menu_dl ;;
            font) menu_font ;;
            status) fc5_status ;;
            reload) fc5_reload ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

menu_set() {
    local -a rows=() t
    while IFS= read -r t; do
        rows+=("$t|$t|$([ "$t" = "$(fc5_current)" ] && echo 当前 || echo 可用)")
    done < <(fc5_list_themes)
    [ "${#rows[@]}" -eq 0 ] && { err "无可用主题"; return 0; }
    rows+=("back|← 返回|")
    local c
    c=$(dt_menu "fcitx5 主题" "选择要启用的主题" "${rows[@]}") || return 0
    [ "$c" = back ] && return 0
    fc5_set_theme "$c"
}

menu_dl() {
    local c
    c=$(dt_menu "下载 fcitx5 主题" "第三方主题（镜像下载）" \
        "mc|Material Color|fcitx5/fcitx5-material-color（经典 Material 风格）" \
        "nord|Nord|fcitx5/fcitx5-nord（北欧冷色）" \
        "gruvbox|Gruvbox|fcitx5/fcitx5-gruvbox（复古暖色）" \
        "back|← 返回|") || return 0
    case "$c" in
        mc) fc5_install_repo "https://github.com/fcitx5/fcitx5-material-color" ;;
        nord) fc5_install_repo "https://github.com/fcitx5/fcitx5-nord" ;;
        gruvbox) fc5_install_repo "https://github.com/fcitx5/fcitx5-gruvbox" ;;
        __quit) exit 0 ;;
        back) return 0 ;;
    esac
}

menu_font() {
    local c
    c=$(dt_menu "fcitx5 字体" "设置输入法候选/菜单字体（写 classicui.conf）：" \
        "set|设置字体|如: Noto Sans CJK SC 12" \
        "reset|恢复默认|删除 Font 行" \
        "back|← 返回|") || return 0
    case "$c" in
        set)
            local v
            v=$(dt_ask_text "字体" "格式: 字体名 大小，如 Noto Sans CJK SC 12" "Noto Sans CJK SC 12") || return 0
            if grep -qE '^Font=' "$FC5_CONF" 2>/dev/null; then
                awk -v f="Font=$v" '/^Font=/{print f; next} {print}' "$FC5_CONF" > "$FC5_CONF.tmp" && mv "$FC5_CONF.tmp" "$FC5_CONF"
            else
                printf 'Font=%s\n' "$v" >> "$FC5_CONF"
            fi
            log "已设置字体: $v"; fc5_reload ;;
        reset)
            awk '!/^Font=/{print}' "$FC5_CONF" > "$FC5_CONF.tmp" && mv "$FC5_CONF.tmp" "$FC5_CONF"
            log "已恢复默认字体"; fc5_reload ;;
        __quit) exit 0 ;;
        back) return 0 ;;
    esac
}

case "${1:-}" in
    status) fc5_status ;;
    list) fc5_list_themes ;;
    set) if [ -n "${2:-}" ]; then fc5_set_theme "$2"; else err "用法: fcitx5-style.sh set <主题>"; fi ;;
    reload) fc5_reload ;;
    *) fc5_menu ;;
esac
