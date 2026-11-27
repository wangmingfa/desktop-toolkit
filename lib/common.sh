#!/usr/bin/env bash
# =============================================================================
# desktop-toolkit / 公共函数库
# 所有模块 source 本文件即可获得：仓库根目录、DBUS 环境、备份、日志
# =============================================================================

# 仓库根目录 (本文件位于 <repo>/lib/common.sh)
DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 当前用户 UID / DBUS 会话地址 (脚本可能运行在容器里，需显式指向宿主会话)
DT_UID="$(id -u)"
DT_DBUS_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${DT_UID}/bus XDG_RUNTIME_DIR=/run/user/${DT_UID}"

dt_log() { echo "[desktop-toolkit] $*"; }
dt_err() { echo "[desktop-toolkit] 错误: $*" >&2; }

# 带时间戳备份一个配置文件： dt_backup ~/.config/kwinrc
dt_backup() {
    local f="$1"
    [ -f "$f" ] || return 0
    local bak="${f}.bak-dt-$(date +%Y%m%d-%H%M%S)"
    cp -a "$f" "$bak" && dt_log "已备份: $bak"
}

# 是否运行在 KDE / Plasma 桌面（KDE 上优先用原生 kdialog，而不是 GTK 的 zenity）
dt_is_kde() {
    case "${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-} ${KDE_FULL_SESSION:-}" in
        *KDE*|*plasma*|*Plasma*) return 0 ;;
    esac
    return 1
}

# 检测 GUI 工具：KDE 桌面优先用原生 kdialog（菜单/弹窗由 Plasma 主题渲染、随内容
# 自适应大小）；其余（GNOME / 容器）用 zenity；两者都没有则退化为 TUI。
dt_detect_gui() {
    if dt_is_kde && command -v kdialog >/dev/null 2>&1; then
        echo kdialog
    elif command -v zenity >/dev/null 2>&1; then
        echo zenity
    elif command -v kdialog >/dev/null 2>&1; then
        echo kdialog
    else
        echo none
    fi
}

# =============================================================================
# 国内网络 / GitHub 镜像加速
#   涉及 GitHub 的资源（主题/图标/光标仓库）在部分网络下慢或不可达，
#   可用国内镜像加速。通过环境变量控制，方便复用：
#     DT_MIRROR=auto|ghproxy|ghfast|fastgit|off   (默认 auto: 先直连, 失败自动走镜像)
#     GH_PROXY=<https://xxx>                (ghproxy 类镜像前缀, 可换)
#     DT_GIT_STALL=<秒>                        (某源传输停滞多少秒后放弃, 默认 20)
#     DT_GIT_CONNECT=<秒>                     (连接/握手超时, 默认 10)
#     DT_GIT_KILL=<秒>                       (单源硬上限, 到点强制中止该源, 默认 60)
#   注意: 这类镜像站地址会变动, 失效时改 GH_PROXY 即可。
# 已验证可用(2026-11): gh-proxy.com / ghfast.top；直连 github.com 在部分网络下超时。
# =============================================================================
DT_MIRROR="${DT_MIRROR:-auto}"
# 前缀式镜像: <前缀>/https://github.com/owner/repo.git
GH_PROXY="${GH_PROXY:-https://gh-proxy.com}"
DT_GHFAST="${DT_GHFAST:-https://ghfast.top}"
# 路径式镜像: https://fastgit.org/github.com/owner/repo.git
DT_FASTGIT="${DT_FASTGIT:-https://fastgit.org/github.com/}"
# 传输停滞超时(秒): 某个源传输中长时间无数据则中止, 快速轮到下一源
DT_GIT_STALL="${DT_GIT_STALL:-20}"
# 连接/TLS 握手超时(秒): lowSpeedTime 管不到握手阶段的死等, 需单独限
DT_GIT_CONNECT="${DT_GIT_CONNECT:-10}"
# 单个源的硬上限(秒): 到点强制中止该源, 这是 dt_clone 超时行为的真正保证
DT_GIT_KILL="${DT_GIT_KILL:-60}"

# 路径式镜像地址: https://fastgit.org/github.com/owner/repo.git
dt_fastgit_url() { # https://github.com/owner/repo(.git)
    echo "$DT_FASTGIT${1#https://github.com/}"
}

# 把 github 完整 URL 按当前镜像改写
dt_github() { # https://github.com/owner/repo(.git)
    local url="$1"
    case "$DT_MIRROR" in
        ghproxy) echo "$GH_PROXY/$url" ;;
        ghfast)  echo "$DT_GHFAST/$url" ;;
        fastgit) dt_fastgit_url "$url" ;;
        *) echo "$url" ;;  # auto/off 原样返回(内部由 dt_clone 决定回退)
    esac
}

# 浅克隆仓库，带镜像回退：dt_clone <github_url> <dest> [branch]
dt_clone() {
    local url="$1" dest="$2" branch="${3:-}"
    local -a candidates=()
    case "$DT_MIRROR" in
        off)     candidates=("$url") ;;
        ghproxy) candidates=("$(dt_github "$url")") ;;
        ghfast)  candidates=("$(dt_github "$url")") ;;
        fastgit) candidates=("$(dt_github "$url")") ;;
        auto)    candidates=("$url" "$GH_PROXY/$url" "$DT_GHFAST/$url" "$(dt_fastgit_url "$url")") ;;
    esac
    rm -rf "$dest" 2>/dev/null || true

    local errf; errf=$(mktemp)
    local m rc=1 st=0
    # 单源硬上限: git 的 lowSpeed/connectTimeout 在中途断连时会内部重试, 实测仍会
    # 拖到 160s 才返回, 不可靠。故用 timeout 兜底——到点必杀, 保证尽快轮到下一源。
    local -a gcopts=(-c http.version=HTTP/1.1
                     -c http.lowSpeedLimit=1000
                     -c "http.lowSpeedTime=${DT_GIT_STALL:-20}"
                     -c "http.connectTimeout=${DT_GIT_CONNECT:-10}")
    for m in "${candidates[@]}"; do
        echo "  [git] 尝试: $m" >&2
        # 强制 HTTP/1.1: 规避部分代理/镜像对 HTTP/2 流的重置
        # GIT_TERMINAL_PROMPT=0: 卡住时别去弹密码/凭据提示, 直接判失败走下一源
        # -k 5: 到点先 TERM, 再等 5s 后 KILL
        st=0
        if [ -n "$branch" ]; then
            GIT_TERMINAL_PROMPT=0 timeout -k 5 "${DT_GIT_KILL:-60}" git "${gcopts[@]}" \
                clone --depth 1 -b "$branch" "$m" "$dest" 2>"$errf" || st=$?
        else
            GIT_TERMINAL_PROMPT=0 timeout -k 5 "${DT_GIT_KILL:-60}" git "${gcopts[@]}" \
                clone --depth 1 "$m" "$dest" 2>"$errf" || st=$?
        fi
        [ "$st" = 0 ] && rc=0
        [ "$rc" = 0 ] && break
        # 超时被杀的源: git 最后写的是进度行, 打印出来没意义, 直接说明是超时
        if [ "$st" = 124 ] || [ "$st" = 137 ]; then
            echo "  [git]   (超过 ${DT_GIT_KILL:-60}s 无进展, 已强制中止该源; 可调小 DT_GIT_KILL)" >&2
        elif [ -s "$errf" ]; then
            # 否则打印 git 的真实报错(最后一行)，避免只看到"克隆失败"无从排查
            sed -n '$p' "$errf" | sed 's/^/  [git]   /' >&2
        fi
        rm -rf "$dest" 2>/dev/null || true
    done
    rm -f "$errf"

    if [ "$rc" != 0 ]; then
        echo "  [git] 克隆失败(已尝试 ${#candidates[@]} 个源): $url" >&2
        echo "  [git] 可调 DT_MIRROR=off|ghproxy|ghfast|fastgit 或 GH_PROXY=<镜像前缀> 后重跑" >&2
        return 1
    fi
}

# =============================================================================
# 下载 GitHub release 资产（tar.gz / deb / rpm / .sha256 等），带镜像回退。
#   与 dt_clone 同一套镜像候选：直连 → gh-proxy.com → ghfast.top（auto 模式）。
#   用于"下载发行包"场景，与"git clone 仓库"的 dt_clone 互补。
#   用法： dt_download <github_asset_url> <dest>
#   成功 0，失败 1；进度/错误全部走 stderr（stdout 不输出，避免被 $( ) 捕获污染）。
#   可调环境变量：DT_DL_KILL=<单源硬上限秒，默认 300>（大包慢网放宽）；
#                 其余复用 dt_clone 的 DT_MIRROR/GH_PROXY/DT_GHFAST/DT_GIT_CONNECT。
# 已验证可用(2026-11): gh-proxy.com / ghfast.top。
# =============================================================================
DT_DL_KILL="${DT_DL_KILL:-300}"
dt_download() {
    local url="$1" dest="$2"
    local -a candidates=()
    case "$DT_MIRROR" in
        off)     candidates=("$url") ;;
        ghproxy) candidates=("$GH_PROXY/$url") ;;
        ghfast)  candidates=("$DT_GHFAST/$url") ;;
        fastgit) candidates=("$(dt_fastgit_url "$url")") ;;
        auto)    candidates=("$url" "$GH_PROXY/$url" "$DT_GHFAST/$url") ;;
    esac

    local m rc=1 st=0
    for m in "${candidates[@]}"; do
        echo "  [download] 尝试: $m" >&2
        st=0
        # -f: HTTP>=400 即失败; --retry 2 对瞬断重试; --http1.1 规避部分镜像对 HTTP/2 流重置
        # 单源硬上限用外部 timeout(与 dt_clone 同理由: curl 内部超时不可靠)
        timeout -k 5 "$DT_DL_KILL" curl -fL --http1.1 --retry 2 \
            --connect-timeout "${DT_GIT_CONNECT:-10}" \
            --max-time "$DT_DL_KILL" \
            -o "$dest" "$m" 2>"$dest.err" || st=$?
        if [ "$st" = 0 ] && [ -s "$dest" ]; then
            rc=0; break
        fi
        # 打印 curl 真实报错最后一行(若有)，便于定位是超时还是 404
        if [ -s "$dest.err" ]; then
            sed -n '$p' "$dest.err" | sed 's/^/  [download]   /' >&2
        fi
        rm -f "$dest" "$dest.err" 2>/dev/null || true
    done
    rm -f "$dest.err" 2>/dev/null || true
    if [ "$rc" != 0 ]; then
        echo "  [download] 下载失败(已尝试 ${#candidates[@]} 个源): $url" >&2
        echo "  [download] 可调 DT_MIRROR=off|ghproxy|ghfast 或 GH_PROXY=<镜像前缀> 后重跑" >&2
        return 1
    fi
}

# =============================================================================
# 现问 GitHub API 解析"最新 release 的资产 URL"（版本会变，别硬编码 tag）。
#   用法: dt_github_latest_asset <owner/repo> <资产URL正则> [兜底URL]
#   - 直连 api.github.com（限 10s），失败自动重试一次（瞬断容忍）；
#     api.github.com 无稳定镜像，路径式镜像(gh-proxy 等)只代理 github.com 文件。
#   - 解析失败时若给了兜底URL则用它（用一个已知稳定的硬编码 tag），
#     兜底URL 仍会被 dt_download 的镜像回退覆盖到弱网场景。
#   - stdout 只输出 URL（常被 $( ) 捕获）；探测过程/错误全走 stderr。
#   - 用法参考 §3.0b：管道尾必须 || true（grep 无匹配时 pipefail 静默失败）。
# 示例: url=$(dt_github_latest_asset "neovim/neovim" 'nvim-linux-x86_64\.tar\.gz' \
#          "https://github.com/neovim/neovim/releases/download/v0.11.3/nvim-linux-x86_64.tar.gz")
# =============================================================================
dt_github_latest_asset() { # <owner/repo> <资产URL正则> [fallback_url]
    local repo="$1" regex="$2" fallback="${3:-}"
    local api="https://api.github.com/repos/$repo/releases/latest"
    local try url=""
    for try in 1 2; do
        url=$(timeout 10 curl -fsSL --http1.1 --max-time 10 "$api" 2>/dev/null |
            grep -oE "https://[^\"]*$regex" | head -1 || true)
        # head 收到 SIGPIPE 退出码非零属正常，管道整体已被 || true 兜住
        [ -n "$url" ] && { echo "$url"; return 0; }
        echo "  [download] GitHub API 解析失败(第 ${try} 次): $repo" >&2
    done
    if [ -n "$fallback" ]; then
        echo "  [download] 使用硬编码兜底 URL: $fallback" >&2
        echo "$fallback"
        return 0
    fi
    return 1
}
