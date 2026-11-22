#!/usr/bin/env bash
# =============================================================================
# fsearch.sh —— 文件快速搜索（fd + fzf + bat + ripgrep）
#
# 查找文件(模糊选择+预览)、内容搜索、大文件定位。fd/fzf/ripgrep 已装,
# bat(语法高亮预览)可选安装。放进 modules/system/ 由 sub_system 自动扫描。
#
# 用法: bash fsearch.sh [find|content|big|install]
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

fs_log() { echo -e "  ${DT_CYAN}[fsearch]${DT_NC} $*"; }
fs_err() { echo -e "  ${DT_RED}[fsearch] 错误:${DT_NC} $*" >&2; }

fs_has() { command -v "$1" >/dev/null 2>&1; }

fs_need_tty() { # fzf/交互需终端
    if [ ! -t 0 ]; then
        fs_err "交互式搜索需要终端。请在一个终端里运行。"
        return 1
    fi
    return 0
}

fs_find() { # 查找文件: fd 列出 → fzf 选择 → bat 预览/打开
    fs_has fd && fs_has fzf || { fs_err "需要 fd 和 fzf（已装：fd=$(fs_has fd && echo 是 || echo 否) fzf=$(fs_has fzf && echo 是 || echo 否)）"; return 1; }
    fs_need_tty || return 1
    local dir
    dir=$(dt_ask_text "查找目录" "在哪个目录查找（回车=当前目录）" "$HOME") || return 0
    [ -n "$dir" ] || dir="$HOME"
    [ -d "$dir" ] || { fs_err "目录不存在: $dir"; return 1; }
    fs_log "查找 $dir（输入筛选，Enter 选择，Esc 取消）..."
    local sel
    # fd 列出 → fzf 选择（bat 预览文件内容）
    sel=$(fd --type f --hidden --exclude .git . "$dir" 2>/dev/null | \
        fzf --preview 'command -v bat >/dev/null 2>&1 && bat --color=always --line-range=:30 {} 2>/dev/null || cat {} 2>/dev/null' \
            --preview-window=right:50% 2>/dev/null) || return 0
    [ -n "$sel" ] || return 0
    echo -e "  选中: ${DT_GREEN}$sel${DT_NC}"
    # 尝试用 xdg-open 打开（GUI），失败则提示路径
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$sel" >/dev/null 2>&1 &
        fs_log "已请求打开（xdg-open）。"
    else
        fs_log "路径: $sel"
    fi
}

fs_content() { # 内容搜索: ripgrep
    fs_has rg || { fs_err "需要 ripgrep（已装: 否）"; return 1; }
    local pat dir
    pat=$(dt_ask_text "内容搜索" "要搜的正则（rg 语法）" "") || return 0
    [ -n "$pat" ] || return 0
    dir=$(dt_ask_text "搜索目录" "在哪个目录搜（回车=$HOME）" "$HOME") || return 0
    [ -n "$dir" ] || dir="$HOME"
    fs_log "rg '$pat' $dir ..."
    rg --hidden --line-number --color=never "$pat" "$dir" 2>/dev/null | head -40 || \
        { fs_log "无匹配或搜索中断"; }
}

fs_big() { # 大文件定位（>100M 默认）
    local dir minsize
    dir=$(dt_ask_text "大文件定位" "在哪个目录找（回车=$HOME）" "$HOME") || return 0
    [ -n "$dir" ] || dir="$HOME"
    minsize=$(dt_ask_text "最小大小" "大于多少（如 100M/1G，回车=100M）" "100M") || return 0
    [ -n "$minsize" ] || minsize="100M"
    fs_log "找 $dir 下 >$minsize 的文件..."
    find "$dir" -type f -size "+$minsize" -not -path '*/.git/*' 2>/dev/null \
        -printf '%s %p\n' | sort -rn | head -15 | \
        while read -r size p; do
            printf '  %8s  %s\n' "$(numfmt --to=iec "$size" 2>/dev/null || echo "$size")" "$p"
        done
    fs_log "完成（仅显示前 15 个）"
}

fs_install() { # 装 bat（fd/fzf/rg 已装）
    local -a need=()
    for t in fd fzf rg; do fs_has "$t" || need+=("$t"); done
    if [ "${#need[@]}" -gt 0 ]; then
        fs_log "缺 fd/fzf/rg，将一并装 ${need[*]} ..."
    fi
    if ! fs_has bat; then
        if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
            fs_err "安装 bat 需 sudo 密码，但当前不是交互终端。请在一个终端里运行。"
            return 1
        fi
        fs_log "安装 bat ..."
        sudo dnf install -y bat "${need[@]}" || { fs_err "安装失败"; return 1; }
    else
        fs_log "bat 已装"
    fi
    fs_log "完成（fd/fzf/rg/bat 均可用了）"
}

fs_status() {
    echo "=== 文件搜索工具状态 ==="
    for t in fd fzf bat rg; do
        fs_has "$t" && echo "  ✅ $t" || echo "  ❌ $t（未装）"
    done
}

fs_menu() {
    while true; do
        local c
        c=$(dt_menu "文件快速搜索" "fd/fzf 模糊查找 + bat 预览 + rg 内容搜索：" \
            "find|1. 查找文件|fd + fzf 选择，bat 预览，Enter 打开" \
            "content|2. 内容搜索|rg 正则搜文件内容" \
            "big|3. 大文件定位|找 >100M（可调）的文件" \
            "install|4. 安装 bat|fd/fzf/rg 已装，bat 需 sudo" \
            "status|5. 状态|已装/未装" \
            "back|← 返回|") || return 0
        case "$c" in
            find) fs_find ;;
            content) fs_content ;;
            big) fs_big ;;
            install) fs_install ;;
            status) fs_status ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    find) fs_find ;;
    content) fs_content ;;
    big) fs_big ;;
    install) fs_install ;;
    status) fs_status ;;
    *) fs_menu ;;
esac
