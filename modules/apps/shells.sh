#!/usr/bin/env bash
# =============================================================================
# shells.sh —— 各种 Shell 安装器（fish / nushell / zsh / elvish / xonsh / tcsh / ksh / dash）
#
# 发行版感知（Fedora / Ubuntu / Debian / Arch）：
#   - 先按发行版列包名安装；源里没有时按条目备注处理（nushell 在 Debian/Ubuntu
#     源里没有 → 自动下载官方 GitHub 二进制装到 ~/.local/bin/nu）。
#   - 只支持官方源能直接装的；需要第三方源的（PowerShell）诚实标注、不自动装。
# 另提供"设为默认登录 shell"（chsh，会校验 /etc/shells）。
#
# 用法:
#   bash shells.sh                 # 图形/文本菜单
#   bash shells.sh list            # 列出各 shell 在本机的状态
#   bash shells.sh install fish zsh
#   bash shells.sh switch          # 列出本机已有 shell，选中即进入（当前终端）
#   bash shells.sh default fish    # 设为默认登录 shell（chsh，下次登录生效）
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"

log() { echo "  [shells] $*"; }
err() { echo "  [shells] 错误: $*" >&2; }

# ---------------------------------------------------------------------------
# 发行版探测
# ---------------------------------------------------------------------------
sh_distro() {
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
# 清单: id|名称|说明|fedora|ubuntu|debian|arch|可执行名|备注
#   包名为 THIRD = 需第三方源，不自动安装（备注里给手动方法）
# ---------------------------------------------------------------------------
sh_catalog() {
    cat <<'EOF'
fish|fish|友好的交互式 shell（自动补全 / 语法高亮 / 主题多）|fish|fish|fish|fish|fish|
nushell|Nushell|结构化数据管道 shell（输出像表格，命令返回数据）|nushell|nushell|nushell|nushell|nu|Debian/Ubuntu 源里通常没有，会自动改用官方 GitHub 二进制(~/.local/bin/nu)
zsh|Zsh|经典可扩展 shell（oh-my-zsh 生态）|zsh|zsh|zsh|zsh|zsh|
elvish|Elvish|现代表达力 shell（结构化管道、跨平台）|elvish|elvish|elvish|elvish|elvish|
xonsh|Xonsh|Python 语法 shell（脚本就是 Python）|xonsh|xonsh|xonsh|xonsh|xonsh|
tcsh|tcsh|C shell 增强版（语法接近 C，老牌）|tcsh|tcsh|tcsh|tcsh|tcsh|
ksh|KornShell|AT&T Korn shell（POSIX + 扩展）|ksh|ksh|ksh|ksh|ksh|
dash|dash|POSIX 极简 shell（很多发行版的 /bin/sh）|dash|dash|dash|dash|dash|
powershell|PowerShell|微软跨平台 shell/脚本（pwsh）|THIRD|THIRD|THIRD|THIRD|pwsh|需先加微软软件源，本脚本不自动配置（见说明）
EOF
}

sh_field() { # <id> <列号>
    sh_catalog | awk -F'|' -v id="$1" -v c="$2" '$1==id {print $c}'
}

sh_ids() { sh_catalog | cut -d'|' -f1; }

sh_pkg() { # <id> → 当前发行版的包名（可能为空 / THIRD）
    local id="$1" distro col
    distro=$(sh_distro)
    case "$distro" in
        fedora) col=4 ;;
        ubuntu) col=5 ;;
        debian) col=6 ;;
        arch)   col=7 ;;
        *) echo ""; return 0 ;;
    esac
    sh_field "$id" "$col"
}

sh_bin() { sh_field "$1" 8; }

# 是否已安装（命令在 PATH，或 nushell 的 ~/.local/bin 回退位置）
sh_installed() { # <id>
    local bin path
    bin=$(sh_bin "$1")
    [ -n "$bin" ] || return 1
    command -v "$bin" >/dev/null 2>&1 && return 0
    [ -x "$HOME/.local/bin/$bin" ] && return 0
    return 1
}

sh_bin_path() { # <id> → 可执行文件的绝对路径
    local bin path
    bin=$(sh_bin "$1")
    path=$(command -v "$bin" 2>/dev/null || true)
    [ -n "$path" ] || path="$HOME/.local/bin/$bin"
    echo "$path"
}

sh_version() { # <id> → 版本首行（取不到则空）
    local bin p
    bin=$(sh_bin "$1")
    p=$(sh_bin_path "$1")
    [ -x "$p" ] || { echo ""; return 0; }
    case "$bin" in
        nu)  "$p" --version 2>/dev/null | head -1 || true ;;
        ksh) "$p" --version 2>/dev/null | head -1 || true ;;
        *)   "$p" --version 2>/dev/null | head -1 || true ;;
    esac
}

# ---------------------------------------------------------------------------
# 安装
# ---------------------------------------------------------------------------
sh_repo_has() { # <pkg>
    local pkg="$1" distro
    distro=$(sh_distro)
    case "$distro" in
        fedora) dnf -q repoquery --available "$pkg" >/dev/null 2>&1 ;;
        arch)   pacman -Si "$pkg" >/dev/null 2>&1 ;;
        debian|ubuntu) apt-cache show "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

APT_UPDATED=0
sh_apt_update_once() {
    [ "$APT_UPDATED" = 1 ] && return 0
    APT_UPDATED=1
    sudo apt-get update || return 1
}

sh_pkg_install() { # <pkg>...（当前发行版）
    local distro
    distro=$(sh_distro)
    case "$distro" in
        fedora) sudo dnf install -y "$@" ;;
        arch)   sudo pacman -S --needed --noconfirm "$@" ;;
        debian|ubuntu)
            sh_apt_update_once || return 1
            sudo apt-get install -y "$@"
            ;;
        *) err "不支持的发行版（只支持 Fedora/Ubuntu/Debian/Arch）"; return 1 ;;
    esac
}

# nushell 在 Debian/Ubuntu 源里没有: 用官方 GitHub 二进制装到 ~/.local/bin/nu
sh_install_nushell_fallback() {
    local arch url tmp dir
    case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) err "nushell 二进制: 不支持的架构 $(uname -m)"; return 1 ;;
    esac
    echo "  [shells] Debian/Ubuntu 源里没有 nushell，改用官方 GitHub 二进制（~/.local/bin/nu）…"
    url=$(curl -fsSL --max-time 15 "https://api.github.com/repos/nushell/nushell/releases/latest" 2>/dev/null \
        | grep -oE "https://[^\"]*${arch}-unknown-linux-gnu\\.tar\\.gz" | head -1 || true)
    if [ -z "$url" ]; then
        # 解析失败(无 curl / 被限流)时的稳定兜底：不追最新，保证可用
        url="https://github.com/nushell/nushell/releases/download/0.117.0/nu-0.117.0-${arch}-unknown-linux-gnu.tar.gz"
    fi
    tmp=$(mktemp --suffix=.tar.gz)
    dir=$(mktemp -d)
    if ! DT_DL_KILL=900 dt_download "$url" "$tmp"; then
        rm -f "$tmp"; rm -rf "$dir"
        err "nushell 下载失败: $url"
        return 1
    fi
    if ! tar -xzf "$tmp" -C "$dir" 2>/dev/null; then
        rm -f "$tmp"; rm -rf "$dir"
        err "nushell 压缩包解压失败"
        return 1
    fi
    # 官方 tarball 解出来是嵌套目录 nu-<ver>-<target>/nu（不是根目录）；
    # 用 -print -quit 找第一个 nu，避免 `| head` 在 pipefail 下收 SIGPIPE。
    local nu_bin=""
    nu_bin=$(find "$dir" -maxdepth 2 -type f -name nu -print -quit 2>/dev/null || true)
    if [ ! -f "$nu_bin" ]; then
        rm -f "$tmp"; rm -rf "$dir"
        err "nushell 压缩包里没找到 nu 可执行文件"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$nu_bin" "$HOME/.local/bin/nu" 2>/dev/null || true
    rm -f "$tmp"; rm -rf "$dir"
    "$HOME/.local/bin/nu" --version >/dev/null 2>&1 || { err "nushell 安装后无法运行"; return 1; }
    log "已安装到 ~/.local/bin/nu（若 PATH 里没有 ~/.local/bin，请加进 PATH）"
}

sh_install_one() { # <id> → 0 成功 / 1 失败（自己打印原因）
    local id="$1" name desc pkg note bin
    name=$(sh_field "$id" 2)
    desc=$(sh_field "$id" 3)
    note=$(sh_field "$id" 9)
    bin=$(sh_bin "$id")

    if sh_installed "$id"; then
        log "$name 已安装，跳过（$bin: $(sh_bin_path "$id")）"
        return 0
    fi

    pkg=$(sh_pkg "$id")
    case "$pkg" in
        "" )
            err "$name: 当前发行版（$(sh_distro)）不在支持范围"
            return 1 ;;
        THIRD )
            err "$name: 需要第三方软件源，本脚本不自动配置。${note:-}"
            return 1 ;;
    esac

    # Debian/Ubuntu 的 nushell 走官方二进制
    if [ "$id" = nushell ] && ! sh_repo_has "$pkg"; then
        sh_install_nushell_fallback || return 1
    elif ! sh_repo_has "$pkg"; then
        err "$name: 当前源里没有包 $pkg。${note:-可稍后到官方站点安装。}"
        return 1
    else
        log "安装 $name（包: $pkg）…"
        sh_pkg_install "$pkg" || { err "$name 安装失败（包: $pkg）"; return 1; }
    fi

    if sh_installed "$id"; then
        log "$name 安装完成 ✅（$(sh_version "$id")）"
        return 0
    fi
    err "$name 安装后仍找不到命令 $bin"
    return 1
}

# 结果汇总用（不放进子 shell，保证能写数组）
SH_OK=(); SH_FAIL=()
sh_do_install() { # <id>...
    local id
    [ "$#" -gt 0 ] || { dt_info "没有选择任何 shell。"; return 0; }
    SH_OK=(); SH_FAIL=()
    echo "════════════════════════════════════════════"
    echo " 安装 Shell: $* （发行版: $(sh_distro)）"
    echo "════════════════════════════════════════════"
    for id in "$@"; do
        if sh_install_one "$id"; then
            SH_OK+=("$id")
        else
            SH_FAIL+=("$id")
        fi
    done

    local body=""
    if [ "${#SH_OK[@]}" -gt 0 ]; then
        body+="已就绪:\n"
        for id in "${SH_OK[@]}"; do
            body+="  ✅ $(sh_field "$id" 2)  →  $(sh_bin_path "$id")\n"
        done
    fi
    if [ "${#SH_FAIL[@]}" -gt 0 ]; then
        body+="\n未完成:\n"
        for id in "${SH_FAIL[@]}"; do
            body+="  ❌ $(sh_field "$id" 2)\n"
        done
        body+="\n网络/第三方源受限时可稍后重跑本脚本。"
    fi
    body+="\n\n立即切换: 菜单第 2 项（当前终端生效，exit 返回）。\n设为默认登录 shell: 菜单第 3 项（下次登录生效）。"
    dt_info "Shell 安装结果\n\n$body"

    if [ "${#SH_FAIL[@]}" -eq 0 ]; then
        echo
        echo "  ✅ 全部安装成功。"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 切换当前终端的 shell（列出本机已有 → 选中即进入）
#
# 说明：这里只切【当前终端/当前会话】，不碰 /etc/passwd，退出(exit)就回到上级菜单。
#       想永久换掉登录 shell 用下面「设为默认登录 shell」(chsh，下次登录生效)。
# ---------------------------------------------------------------------------
sh_current_shell() {
    getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f7 || true
}

# 单个 shell 的版本号（只取 x.y[.z]，取不到回退首行截断，再取不到留空）
# 各家 --version 文案差别很大（"GNU bash，版本 5.3.15(1)-release (x86_64-…)"
# / "fish, version 4.6.0" / "0.117.0"），直接截断首行会切在括号中间很难看。
sh_shell_version() { # <path>
    local out
    [ -x "$1" ] || { echo ""; return 0; }
    # 先收集再处理，不要 `| head -1`：pipefail 下上游会吃 SIGPIPE 让整条管道非零
    out=$("$1" --version 2>/dev/null || true)
    if [ -z "$out" ]; then out=$("$1" -V 2>/dev/null || true); fi
    out=${out%%$'\n'*}
    if [[ $out =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "${out:0:48}"
    fi
}

# 判断"确实是个能用的 shell"：能用 -c 跑命令。tmux 之类被 /etc/shells 塞进来的
# 伪条目没有 -c，会被这里筛掉（别只看 /etc/shells，它不代表都是 shell）。
sh_is_shell() { # <path>
    [ -x "$1" ] || return 1
    case "$(basename "$1")" in nologin|false) return 1 ;; esac
    "$1" -c true >/dev/null 2>&1
}

# 本机已有的 shell（去重后一行一个 [绝对路径]）
# 来源: /etc/shells(权威登录 shell 列表) + PATH 里的常见 shell + ~/.local/bin(nushell 二进制)
sh_available_shells() {
    local -a cand=()
    local line p n
    if [ -r /etc/shells ]; then
        while IFS= read -r line; do
            case "$line" in ''|'#'*) continue ;; esac
            cand+=("$line")
        done < /etc/shells
    fi
    for n in bash sh zsh fish nu elvish xonsh tcsh ksh mksh dash; do
        p=$(command -v "$n" 2>/dev/null || true)
        [ -n "$p" ] && cand+=("$p")
    done
    for n in nu elvish xonsh fish; do
        [ -x "$HOME/.local/bin/$n" ] && cand+=("$HOME/.local/bin/$n")
    done

    local seen="" real
    for p in "${cand[@]}"; do
        sh_is_shell "$p" || continue
        real=$(readlink -f "$p" 2>/dev/null || echo "$p")
        case " $seen " in *" $real "*) continue ;; esac
        seen="$seen $real"
        echo "$real"
    done
}

sh_shell_label() { # <path> → 菜单显示名
    case "$(basename "$1")" in
        nu) echo "nu（Nushell）" ;;
        elvish) echo "elvish" ;;
        *) echo "$(basename "$1")" ;;
    esac
}

# 进入所选 shell：exec 替换本进程，所以 exit 后直接回到上级菜单，不留嵌套壳
sh_switch_to() { # <path>
    local path="$1" name
    name=$(sh_shell_label "$path")
    echo
    echo "  ▶ 正在进入 $name（$path）…"
    echo "    输入 exit 即可返回上一级菜单（不会改默认登录 shell）"
    echo
    exec "$path"
}

sh_menu_switch() {
    local -a rows=()
    local s name ver cur cur_real
    cur=$(sh_current_shell)
    cur_real=$(readlink -f "$cur" 2>/dev/null || echo "$cur")
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        name=$(sh_shell_label "$s")
        ver=$(sh_shell_version "$s")
        local mark="" desc
        [ "$s" = "$cur_real" ] && mark="（默认登录 shell）"
        if [ -n "$ver" ]; then desc="$ver$mark"; else desc="$s$mark"; fi
        rows+=("$s|$name|$desc")
    done < <(sh_available_shells)

    if [ "${#rows[@]}" -eq 0 ]; then
        dt_info "没有找到可用的 shell。\n请先用菜单第 1 项安装一个（fish / zsh / nushell …）。"
        return 0
    fi
    local n=${#rows[@]}
    rows+=("back|← 返回|")

    local c
    c=$(dt_menu "切换到某个 shell（本终端立即生效）" \
        "本机已有 ${n} 个 shell；选中即进入，输入 exit 返回。当前默认登录 shell: ${cur:-未知}" \
        "${rows[@]}") || return 0
    case "$c" in
        __quit) exit 0 ;;
        back) return 0 ;;
        *) sh_switch_to "$c" ;;
    esac
}

# ---------------------------------------------------------------------------
# 设为默认登录 shell（chsh，下次登录生效）
# ---------------------------------------------------------------------------

sh_set_default_path() { # <path>
    local path="$1" name cur cur_real
    name=$(sh_shell_label "$path")
    cur=$(sh_current_shell)
    cur_real=$(readlink -f "$cur" 2>/dev/null || echo "$cur")
    if [ "$cur_real" = "$path" ]; then
        dt_info "默认登录 shell 已经是 $name（$path），无需修改。"
        return 0
    fi
    dt_info "即将把默认登录 shell 改成：\n\n$name\n$path\n\n当前: ${cur:-未知}\n\n（只影响下次登录后的新会话；当前终端不受影响）\n想立刻体验用菜单第 2 项「切换 shell」。"
    dt_confirm "确认修改默认登录 shell？" || return 0

    # 必须登记到 /etc/shells（chsh 会校验；fish/zsh/nushell 的包大多不自动登记，
    # 本机实测 /etc/shells 里只有 sh/bash/tmux）
    if ! grep -qxF "$path" /etc/shells 2>/dev/null; then
        log "$path 不在 /etc/shells，先登记（需要 sudo）"
        if ! sudo sh -c "grep -qxF '$path' /etc/shells || echo '$path' >> /etc/shells"; then
            err "登记 /etc/shells 失败（需要 sudo 权限）"
            return 1
        fi
    fi

    if ! sudo chsh -s "$path" "${USER:-$(id -un)}"; then
        err "chsh 失败。可手动执行: sudo chsh -s $path ${USER:-$(id -un)}"
        return 1
    fi
    cur=$(sh_current_shell)
    cur_real=$(readlink -f "$cur" 2>/dev/null || echo "$cur")
    if [ "$cur_real" = "$path" ]; then
        echo "  ✅ 默认登录 shell 已改为 $path（下次登录生效）"
        log "当前终端仍是旧 shell；想立即体验用菜单第 2 项，或直接输入: $(basename "$path")"
        return 0
    fi
    err "修改后仍为 ${cur:-未知}，请手动检查 /etc/shells 与 chsh"
    return 1
}

# 兼容 CLI 的 id 形式: shells.sh default fish / nu
sh_set_default() { # <id>
    local id="$1" name path
    name=$(sh_field "$id" 2)
    if ! sh_installed "$id"; then
        dt_info "$name 尚未安装。\n请先在菜单第 1 项安装。"
        return 1
    fi
    path=$(sh_bin_path "$id")
    path=$(readlink -f "$path" 2>/dev/null || echo "$path")
    sh_set_default_path "$path"
}

# ---------------------------------------------------------------------------
# 列表 / 菜单
# ---------------------------------------------------------------------------
sh_list() {
    local id name desc pkg note state ver
    echo "发行版: $(sh_distro)    默认登录 shell: $(sh_current_shell)"
    printf '%-10s %-12s %-26s %s\n' "ID" "名称" "包名" "状态"
    while IFS='|' read -r id name desc _ _ _ _ _ note; do
        pkg=$(sh_pkg "$id")
        [ -z "$pkg" ] && pkg="(不支持)"
        [ "$pkg" = THIRD ] && pkg="(需第三方源)"
        if sh_installed "$id"; then
            ver=$(sh_version "$id")
            state="✓ 已装 $( [ -n "$ver" ] && echo "- $ver" )"
        else
            state="未安装"
        fi
        printf '%-10s %-12s %-26s %s\n' "$id" "$name" "$pkg" "$state"
        [ -n "$note" ] && printf '%-10s %-12s %-26s   ↳ %s\n' "" "" "" "$note"
    done < <(sh_catalog)
}

sh_in_sel() { local x; for x in "${@:2}"; do [ "$x" = "$1" ] && return 0; done; return 1; }

sh_menu_select() {
    local -a sel=()
    local c id name desc pkg ins
    while true; do
        local -a rows=()
        while IFS='|' read -r id name desc _ _ _ _ bin note; do
            pkg=$(sh_pkg "$id")
            ins=""
            if sh_installed "$id"; then
                ins=" ✓已装"
                rows+=("inst-$id|[✓] $name|已安装: $(sh_bin_path "$id")${ins}")
            elif [ "$pkg" = THIRD ] || [ -z "$pkg" ]; then
                rows+=("third-$id|[ ] $name|${desc}｜⚠ 需第三方源/不支持自动安装")
            elif sh_in_sel "$id" "${sel[@]}"; then
                rows+=("$id|[x] $name|${desc}（包: $pkg）")
            else
                rows+=("$id|[ ] $name|${desc}（包: $pkg）")
            fi
        done < <(sh_catalog)
        rows+=("__install|▶ 安装所选|已勾选 ${#sel[@]} 个，需 sudo" "back|← 返回|")

        c=$(dt_menu "Shell 安装（[x] 已勾选，点击切换）" \
            "发行版: $(sh_distro)；[✓] 已装不可重复装；⚠ 项需第三方源，仅在命令行手动装。" \
            "${rows[@]}") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            __install)
                if [ "${#sel[@]}" -eq 0 ]; then
                    dt_info "还没有勾选任何 shell。\\n点击条目切换勾选（[ ] ↔ [x]），再点“安装所选”。"
                else
                    sh_do_install "${sel[@]}"
                fi
                return 0
                ;;
            inst-*) dt_info "$(sh_field "${c#inst-}" 2) 已安装。\n\n路径: $(sh_bin_path "${c#inst-}")\n可直接输入 $(sh_bin "${c#inst-}") 试用。" ;;
            third-*)
                id="${c#third-}"
                dt_info "$(sh_field "$id" 2) 无法自动安装\n\n$(sh_field "$id" 9)\n\n手动方法:\n  Fedora: 加微软源后 sudo dnf install powershell\n  Ubuntu/Debian: 用官方 .deb\n  Arch: AUR (powershell-bin)" ;;
            *)
                if sh_in_sel "$c" "${sel[@]}"; then
                    local -a news=(); local x
                    for x in "${sel[@]}"; do [ "$x" != "$c" ] && news+=("$x"); done
                    sel=("${news[@]}")
                else
                    sel+=("$c")
                fi
                ;;
        esac
    done
}

sh_menu_default() {
    local -a rows=()
    local c s name cur cur_real ver
    cur=$(sh_current_shell)
    cur_real=$(readlink -f "$cur" 2>/dev/null || echo "$cur")
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        name=$(sh_shell_label "$s")
        ver=$(sh_shell_version "$s")
        local mark=""
        [ "$s" = "$cur_real" ] && mark="（当前默认）" && continue   # 已经是默认的没必要再选
        rows+=("$s|$name|$ver")
    done < <(sh_available_shells)
    if [ "${#rows[@]}" -eq 0 ]; then
        dt_info "没有找到可切换的 shell。\n当前默认: ${cur:-未知}\n先用菜单第 1 项安装一个（fish / zsh / nushell …）。"
        return 0
    fi
    rows+=("back|← 返回|")
    c=$(dt_menu "设为默认登录 shell" "当前: ${cur:-未知}；chsh，只影响下次登录（当前终端想换用第 2 项）" "${rows[@]}") || return 0
    case "$c" in
        __quit) exit 0 ;;
        back) return 0 ;;
        *) sh_set_default_path "$c" || true ;;
    esac
}

sh_menu() {
    while true; do
        local c
        c=$(dt_menu "Shell 安装器" \
            "发行版: $(sh_distro)｜默认登录 shell: $(sh_current_shell)" \
            "install|1. 安装 Shell（勾选）|fish / nushell / zsh / elvish / xonsh / tcsh / ksh / dash" \
            "switch|2. 切换 shell（当前终端）|列出本机已有 shell，选中即进入，exit 返回" \
            "default|3. 设为默认登录 shell|chsh，下次登录生效（不动当前终端）" \
            "list|4. 查看状态与版本|本机已装/未装、包名、版本" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            install) sh_menu_select ;;
            switch) sh_menu_switch ;;
            default) sh_menu_default ;;
            list) sh_list ;;
        esac
    done
}

case "${1:-}" in
    list) sh_list ;;
    install) shift; sh_do_install "$@" ;;
    switch) sh_menu_switch ;;
    default) [ -n "${2:-}" ] && sh_set_default "$2" || err "用法: shells.sh default <id>" ;;
    "") sh_menu ;;
    *) err "未知参数: $1（可用: list | install <id...> | switch | default <id>）"; exit 1 ;;
esac
