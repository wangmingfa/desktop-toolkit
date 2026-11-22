#!/usr/bin/env bash
# =============================================================================
# windows-games.sh —— Windows 游戏运行环境（Wine / Lutris / Steam 平台）
#
# 安装"能玩 Windows 游戏"的运行环境：Wine(直接跑 exe) + Lutris(游戏管理器)
# 为必须；Steam(Proton 兼容层)/gamescope/MangoHud/Vulkan 可选（勾选）。
# 不装游戏本体（游戏需 Steam 账户/购买）；装完说明各组件怎么用。
# 注册 main.sh 应用子菜单。
#
# 用法: bash windows-games.sh [install|usage|status]
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

wg_log() { echo -e "  ${DT_CYAN}[win-env]${DT_NC} $*"; }
wg_err() { echo -e "  ${DT_RED}[win-env] 错误:${DT_NC} $*" >&2; }
wg_has() { command -v "$1" >/dev/null 2>&1; }

# 环境组件目录：id|required(1必/0选)|pkg|作用
wg_catalog() {
    cat <<'EOF'
wine|1|wine|Wine 兼容层——直接运行 Windows exe（基础）
lutris|1|lutris|Lutris 游戏管理器——Wine/Proton 前端，脚本化装游戏
steam|0|steam|Steam 客户端——内置 Proton 兼容层，玩 Steam 游戏
gamescope|0|gamescope|gamescope 游戏合成器——缩放/锁帧/窗口游戏优化
mangohud|0|mangohud|MangoHud——帧率/温度性能叠加层
vulkan-loader|0|vulkan-loader|Vulkan 加载器——3D 游戏渲染基础（虚拟显卡收益有限）
EOF
}

wg_in_sel() {
    local x
    for x in "${@:2}"; do [ "$x" = "$1" ] && return 0; done
    return 1
}

wg_install() { # 勾选安装运行环境（Wine/Lutris 必须，其余可选）
    local -a sel=()
    local id req
    while IFS='|' read -r i r _ _; do
        [ "$r" = 0 ] && sel+=("$i")
    done < <(wg_catalog)

    while true; do
        local -a rows=()
        local i r pkg desc
        while IFS='|' read -r i r pkg desc; do
            if [ "$r" = 1 ]; then
                rows+=("req-$i|[*] $pkg|$desc（必须）")
            elif wg_in_sel "$i" "${sel[@]}"; then
                rows+=("$i|[x] $pkg|$desc")
            else
                rows+=("$i|[ ] $pkg|$desc")
            fi
        done < <(wg_catalog)
        rows+=("__install|▶ 安装所选|需 sudo，下载较大" "back|← 返回|")
        local c
        c=$(dt_menu "Windows 游戏运行环境" "*必须(Wine/Lutris)；[x]可选勾选，点击切换。" "${rows[@]}") || return 0
        case "$c" in
            back) return 0 ;;
            __install) break ;;
            req-*) : ;;
            *)
                if wg_in_sel "$c" "${sel[@]}"; then
                    local -a news=(); local x
                    for x in "${sel[@]}"; do [ "$x" != "$c" ] && news+=("$x"); done
                    sel=("${news[@]}")
                else
                    sel+=("$c")
                fi
                ;;
        esac
    done

    local -a pkgs=()
    while IFS='|' read -r i r pkg _; do
        [ "$r" = 1 ] && pkgs+=("$pkg")
    done < <(wg_catalog)
    for id in "${sel[@]}"; do
        local pkg
        pkg=$(wg_catalog | awk -F'|' -v i="$id" '$1==i {print $3}')
        [ -n "$pkg" ] && pkgs+=("$pkg")
    done
    echo -e "  ${DT_YELLOW}⚠ 本机是虚拟机（VMware 虚拟显卡）：3D 游戏跑不动，2D/轻量游戏可行。${DT_NC}"
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        wg_err "安装需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    dt_confirm "安装 ${#pkgs[@]} 个运行环境包（Wine/Lutris/Steam 等）？\n需 sudo 密码，下载可能较大（Steam 数百 MB）。\n\n继续？" || return 0
    wg_log "dnf install -y ${#pkgs[@]} 个包 ..."
    if sudo dnf install -y "${pkgs[@]}"; then
        wg_log "✅ 运行环境安装完成。使用方式见 ② 环境说明。"
    else
        wg_err "安装失败（可能中断）。手动: sudo dnf install -y ${pkgs[*]}"
    fi
}

wg_usage() { # 各组件作用 + 怎么用
    echo -e "  ${DT_BOLD}═══ Windows 游戏运行环境 说明 ═══${DT_NC}"
    echo -e "  ${DT_CYAN}安装的组件：${DT_NC}"
    local i r pkg desc
    while IFS='|' read -r i r pkg desc; do
        local tag; [ "$r" = 1 ] && tag="必须" || tag="可选"
        printf '  %-6s %-14s %s\n' "$tag" "$pkg" "$desc"
    done < <(wg_catalog)
    echo
    echo -e "  ${DT_CYAN}怎么用：${DT_NC}"
    echo "    · Steam：登录账户 → 商店/库买游戏 → 安装时 Proton 自动启用（Steam 设置→兼容性）"
    echo "    · Lutris：添加游戏 → 选安装脚本（Wine/Proton）→ 自动配置 prefix 运行"
    echo "    · Wine：  直接 wine <游戏.exe>（首次初始化 prefix 稍慢）；可用 winecfg 调版本"
    echo "    · gamescope：`gamescope -- <命令>` 包住游戏（缩放/锁帧）"
    echo "    · MangoHud：`MANGOHUD=1 <游戏命令>` 显示帧率/温度"
    echo
    echo -e "  ${DT_YELLOW}本机为虚拟显卡：建议玩 2D/轻量游戏（星露谷/泰拉瑞亚/空洞骑士等）；3A 跑不动。${DT_NC}"
}

wg_status() {
    echo "=== Windows 游戏运行环境状态 ==="
    for t in wine lutris steam gamescope mangohud; do
        if wg_has "$t"; then
            local v
            v=$("$t" --version 2>/dev/null | head -1 || true)
            echo "  ✅ $t  ${v:+($v)}"
        else
            echo "  ❌ $t（未装）"
        fi
    done
}

wg_menu() {
    while true; do
        local c
        c=$(dt_menu "Windows 游戏运行环境" "装好能玩 Windows 游戏的环境（不装游戏本体）：" \
            "install|① 安装运行环境|Wine/Lutris 必须 + Steam/gamescope 等可选（勾选）" \
            "usage|② 环境说明|各组件作用 + 怎么用" \
            "status|③ 状态|wine/lutris/steam 版本" \
            "back|← 返回|") || return 0
        case "$c" in
            install) wg_install ;;
            usage) wg_usage ;;
            status) wg_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    install) wg_install ;;
    usage) wg_usage ;;
    status) wg_status ;;
    *) wg_menu ;;
esac
