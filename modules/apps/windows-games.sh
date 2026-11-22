#!/usr/bin/env bash
# =============================================================================
# windows-games.sh —— Windows 游戏运行环境（Wine / Lutris / Steam 平台）
#
# 发行版感知（Fedora/Ubuntu/Debian/Arch）安装"能玩 Windows 游戏"的环境：
# Wine(直接跑 exe) + Lutris(游戏管理器) 为必须；Steam(Proton)/gamescope/
# MangoHud/Vulkan 可选（勾选-确认模式）。不装游戏本体（需账户/购买）。
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

# 发行版检测：fedora / ubuntu / debian / arch / other
wg_distro() {
    . /etc/os-release 2>/dev/null || true
    case "${ID:-}" in
        fedora) echo fedora ;;
        ubuntu) echo ubuntu ;;
        debian) echo debian ;;
        arch|manjaro|endeavouros) echo arch ;;
        *) echo other ;;
    esac
}

# 环境组件目录：id|required(1必/0选)|作用|fedora|ubuntu|debian|arch|备注
wg_catalog() {
    cat <<'EOF'
wine|1|Wine 兼容层——直接运行 Windows exe（基础）|wine|wine|wine|wine|
lutris|1|Lutris 游戏管理器——Wine/Proton 前端|lutris|lutris|lutris|lutris|
steam|0|Steam 客户端——内置 Proton 兼容层|steam|steam|steam|steam|Ubuntu 需 multiverse, Debian 需 non-free, Arch 需 multilib
gamescope|0|gamescope 游戏合成器——缩放/锁帧|gamescope|gamescope|gamescope|gamescope|
mangohud|0|MangoHud——帧率/温度性能叠加层|mangohud|mangohud|mangohud|mangohud|
vulkan|0|Vulkan 加载器——3D 渲染基础（虚拟显卡收益有限）|vulkan-loader|mesa-vulkan-drivers|mesa-vulkan-drivers|vulkan-icd-loader|
EOF
}

# 取字段：wg_field <id> <col>
wg_field() {
    wg_catalog | awk -F'|' -v i="$1" -v c="$2" '$1==i {print $c; exit}'
}

# 当前发行版包名：wg_pkg <id>（空=该发行版无此包）
wg_pkg() {
    local id="$1" distro col
    distro=$(wg_distro)
    case "$distro" in
        fedora) col=4 ;; ubuntu) col=5 ;; debian) col=6 ;; arch) col=7 ;; *) echo ""; return 0 ;;
    esac
    wg_field "$id" "$col"
}

wg_in_sel() {
    local x
    for x in "${@:2}"; do [ "$x" = "$1" ] && return 0; done
    return 1
}

wg_install_pkgs() { # <pkg...> 按发行版分发
    local distro; distro=$(wg_distro)
    case "$distro" in
        fedora) sudo dnf install -y "$@" ;;
        ubuntu|debian) sudo apt-get update -qq && sudo apt-get install -y "$@" ;;
        arch) sudo pacman -S --needed --noconfirm "$@" ;;
        *) wg_err "不支持的发行版: $distro"; return 1 ;;
    esac
}

wg_install() { # 勾选安装运行环境
    local distro; distro=$(wg_distro)
    if [ "$distro" = other ]; then
        wg_err "当前发行版不受支持。请手动安装 wine/lutris/steam（见包管理器）。"
        return 1
    fi
    local -a sel=()
    local id req
    while IFS='|' read -r i r _ _ _ _ _; do
        [ "$r" = 0 ] && sel+=("$i")
    done < <(wg_catalog)

    while true; do
        local -a rows=()
        local i r desc note pkg
        while IFS='|' read -r i r desc _ _ _ _ note; do
            pkg=$(wg_pkg "$i")
            [ -z "$pkg" ] && continue  # 该发行版无此包（如无第三方源）则不列
            local d="$desc"
            [ -n "$note" ] && d="$d（${note}）"
            if [ "$r" = 1 ]; then
                rows+=("req-$i|[*] $pkg|$d（必须）")
            elif wg_in_sel "$i" "${sel[@]}"; then
                rows+=("$i|[x] $pkg|$d")
            else
                rows+=("$i|[ ] $pkg|$d")
            fi
        done < <(wg_catalog)
        rows+=("__install|▶ 安装所选|需 sudo，下载较大" "back|← 返回|")
        local c
        c=$(dt_menu "Windows 游戏运行环境（$distro）" "*必须(Wine/Lutris)；[x]可选勾选，点击切换。" "${rows[@]}") || return 0
        case "$c" in
            __quit) exit 0 ;;
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
    local pkg
    # 必须包（该发行版有则加）
    while IFS='|' read -r i r _; do
        [ "$r" = 1 ] || continue
        pkg=$(wg_pkg "$i"); [ -n "$pkg" ] && pkgs+=("$pkg")
    done < <(wg_catalog)
    # 勾选的可选包
    for id in "${sel[@]}"; do
        pkg=$(wg_pkg "$id"); [ -n "$pkg" ] && pkgs+=("$pkg")
    done
    [ "${#pkgs[@]}" -eq 0 ] && { wg_err "当前发行版无可用包（检查第三方源）"; return 1; }
    echo -e "  ${DT_YELLOW}⚠ 本机是虚拟机（VMware 虚拟显卡）：3D 游戏跑不动，2D/轻量游戏可行。${DT_NC}"
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        wg_err "安装需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
        return 1
    fi
    dt_confirm "安装 ${#pkgs[@]} 个运行环境包（$distro）？\n需 sudo 密码，下载可能较大。\n\n继续？" || return 0
    wg_log "安装 ${#pkgs[@]} 个包 ..."
    if wg_install_pkgs "${pkgs[@]}"; then
        wg_log "✅ 运行环境安装完成。使用方式见 2. 环境说明。"
    else
        wg_err "安装失败（可能中断）。包名: ${pkgs[*]}"
    fi
}

wg_usage() { # 各组件作用 + 怎么用
    local distro; distro=$(wg_distro)
    echo -e "  ${DT_BOLD}═══ Windows 游戏运行环境 说明（$distro）═══${DT_NC}"
    echo -e "  ${DT_CYAN}安装的组件：${DT_NC}"
    local i r desc pkg note
    while IFS='|' read -r i r desc _ _ _ _ note; do
        pkg=$(wg_pkg "$i")
        local tag; [ "$r" = 1 ] && tag="必须" || tag="可选"
        local d="$desc"; [ -n "$note" ] && d="$d（${note}）"
        printf '  %-6s %-18s %s\n' "$tag" "${pkg:-—}" "$d"
    done < <(wg_catalog)
    echo
    echo -e "  ${DT_CYAN}怎么用：${DT_NC}"
    echo "    · Steam：登录账户 → 买游戏 → 安装时 Proton 自动启用（设置→兼容性）"
    echo "    · Lutris：添加游戏 → 选 Wine/Proton 安装脚本 → 自动配置 prefix"
    echo "    · Wine：  直接 wine <游戏.exe>（首次初始化 prefix 稍慢）"
    echo "    · gamescope：`gamescope -- <命令>`；MangoHud：`MANGOHUD=1 <命令>`"
    echo
    case "$distro" in
        ubuntu|debian)
            echo -e "  ${DT_YELLOW}32 位游戏需 multiarch：sudo dpkg --add-architecture i386 && sudo apt update，再装 wine32。${DT_NC}" ;;
        arch)
            echo -e "  ${DT_YELLOW}老 32 位游戏需启用 multilib 源 + lib32 包（lib32-mangohud 等）。${DT_NC}" ;;
        fedora)
            echo -e "  ${DT_YELLOW}Steam 走 rpmfusion-nonfree-steam 源（已启用则直接装）。${DT_NC}" ;;
    esac
    echo -e "  ${DT_YELLOW}本机为虚拟显卡：建议玩 2D/轻量游戏（星露谷/泰拉瑞亚/空洞骑士等）；3A 跑不动。${DT_NC}"
}

wg_status() {
    echo "=== Windows 游戏运行环境状态（$(wg_distro)） ==="
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
            "install|1. 安装运行环境|Wine/Lutris 必须 + Steam/gamescope 等可选（勾选）" \
            "usage|2. 环境说明|各组件作用 + 怎么用" \
            "status|3. 状态|wine/lutris/steam 版本" \
            "back|← 返回|") || return 0
        case "$c" in
            install) wg_install ;;
            usage) wg_usage ;;
            status) wg_status ;;
            __quit) exit 0 ;;
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
