#!/usr/bin/env bash
# =============================================================================
# dms-topbar.sh —— DMS 顶栏监控组件管理（CPU/内存/磁盘/温度/网速/电池）
#
# DMS 内置顶栏组件由 barConfigs 控制（~/.config/dms/settings.json 只存非默认值）。
# 本模块读取 SPEC 默认 barConfigs（SettingsSpec.js）+ settings 现状，增删组件
# 写回 settings.json（先备份 .bak），重启 dms.service 生效。
# 不硬改 DMS QML；只动 settings.json 的 barConfigs 字段。
#
# 用法: bash dms-topbar.sh [status|list|add <id> [left|center|right]|remove <id>|reset]
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_BOLD=$'\033[1m'; DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'
    DT_CYAN=$'\033[0;36m'; DT_RED=$'\033[0;31m'; DT_NC=$'\033[0m'
else
    DT_BOLD=""; DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_NC=""
fi

dt_log() { echo -e "  ${DT_CYAN}[dms-topbar]${DT_NC} $*"; }
dt_err() { echo -e "  ${DT_RED}[dms-topbar] 错误:${DT_NC} $*" >&2; }

DMS_SETTINGS="$HOME/.config/dms/settings.json"

# 监控相关组件 id → 中文标签
MONITOR_WIDGETS="cpuUsage|memUsage|diskUsage|cpuTemp|gpuTemp|network_speed_monitor|battery"
monitor_label() {
    case "$1" in
        cpuUsage) echo "CPU 使用率" ;;
        memUsage) echo "内存使用率" ;;
        diskUsage) echo "磁盘使用率" ;;
        cpuTemp) echo "CPU 温度" ;;
        gpuTemp) echo "GPU 温度" ;;
        network_speed_monitor) echo "网络速度" ;;
        battery) echo "电池" ;;
        *) echo "$1" ;;
    esac
}

# --- python 助手: 读 SPEC 默认 barConfigs / 读 settings / 增删组件 / 写回 ---
# 用法: dt_py <op> [args...]  → stdout 为人类可读结果（错误走 stderr）
dt_py() {
    python3 - "$DMS_SETTINGS" "$@" <<'PY'
import json, re, sys, os, shutil

SETTINGS = sys.argv[1]
op = sys.argv[2]
args = sys.argv[3:]

SPEC = "/usr/share/quickshell/dms/Common/settings/SettingsSpec.js"
CATALOG = "/usr/share/quickshell/dms/Common/BarWidgetCatalog.qml"
MONITOR = {"cpuUsage","memUsage","diskUsage","cpuTemp","gpuTemp","network_speed_monitor","battery"}

def parse_spec_bars():
    src = open(SPEC).read()
    i = src.index("barConfigs:")
    seg = src[i:i+12000]
    m = re.search(r"def:\s*\[", seg)
    start = seg.index("[", m.start())
    depth = 0; end = None
    for j in range(start, len(seg)):
        if seg[j] == "[": depth += 1
        elif seg[j] == "]":
            depth -= 1
            if depth == 0: end = j + 1; break
    block = seg[start:end]
    block2 = re.sub(r"(^|\n)(\s*)([A-Za-z_$][\w$]*)(:)(\s)", r'\1\2"\3"\4\5', block)
    block2 = re.sub(r"//[^\n]*", "", block2)
    block2 = re.sub(r",(\s*[}\]])", r"\1", block2)
    return json.loads(block2)

def load_settings():
    try: return json.load(open(SETTINGS))
    except: return {}

def cur_bars(s):
    b = s.get("barConfigs")
    if isinstance(b, list) and b: return b
    return parse_spec_bars()

def widget_ids():
    try:
        qml = open(CATALOG).read()
    except: return []
    ids = []
    for p in qml.split('"id":')[1:]:
        m = re.match(r'\s*"([^"]+)"', p)
        if m: ids.append(m.group(1))
    return ids

def save(s):
    if os.path.exists(SETTINGS):
        shutil.copy(SETTINGS, SETTINGS + ".bak")
    json.dump(s, open(SETTINGS, "w"), indent=2, ensure_ascii=False)

def dump_bars(bars):
    out = []
    for b in bars:
        line = f"  {b.get('name','?')} (id={b.get('id','?')})"
        if b.get("enabled") is False: line += " [禁用]"
        out.append(line)
        for sec in ("leftWidgets","centerWidgets","rightWidgets"):
            ws = b.get(sec, [])
            if not ws: continue
            sec_name = sec.replace("Widgets","")
            marks = []
            for w in ws:
                mark = "●" if w in MONITOR else " "
                marks.append(f"{mark}{w}")
            out.append(f"    {sec_name:6s}: " + ", ".join(marks))
    return "\n".join(out)

def bar_section(b, sec):
    key = {"left":"leftWidgets","center":"centerWidgets","right":"rightWidgets"}.get(sec)
    return key, (b.get(key) if key else [])

if op == "status":
    bars = cur_bars(load_settings())
    print(dump_bars(bars))
elif op == "list":
    print("\n".join(widget_ids()))
elif op == "add":
    wid, sec = args[0], (args[1] if len(args) > 1 else "right")
    ids = widget_ids()
    if wid not in ids:
        print(f"ERROR: 未知组件 id「{wid}」(可用: dms-topbar list)"); sys.exit(1)
    s = load_settings()
    bars = cur_bars(s)
    key, ws = bar_section(bars[0], sec)
    if wid in ws:
        print(f"已在 {sec} 中: {wid}"); sys.exit(0)
    bars[0][key] = ws + [wid]
    s["barConfigs"] = bars
    save(s)
    print(f"已添加 {wid} 到 {sec}（重启 dms 生效）")
elif op == "remove":
    wid = args[0]
    s = load_settings()
    bars = cur_bars(s)
    found = False
    for b in bars:
        for key in ("leftWidgets","centerWidgets","rightWidgets"):
            if wid in b.get(key, []):
                b[key] = [w for w in b[key] if w != wid]
                found = True
    if not found:
        print(f"未找到: {wid}"); sys.exit(0)
    s["barConfigs"] = bars
    save(s)
    print(f"已移除 {wid}（重启 dms 生效）")
elif op == "reset":
    s = load_settings()
    if "barConfigs" not in s:
        print("当前就是默认顶栏"); sys.exit(0)
    del s["barConfigs"]
    save(s)
    print("已恢复默认顶栏（删除 barConfigs，重启 dms 生效）")
else:
    print(f"ERROR: 未知操作 {op}"); sys.exit(1)
PY
}

# --- bash 包装 ---
dt_status() {
    echo -e "  ${DT_BOLD}═══ DMS 顶栏组件（●=监控相关）═══${DT_NC}"
    local out
    out=$(dt_py status 2>&1) || { dt_err "$out"; return 1; }
    echo -e "$out"
    echo
    echo -e "  ${DT_YELLOW}提示: 组件改后需重启 dms（${DT_NC}systemctl --user restart dms${DT_YELLOW}）${DT_NC}"
}

dt_add() { # <id> [left|center|right]
    local wid="${1:-}" sec="${2:-right}"
    [ -n "$wid" ] || return 0
    case "$sec" in left|center|right) ;; *) sec=right ;; esac
    local out
    out=$(dt_py add "$wid" "$sec" 2>&1) || { dt_err "$out"; return 1; }
    dt_log "$out"
}

dt_remove() { # <id>
    local wid="${1:-}"
    [ -n "$wid" ] || return 0
    local out
    out=$(dt_py remove "$wid" 2>&1) || { dt_err "$out"; return 1; }
    dt_log "$out"
}

dt_reset() {
    local out
    out=$(dt_py reset 2>&1) || { dt_err "$out"; return 1; }
    dt_log "$out"
}

dt_toggle() { # <id> —— 在顶栏开/关单个监控组件
    local wid="$1" cur present
    cur=$(dt_py status 2>/dev/null)
    # 组件在顶栏(●或空格前缀 + 名字)则关闭, 否则开启
    if printf '%s\n' "$cur" | grep -qE "[● ]${wid}(,|$)"; then
        dt_log "关闭 $(monitor_label "$wid") ..."
        dt_remove "$wid"
    else
        dt_log "开启 $(monitor_label "$wid") ..."
        dt_add "$wid" right
    fi
}

dt_menu_monitor() {
    while true; do
        local cur out c
        cur=$(dt_py status 2>/dev/null)
        # 逐个监控组件, 标记开/关
        local -a rows=()
        local wid state
        for wid in cpuUsage memUsage diskUsage cpuTemp gpuTemp network_speed_monitor battery; do
            if printf '%s\n' "$cur" | grep -qE "●${wid}(,|$)"; then state="已开"; else state="已关"; fi
            rows+=("$wid|$(monitor_label "$wid")|顶栏 ${state}")
        done
        rows+=("all-on|⚡ 全部开启|CPU/内存/磁盘/温度/网速/电池" "all-off|○ 全部关闭|移除所有监控组件" "back|← 返回|")
        c=$(dt_menu "DMS 顶栏监控组件" "点击切换某个组件（改后需重启 dms）：" "${rows[@]}") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            all-on)
                for wid in cpuUsage memUsage diskUsage cpuTemp gpuTemp network_speed_monitor battery; do dt_add "$wid" right; done ;;
            all-off)
                for wid in cpuUsage memUsage diskUsage cpuTemp gpuTemp network_speed_monitor battery; do dt_remove "$wid"; done ;;
            *) dt_toggle "$c" ;;
        esac
    done
}

dt_menu() {
    while true; do
        local c
        c=$(dt_menu "DMS 顶栏监控" "管理 DMS 顶栏组件（CPU/内存/磁盘/温度/网速/电池）：" \
            "status|1. 查看当前顶栏|各位置组件列表(●=监控)" \
            "monitor|2. 监控组件开关|逐个开/关 CPU/内存/磁盘/温度/网速/电池" \
            "add|3. 自定义添加|输入组件 id + 位置(left/center/right)" \
            "remove|4. 移除组件|输入组件 id" \
            "reset|5. 恢复默认顶栏|删除 barConfigs 还原默认" \
            "back|← 返回|") || return 0
        case "$c" in
            status) dt_status ;;
            monitor) dt_menu_monitor ;;
            add)
                local wid sec
                wid=$(dt_ask_text "添加组件" "组件 id（dms-topbar list 查看可用）" "") || continue
                [ -n "$wid" ] || continue
                sec=$(dt_menu "位置" "添加到哪个位置：" "left|左侧|" "center|中间|" "right|右侧(推荐)|") || continue
                [ "$sec" = __quit ] && exit 0
                dt_add "$wid" "$sec" ;;
            remove)
                local wid
                wid=$(dt_ask_text "移除组件" "组件 id（当前顶栏的）" "") || continue
                [ -n "$wid" ] || continue
                dt_remove "$wid" ;;
            reset)
                if dt_confirm "恢复默认顶栏？（会移除你添加的所有组件）"; then dt_reset; fi ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    status) dt_status ;;
    list) dt_py list ;;
    add) [ -n "${2:-}" ] && dt_add "$2" "${3:-right}" || dt_err "用法: dms-topbar.sh add <id> [left|center|right]" ;;
    remove) [ -n "${2:-}" ] && dt_remove "$2" || dt_err "用法: dms-topbar.sh remove <id>" ;;
    reset) dt_reset ;;
    *) dt_menu ;;
esac
