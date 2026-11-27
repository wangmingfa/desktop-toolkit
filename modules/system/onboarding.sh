#!/usr/bin/env bash
# =============================================================================
# onboarding.sh —— 新系统初始化清单（装机后要做的事）
#
# 刚装好的 Linux 需要做哪些事：更新/代理/git/工具/应用/桌面/输入法/字体/
# 监控/电源/备份/维护。每项对应项目里已有模块（不重复实现），检测完成状态
# 标 ✓，未完成可逐项执行或全部执行。放进 modules/system/ 自动扫描。
#
# 用法: bash onboarding.sh [list|run <id>|all]
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

ob_log() { echo -e "  ${DT_CYAN}[onboarding]${DT_NC} $*"; }
ob_err() { echo -e "  ${DT_RED}[onboarding] 错误:${DT_NC} $*" >&2; }

# 清单：id|名称|说明
ob_catalog() {
    cat <<'EOF'
update|系统更新|dnf 升级到最新（新系统先更新）
proxy|网络代理/镜像|受限网络走镜像/代理
git|git 配置|user.name/email/默认分支
tools|基础开发工具|git/python/node/gcc/cmake 等
apps|常用应用|浏览器/办公/媒体
de|桌面环境/WM|GNOME/KDE/niri 选一个
fcitx|中文输入法|fcitx5 + 主题
font|字体|中文/编程 Nerd Font
monitor|系统监控工具|btop/inxi/duf 等
power|电源/性能|power-profiles/tuned 方案
backup|定时备份|配置自动备份
cleanup|系统维护|清缓存/旧内核/journal
EOF
}

# 完成检测：ob_done <id> → 0 已完成
ob_done() {
    case "$1" in
        update)
            dnf check-update 2>/dev/null | grep -qE '^[a-z0-9._-]+[[:space:]]+[0-9]' && return 1 || return 0 ;;
        proxy)
            [ -f "$HOME/.config/environment.d/dt-proxy.conf" ] || git config --global --get http.proxy >/dev/null 2>&1 ;;
        git)
            [ -n "$(git config --get user.name 2>/dev/null)" ] ;;
        tools)
            command -v cmake >/dev/null 2>&1 && command -v gcc >/dev/null 2>&1 ;;
        apps)
            rpm -q chromium >/dev/null 2>&1 || rpm -q vlc >/dev/null 2>&1 || rpm -q libreoffice >/dev/null 2>&1 ;;
        de)
            rpm -q gnome-shell >/dev/null 2>&1 || rpm -q plasma-workspace >/dev/null 2>&1 || command -v niri >/dev/null 2>&1 ;;
        fcitx)
            pgrep -x fcitx5 >/dev/null 2>&1 ;;
        font)
            ls -d "$HOME"/.local/share/fonts/nerd-* >/dev/null 2>&1 ;;
        monitor)
            command -v btop >/dev/null 2>&1 || command -v inxi >/dev/null 2>&1 ;;
        power)
            tuned-adm active 2>/dev/null | grep -qi active ;;
        backup)
            systemctl --user is-enabled backup-config.timer >/dev/null 2>&1 ;;
        cleanup)
            local size; size=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]' | head -1 || echo "0")
            case "$size" in *M*) [ "${size%M%.*}" -lt 500 ] 2>/dev/null && return 0 || return 1 ;; *) return 0 ;; esac ;;
        *) return 1 ;;
    esac
}

# 执行：ob_run <id> —— 调对应模块（CLI 或打开菜单）
ob_run() {
    case "$1" in
        update)  bash "$DT_ROOT/modules/system/update.sh" upgrade ;;
        proxy)   bash "$DT_ROOT/modules/network/proxy-setup.sh" on ;;
        git)     bash "$DT_ROOT/modules/dev/setup-dev.sh" git ;;
        tools)   bash "$DT_ROOT/modules/dev/setup-dev.sh" tools ;;
        apps)    bash "$DT_ROOT/modules/apps/app-installer.sh" ;;
        de)      bash "$DT_ROOT/modules/wm/de-installer.sh" ;;
        fcitx)   bash "$DT_ROOT/modules/appearance/fcitx5-style.sh" ;;
        font)    bash "$DT_ROOT/modules/appearance/font-manager.sh" nerd ;;
        monitor) bash "$DT_ROOT/modules/system/monitor.sh" install btop; bash "$DT_ROOT/modules/system/sysinfo.sh" install ;;
        power)   bash "$DT_ROOT/modules/system/power-profiles.sh" install; bash "$DT_ROOT/modules/system/tuned-mgr.sh" install ;;
        backup)  bash "$DT_ROOT/modules/backup/backup-config.sh" ;;
        cleanup) bash "$DT_ROOT/modules/system/cleanup.sh" ;;
        *) ob_err "未知项: $1"; return 1 ;;
    esac
}

ob_list() { # 打印清单 + 状态
    local id name desc st
    echo -e "  ${DT_BOLD}═══ 新系统初始化清单 ═══${DT_NC}"
    while IFS='|' read -r id name desc; do
        if ob_done "$id"; then st="${DT_GREEN}✓${DT_NC} 完成"; else st="${DT_YELLOW}○${DT_NC} 待办"; fi
        printf '  %s  %-16s %s\n' "$st" "$name" "$desc"
    done < <(ob_catalog)
}

ob_menu() {
    while true; do
        local -a rows=()
        local id name desc st
        while IFS='|' read -r id name desc; do
            if ob_done "$id"; then st="✓ 完成"; else st="○ 待办"; fi
            rows+=("$id|$name|$st · $desc")
        done < <(ob_catalog)
        rows+=("all|▶ 全部执行|按清单顺序执行未完成的" "back|← 返回|")
        local c
        c=$(dt_menu "新系统初始化" "装机后要做的事（✓完成/○待办，选中执行）：" "${rows[@]}") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            all)
                ob_list
                dt_confirm "按清单顺序执行所有未完成项？\n（需 sudo 密码，部分项会打开对应模块）" || continue
                while IFS='|' read -r id name _; do
                    if ! ob_done "$id"; then
                        echo
                        echo -e "  ${DT_BOLD}── 执行: $name ──${DT_NC}"
                        ob_run "$id"
                    fi
                done < <(ob_catalog)
                dt_info "全部执行结束。请确认各项状态（重开本清单看 ✓）。"
                ;;
            *) ob_run "$c" ;;
        esac
    done
}

case "${1:-}" in
    list) ob_list ;;
    run) [ -n "${2:-}" ] && ob_run "$2" || ob_err "用法: onboarding.sh run <id>" ;;
    all)
        while IFS='|' read -r id name _; do
            if ! ob_done "$id"; then
                echo -e "  ${DT_BOLD}── 执行: $name ──${DT_NC}"
                ob_run "$id"
            fi
        done < <(ob_catalog)
        ob_list ;;
    *) ob_menu ;;
esac
