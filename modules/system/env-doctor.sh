#!/usr/bin/env bash
# =============================================================================
# env-doctor.sh —— 通用环境体检（磁盘/内存/服务/更新/输入法）
#
# 与 niri-doctor.sh（niri 专项）互补：这里是"整机"层面的健康检查，只读，
# 不修改任何配置。放进 modules/system/ 由 main.sh 的 sub_system 自动扫描。
#
# 用法: bash env-doctor.sh
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'; DT_CYAN=$'\033[0;36m'
    DT_RED=$'\033[0;31m';   DT_BOLD=$'\033[1m';       DT_NC=$'\033[0m'
else
    DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_BOLD=""; DT_NC=""
fi

n=0; warn=0
ok()  { n=$((n+1)); echo -e "  ${DT_GREEN}✔${DT_NC} $*"; }
wrn() { n=$((n+1)); warn=$((warn+1)); echo -e "  ${DT_YELLOW}⚠${DT_NC} $*"; }
bad() { n=$((n+1)); warn=$((warn+1)); echo -e "  ${DT_RED}✘${DT_NC} $*"; }
log() { echo -e "  ${DT_CYAN}[env-doctor]${DT_NC} $*"; }

# 捕获输出后再 grep（pipefail 下避免上游 SIGPIPE 误判）
grep_safe() { # <pattern> <file>
    local out
    out=$(cat "$2" 2>/dev/null || true)
    grep -q "$1" <<<"$out"
}

echo -e "${DT_BOLD}═══ 通用环境体检 ═══${DT_NC}"

# --- 磁盘 ---
DISK_USED=$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
if [ -n "${DISK_USED:-}" ]; then
    if [ "$DISK_USED" -ge 90 ]; then
        bad "根分区已用 ${DISK_USED}%（≥90%，建议清理）"
    elif [ "$DISK_USED" -ge 80 ]; then
        wrn "根分区已用 ${DISK_USED}%（≥80%，留意空间）"
    else
        ok "根分区已用 ${DISK_USED}%"
    fi
else
    wrn "无法读取磁盘使用率"
fi

# --- 内存 ---
MEM_PCT=$(free 2>/dev/null | awk '/^Mem:/ {printf "%d", $3*100/$2}')
if [ -n "${MEM_PCT:-}" ]; then
    if [ "$MEM_PCT" -ge 90 ]; then
        bad "内存占用 ${MEM_PCT}%（≥90%）"
    elif [ "$MEM_PCT" -ge 80 ]; then
        wrn "内存占用 ${MEM_PCT}%（≥80%）"
    else
        ok "内存占用 ${MEM_PCT}%"
    fi
else
    wrn "无法读取内存状态"
fi

# --- 会话/桌面 ---
echo -e "  ${DT_CYAN}── 桌面会话 ──${DT_NC}"
case "${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_TYPE:-}" in
    *:wayland) ok "桌面：${XDG_CURRENT_DESKTOP:-未知} / Wayland" ;;
    *:x11)     ok "桌面：${XDG_CURRENT_DESKTOP:-未知} / X11" ;;
    *)         wrn "未识别桌面会话（${XDG_CURRENT_DESKTOP:-无} / ${XDG_SESSION_TYPE:-无}）" ;;
esac

# --- 关键服务 ---
echo -e "  ${DT_CYAN}── 关键服务 ──${DT_NC}"
chk_svc() { # <unit> <说明>
    if systemctl --user is-active "$1" >/dev/null 2>&1; then
        ok "$2（$1）：运行中"
    elif systemctl --user is-enabled "$1" >/dev/null 2>&1; then
        wrn "$2（$1）：已启用但未运行"
    else
        wrn "$2（$1）：未启用"
    fi
}
# 合成器 / 外壳 / 输入法 / 远程主机 按需探测
pgrep -x niri >/dev/null 2>&1 && ok "niri：运行中" || true
systemctl --user is-active dms >/dev/null 2>&1 && ok "DMS 桌面外壳：运行中" || true
chk_svc uuremote-native.service "UU 远程主机"
pgrep -x fcitx5 >/dev/null 2>&1 && ok "fcitx5：运行中" || wrn "fcitx5：未运行（输入法不可用）"

# --- 失败的 systemd 单元 ---
echo -e "  ${DT_CYAN}── systemd 失败单元 ──${DT_NC}"
FAILED=$(systemctl --user --failed --no-legend 2>/dev/null | awk 'NR==1 && $0!="" {print $2}' | head -1 || true)
if [ -n "${FAILED:-}" ]; then
    bad "存在失败的用户单元：$FAILED（journalctl --user -u $FAILED 查看）"
else
    ok "无失败的用户单元"
fi

# --- 待更新（dnf，限时） ---
echo -e "  ${DT_CYAN}── 系统更新 ──${DT_NC}"
UPD=$(timeout 60 dnf -q check-update 2>/dev/null | grep -vc '^$' || true)
if [ "${UPD:-0}" -gt 0 ]; then
    wrn "有 ${UPD} 个可用更新（sudo dnf upgrade 安装）"
else
    ok "系统已是最新"
fi

# --- 输入法 ---
echo -e "  ${DT_CYAN}── 输入法 ──${DT_NC}"
if command -v rpm >/dev/null 2>&1 && rpm -q wowtype >/dev/null 2>&1; then
    ok "WowType 已安装（$(rpm -q --qf '%{VERSION}' wowtype 2>/dev/null || echo ?)）"
else
    wrn "WowType 未安装"
fi
if grep_safe '^DefaultIM=wowtype' "$HOME/.config/fcitx5/profile"; then
    ok "fcitx5 默认输入法：wowtype"
elif [ -f "$HOME/.config/fcitx5/profile" ]; then
    wrn "fcitx5 默认输入法不是 wowtype"
else
    wrn "fcitx5 未配置输入法"
fi

echo
echo -e "  ${DT_GREEN}${DT_BOLD}体检完成：${n} 项（${warn} 项提示）。${DT_NC}"
