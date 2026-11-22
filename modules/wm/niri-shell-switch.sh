#!/usr/bin/env bash
# =============================================================================
# niri-shell-switch.sh — 在 niri 的两个桌面外壳之间切换(DMS ↔ Noctalia)
#
# 背景: 两个外壳都是完整桌面壳, 同时启用会抢顶栏 / 程序坞 / Alt+Tab, 现象是
#   "顶栏重叠"或"快捷键互相覆盖"。切换 = 关掉一个的自启 + 打开另一个的自启。
#
# 各外壳的"自启"由两部分组成:
#   DMS      : systemd 用户服务 dms(WantedBy=graphical-session.target)
#              + config.kdl 里 include "dms/*.kdl"(配色/布局/绑定)
#   Noctalia : systemd 用户服务 noctalia(WantedBy=niri.service)
#              + config.kdl 里 spawn-at-startup "noctalia" + include "noctalia.kdl"
#
# 用法: bash niri-shell-switch.sh [dms|noctalia|none]
#   不带参数 → 交互式选择; 带参数 → 直接切到该外壳(非交互环境可用)
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

NCFG="$HOME/.config/niri/config.kdl"

log() { echo "  [shell-switch] $*"; }
err() { echo "  [shell-switch] 错误: $*" >&2; }

# ---------------------------------------------------------------------------
# 检测: 当前实际启用了哪些外壳
# ---------------------------------------------------------------------------
dms_on()      { systemctl --user is-enabled dms >/dev/null 2>&1; }
noctalia_on() { systemctl --user is-enabled noctalia.service >/dev/null 2>&1; }

dms_pkg_on()      { command -v dms >/dev/null 2>&1 || rpm -q dms >/dev/null 2>&1; }
noctalia_pkg_on() { command -v noctalia >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# DMS: 处理 config.kdl 里的 dms include 行
#   设计为"从备份整体重建"(build_shell_cfg), 而非增量注释/还原:
#   增量的多次开关组合容易产生中间态丢失, 从原始配置重建则始终幂等。
#   awk 逐行处理, 避免 sed 替换串含空格/括号破坏引号嵌套。
# ---------------------------------------------------------------------------
DMSMARK="# shell-switch-dms"   # 临时标记, build_shell_cfg 用后即清理
CFG_ORIG=""                     # 原始配置备份路径(本进程内只备一次)

# 确保存在一份原始配置备份(未含任何 shell-switch 标记)
#   用【固定】路径且只在不存在时备份: 若路径带时间戳, 每次切换都会新存一份,
#   第二份存的是"已被切换过的"配置, 会污染重建基准 —— 实测踩过。
backup_orig() {
    CFG_ORIG="${NCFG}.orig-shellswitch"
    [ -f "$CFG_ORIG" ] && return 0
    grep -qsF "$DMSMARK" "$NCFG" 2>/dev/null && return 0
    cp -a "$NCFG" "$CFG_ORIG" 2>/dev/null || true
}

# 按目标状态重建 config.kdl: keep_dms / keep_noctalia = 1 保留, 0 移除
build_shell_cfg() { # <keep_dms> <keep_noctalia>
    backup_orig
    [ -f "$CFG_ORIG" ] || { err "无原始配置备份, 跳过重建"; return 1; }
    local kd="$1" kn="$2"
    awk -v mark="$DMSMARK" -v kd="$kd" -v kn="$kn" '
        {
            line = $0
            sub(mark, "", line)          # 去掉历史标记, 从干净状态判断
            is_dms = (line ~ /^include[[:space:]]+optional=true[[:space:]]+"dms\//)
            is_noc = (line ~ /^spawn-at-startup "noctalia"$/ || line ~ /^include "noctalia.kdl"$/)
            if (is_dms)      { if (kd == 1) print line; next }
            if (is_noc)      { if (kn == 1) print line; next }
            print line
        }
    ' "$CFG_ORIG" > "${NCFG}.tmp" && mv "${NCFG}.tmp" "$NCFG"
    log "已按目标状态重建 config.kdl(dms=$kd, noctalia=$kn)"
}

# 配置改动统一由 apply() 调 build_shell_cfg, 这里只管理服务状态
disable_dms_cfg()     { :; }
enable_dms_cfg()      { :; }

disable_dms() {   # 只关 systemd 服务; 配置改动由 apply() 统一重建
    if systemctl --user is-enabled dms >/dev/null 2>&1; then
        systemctl --user disable dms 2>/dev/null \
            && log "已停用 DMS 用户服务(dms)" \
            || err "停用 dms 服务失败, 可手动: systemctl --user disable dms"
    fi
}

enable_dms() {
    if dms_pkg_on && ! dms_on; then
        systemctl --user enable dms 2>/dev/null \
            && log "已启用 DMS 用户服务" \
            || err "启用 dms 服务失败, 可手动: systemctl --user enable dms"
    fi
}

# ---------------------------------------------------------------------------
# Noctalia: 只开关 systemd 用户服务
#   config.kdl 的 spawn/include 行由 build_shell_cfg 统一重建, 这里不再改动
# ---------------------------------------------------------------------------
disable_noctalia_cfg() { :; }
enable_noctalia_cfg()  { :; }

disable_noctalia() {
    if noctalia_on; then
        systemctl --user disable noctalia.service 2>/dev/null \
            && log "已停用 Noctalia 用户服务" \
            || err "停用 noctalia 服务失败, 可手动: systemctl --user disable noctalia.service"
    fi
}

enable_noctalia() {
    if noctalia_pkg_on && ! noctalia_on; then
        systemctl --user enable noctalia.service 2>/dev/null \
            && log "已启用 Noctalia 用户服务" \
            || err "启用 noctalia 服务失败, 可手动: systemctl --user enable noctalia.service"
    fi
}

# ---------------------------------------------------------------------------
# 应用切换: 按目标状态重建 config.kdl + 开关对应服务
# ---------------------------------------------------------------------------
apply() { # <dms|noctalia|none>
    local target="$1" kd=0 kn=0
    echo
    echo "==> 切换到: ${target:-（无外壳）}"

    # 1) 按目标状态从原始配置重建 config.kdl(一次成型, 天然幂等)
    case "$target" in
        dms)      kd=1 ;;
        noctalia) kn=1 ;;
    esac
    [ -f "$NCFG" ] && build_shell_cfg "$kd" "$kn"

    # 2) 关掉全部服务(幂等: 未启用时内部 no-op)
    disable_dms
    disable_noctalia

    # 3) 只开目标的服务
    case "$target" in
        dms)      enable_dms ;;
        noctalia) enable_noctalia ;;
        none)     log "已停用两个外壳" ;;
        *)        err "未知目标: $target"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
echo "══════════════════════════════════════════"
echo " niri 桌面外壳切换"
echo "══════════════════════════════════════════"
echo
echo -e "  当前状态:"
dms_on      && echo "    DMS      : 已启用" || echo "    DMS      : 未启用$({ dms_pkg_on; } && echo "(未安装)")"
noctalia_on && echo "    Noctalia : 已启用" || echo "    Noctalia : 未启用$({ noctalia_pkg_on; } && echo "(未安装)")"

if dms_on && noctalia_on; then
    echo
    echo "  ⚠ 两个外壳都开着, 会抢顶栏/程序坞/Alt+Tab —— 请选一个。"
fi
echo

# 目标: 命令行参数优先, 否则交互选择
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    [ -t 0 ] || { err "非交互环境请用: bash $0 dms|noctalia|none"; exit 1; }
    TARGET=$(dt_menu "选择要启用的外壳" "两个都是完整桌面壳, 同时开会抢顶栏:" \
        "dms|DMS (Dux Modular Shell)|$({ dms_pkg_on; } && echo '已安装' || echo '未安装')" \
        "noctalia|Noctalia|$({ noctalia_pkg_on; } && echo '已安装' || echo '未安装')" \
        "none|都不启用|只留 niri 本体" \
        "cancel|取消|") || { err "已取消"; exit 0; }
    case "$TARGET" in
        dms|noctalia|none) ;;
        *) err "已取消"; exit 0 ;;
    esac
fi

# 二次确认: 切换会关掉当前正在用的外壳(非交互环境直接执行)
if [ -t 0 ]; then
    dt_confirm "确认切换到 \"${TARGET}\"？这会停用另一个外壳。" || true
fi
apply "$TARGET"

echo
echo -e "  切换完成。生效方式(任选其一):"
echo -e "    • 注销后重新登录"
echo -e "    • 立即重载配置: ${DT_CYAN:-}niri msg action config-reload${DT_NC:-}"