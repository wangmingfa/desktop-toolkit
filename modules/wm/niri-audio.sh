#!/usr/bin/env bash
# =============================================================================
# niri-audio.sh —— 音频控制 + 快捷键（pamixer + playerctl）
#
# 生成 ~/.config/niri/audio.kdl(binds: 音量/静音/媒体键)，主配置末尾加
# `include optional=true "audio.kdl"`(幂等)。与 niri-tools 的 tools.kdl、
# niri-config 的 dt-settings.kdl 各自独立 include，互不干扰。
# 注册 main.sh WM 子菜单。
#
# 用法: bash niri-audio.sh [install|uninstall|status|up|down|mute|play]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
log() { echo "  [niri-audio] $*"; }
err() { echo "  [niri-audio] 错误: $*" >&2; }

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
MAIN="$NIRI_DIR/config.kdl"
AUDIO="$NIRI_DIR/audio.kdl"
AUDIO_INCLUDE='include optional=true "audio.kdl"'
PKGS="pamixer"   # playerctl 已有，不强制

# --- include 管理(awk 幂等, 参照 niri-tools) ---
ensure_include() {
    grep -q 'audio\.kdl' "$MAIN" 2>/dev/null && return 0
    awk -v inc="$AUDIO_INCLUDE" '{ print } END { print ""; print "// dt-audio include (niri-audio.sh 管理)"; print inc }' "$MAIN" > "$MAIN.tmp" \
        && mv "$MAIN.tmp" "$MAIN"
    log "已在主配置末尾加入 include audio.kdl"
}

remove_include() {
    awk -v inc="$AUDIO_INCLUDE" '
        /dt-audio include/ { skip=1; next }
        skip && /^include optional=true "audio.kdl"/ { skip=0; next }
        { print }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    log "已从主配置移除 include audio.kdl"
}

# --- 生成 audio.kdl（音量/静音/媒体键） ---
gen_audio() {
    cat > "$AUDIO" <<'KDL'
// 由 desktop-toolkit niri-audio.sh 生成；请用工具修改，手改可能被覆盖。
binds {
    XF86AudioRaiseVolume { spawn "pamixer" "-i" "5"; }
    XF86AudioLowerVolume { spawn "pamixer" "-d" "5"; }
    XF86AudioMute { spawn "pamixer" "--toggle-mute"; }
    XF86AudioPlay { spawn "playerctl" "play-pause"; }
    XF86AudioNext { spawn "playerctl" "next"; }
    XF86AudioPrev { spawn "playerctl" "previous"; }
}
KDL
    log "音量/静音/媒体键快捷键已写入 audio.kdl"
}

# --- 安装/修复 ---
install_pkgs() {
    command -v pamixer >/dev/null 2>&1 && { log "pamixer 已装"; return 0; }
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        err "安装 pamixer 需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    log "安装 pamixer ..."
    if ! sudo dnf install -y "$PKGS"; then
        err "安装失败，请手动: sudo dnf install $PKGS"
        return 1
    fi
    log "pamixer 安装完成"
}

do_install() {
    install_pkgs || return 1
    gen_audio
    ensure_include
    command -v niri >/dev/null 2>&1 && niri msg action load-config-file 2>/dev/null \
        && log "已热重载 niri（音量/媒体键立即生效）" \
        || log "niri 未运行或重载失败，下次启动生效"
    log "完成。音量键(XF86Audio*)/媒体键(play/next/prev)已绑定。"
}

do_uninstall() {
    rm -f "$AUDIO"
    remove_include
    command -v niri >/dev/null 2>&1 && niri msg action load-config-file 2>/dev/null || true
    log "已移除 audio.kdl 与 include（pamixer 保留，如需卸载: sudo dnf remove pamixer）"
}

# --- 快捷动作 ---
vol_up()   { command -v pamixer >/dev/null 2>&1 && pamixer -i 5 && echo "  音量: $(pamixer --get-volume)%"; }
vol_down() { command -v pamixer >/dev/null 2>&1 && pamixer -d 5 && echo "  音量: $(pamixer --get-volume)%"; }
vol_mute() { command -v pamixer >/dev/null 2>&1 && pamixer --toggle-mute && echo "  已切换静音"; }
play()     { command -v playerctl >/dev/null 2>&1 && playerctl play-pause 2>/dev/null; }

status() {
    echo "=== niri-audio 状态 ==="
    command -v pamixer >/dev/null 2>&1 \
        && echo "  ✅ pamixer  音量: $(pamixer --get-volume 2>/dev/null)%" \
        || echo "  ❌ pamixer 未装"
    command -v playerctl >/dev/null 2>&1 && echo "  ✅ playerctl" || echo "  ❌ playerctl 未装"
    [ -f "$AUDIO" ] && echo "  ✅ audio.kdl 已生成" || echo "  ❌ audio.kdl 未生成"
    grep -q 'audio\.kdl' "$MAIN" 2>/dev/null && echo "  ✅ 主配置已 include audio.kdl" || echo "  ❌ 未 include"
}

menu() {
    while true; do
        local c
        c=$(dt_menu "niri 音频控制" "音量/静音/媒体键快捷键（pamixer + playerctl）：" \
            "install|1. 安装/修复|装 pamixer + 生成快捷键(audio.kdl)" \
            "up|2. 音量 +5|调大当前输出" \
            "down|3. 音量 -5|调小当前输出" \
            "mute|4. 静音切换|开/关静音" \
            "play|5. 播放/暂停|playerctl play-pause" \
            "status|6. 状态|工具/快捷键/音量" \
            "uninstall|7. 卸载快捷键|移除 audio.kdl 与 include(保留 pamixer)" \
            "back|← 返回|") || return 0
        case "$c" in
            install) do_install ;;
            up) vol_up ;;
            down) vol_down ;;
            mute) vol_mute ;;
            play) play ;;
            status) status ;;
            uninstall) do_uninstall ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    install) do_install ;;
    uninstall) do_uninstall ;;
    status) status ;;
    up) vol_up ;;
    down) vol_down ;;
    mute) vol_mute ;;
    play) play ;;
    *) menu ;;
esac
