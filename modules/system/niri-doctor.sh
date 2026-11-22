#!/usr/bin/env bash
# =============================================================================
# niri-doctor.sh — niri 环境体检
#
# 背景: "装完 niri 但登录界面出不来 / 起来后顶栏缺失"这类问题, 原因散落在
#   包是否装好、会话文件写法、显示管理器单元名、niri 版本门槛、用户级文件残留
#   等多个地方。过去靠一条条排查, 现在一次体检全部列出, 并可一键修复。
#
# 检测项全部来自本仓库真实踩过的坑(见 AGENTS.md 第 10 节):
#   a) niri 包未安装
#   b) 系统级会话文件缺失 / 在错误的用户级目录
#   c) Exec 不是绝对路径
#   d) 缺 X-GDM-CanRunHeadless=true —— GDM 静默丢弃该会话的根因
#   e) niri 版本低于 26.04 —— Noctalia 模糊规则会报配置错误
#   f) 显示管理器单元探测不到(收尾的"重启"命令会失败)
#   g) DMS systemd 用户服务未激活
#   h) dms 与 noctalia 双外壳同时自启(抢顶栏/程序坞/快捷键)
#
# 用法: bash niri-doctor.sh [--fix]
#   --fix  检测出可自动修复的问题时直接修, 不再逐个询问
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
# niri.sh 提供颜色变量与显示管理器探测; 它自身依赖 common.sh 的 dt_detect_gui 等
source "$DT_ROOT/lib/niri.sh"
# ui.sh 提供 dt_confirm(GUI 可用时弹框, 否则退化为文本 [y/N])
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

AUTO_FIX=0
[ "${1:-}" = "--fix" ] && AUTO_FIX=1

# ---------------------------------------------------------------------------
# 颜色: niri_color_init 在非 tty 下会把它们置为空串
# 用 ${VAR:-} 兜底, 即使未调用 init 也不会因未绑定变量退出
# ---------------------------------------------------------------------------
niri_color_init 2>/dev/null || true
C_OK=${DT_GREEN:-}; C_BAD=${DT_RED:-$'\033[0;31m'}; C_WARN=${DT_YELLOW:-}
C_YELLOW=${DT_YELLOW:-}; C_CYAN=${DT_CYAN:-}; C_NC=${DT_NC:-}; C_BOLD=${DT_BOLD:-}

# 会话文件路径(与 lib/niri.sh 保持一致)
SYS_DIR=/usr/share/wayland-sessions
SYS_FILE="$SYS_DIR/niri.desktop"
USR_FILE="$HOME/.local/share/wayland-sessions/niri.desktop"
NCFG="$HOME/.config/niri/config.kdl"

log() { echo "  [doctor] $*"; }
err() { echo "  [doctor] 错误: $*" >&2; }

n=0; fail=0; warn=0
FIXABLE=()    # 可自动修复项的函数名, 供 --fix / 交互修复使用
FIX_LABEL=()  # 与 FIXABLE 一一对应的用户可读标签(不含函数名)

# ok / bad / wrn <消息>; bad 可带 [修复函数名] [友好标签]
ok()  { n=$((n+1)); echo -e "${C_OK}✔${C_NC} $*"; }
wrn() { n=$((n+1)); warn=$((warn+1)); echo -e "${C_WARN}⚠${C_NC} $*"; }
bad() {
    local msg="$1"; shift || true
    n=$((n+1)); fail=$((fail+1))
    # 第 2 个参数若是修复函数名, 第 3 个是它的友好标签; 只打印标签, 不泄露函数名
    if [ "${1:-}" != "" ]; then
        FIXABLE+=("$1")
        FIX_LABEL+=("${2:-自动修复}")
        echo -e "${C_BAD}✘${C_NC} ${msg}（可修复：${FIX_LABEL[-1]}）"
    else
        echo -e "${C_BAD}✘${C_NC} ${msg}"
    fi
}

echo
echo -e "${C_BOLD}═══ niri 环境体检 ═══${C_NC}"

# ---------------------------------------------------------------------------
# 1) niri 本体
# ---------------------------------------------------------------------------
if command -v niri >/dev/null 2>&1; then
    ok "niri 已安装: $(niri --version 2>/dev/null | head -1)"
else
    bad "未安装 niri(合成器本体缺失, 其余项无从谈起)" ""
    echo
    echo -e "${C_CYAN}先跑: bash $DT_ROOT/modules/wm/niri-dms.sh${C_NC}"
    echo -e "${C_CYAN}或:   bash $DT_ROOT/modules/wm/niri-noctalia.sh(会自动连带装 niri)${C_NC}"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2) 系统级会话文件
# ---------------------------------------------------------------------------
if [ -f "$SYS_FILE" ]; then
    ok "系统级会话文件存在: $SYS_FILE"

    # 2a) Exec 绝对路径
    if grep -q '^Exec=/usr/bin/niri-session' "$SYS_FILE" 2>/dev/null; then
        ok "Exec 为绝对路径: $(grep '^Exec=' "$SYS_FILE" | head -1 | cut -d= -f2-)"
    elif [ -f "$SYS_FILE" ] && grep -q '^Exec=niri-session' "$SYS_FILE" 2>/dev/null; then
        bad "Exec 是裸命令名(应为 /usr/bin/niri-session 绝对路径)" fix_exec "Exec 改绝对路径"
    else
        wrn "Exec 写法不标准, 建议改为 Exec=/usr/bin/niri-session"
    fi

    # 2b) X-GDM-CanRunHeadless —— GDM 静默过滤会话的根因
    if grep -q '^X-GDM-CanRunHeadless=true' "$SYS_FILE" 2>/dev/null; then
        ok "含 X-GDM-CanRunHeadless=true(GDM 不会静默丢弃该会话)"
    else
        bad "缺 X-GDM-CanRunHeadless=true(GDM 下登录界面不会出现 niri)" fix_headless "补 headless 键"
    fi
else
    bad "系统级会话文件缺失: $SYS_FILE(登录界面不会列出 niri)" fix_session "补系统级会话文件"
fi

# ---------------------------------------------------------------------------
# 3) 用户级残留文件: 对 greeter 无效, 还会误导
# ---------------------------------------------------------------------------
if [ -f "$USR_FILE" ]; then
    bad "用户级会话文件残留: $USR_FILE(对 greeter 无效, 应删除)" fix_user_file "删用户级残留"
else
    ok "无用户级会话文件残留"
fi

# ---------------------------------------------------------------------------
# 4) niri 版本门槛(Noctalia 模糊规则要 >= 26.04)
# ---------------------------------------------------------------------------
NIRI_VER=$(niri --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
if [ -n "$NIRI_VER" ]; then
    CURR=${NIRI_VER%.*}; NEXT=${NIRI_VER#*.}
    CURR=$((10#$CURR)); NEXT=$((10#$NEXT))
    if [ "$CURR" -gt 26 ] || { [ "$CURR" -eq 26 ] && [ "$NEXT" -ge 4 ]; }; then
        ok "niri 版本 ${NIRI_VER} ≥ 26.04(Noctalia 模糊规则可用)"
    else
        wrn "niri ${NIRI_VER} < 26.04: Noctalia 的 blur 规则会报配置错误, 升级 niri 后可用"
    fi
else
    wrn "无法获取 niri 版本, 跳过版本门槛检查"
fi

# ---------------------------------------------------------------------------
# 5) 显示管理器单元
# ---------------------------------------------------------------------------
DM_UNIT=$(niri_dm_unit 2>/dev/null || true)
if [ -n "$DM_UNIT" ]; then
    ok "显示管理器: ${DM_UNIT%.service}(重启命令: sudo systemctl restart ${DM_UNIT})"
else
    wrn "未探测到已知显示管理器(gdm/sddm/lightdm/plasmalogin), 重启命令可能需手动"
fi

# ---------------------------------------------------------------------------
# 6) DMS systemd 用户服务(可选: 未装 DMS 则不报)
# ---------------------------------------------------------------------------
if rpm -q dms >/dev/null 2>&1 || command -v dms >/dev/null 2>&1; then
    if systemctl --user is-active dms >/dev/null 2>&1 \
        || [ -L "$(systemctl --user show -p FragmentPath --value dms 2>/dev/null)" ]; then
        ok "DMS systemd 用户服务已激活"
    else
        wrn "DMS 已安装但用户服务未激活(登录时不会自启 dms)"
    fi
else
    log "未安装 DMS, 跳过 DMS 服务检查"
fi

# ---------------------------------------------------------------------------
# 7) 双外壳冲突: dms 与 noctalia 同时自启会抢顶栏
# ---------------------------------------------------------------------------
HAS_DMS=0; HAS_NOC=0
[ -f "$HOME/.config/niri/dms/binds.kdl" ] && HAS_DMS=1
grep -qs 'spawn-at-startup "noctalia"' "$NCFG" 2>/dev/null && HAS_NOC=1
if [ "$HAS_DMS" = 1 ] && [ "$HAS_NOC" = 1 ]; then
    bad "检测到 DMS 与 Noctalia 双外壳同时启用(会抢顶栏/程序坞/Alt+Tab)" ""
    echo -e "    切换器: bash $DT_ROOT/modules/wm/niri-shell-switch.sh"
else
    ok "无双外壳冲突(当前启用: $([ "$HAS_DMS" = 1 ] && echo DMS || true)$([ "$HAS_NOC" = 1 ] && echo Noctalia || true))"
fi

# ---------------------------------------------------------------------------
# 修复函数: 每项只改该改的, 全部幂等
# ---------------------------------------------------------------------------
fix_exec() {
    sed -i 's|^Exec=niri-session$|Exec=/usr/bin/niri-session|' "$SYS_FILE" \
        && log "已把 Exec 改为绝对路径" || err "改 Exec 失败"
}
fix_headless() {
    grep -q '^X-GDM-CanRunHeadless=' "$SYS_FILE" 2>/dev/null \
        && sed -i 's|^X-GDM-CanRunHeadless=.*|X-GDM-CanRunHeadless=true|' "$SYS_FILE" \
        || echo 'X-GDM-CanRunHeadless=true' >> "$SYS_FILE"
    log "已补 X-GDM-CanRunHeadless=true"
}
fix_session() {
    # 复用 lib/niri.sh 的完整实现(幂等)
    niri_ensure_dm_session
}
fix_user_file() {
    rm -f "$USR_FILE" && log "已删除用户级残留 $USR_FILE"
}

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
    echo -e "${C_OK}${C_BOLD}体检通过：${n} 项全部正常（${warn} 项提示）。${C_NC}"
else
    echo -e "${C_BAD}${C_BOLD}体检发现 ${fail} 项问题（共 ${n} 项，${warn} 项提示）。${C_NC}"
    if [ "${#FIXABLE[@]}" -gt 0 ]; then
        echo -e "  其中 ${#FIXABLE[@]} 项可自动修复。"
        if [ "$AUTO_FIX" = 1 ]; then
            echo -e "${C_CYAN}==> --fix 已指定, 开始自动修复…${C_NC}"
            for fn in "${FIXABLE[@]}"; do "$fn" || true; done
        elif [ -t 0 ]; then
            echo
            if dt_confirm "要现在自动修复这 ${#FIXABLE[@]} 项吗？"; then
                for fn in "${FIXABLE[@]}"; do "$fn" || true; done
            else
                echo -e "  ${C_CYAN}已跳过。可稍后执行: bash $0 --fix${C_NC}"
            fi
        else
            echo -e "  非交互环境, 用 ${C_CYAN}bash $0 --fix${C_NC} 自动修复。"
        fi
        echo
        echo -e "  ${C_YELLOW}修复后需重启显示管理器才生效: ${C_CYAN}sudo systemctl restart ${DM_UNIT:-<你的显示管理器>}${C_NC}"
    fi
fi