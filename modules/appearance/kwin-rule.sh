#!/usr/bin/env bash
# =============================================================================
# 让配置中心的弹窗（zenity / kdialog）不进入任务栏 / Dock
#
# 配置中心每次翻页都会新开一个窗口，默认会在 Dock 上生成图标、来回闪烁。
# 这里写入 KWin 窗口规则（skipTaskbar），由 KWin 自动匹配，开机永久生效，
# 不需要常驻进程，也不影响窗口正常显示与聚焦。
#
# 用法:
#   kwin-rule.sh install   写入/更新规则并让 KWin 立即生效
#   kwin-rule.sh remove    删除 desktop-toolkit 相关规则
#   kwin-rule.sh status    查看当前规则
# =============================================================================
set -euo pipefail

KWINRULES="$HOME/.config/kwinrulesrc"
DBUS_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000"
TAG_PREFIX="desktop-toolkit:"
RULE_DESC="desktop-toolkit: 配置弹窗不进任务栏/Dock"
CLASSES=(zenity kdialog)

kwin_reconfigure() {
    env $DBUS_ENV busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
}

# 用 python 安全地增删规则组，保留其它已有规则
rule_edit() { # install|remove
    python3 - "$KWINRULES" "$1" "$TAG_PREFIX" "$RULE_DESC" "${CLASSES[@]}" <<'PY'
import sys, os, re, collections

path, action, tag_prefix, desc = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
classes = sys.argv[5:]

groups = collections.OrderedDict()
order = []
cur = None
if os.path.exists(path):
    for raw in open(path, encoding="utf-8", errors="replace").read().splitlines():
        s = raw.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1]
            groups[cur] = collections.OrderedDict()
            order.append(cur)
        elif cur is not None and "=" in raw:
            k, v = raw.split("=", 1)
            groups[cur][k.strip()] = v.strip()

# 删除旧的 desktop-toolkit 规则
removed = [g for g in order if groups[g].get("Description", "").startswith(tag_prefix)]
for g in removed:
    del groups[g]
    order.remove(g)

if action == "install":
    # 为每个窗口类各建一条规则
    used = [int(g) for g in groups if re.fullmatch(r"\d+", g)]
    nxt = max(used) + 1 if used else 1
    new_ids = []
    for cls in classes:
        rid = str(nxt); nxt += 1
        groups[rid] = collections.OrderedDict([
            ("Description", desc + f" ({cls})"),
            ("wmclass", cls),
            ("wmclassmatch", "1"),
            ("wmclasscomplete", "false"),
            ("skiptaskbar", "true"),
            ("skiptaskbarrule", "2"),
        ])
        order.append(rid)
        new_ids.append(rid)
    # 去掉旧的同义规则后，General 的 count/rules/Order 重新统计（含用户已有规则）
    rule_ids = [g for g in order if re.fullmatch(r"\d+", g)]
    gen = groups.setdefault("General", collections.OrderedDict())
    gen["count"] = str(len(rule_ids))
    gen["rules"] = ",".join(rule_ids)
    if "Order" in gen:
        gen["Order"] = ",".join(rule_ids)
    print("installed:" + ",".join(new_ids))
else:
    rule_ids = [g for g in order if re.fullmatch(r"\d+", g)]
    if "General" in groups:
        groups["General"]["count"] = str(len(rule_ids))
        groups["General"]["rules"] = ",".join(rule_ids)
        if "Order" in groups["General"]:
            groups["General"]["Order"] = ",".join(rule_ids)
    print("removed:" + ",".join(removed))

# 输出：General 放最前，其余保持顺序
out = []
for g in ["General"] + [x for x in order if x != "General"]:
    if g not in groups:
        continue
    out.append(f"[{g}]")
    for k, v in groups[g].items():
        out.append(f"{k}={v}")
    out.append("")
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w", encoding="utf-8").write("\n".join(out).rstrip() + "\n")
PY
}

case "${1:-status}" in
    install)
        rule_edit install >/dev/null
        kwin_reconfigure
        echo "已启用：配置弹窗不进任务栏 / Dock（KWin 规则）"
        ;;
    remove)
        rule_edit remove >/dev/null
        kwin_reconfigure
        echo "已移除：desktop-toolkit 的 KWin 规则"
        ;;
    status)
        if [ -f "$KWINRULES" ] && grep -q "$TAG_PREFIX" "$KWINRULES"; then
            echo "状态: 已启用（配置弹窗不进 Dock）"
            grep -nE "^\[|Description=" "$KWINRULES" | grep -B1 "desktop-toolkit" || true
        else
            echo "状态: 未启用"
        fi
        ;;
    *)
        echo "用法: $0 {install|remove|status}" >&2
        exit 1 ;;
esac
