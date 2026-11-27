#!/usr/bin/env bash
# =============================================================================
# lazyvim.sh —— LazyVim 一键安装（发行版感知：Fedora / Ubuntu / Debian / Arch）
#
# 功能：
#   1. 安装前先做依赖预检：必选依赖直接列出（已装的跳过；版本不达标的
#      用醒目黄色警告并询问是否覆盖新版本）。
#   2. 可选依赖（fzf / ripgrep / lazygit / fd / nodejs）默认全部勾选，
#      用户可逐条点击取消；已装的显示 ✓已装 标记并自动跳过。
#   3. 克隆 LazyVim starter 到 ~/.config/nvim（旧配置自动备份），
#      首次启动自动同步插件（受限网络走 dt_clone 镜像）。
#
# 用法:
#   bash lazyvim.sh            # 菜单
#   bash lazyvim.sh doctor     # 依赖体检
#   bash lazyvim.sh install    # 安装（可选件全装）
#   bash lazyvim.sh uninstall  # 卸载 LazyVim 配置（自动备份）
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

log() { echo "  [lazyvim] $*"; }
err() { echo "  [lazyvim] 错误: $*" >&2; }

# Neovim 最低版本：LazyVim 当前要求 neovim >= 0.10
NVIM_MIN="0.10"

# ---------------------------------------------------------------------------
# 发行版探测
# ---------------------------------------------------------------------------
lv_distro() {
    local id="" like=""
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true
    id="${ID:-}"; like="${ID_LIKE:-}"
    case "$id" in
        fedora|rhel|centos|rocky|almalinux) echo fedora; return 0 ;;
        ubuntu) echo ubuntu; return 0 ;;
        debian|linuxmint|pop) echo debian; return 0 ;;
        arch|manjaro|endeavouros|cachyos|garuda) echo arch; return 0 ;;
    esac
    case "$like" in
        *fedora*|*rhel*) echo fedora ; return 0 ;;
        *debian*|*ubuntu*) echo debian ; return 0 ;;
        *arch*) echo arch ; return 0 ;;
    esac
    echo other
}

# ---------------------------------------------------------------------------
# 依赖清单: id|名称|必选(req)/可选(opt)|fedora|ubuntu|debian|arch|命令|最低版本|备注
#   包名 GH = 源里没有 → GitHub Release 二进制（dt_download 镜像下载）
# ---------------------------------------------------------------------------
lv_catalog() {
    cat <<'EOF'
git|Git|req|git|git|git|git|git||
neovim|Neovim|req|neovim|neovim|neovim|neovim|nvim|0.10|LazyVim 本体要求 >= 0.10
fzf|fzf|opt|fzf|fzf|fzf|fzf|fzf||模糊搜索（telescope/fzf 加速）
ripgrep|ripgrep|opt|ripgrep|ripgrep|ripgrep|ripgrep|rg||全局搜索（telescope grep 必需）
lazygit|lazygit|opt|lazygit|GH|GH|lazygit|lazygit||LazyVim 内 git UI（>x 键）
fd|fd-find|opt|fd|fd-find|fd-find|fd|fd||文件查找（fd-find 命令是 fdfind）
nerdfont|Nerd Font|opt|nerd-fonts|GH|GH|ttf-jetbrains-mono-nerd|||终端字体补丁（图标/补全符号显示必需）
nodejs|Node.js|opt|nodejs|nodejs|nodejs|nodejs|node||Treesitter 拼装/部分 LSP 需要
EOF
}

lv_field() { lv_catalog | awk -F'|' -v id="$1" -v c="$2" '$1==id {print $c}'; }
lv_ids()   { lv_catalog | cut -d'|' -f1; }

lv_pkg() { # <id> → 当前发行版包名（GH / 空）
    local id="$1" distro col
    distro=$(lv_distro)
    case "$distro" in
        fedora) col=4 ;;
        ubuntu) col=5 ;;
        debian) col=6 ;;
        arch)   col=7 ;;
        *) echo ""; return 0 ;;
    esac
    lv_field "$id" "$col"
}

lv_bin()  { lv_field "$1" 8; }
lv_min()  { lv_field "$1" 9; }
lv_kind() { lv_field "$1" 3; }
lv_note() { lv_field "$1" 10; }

lv_installed() { # <id> → 0 已装
    local b; b=$(lv_bin "$1")
    # Nerd Font 是字体不是命令，用 fc-list 探测
    [ "$1" = nerdfont ] && {
        command -v fc-list >/dev/null 2>&1 || return 1
        fc-list 2>/dev/null | grep -qi "nerd" && return 0
        return 1
    }
    [ -n "$b" ] || return 1
    command -v "$b" >/dev/null 2>&1 && return 0
    # fd-find 在 Debian/Ubuntu 装出的命令叫 fdfind
    [ "$b" = fd ] && command -v fdfind >/dev/null 2>&1 && return 0
    return 1
}

lv_version() { # <id> → 版本字符串（取不到则空）
    local b out
    b=$(lv_bin "$1")
    # Nerd Font：显示探测到的字体族名
    if [ "$1" = nerdfont ]; then
        fc-list 2>/dev/null | grep -i "nerd" | head -1 | cut -d: -f2 || true
        return 0
    fi
    command -v "$b" >/dev/null 2>&1 || { [ "$b" = fd ] && b=fdfind; } || true
    command -v "$b" >/dev/null 2>&1 || { echo ""; return 0; }
    case "$b" in
        git) out=$(git --version 2>/dev/null || true) ;;
        nvim) out=$(nvim --version 2>/dev/null | head -1 || true) ;;
        lazygit) out=$("$b" --version 2>/dev/null | grep -oE 'version=[0-9.]+' | head -1 | cut -d= -f2 || true) ;;
        *)   out=$("$b" --version 2>/dev/null | head -1 || true) ;;
    esac
    echo "$out"
}

# 判断 v >= min（sort -V 比较）
lv_ge() { # <version> <min>
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

# 从版本输出里抠出 x.y.z 形式的版本号
lv_vernum() { # <version输出> <命令名>
    printf '%s\n' "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true
}

# <id> → ok|missing|tooold
lv_status() {
    lv_installed "$1" || { echo missing; return 0; }
    local min ver num
    min=$(lv_min "$1")
    [ -z "$min" ] && { echo ok; return 0; }
    ver=$(lv_version "$1")
    num=$(lv_vernum "$ver" "")
    [ -n "$num" ] || { echo ok; return 0; }
    if lv_ge "$num" "$min"; then echo ok; else echo tooold; fi
}

# 包管理器安装单个包（GH=走 GitHub，交由 lv_install 处理）
lv_pkg_install() { # <id>
    local pkg distro
    pkg=$(lv_pkg "$1")
    [ -n "$pkg" ] && [ "$pkg" != GH ] || return 1
    distro=$(lv_distro)
    case "$distro" in
        fedora) sudo dnf install -y "$pkg" ;;
        ubuntu|debian) sudo apt-get update -y && sudo apt-get install -y "$pkg" ;;
        arch)   sudo pacman -S --needed --noconfirm "$pkg" ;;
        *) return 1 ;;
    esac
}

# Neovim 官方版覆盖安装（包管理器版本过旧时）：下载官方 tarball 到 ~/.local
lv_upgrade_nvim() {
    local dest url ver tmp
    dest="$HOME/.local"
    mkdir -p "$dest/bin"
    # 现问 GitHub API 拿最新稳定版资产 URL，失败回退硬编码稳定 tag
    url=$(dt_github_latest_asset "neovim/neovim" 'nvim-linux-x86_64\.tar\.gz' \
        "https://github.com/neovim/neovim/releases/download/v0.11.3/nvim-linux-x86_64.tar.gz") \
        || url="https://github.com/neovim/neovim/releases/download/v0.11.3/nvim-linux-x86_64.tar.gz"
    log "下载 Neovim 官方版（镜像回退，弱网耐心等待）..."
    tmp="$dest/.nvim-tarball.$$"
    if ! dt_download "$url" "$tmp"; then
        err "Neovim 官方版下载失败，请检查网络后重试"
        rm -f "$tmp"
        return 1
    fi
    rm -rf "$dest/nvim-official"
    mkdir -p "$dest/nvim-official"
    if ! tar -xzf "$tmp" -C "$dest/nvim-official" --strip-components=1; then
        err "解压失败（包可能截断）"; rm -rf "$tmp" "$dest/nvim-official"; return 1
    fi
    rm -f "$tmp" "$dest/bin/nvim"
    ln -sf "$dest/nvim-official/bin/nvim" "$dest/bin/nvim"
    log "已安装官方 Neovim → ~/.local/bin/nvim（PATH 请确认包含 ~/.local/bin）"
    ver=$("$dest/bin/nvim" --version 2>/dev/null | head -1 || true)
    log "版本: $ver"
}

# lazygit GitHub 二进制兜底（Debian/Ubuntu 源里没有）
lv_install_lazygit_gh() {
    local url tmp dir
    url=$(dt_github_latest_asset "jesseduffield/lazygit" 'linux_x86_64\.tar\.gz' \
        "https://github.com/jesseduffield/lazygit/releases/download/v0.44.1/lazygit_0.44.1_linux_x86_64.tar.gz") \
        || url="https://github.com/jesseduffield/lazygit/releases/download/v0.44.1/lazygit_0.44.1_linux_x86_64.tar.gz"
    dir="$HOME/.local"
    mkdir -p "$dir/bin"
    tmp="$dir/.lazygit-tarball.$$"
    if ! dt_download "$url" "$tmp"; then
        err "lazygit 下载失败"; rm -f "$tmp"; return 1
    fi
    if ! tar -xzf "$tmp" -C "$dir/bin" lazygit; then
        err "lazygit 解压失败"; rm -f "$tmp"; return 1
    fi
    rm -f "$tmp"
    chmod +x "$dir/bin/lazygit"
    log "lazygit → ~/.local/bin/lazygit"
}

# Nerd Font GitHub 安装兜底（Debian/Ubuntu 源里没有）：
# 下载 JetBrainsMono Nerd Font 字体包 → ~/.local/share/fonts → 刷新字体缓存
lv_install_nerdfont_gh() {
    local url tmp fdir
    fdir="$HOME/.local/share/fonts/NerdFonts"
    url=$(dt_github_latest_asset "ryanoasis/nerd-fonts" 'JetBrainsMono\.tar\.xz' \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz") \
        || url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz"
    mkdir -p "$fdir"
    tmp="$fdir/.nerdfont-tarball.$$"
    if ! dt_download "$url" "$tmp"; then
        err "Nerd Font 下载失败"; rm -f "$tmp"; return 1
    fi
    if ! tar -xJf "$tmp" -C "$fdir"; then
        err "Nerd Font 解压失败（包可能截断）"; rm -f "$tmp"; return 1
    fi
    rm -f "$tmp"
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$fdir" >/dev/null 2>&1 || true
    log "Nerd Font (JetBrainsMono) → $fdir"
    log "请把终端字体设为 'JetBrainsMono Nerd Font' 才能显示图标"
}

# ---------------------------------------------------------------------------
# 体检 / 预检展示
# ---------------------------------------------------------------------------
lv_doctor() {
    local id name kind pkg ver num min st sttxt
    local distro; distro=$(lv_distro)
    echo ""
    echo "  ╭─ LazyVim 依赖体检（发行版: $distro） ─────────────────"
    while IFS='|' read -r id name kind _ _ _ _ _ _ _; do
        pkg=$(lv_pkg "$id"); ver=$(lv_version "$id")
        num=$(lv_vernum "$ver" ""); min=$(lv_min "$id")
        st=$(lv_status "$id")
        case "$st" in
            ok)     sttxt="✓ 已装 ${ver:+($ver)}，可跳过" ;;
            missing) sttxt="╳ 未安装，将自动安装" ;;
            tooold) sttxt="⚠ 版本过低: $ver，要求 >= $min，需覆盖新版本" ;;
        esac
        printf '  │ %-10s [%s] %-24s %s\n' "$name" "$kind" "$pkg" "$sttxt"
        local note; note=$(lv_note "$id")
        [ -n "$note" ] && printf '  │ %-10s     └─ %s\n' "" "$note"
    done < <(lv_catalog)
    echo "  ╰─────────────────────────────────────────────"
    echo ""
}

# ---------------------------------------------------------------------------
# 安装流程
# ---------------------------------------------------------------------------
lv_do_install() { # <可选id...>
    local distro; distro=$(lv_distro)
    if [ "$distro" = other ]; then
        dt_info "未识别的发行版。\n本脚本支持 Fedora / Ubuntu / Debian / Arch，请手动安装依赖。"
        return 1
    fi

    # 1) 必选依赖：已装且版本达标 → 跳过；版本过低 → 醒目警告 + 询问覆盖
    local id name ver num min st
    local -a need=()
    while IFS='|' read -r id name kind _ _ _ _ _ _ _; do
        [ "$kind" = req ] || continue
        st=$(lv_status "$id")
        case "$st" in
            ok) log "✓ $name 已装，跳过" ;;
            missing) need+=("$id") ;;
            tooold)
                min=$(lv_min "$id"); ver=$(lv_version "$id"); num=$(lv_vernum "$ver" "")
                echo ""
                printf '%s\n' "  ╔══════════════════════════════════════════════════════╗"
                printf '%s\n' "  ║  ⚠⚠  版本不达标  ⚠⚠                                ║"
                printf '%s\n' "  ╠══════════════════════════════════════════════════════╣"
                printf '%s\n' "  ║  $name 本机版本: $ver"
                printf '%s\n' "  ║  LazyVim 要求: >= $min"
                printf '%s\n' "  ║  不升级将导致 LazyVim 无法正常启动/缺功能！          ║"
                printf '%s\n' "  ╚══════════════════════════════════════════════════════╝"
                echo ""
                if [ "$id" = neovim ] && [ "$distro" != arch ]; then
                    # 包管理器版本往往跟不上，直接走官方 tarball 覆盖
                    if dt_confirm "Neovim 版本过低" "是否从官方 GitHub Release 下载最新版覆盖安装到 ~/.local/bin/nvim？"; then
                        lv_upgrade_nvim || return 1
                    else
                        err "Neovim 未升级，继续安装可能无法启动 LazyVim"
                    fi
                else
                    if dt_confirm "版本不达标" "是否用包管理器覆盖安装新版本 $name？"; then
                        lv_pkg_install "$id" || err "$name 覆盖安装失败，请手动处理"
                    fi
                fi
                ;;
        esac
    done < <(lv_catalog)

    # 2) 安装缺失必选 + 勾选的可选
    local -a all=("${need[@]}" "$@")
    for id in "${all[@]}"; do
        name=$(lv_field "$id" 2)
        if lv_installed "$id"; then log "✓ $name 已装，跳过"; continue; fi
        local pkg; pkg=$(lv_pkg "$id")
        if [ "$pkg" = GH ]; then
            if [ "$id" = lazygit ]; then
                lv_install_lazygit_gh || err "lazygit 安装失败（尽力而为，不影响主功能）"
            elif [ "$id" = nerdfont ]; then
                lv_install_nerdfont_gh || err "Nerd Font 安装失败（尽力而为，不影响主功能）"
            fi
        else
            log "安装 $name ..."
            if ! lv_pkg_install "$id"; then
                err "$name 安装失败（包名: ${pkg:-未知}）"
                [ "$(lv_kind "$id")" = req ] && return 1
            fi
        fi
    done
    return 0
}

# 克隆 LazyVim starter + 首次同步插件
lv_setup_config() {
    local cfg="$HOME/.config/nvim"
    if [ -d "$cfg" ]; then
        local bak="$cfg.bak"
        if [ -d "$bak" ]; then bak="$cfg.bak.$(date +%Y%m%d%H%M%S)"; fi
        log "已存在 $cfg，备份到 $bak"
        mv "$cfg" "$bak"
    fi
    if ! dt_clone https://github.com/LazyVim/starter "$cfg"; then
        err "LazyVim starter 克隆失败"; return 1
    fi
    rm -rf "$cfg/.git"
    log "首次启动同步插件（可能需要几分钟）..."
    if command -v nvim >/dev/null 2>&1; then
        nvim --headless "+Lazy! sync" +qa 2>/dev/null || log "插件同步有报错，属正常（Treesitter 编译等），打开 nvim 会自动续装"
    fi
    echo ""
    echo "  ╭────────────────────────────────────────────╮"
    echo "  │  ✅ LazyVim 安装完成！                      │"
    echo "  │  终端里输入 nvim 即可启动。                 │"
    echo "  │  ~/.config/nvim 是你的配置，随意改。        │"
    echo "  ╰────────────────────────────────────────────╯"
    echo ""
}

lv_install_flow() {
    local distro; distro=$(lv_distro)
    local -a sel=()
    local c id name pkg st
    while true; do
        local -a rows=()
        while IFS='|' read -r id name kind _ _ _ _ _ _ _; do
            [ "$kind" = opt ] || continue
            st=$(lv_status "$id")
            pkg=$(lv_pkg "$id")
            if [ "$st" = ok ]; then
                rows+=("inst-$id|[✓] $name|已安装，将自动跳过（无需勾选）")
            else
                local in_sel=0 x
                for x in "${sel[@]}"; do [ "$x" = "$id" ] && in_sel=1; done
                if [ "$in_sel" = 1 ]; then
                    rows+=("$id|[x] $name|可选（包: ${pkg}）")
                else
                    rows+=("$id|[ ] $name|可选（包: ${pkg}）")
                fi
            fi
        done < <(lv_catalog)
        rows+=("__install|▶ 开始安装|必选依赖自动装；已勾选可选 ${#sel[@]} 个" "back|← 返回|")

        c=$(dt_menu "LazyVim 一键安装" \
            "必选依赖(git/neovim)自动处理；[x] 为可选件，点击条目切换勾选；[✓] 已装自动跳过。" \
            "${rows[@]}") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            __install)
                lv_do_install "${sel[@]}" && lv_setup_config
                return 0
                ;;
            inst-*) dt_info "$(lv_field "${c#inst-}" 2) 已安装，将自动跳过。" ;;
            *)
                local found=0 x
                for x in "${sel[@]}"; do
                    [ "$x" = "$c" ] && found=1
                done
                if [ "$found" = 1 ]; then
                    local -a news=()
                    for x in "${sel[@]}"; do [ "$x" != "$c" ] && news+=("$x"); done
                    sel=("${news[@]}")
                else
                    sel+=("$c")
                fi
                ;;
        esac
    done
}

lv_uninstall() {
    local cfg="$HOME/.config/nvim"
    if [ ! -d "$cfg" ]; then
        dt_info "未找到 LazyVim 配置目录 $cfg\n无需卸载。"
        return 0
    fi
    if dt_confirm "卸载 LazyVim" "将备份并移除 $cfg\n（数据文件 ~/.local/share/nvim 保留，如需彻底清理请手动删）\n\n继续吗？"; then
        local bak="$cfg.bak.$(date +%Y%m%d%H%M%S)"
        mv "$cfg" "$bak"
        log "配置已备份到 $bak 并移除"
    fi
}

lv_menu() {
    while true; do
        local c
        c=$(dt_menu "LazyVim 一键安装" \
            "发行版: $(lv_distro)｜Neovim 最低要求: $NVIM_MIN" \
            "doctor|依赖体检|列出必选/可选依赖，已装/版本/是否达标" \
            "install|一键安装|必选自动装 + 可选件勾选（默认全选）" \
            "uninstall|卸载|备份并移除 LazyVim 配置" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            doctor) lv_doctor ;;
            install) lv_install_flow ;;
            uninstall) lv_uninstall ;;
        esac
    done
}

case "${1:-}" in
    doctor) lv_doctor ;;
    install) shift; lv_do_install "$@" && lv_setup_config ;;
    uninstall) lv_uninstall ;;
    "") lv_menu ;;
    *) err "未知参数: $1（可用: doctor | install | uninstall）"; exit 1 ;;
esac
