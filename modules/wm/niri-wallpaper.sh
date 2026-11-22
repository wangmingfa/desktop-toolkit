#!/usr/bin/env bash
# =============================================================================
# niri 壁纸 + 锁屏(swaylock) 美化
# -----------------------------------------------------------------------------
# 壁纸: 用 niri 原生 `output { background-image }`(无名字=所有输出, 实测 26.04
#       合法, 无需 swaybg 额外进程)。写入独立 ~/.config/niri/wallpaper.kdl,
#       主配置末尾 include(幂等, 与 tools.kdl/dt-settings.kdl 互不干扰)。
# 锁屏: swaylock 样式预设写 ~/.config/swaylock/config。
# 受限网络不下载壁纸: 请自行放图片到 ~/Pictures/Wallpapers/ 或用本工具输入路径。
#
# 用法: niri-wallpaper.sh [set|lock|clear|status|uninstall|menu]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

log() { dt_log "$*"; }
err() { dt_err "$*"; }

NIRI_DIR="$HOME/.config/niri"
MAIN="$NIRI_DIR/config.kdl"
WALL="$NIRI_DIR/wallpaper.kdl"
WP_DIR="$HOME/Pictures/Wallpapers"
LOCK_CFG="$HOME/.config/swaylock/config"
LOCK_BAK="$HOME/.config/swaylock/config.dt-bak"
TOOLS_INCLUDE='include optional=true "wallpaper.kdl"'

# ---------------------------------------------------------------------------
# 壁纸
# ---------------------------------------------------------------------------
pick_wallpaper() {
    # 优先从 ~/Pictures/Wallpapers 选择, 否则输入路径
    if [ -d "$WP_DIR" ] && ls "$WP_DIR"/*.{png,jpg,jpeg,webp} >/dev/null 2>&1; then
        local -a rows=() f i=0
        for f in "$WP_DIR"/*.{png,jpg,jpeg,webp}; do [ -f "$f" ] && { rows+=("$f|$(basename "$f")|"); i=$((i+1)); }; done
        rows+=("custom|输入自定义路径|")
        rows+=("back|← 取消|")
        local sel
        sel=$(dt_menu "选择壁纸" "从 ~/Pictures/Wallpapers 选择：" "${rows[@]}") || return 2
        [ "$sel" = __quit ] && exit 0
        [ -z "$sel" ] && return 2
        [ "$sel" = back ] && return 2
        if [ "$sel" = custom ]; then
            sel=$(dt_ask_text "壁纸路径" "输入图片绝对路径(png/jpg/webp)" "") || return 2
            [ -n "$sel" ] || return 2
        fi
        [ -f "$sel" ] && echo "$sel" && return 0
        err "文件不存在: $sel"
        return 2
    fi
    local p
    p=$(dt_ask_text "壁纸路径" "输入图片绝对路径(或放入 $WP_DIR)" "") || return 2
    [ -n "$p" ] && [ -f "$p" ] && echo "$p" && return 0
    [ -n "$p" ] && err "文件不存在: $p"
    return 2
}

gen_wallpaper_kdl() { # <path>
    cat > "$WALL" <<KDL
// dt-wallpaper: niri 壁纸(由 niri-wallpaper.sh 管理); 无名字 output=应用到所有输出
output {
    background-image "$1"
}
KDL
}

ensure_include() {
    grep -q 'wallpaper\.kdl' "$MAIN" 2>/dev/null && return 0
    awk -v inc="$TOOLS_INCLUDE" '{ print } END { print ""; print "// dt-wallpaper include (niri-wallpaper.sh 管理)"; print inc }' "$MAIN" > "$MAIN.tmp" \
        && mv "$MAIN.tmp" "$MAIN"
    log "已在主配置末尾加入 include wallpaper.kdl"
}

remove_include() {
    [ -f "$MAIN" ] || return 0
    awk -v inc="$TOOLS_INCLUDE" '
        /dt-wallpaper include/ { skip=1; next }
        skip && /^include optional=true "wallpaper.kdl"/ { skip=0; next }
        { print }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    log "已从主配置移除 include wallpaper.kdl"
}

set_wallpaper() {
    local p
    p=$(pick_wallpaper) || return 0
    mkdir -p "$NIRI_DIR"
    gen_wallpaper_kdl "$p"
    ensure_include
    log "壁纸已设置: $p（需 niri msg reload-config 生效）"
}

clear_wallpaper() {
    remove_include
    rm -f "$WALL"
    log "已清除壁纸（主配置 background-color 等保留）"
}

# ---------------------------------------------------------------------------
# 随机壁纸轮换：立即换一张 + systemd 用户 timer 定时轮换
# ---------------------------------------------------------------------------
wp_list() { # 列出 WP_DIR 里的图片
    [ -d "$WP_DIR" ] && ls "$WP_DIR"/*.{png,jpg,jpeg,webp} 2>/dev/null
}

rotate_once() { # 随机选一张, 写 wallpaper.kdl + reload
    local -a imgs
    mapfile -t imgs < <(wp_list)
    if [ "${#imgs[@]}" -eq 0 ]; then
        err "无图片。请先放图片到 $WP_DIR（png/jpg/webp）"
        return 1
    fi
    local p
    p=${imgs[$((RANDOM % ${#imgs[@]}))]}
    mkdir -p "$NIRI_DIR"
    gen_wallpaper_kdl "$p"
    ensure_include
    command -v niri >/dev/null 2>&1 && timeout 5 niri msg reload-config 2>/dev/null || true
    log "已轮换壁纸: $(basename "$p")"
}

rotate_setup() { # <分钟>
    local mins="${1:-30}"
    local unit_dir="$HOME/.config/systemd/user"
    rotate_once || true
    mkdir -p "$unit_dir"
    cat > "$unit_dir/wallpaper-rotate.service" <<EOF
[Unit]
Description=Rotate niri wallpaper (desktop-toolkit)
[Service]
Type=oneshot
ExecStart=$DT_ROOT/modules/wm/niri-wallpaper.sh rotate
EOF
    cat > "$unit_dir/wallpaper-rotate.timer" <<EOF
[Unit]
Description=Rotate niri wallpaper every ${mins} min
[Timer]
OnBootSec=${mins}min
OnUnitActiveSec=${mins}min
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now wallpaper-rotate.timer
    log "已开启壁纸轮换（每 ${mins} 分钟）"
}

rotate_disable() {
    systemctl --user disable --now wallpaper-rotate.timer 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/wallpaper-rotate.service" \
          "$HOME/.config/systemd/user/wallpaper-rotate.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    log "已关闭壁纸轮换"
}

rotate_status() {
    if systemctl --user is-enabled wallpaper-rotate.timer >/dev/null 2>&1; then
        echo "  ✅ 轮换 timer 已启用"
        systemctl --user list-timers wallpaper-rotate.timer --no-pager 2>/dev/null \
            | tail -2 | head -1 | sed 's/^/  /'
    else
        echo "  ❌ 轮换 timer 未启用"
    fi
    echo "  图片数量: $(wp_list | wc -l)（$WP_DIR）"
}

# ---------------------------------------------------------------------------
# 锁屏 (swaylock)
# ---------------------------------------------------------------------------
lock_preset() { # style
    local style="$1"
    mkdir -p "$(dirname "$LOCK_CFG")"
    [ -f "$LOCK_CFG" ] && [ ! -f "$LOCK_BAK" ] && cp "$LOCK_CFG" "$LOCK_BAK"
    case "$style" in
        simple)
            cat > "$LOCK_CFG" <<'CFG'
color=000000cc
font-size=24
ring-color=7c9bff
key-hl-color=7c9bff
separator-color=7c9bff
CFG
            ;;
        frost)
            cat > "$LOCK_CFG" <<'CFG'
blur=10
screenshot
color=00000099
font-size=28
inside-color=00000000
ring-color=88aaff
key-hl-color=88aaff
bs-hl-color=ff8899
separator-color=88aaff
CFG
            ;;
        *)
            # 恢复默认(移除本工具写的, 回退备份或删)
            [ -f "$LOCK_BAK" ] && mv "$LOCK_BAK" "$LOCK_CFG" || rm -f "$LOCK_CFG"
            return 0
            ;;
    esac
    log "锁屏样式已设为: $style (swaylock 读取 ~/.config/swaylock/config)"
}

# ---------------------------------------------------------------------------
# 菜单/状态
# ---------------------------------------------------------------------------
status() {
    echo "=== 壁纸 ==="
    if [ -f "$WALL" ]; then grep -oE 'background-image "[^"]+"' "$WALL" | sed 's/^/  /' || echo "  (未设置)"; else echo "  (未设置)"; fi
    grep -q 'wallpaper\.kdl' "$MAIN" 2>/dev/null && echo "  ✅ 已 include" || echo "  ❌ 未 include"
    echo "=== 锁屏(swaylock) ==="
    [ -f "$LOCK_CFG" ] && echo "  样式: $(grep -oE '^(blur|color)=' "$LOCK_CFG" | head -2 | tr '\n' ' ')" || echo "  (默认)"
    echo "=== 工具 ==="
    command -v swaylock >/dev/null 2>&1 && echo "  ✅ swaylock $(swaylock --version 2>/dev/null | head -1 | awk '{print $2}')" || echo "  ❌ swaylock 未装"
}

# ---------------------------------------------------------------------------
# 壁纸网络下载（受限网络走 dt_download 镜像回退）
# ---------------------------------------------------------------------------
dl_wallpaper() { # [url] —— 输入 URL → 下载到 WP_DIR，可设为壁纸
    local url="${1:-}"
    [ -n "$url" ] || url=$(dt_ask_text "壁纸 URL" "输入图片直链(png/jpg/webp)。GitHub 链接自动走镜像。" "") || return 0
    [ -n "$url" ] || return 0
    mkdir -p "$WP_DIR"
    name=$(basename "$url" | sed 's/[^A-Za-z0-9._-]/_/g')
    [ -n "$name" ] && [ "$name" != "." ] || name="wallpaper-$(date +%s).jpg"
    log "下载 $name ..."
    if dt_download "$url" "$WP_DIR/$name"; then
        log "已下载: $WP_DIR/$name（${name}）"
        if dt_confirm "下载完成。立即设为壁纸？"; then
            gen_wallpaper_kdl "$WP_DIR/$name"
            ensure_include
            command -v niri >/dev/null 2>&1 && timeout 5 niri msg reload-config 2>/dev/null || true
            log "已设为壁纸"
        fi
    else
        err "下载失败（网络受限时已尝试镜像）。可稍后重试或换源。"
    fi
}

menu_rotate() {
    while true; do
        local c
        c=$(dt_menu "随机壁纸轮换" "立即换一张或 systemd 定时轮换（图片放 $WP_DIR）：" \
            "once|1. 立即换一张|随机选一张 + 热重载" \
            "30|2. 开启轮换(30 分钟)|systemd 用户 timer" \
            "60|3. 开启轮换(60 分钟)|systemd 用户 timer" \
            "off|4. 关闭轮换|停 timer + 删单元" \
            "status|5. 状态|timer/图片数量" \
            "back|← 返回|") || return 0
        case "$c" in
            once) rotate_once ;;
            30) rotate_setup 30 ;;
            60) rotate_setup 60 ;;
            off) rotate_disable ;;
            status) rotate_status ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

menu() {
    while true; do
        local c
        c=$(dt_menu "niri 壁纸 / 锁屏" "壁纸用 niri 原生 background-image; 锁屏 swaylock 样式" \
            "set|1. 设置壁纸|从 ~/Pictures/Wallpapers 选或输入路径" \
            "lock|2. 锁屏样式|swaylock 预设(极简/磨砂玻璃/默认)" \
            "rotate|3. 随机壁纸轮换|立即换一张 / 定时轮换" \
            "download|4. 下载壁纸|URL 下载到 Wallpapers(镜像回退)" \
            "status|5. 查看状态|壁纸 + 锁屏配置" \
            "clear|6. 清除壁纸|移除 wallpaper.kdl 与 include" \
            "uninstall|7. 卸载|清壁纸 + 锁屏样式恢复默认" \
            "back|← 返回|") || return 0
        case "$c" in
            set) set_wallpaper ;;
            lock)
                local s
                s=$(dt_menu "锁屏样式" "swaylock 预设:" "simple|极简|纯色+圆角时钟" "frost|磨砂玻璃|模糊截图+透明" "default|恢复默认|移除本工具配置") || continue
                [ "$s" = __quit ] && exit 0
                lock_preset "$s" ;;
            rotate) menu_rotate ;;
            download) dl_wallpaper ;;
            status) status ;;
            clear) clear_wallpaper ;;
            uninstall) clear_wallpaper; lock_preset default ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    set) set_wallpaper ;;
    rotate) rotate_once ;;
    rotate-setup) rotate_setup "${2:-30}" ;;
    rotate-off) rotate_disable ;;
    rotate-status) rotate_status ;;
    download) dl_wallpaper "${2:-}" ;;
    clear) clear_wallpaper ;;
    status) status ;;
    uninstall) clear_wallpaper; lock_preset default ;;
    menu) menu ;;
    *) echo "用法: niri-wallpaper.sh [set|clear|status|uninstall|menu]" >&2; exit 1 ;;
esac
