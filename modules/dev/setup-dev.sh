#!/usr/bin/env bash
# =============================================================================
# setup-dev.sh —— 开发环境配置（git / 常用开发工具）
#
# 用法: bash setup-dev.sh         菜单
#       bash setup-dev.sh git     配置 git（user.name/email/默认分支）
#       bash setup-dev.sh tools   安装常用开发工具（需 sudo）
#       bash setup-dev.sh status  查看当前 git/工具状态
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

log() { echo -e "  ${DT_CYAN}[dev]${DT_NC} $*"; }
warn() { echo -e "  ${DT_YELLOW}[dev] 注意:${DT_NC} $*" >&2; }
err() { echo -e "  ${DT_RED}[dev] 错误:${DT_NC} $*" >&2; }

# ---------------------------------------------------------------------------
# git 配置
# ---------------------------------------------------------------------------
dev_git() {
    local name email
    name=$(git config --get user.name 2>/dev/null || true)
    email=$(git config --get user.email 2>/dev/null || true)
    echo -e "${DT_BOLD}═══ git 配置 ═══${DT_NC}"
    [ -n "$name" ] && log "当前 user.name: $name" || warn "user.name 未设置"
    [ -n "$email" ] && log "当前 user.email: $email" || warn "user.email 未设置"

    if ! dt_confirm "重新配置 git 身份吗？"; then return 0; fi
    name=$(dt_ask_text "姓名" "git user.name（提交作者）" "$name") || return 0
    email=$(dt_ask_text "邮箱" "git user.email" "$email") || return 0
    [ -n "$name" ] && git config --global user.name "$name" && log "user.name → $name" || true
    [ -n "$email" ] && git config --global user.email "$email" && log "user.email → $email" || true

    # 常用默认值（幂等，已有不覆盖）
    git config --global init.defaultBranch main 2>/dev/null || true
    git config --global pull.rebase false 2>/dev/null || true
    log "默认分支 main、pull.rebase=false 已就绪"
}

# ---------------------------------------------------------------------------
# 开发工具安装（需 sudo）
# ---------------------------------------------------------------------------
dev_tools() {
    local -a pkgs=()
    if command -v dnf >/dev/null 2>&1; then
        pkgs=(git python3 python3-pip nodejs npm gcc gcc-c++ make cmake
              ripgrep fd-find jq unzip zip)
    elif command -v apt-get >/dev/null 2>&1; then
        pkgs=(git python3 python3-pip nodejs npm gcc g++ make cmake
              ripgrep fd-find jq unzip zip)
    elif command -v pacman >/dev/null 2>&1; then
        pkgs=(git python python-pip nodejs npm gcc make cmake
              ripgrep fd jq unzip zip)
    else
        err "未识别包管理器"
        return 1
    fi
    echo -e "${DT_BOLD}═══ 安装开发工具 ═══${DT_NC}"
    log "将安装：${pkgs[*]}"
    if ! dt_confirm "继续？（需要 sudo 密码）"; then return 0; fi
    case "$(command -v dnf >/dev/null 2>&1 && echo dnf || command -v apt-get >/dev/null 2>&1 && echo apt || echo pacman)" in
        dnf)  sudo dnf install -y "${pkgs[@]}" ;;
        apt)  sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}" ;;
        *)    sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    esac || { err "安装失败"; return 1; }
    log "开发工具安装完成"
}

# ---------------------------------------------------------------------------
# 语言运行时（Go / Rust）与容器
# ---------------------------------------------------------------------------
dev_langs() {
    local -a pkgs=()
    if command -v dnf >/dev/null 2>&1; then
        pkgs=(golang rust cargo)
    elif command -v apt-get >/dev/null 2>&1; then
        pkgs=(golang rustc cargo)
    elif command -v pacman >/dev/null 2>&1; then
        pkgs=(go rust)
    else
        err "未识别包管理器"; return 1
    fi
    echo -e "${DT_BOLD}═══ 安装语言运行时 ═══${DT_NC}"
    log "将安装：${pkgs[*]}"
    if ! dt_confirm "继续？（需要 sudo 密码）"; then return 0; fi
    case "$(command -v dnf >/dev/null 2>&1 && echo dnf || command -v apt-get >/dev/null 2>&1 && echo apt || echo pacman)" in
        dnf)  sudo dnf install -y "${pkgs[@]}" ;;
        apt)  sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}" ;;
        *)    sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    esac || { err "安装失败"; return 1; }
    log "语言运行时安装完成（go/rustc/cargo）"
}

dev_docker() {
    echo -e "${DT_BOLD}═══ 容器 ═══${DT_NC}"
    if command -v dnf >/dev/null 2>&1; then
        if command -v podman >/dev/null 2>&1; then
            log "Podman 已装（当前 Fedora 默认容器方案）"
        else
            if dt_confirm "安装 Podman（Fedora 官方源，Docker 需 docker-ce 第三方源不自动装）？"; then
                sudo dnf install -y podman && log "Podman 安装完成"
            fi
        fi
        log "Docker 需 docker-ce 第三方源（Fedora 官方源没有），如需请手动配置："
        log "  https://docs.docker.com/engine/install/fedora/"
    elif command -v apt-get >/dev/null 2>&1; then
        if dt_confirm "安装 Docker（docker.io）？"; then
            sudo apt-get update -qq && sudo apt-get install -y docker.io && log "Docker 安装完成"
        fi
    elif command -v pacman >/dev/null 2>&1; then
        if dt_confirm "安装 Docker？"; then
            sudo pacman -S --needed --noconfirm docker && log "Docker 安装完成"
        fi
    else
        err "未识别包管理器"; return 1
    fi
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
dev_status() {
    echo -e "${DT_BOLD}═══ 开发环境状态 ═══${DT_NC}"
    log "git: $(git --version 2>/dev/null || echo 未安装)"
    log "python3: $(python3 --version 2>/dev/null || echo 未安装)"
    log "node: $(node --version 2>/dev/null || echo 未安装)"
    log "npm: $(npm --version 2>/dev/null || echo 未安装)"
    log "gcc: $(gcc --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 未安装)"
    log "git user.name: $(git config --get user.name 2>/dev/null || echo 未设置)"
    log "git user.email: $(git config --get user.email 2>/dev/null || echo 未设置)"
    log "git 默认分支: $(git config --get init.defaultBranch 2>/dev/null || echo 未设置)"
    log "go: $(go version 2>/dev/null || echo 未安装)"
    log "rustc: $(rustc --version 2>/dev/null || echo 未安装)"
    log "cargo: $(cargo --version 2>/dev/null || echo 未安装)"
    log "podman: $(podman --version 2>/dev/null || echo 未安装)"
}

# ---------------------------------------------------------------------------
# 菜单 / 分发
# ---------------------------------------------------------------------------
dev_menu() {
    while true; do
        local c
        c=$(dt_menu "开发环境" "git 配置与常用开发工具：" \
            "git|配置 git|user.name/email/默认分支" \
            "tools|安装开发工具|git/python/node/gcc/cmake 等（需 sudo）" \
            "langs|语言运行时|Go/Rust（需 sudo）" \
            "docker|容器|Podman（Fedora 官方源）/ Docker（第三方源）" \
            "status|查看状态|当前 git/工具/语言版本" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            git) dev_git ;;
            tools) dev_tools ;;
            langs) dev_langs ;;
            docker) dev_docker ;;
            status) dev_status ;;
        esac
        echo
    done
}

case "${1:-}" in
    "") dev_menu ;;
    git) dev_git ;;
    tools) dev_tools ;;
    status) dev_status ;;
    -h|--help|help)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) err "未知参数：$1（--help 查看用法）"; exit 2 ;;
esac
