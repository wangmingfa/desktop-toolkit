#!/usr/bin/env bash
# =============================================================================
# niri 日常工具: 截图 / 录屏 / 剪贴板历史 + 快捷键
# -----------------------------------------------------------------------------
# 安装 wlroots 标准工具(dnf) 并生成 ~/.config/niri/tools.kdl(binds)，主配置
# 末尾加 `include optional=true "tools.kdl"`(幂等, 与 niri-config 的 dt-settings.kdl
# 互不干扰)。快捷键: Print 截图UI / Super+Shift+S 全屏 / Super+P 录屏开关 /
# Super+V 剪贴板历史(fuzzel 菜单)。
#
# 用法: niri-tools.sh [install|uninstall|status|menu]
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

log() { dt_log "$*"; }
err() { dt_err "$*"; }

NIRI_DIR="$HOME/.config/niri"
MAIN="$NIRI_DIR/config.kdl"
TOOLS="$NIRI_DIR/tools.kdl"

PKGS="grim slurp wl-clipboard wf-recorder cliphist swappy"
TOOLS_INCLUDE='include optional=true "tools.kdl"'

# 生成 binds(只含快捷键; 动作名已在 niri 26.04 validate 验证)
gen_tools_kdl() {
    cat > "$TOOLS" <<'KDL'
// dt-tools: niri 截图/录屏/剪贴板历史快捷键(由 niri-tools.sh 管理)
binds {
    // 截图 UI(区域/全屏/窗口可选)
    Print { screenshot-ui-open; }
    // 全屏截图直接保存
    Super+Shift+S { screenshot; }
    // 录屏开关: 再按一次停止
    Super+P { spawn "sh -c 'pgrep -f wf-recorder >/dev/null && pkill -f wf-recorder || wf-recorder -f $HOME/Videos/recording-$(date +%F-%H%M%S).mp4'"; }
    // 剪贴板历史: fuzzel 菜单选择
    Super+V { spawn "sh -c 'cliphist list | fuzzel --dmenu | cliphist decode | wl-copy'"; }
}
KDL
}

ensure_include() {
    grep -q 'tools\.kdl' "$MAIN" 2>/dev/null && return 0
    # 幂等: 在主配置末尾追加 include(awk -v 传变量, 避免含双引号的 include 行拼进 awk 程序)
    awk -v inc="$TOOLS_INCLUDE" '{ print } END { print ""; print "// dt-tools include (niri-tools.sh 管理)"; print inc }' "$MAIN" > "$MAIN.tmp" \
        && mv "$MAIN.tmp" "$MAIN"
    log "已在主配置末尾加入 include tools.kdl"
}

remove_include() {
    [ -f "$MAIN" ] || return 0
    awk -v inc="$TOOLS_INCLUDE" '
        /dt-tools include/ { skip=1; next }
        skip && /^include optional=true "tools.kdl"/ { skip=0; next }
        { print }
    ' "$MAIN" > "$MAIN.tmp" && mv "$MAIN.tmp" "$MAIN"
    log "已从主配置移除 include tools.kdl"
}

install_tools() {
    if ! command -v dnf >/dev/null 2>&1; then
        err "非 dnf 发行版，请手动安装: $PKGS"
        return 1
    fi
    # 只装缺失的(幂等)
    local need=() p
    for p in grim slurp wl-clipboard wf-recorder cliphist swappy; do
        command -v "$p" >/dev/null 2>&1 || need+=("$p")
    done
    if [ "${#need[@]}" -gt 0 ]; then
        log "安装: ${need[*]}（需 sudo）"
        sudo dnf install -y "${need[@]}" || { err "dnf 安装失败"; return 1; }
    else
        log "工具已全部安装"
    fi
    mkdir -p "$NIRI_DIR"
    gen_tools_kdl
    ensure_include
    log "截图/录屏/剪贴板快捷键已写入 tools.kdl"
    log "生效: 重启 niri 或 niri msg reload-config（Print/Super+P/Super+V）"
}

uninstall_tools() {
    remove_include
    rm -f "$TOOLS"
    log "已移除 tools.kdl 与 include（工具包保留，如需卸载: sudo dnf remove $PKGS）"
}

status_tools() {
    echo "=== 工具状态 ==="
    for p in grim slurp wf-recorder cliphist swappy fuzzel wl-copy; do
        command -v "$p" >/dev/null 2>&1 && echo "  ✅ $p" || echo "  ❌ $p"
    done
    echo "=== tools.kdl ==="
    [ -f "$TOOLS" ] && grep -E "Print|Super\+P|Super\+V|Super\+Shift" "$TOOLS" || echo "  (未安装)"
    echo "=== 主配置 include ==="
    grep -q 'tools\.kdl' "$MAIN" 2>/dev/null && echo "  ✅ tools.kdl 已 include" || echo "  ❌ 未 include"
}

menu() {
    while true; do
        local c
        c=$(dt_menu "niri 日常工具" "截图 / 录屏 / 剪贴板历史 + 快捷键（需 sudo 装工具）" \
            "install|1. 安装工具+快捷键|grim/slurp/wf-recorder/cliphist + Print/Super+P/Super+V" \
            "status|2. 查看状态|工具 + 快捷键是否就绪" \
            "uninstall|3. 卸载快捷键|移除 tools.kdl 与 include(保留工具包)" \
            "back|← 返回|") || return 0
        case "$c" in
            install) install_tools ;;
            status) status_tools ;;
            uninstall) uninstall_tools ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    install) install_tools ;;
    uninstall) uninstall_tools ;;
    status) status_tools ;;
    menu) menu ;;
    *) echo "用法: niri-tools.sh [install|uninstall|status|menu]" >&2; exit 1 ;;
esac
