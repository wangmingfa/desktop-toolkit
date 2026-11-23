#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit / 仓库自检（提交前 / CI 用）
#
# 背景: 本仓库反复踩过的 bug 都落在同一小撮静态可查的模式上——
#   硬编码显示管理器(restart gdm 在 CachyOS 报 Unit not found)、
#   sed 嵌套引号(未闭合引号语法错误, 报错行号还指向无关位置)、
#   状态切换类脚本用时间戳备份(第二次切换污染重建基准)、
#   set -u 下颜色/标记变量未加 :-(各自炸过一次)。
# 本脚本把这些模式固化成规则, 提交前跑一遍即可拦住回归。
#
# 用法:  bash scripts/self-check.sh
#   只读检查, 不需要 sudo, 不改任何文件。
#   任一 FAIL 退出非零(适合挂在提交前/CI); 只有 WARN 也视为通过。
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 颜色: 非 tty 退化为空串, 避免 ANSI 混进日志(与 AGENTS.md 第 8 节一致)
if [ -t 1 ]; then
    B=$'\033[1m'; G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; C=$'\033[0;36m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; R=""; C=""; N=""
fi

n=0; fail=0; warn=0
ok()  { n=$((n+1)); echo -e "${G}✔${N} $*"; }
wrn() { n=$((n+1)); warn=$((warn+1)); echo -e "${Y}⚠${N} $*"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo -e "${R}✘${N} $*"; }
sec() { echo; echo -e "${B}── $* ──${N}"; }

# 收集所有脚本(模块 + 库 + 入口; find 在管道里可能非零, 必须容错)
mapfile -t SH_FILES < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*' 2>/dev/null | sort) || true
[ "${#SH_FILES[@]}" -eq 0 ] && { echo "未找到任何 .sh（ROOT=$ROOT）"; exit 1; }

# ---------------------------------------------------------------------------
# 1) 核心文件存在
# ---------------------------------------------------------------------------
sec "核心文件存在"
for f in main.sh lib/common.sh lib/ui.sh lib/niri.sh; do
    if [ -f "$ROOT/$f" ]; then
        ok "$f"
    else
        bad "$f 缺失（其他检查可能因此全部误报）"
    fi
done

# ---------------------------------------------------------------------------
# 2) 语法检查 bash -n
# ---------------------------------------------------------------------------
sec "语法检查 (bash -n)"
syn=0
for f in "${SH_FILES[@]}"; do
    if ! bash -n "$f" 2>/tmp/dt-selfcheck-syn.$$; then
        bad "$(basename "$f"): $(sed -n '1p' /tmp/dt-selfcheck-syn.$$)"
        syn=1
    fi
done
rm -f /tmp/dt-selfcheck-syn.$$
[ "$syn" -eq 0 ] && ok "全部 ${#SH_FILES[@]} 个脚本 bash -n 通过"

# ---------------------------------------------------------------------------
# 3) 可执行权限（仅提示，不算失败）
#
# 仓库内所有调用一律 `bash xxx.sh`（不只是 `./xxx.sh`），生成的应用启动器也写成
# `Exec=/bin/bash <脚本>`，所以**可执行位不再是硬性依赖**；而 git 的 mode 位在
# 某些同步/CI 环境下会丢（100755 变 100644），拿它当 CI 失败条件会误报。
# 这里保留提示 + 修复命令，想用 `./main.sh` 的人仍能看到怎么补。
# ---------------------------------------------------------------------------
sec "可执行权限（建议，非必需）"
notexec=0
shown=0
while IFS= read -r f; do
    [ -x "$f" ] && continue
    notexec=$((notexec+1))
    if [ "$shown" -lt 5 ]; then                 # 只在日志里列前 5 个，避免刷屏
        wrn "${f#$ROOT/} 不可执行（建议 chmod +x；调用处都用 bash，不影响运行）"
        shown=$((shown+1))
    fi
done < <( { find "$ROOT/modules" -name '*.sh' 2>/dev/null; echo "$ROOT/main.sh"; } | sort -u ) || true
if [ "$notexec" -eq 0 ]; then
    ok "modules/ 与 main.sh 全部可执行（./xxx.sh 可直接跑）"
else
    [ "$notexec" -gt "$shown" ] && wrn "另有 $((notexec-shown)) 个脚本同样缺可执行位（同上，不影响运行）"
    echo "    一次性修正: chmod +x main.sh && find modules -name '*.sh' -exec chmod +x {} +"
    echo "    若 git 里 mode 仍是 100644（同步工具丢位）: git update-index --chmod=+x <文件>"
fi

# ---------------------------------------------------------------------------
# 4) 硬编码显示管理器(应统一走 niri_dm_unit / niri_restart_dm)
#    awk: 跳过纯注释行; 命令里出现 systemctl restart gdm|sddm|... 即报。
#    lib/niri.sh 的提示文案用的是 ${dm} 变量, 不会命中。
# ---------------------------------------------------------------------------
sec "硬编码显示管理器 (应统一走 niri_dm_unit)"
dmhit=0
for f in "${SH_FILES[@]}"; do
    while IFS= read -r hit; do
        bad "$hit"
        dmhit=1
    done < <(awk '
        /^[[:space:]]*#/ { next }
        {
            # 去掉双引号字符串字面量(错误/提示文案里的示例不算真命令)
            s = $0
            gsub(/"[^"]*"/, "", s)
            if (s ~ /systemctl[[:space:]]+(restart|reload|stop|enable|disable)[[:space:]]+(gdm|gdm3|sddm|lightdm|plasmalogin)(\.service)?/) {
                print FILENAME ":" FNR ": " $0
            }
        }
    ' "$f")
done
[ "$dmhit" -eq 0 ] && ok "无硬编码 DM 重启(全部经 niri_dm_unit 探测)"

# ---------------------------------------------------------------------------
# 5) sed 嵌套引号(应改用 awk 按行改写, 见 AGENTS.md 9.2 铁律 2)
#    命中特征: 同一 sed 命令里出现 ' 与 " 直接拼接(如 '"$MARK')
#    用 awk 的 \047 表示单引号, 避免本脚本自己踩引号地狱。
# ---------------------------------------------------------------------------
sec "sed 引号拼接 (建议 awk 改写)"
sedhit=0
for f in "${SH_FILES[@]}"; do
    while IFS= read -r ln; do
        bad "$ln"
        sedhit=1
    done < <(awk '/^[[:space:]]*#/ { next } index($0, "\047\"$") > 0 && $0 ~ /sed/ { print FILENAME ":" FNR ": " $0 }' "$f")
done
[ "$sedhit" -eq 0 ] && ok "无 sed 引号拼接"

# ---------------------------------------------------------------------------
# 6) 状态切换类脚本不得用时间戳备份(应存固定路径原始配置再整体重建)
# ---------------------------------------------------------------------------
sec "状态切换脚本的时间戳备份 (应存固定路径)"
# 状态切换类(enable/disable 往返)用时间戳备份会污染重建基准(AGENTS.md 9.2)。
# 已知的切换器 shell-switch 直接 FAIL; wm/ 下其它脚本若出现 dt_backup 先告警。
SW="$ROOT/modules/wm/niri-shell-switch.sh"
if [ -f "$SW" ] && grep -q 'dt_backup' "$SW" 2>/dev/null; then
    bad "niri-shell-switch.sh 用了 dt_backup(时间戳备份); 切换态应存固定路径并整体重建"
else
    ok "niri-shell-switch.sh 未用时间戳备份"
fi
dt_other=0
while IFS= read -r hit; do
    wrn "$hit(状态往返类脚本用 dt_backup 有污染风险, 见 AGENTS.md 9.2)"
    dt_other=1
done < <(grep -rn 'dt_backup' "$ROOT/modules/wm/" 2>/dev/null | grep -v 'niri-shell-switch.sh' || true)
[ "$dt_other" -eq 0 ] || true

# ---------------------------------------------------------------------------
# 7) 严格模式 set -u + pipefail(AGENTS.md 第 5 节)
#    niri-doctor 有意用 set -uo pipefail(无 -e), 属可接受变体。
# ---------------------------------------------------------------------------
sec "严格模式 (set -u + pipefail)"
# 只查"直接执行"的脚本(main.sh + modules/, 排除被 source 的 lib-*.sh 与 lib/);
# 库文件是被 source 的, 本来就不该带 set -u。
# niri-doctor 有意用 set -uo pipefail(无 -e), 属可接受变体。
strictmiss=0
for f in "${SH_FILES[@]}"; do
    case "$f" in
        */lib/*) continue ;;
        */lib-*.sh) continue ;;
    esac
    u=0; pf=0
    grep -qE 'set[[:space:]]+-[a-z]*u' "$f" 2>/dev/null && u=1
    grep -q 'pipefail' "$f" 2>/dev/null && pf=1
    if [ "$u" -ne 1 ] || [ "$pf" -ne 1 ]; then
        wrn "${f#$ROOT/} 缺 $([ "$u" -ne 1 ] && echo 'set -u' || true)$([ "$u" -ne 1 ] && [ "$pf" -ne 1 ] && echo ' 或 ' || true)$([ "$pf" -ne 1 ] && echo 'pipefail' || true)"
        strictmiss=1
    fi
done
[ "$strictmiss" -eq 0 ] && ok "全部脚本含 set -u 与 pipefail"

# ---------------------------------------------------------------------------
# 8) set -u 下颜色/标记变量未加 :-(仅告警; 这些变量由 niri_color_init 等
#    条件初始化, 未调用/调用失败时未绑定会直接退出)
# ---------------------------------------------------------------------------
sec "未加 :-( 的易未绑定变量 (仅告警)"
# 风险定义: 文件用了 ${VAR}(无 :-) 且【从未给 VAR 赋值】(无 VAR= / local VAR / VAR:=)。
# 若顶部已赋值(如 doctor 的 C_YELLOW=${DT_YELLOW:-}), 后续引用是绑定的, 不报。
warned=0
VARS="DT_GREEN DT_YELLOW DT_CYAN DT_BOLD DT_NC DT_RED DT_BLUE C_YELLOW C_GREEN C_BAD C_WARN C_NC C_BOLD C_CYAN MARK"
for f in "${SH_FILES[@]}"; do
    grep -qE 'set[[:space:]]+-[a-z]*u' "$f" 2>/dev/null || continue
    for v in $VARS; do
        grep -qF "\${${v}}" "$f" 2>/dev/null || continue
        # 文件里是否给该变量赋值过(含 local/declare/readonly 声明)
        assigned=0
        grep -qE "${v}[[:space:]]*=" "$f" 2>/dev/null && assigned=1
        grep -qE "(local|declare|readonly)[[:space:]]+${v}([[:space:]]|=|$)" "$f" 2>/dev/null && assigned=1
        [ "$assigned" -eq 1 ] && continue
        wrn "${f#$ROOT/}: \${$v} 未加 :-( 且文件未赋值, set -u 下可能未绑定而退出"
        warned=1
    done
done
[ "$warned" -eq 0 ] && ok "未发现未加兜底且未赋值的易未绑定变量"

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
echo
echo -e "──────────────────────────────────────────────"
if [ "$fail" -eq 0 ]; then
    echo -e "${G}${B}自检通过：${n} 项检查全部正常（${warn} 项提示）。${N}"
    exit 0
else
    echo -e "${R}${B}自检发现 ${fail} 项问题（共 ${n} 项，${warn} 项提示）。${N}"
    echo -e "  修复后重跑: ${C}bash scripts/self-check.sh${N}"
    exit 1
fi
