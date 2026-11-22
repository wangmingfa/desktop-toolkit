#!/usr/bin/env bash
# =============================================================================
# uu-remote.sh —— 网易 UU 远程 Linux 被控端（社区开源实现）一键安装与管理
#
# 说明：网易 UU 远程官方没有 Linux 版，这里安装社区最成熟的纯 Rust 原生实现
#   VallierDev/uu-remote-linux（GPL-3.0，非官方，与网易无关，无 Wine、无 Windows 组件）。
#   装好后用官方手机/Mac/Windows 客户端即可远程控制本机（桌面/文件/终端/端口映射）。
#
# 功能：安装/更新（镜像下载 + SHA256 校验 + ffmpeg/libx264 + 用户服务）、
#       扫码登录、状态、体检一键修复、日志、卸载。
#
# 用法：
#   bash uu-remote.sh            菜单
#   bash uu-remote.sh install    安装/更新（走 gh-proxy.com / ghfast.top 镜像）
#   bash uu-remote.sh login      扫码登录（需终端 + 手机 UU 远程 App）
#   bash uu-remote.sh status     查看服务/编码器/设备连接状态
#   bash uu-remote.sh doctor     体检并可一键修复
#   bash uu-remote.sh logs       实时查看日志
#   bash uu-remote.sh remove     卸载（可保留 ffmpeg）
#
# 环境变量：
#   UU_VERSION=<v0.x.y>   指定版本（默认自动查最新，查不到用已知默认）
#   UU_MIRROR=auto|ghproxy|ghfast|off   下载镜像策略（默认 auto，复用 lib/common.sh）
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 常量与颜色（颜色非 tty 下退化为空串，与 AGENTS.md 第 8 节一致）
# ---------------------------------------------------------------------------
UU_REPO="VallierDev/uu-remote-linux"
UU_API="https://api.github.com/repos/$UU_REPO"
UU_VERSION_DEFAULT="v0.2.64"          # 已知可用版本，自动查最新失败时的兜底
UU_PREFIX="https://github.com/$UU_REPO/releases/download"
UU_BIN="$HOME/.local/bin/uuremote-server"
UU_VIEWER="$HOME/.local/bin/uuremote-viewer"
UU_UNIT="$HOME/.config/systemd/user/uuremote-native.service"

if [ -t 1 ]; then
    DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'; DT_CYAN=$'\033[0;36m'
    DT_RED=$'\033[0;31m';   DT_BOLD=$'\033[1m';       DT_NC=$'\033[0m'
else
    DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_BOLD=""; DT_NC=""
fi

log() { echo -e "  ${DT_CYAN}[uu]${DT_NC} $*"; }
warn() { echo -e "  ${DT_YELLOW}[uu] 注意:${DT_NC} $*" >&2; }
err() { echo -e "  ${DT_RED}[uu] 错误:${DT_NC} $*" >&2; }

# ---------------------------------------------------------------------------
# 检测辅助
# ---------------------------------------------------------------------------
uu_arch() { # -> x86_64 | aarch64 | ""
    local m="${UU_ARCH:-$(uname -m 2>/dev/null)}"
    case "$m" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        *) echo "" ;;
    esac
}

uu_glibc_ok() { # glibc >= 2.35
    ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | awk -F. '{ exit !($1>2 || ($1==2 && $2>=35)) }'
}

# pipefail 下"命令 | grep -q"会让上游收 SIGPIPE 而误判失败，故一律先捕获再 grep。
uu_ffmpeg_x264_ok() {
    command -v ffmpeg >/dev/null 2>&1 || return 1
    local enc
    enc=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
    grep -qw libx264 <<<"$enc"
}

uu_service_active() { systemctl --user is-active uuremote-native.service >/dev/null 2>&1; }
uu_service_enabled() { systemctl --user is-enabled uuremote-native.service >/dev/null 2>&1; }

uu_installed() { [ -x "$UU_BIN" ]; }

# ---------------------------------------------------------------------------
# 版本：自动查最新（走镜像 API），失败回退已知默认
# ---------------------------------------------------------------------------
uu_detect_version() {
    local v=""
    v=$(timeout -k 5 25 curl -fsSL --http1.1 --connect-timeout 10 --max-time 20 \
        "$GH_PROXY/$UU_API/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
    [ -z "$v" ] && v=$(timeout -k 5 25 curl -fsSL --http1.1 --connect-timeout 10 --max-time 20 \
        "$DT_GHFAST/$UU_API/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
    if [ -z "$v" ]; then
        warn "自动查询最新版本失败（网络受限？），使用已知默认 $UU_VERSION_DEFAULT"
        echo "$UU_VERSION_DEFAULT"
        return 0
    fi
    echo "$v"
}

# ---------------------------------------------------------------------------
# 下载 + SHA256 校验：uu_fetch_asset <version> <asset> <dest>
# ---------------------------------------------------------------------------
uu_fetch_asset() {
    local version="$1" asset="$2" dest="$3"
    log "下载 $asset"
    if ! dt_download "$UU_PREFIX/$version/$asset" "$dest"; then
        err "下载 $asset 失败"
        return 1
    fi
}

uu_verify_sha256() { # <asset> <file>
    local asset="$1" file="$2" expected actual
    expected=$(awk -v a="$asset" '$2==a {print $1}' "$file.sha256" | head -1 || true)
    if [ -z "$expected" ]; then
        err "SHA256SUMS 里没有 $asset 的条目"
        return 1
    fi
    actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}' || true)
    if [ "$actual" != "$expected" ]; then
        err "$asset 校验和不匹配（期望 $expected，实际 $actual）"
        return 1
    fi
    log "SHA256 校验通过"
}

# ---------------------------------------------------------------------------
# 安装主体
# ---------------------------------------------------------------------------
uu_install() {
    local arch version asset tmp
    arch=$(uu_arch)
    if [ -z "$arch" ]; then
        err "当前架构不受支持（仅 x86_64 / aarch64）。可设 UU_ARCH 强制指定。"
        return 1
    fi
    if ! uu_glibc_ok; then
        err "系统 glibc 过旧（需 ≥ 2.35，当前 $(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+'))"
        return 1
    fi
    version="${UU_VERSION:-$(uu_detect_version)}"
    [ "${version#v}" != "$version" ] || version="v$version"
    asset="uu-remote-linux-${version}-${arch}-linux.tar.gz"

    if ! command -v curl >/dev/null 2>&1; then
        err "需要 curl"
        return 1
    fi

    echo -e "${DT_BOLD}═══ UU 远程安装 ${version}（${arch}）═══${DT_NC}"
    log "仓库：$UU_REPO（社区开源实现，非官方）"

    tmp=$(mktemp -d) || { err "创建临时目录失败"; return 1; }
    trap 'rm -rf "$tmp"' EXIT

    # 1) SHA256SUMS + 包
    uu_fetch_asset "$version" SHA256SUMS "$tmp/SHA256SUMS" || return 1
    uu_fetch_asset "$version" "$asset" "$tmp/$asset" || return 1
    uu_verify_sha256 "$asset" "$tmp/$asset" || return 1

    # 2) 解压
    log "解压..."
    tar xzf "$tmp/$asset" -C "$tmp" || { err "解压失败"; return 1; }
    local src="$tmp/uu-remote-linux-${version}-${arch}-linux"
    [ -f "$src/install.sh" ] || { err "压缩包结构异常（缺 install.sh）"; return 1; }

    # 3) 安装二进制 + 用户服务（非 root；ffmpeg 单独处理）
    log "安装程序到 ~/.local（无需 root）"
    ( cd "$src" && ./install.sh --no-ffmpeg ) || true

    if ! uu_installed; then
        err "程序安装失败（$UU_BIN 不存在）"
        return 1
    fi
    log "程序已安装：$UU_BIN"

    # 4) ffmpeg/libx264（缺则装，需要 sudo）
    if uu_ffmpeg_x264_ok; then
        log "FFmpeg libx264 编码器：已就绪"
    else
        warn "FFmpeg 缺 libx264（否则远程画面会一直停在“正在传输画面”）"
        if dt_confirm "现在安装带 libx264 的 ffmpeg 吗？（需要 sudo 密码）"; then
            uu_ensure_ffmpeg || warn "ffmpeg 安装未成功，可稍后手动处理"
        fi
    fi

    # 5) 启用用户服务
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now uuremote-native.service 2>/dev/null || true
    if uu_service_active; then
        log "用户服务已启用并运行（开机随图形会话自启）"
    else
        warn "服务未运行，手动启动：systemctl --user start uuremote-native.service"
    fi

    echo
    echo -e "${DT_GREEN}${DT_BOLD}✅ 安装完成！${DT_NC}"
    echo -e "  ${DT_YELLOW}下一步：${DT_NC}运行 ${DT_CYAN}bash $0 login${DT_NC} 用手机 UU 远程 App 扫码登录，"
    echo -e "  之后设备会出现在你的 UU 账号设备列表，用官方客户端即可远程控制。"
    if uu_service_active && ! uu_logged_in; then
        if dt_confirm "现在扫码登录吗？"; then
            uu_login
        fi
    fi
    return 0
}

# ---------------------------------------------------------------------------
# ffmpeg/libx264：按发行版包管理器装（Fedora 先启 RPM Fusion free）
# ---------------------------------------------------------------------------
uu_ensure_ffmpeg() {
    if uu_ffmpeg_x264_ok; then return 0; fi
    if command -v dnf >/dev/null 2>&1; then
        # Fedora 自带 ffmpeg-free 无 libx264，完整版在 RPM Fusion free
        local repolist
        repolist=$(dnf repolist --enabled 2>/dev/null || true)
        if ! grep -qi rpmfusion-free <<<"$repolist"; then
            log "启用 RPM Fusion free 仓库"
            sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                || { err "启用 RPM Fusion free 失败"; return 1; }
        fi
        log "安装完整版 ffmpeg（替换 ffmpeg-free）"
        sudo dnf install -y --allowerasing ffmpeg || { err "dnf 安装 ffmpeg 失败"; return 1; }
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y ffmpeg || return 1
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm ffmpeg || return 1
    else
        warn "未识别的包管理器，请手动安装带 libx264 的 ffmpeg"
        return 1
    fi
    # dnf 事务刚结束偶尔检测不准，稍等重试
    local i
    for i in 1 2 3 4 5; do uu_ffmpeg_x264_ok && break; sleep 2; done
    if uu_ffmpeg_x264_ok; then
        log "FFmpeg libx264 编码器：已就绪"
        return 0
    fi
    err "安装后仍检测不到 libx264（检查：ffmpeg -hide_banner -encoders | grep libx264）"
    return 1
}

# ---------------------------------------------------------------------------
# 扫码登录（需终端）
# ---------------------------------------------------------------------------
uu_logged_in() { # 设备是否已连接云端（从日志粗判；捕获后再 grep，避免 SIGPIPE）
    local out
    out=$(journalctl --user -u uuremote-native.service --no-pager -n 2000 2>/dev/null || true)
    grep -q 'status=Some("CONNECTED")' <<<"$out"
}

uu_login() {
    if ! uu_installed; then
        err "未安装，先运行：bash $0 install"
        return 1
    fi
    if ! [ -t 0 ]; then
        err "扫码登录需要在终端里运行（本环境无交互终端）"
        return 1
    fi
    echo -e "${DT_BOLD}请用手机「UU远程」App 扫描下方二维码${DT_NC}"
    "$UU_BIN" login
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
uu_status() {
    echo -e "${DT_BOLD}═══ UU 远程状态 ═══${DT_NC}"
    # 程序
    if uu_installed; then
        log "程序：已安装（$UU_BIN）"
    else
        warn "程序：未安装"
    fi
    [ -x "$UU_VIEWER" ] && log "控制端 uuremote-viewer：已安装" || true
    # 编码器
    if uu_ffmpeg_x264_ok; then
        log "FFmpeg libx264：已就绪"
    else
        warn "FFmpeg libx264：缺失（远程画面无法传输）"
    fi
    # 服务
    if uu_service_enabled; then
        log "用户服务：已启用（开机自启）"
    else
        warn "用户服务：未启用"
    fi
    if uu_service_active; then
        log "用户服务：运行中"
    else
        warn "用户服务：未运行"
    fi
    # 设备连接
    if uu_logged_in; then
        log "设备连接：已连接云端（CONNECTED）"
    else
        warn "设备连接：未登录/未连接（运行 bash $0 login）"
    fi
    # 镜像
    log "下载镜像策略：${DT_MIRROR:-auto}（GH_PROXY=${GH_PROXY:-https://gh-proxy.com}，ghfast=${DT_GHFAST:-https://ghfast.top}）"
}

# ---------------------------------------------------------------------------
# 体检 + 一键修复
# ---------------------------------------------------------------------------
uu_doctor() {
    local n=0 fail=0 warn=0 arch
    local -a fixes=()
    ok()  { n=$((n+1)); echo -e "  ${DT_GREEN}✔${DT_NC} $*"; }
    bad() { n=$((n+1)); fail=$((fail+1)); echo -e "  ${DT_RED}✘${DT_NC} $*"; }
    wrn() { n=$((n+1)); warn=$((warn+1)); echo -e "  ${DT_YELLOW}⚠${DT_NC} $*"; }

    echo -e "${DT_BOLD}═══ UU 远程体检 ═══${DT_NC}"
    arch=$(uu_arch)
    if [ -n "$arch" ]; then ok "架构：$arch"; else bad "架构不受支持（仅 x86_64/aarch64）"; fi
    if uu_glibc_ok; then ok "glibc ≥ 2.35"; else bad "glibc 过旧（需 ≥ 2.35）"; fi
    if uu_installed; then ok "程序已安装"; else bad "程序未安装（可修复：install）"; fixes+=(uu_install); fi
    if uu_ffmpeg_x264_ok; then ok "FFmpeg libx264 已就绪"; else bad "FFmpeg 缺 libx264（可修复）"; fixes+=(uu_ensure_ffmpeg); fi
    if uu_service_enabled && uu_service_active; then
        ok "用户服务已启用并运行"
    else
        bad "用户服务未启用/未运行（可修复）"; fixes+=(uu_enable_service)
    fi
    if uu_logged_in; then ok "设备已连接云端"; else wrn "设备未登录（login）"; fi

    echo
    if [ "$fail" -eq 0 ]; then
        echo -e "  ${DT_GREEN}${DT_BOLD}体检通过：${n} 项全部正常（${warn} 项提示）。${DT_NC}"
        return 0
    fi
    echo -e "  ${DT_RED}${DT_BOLD}发现 ${fail} 项问题。${DT_NC}"
    if [ -t 0 ] && dt_confirm "自动修复这 ${#fixes[@]} 项吗？（可能需 sudo）"; then
        local f
        for f in "${fixes[@]}"; do "$f" || true; done
        echo -e "  ${DT_CYAN}修复完成，重跑 bash $0 doctor 复查。${DT_NC}"
    fi
    return 0
}

uu_enable_service() {
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now uuremote-native.service 2>/dev/null || true
    uu_service_active && { log "用户服务已启动"; return 0; } || { warn "服务启动失败"; return 1; }
}

# ---------------------------------------------------------------------------
# 日志（需终端）
# ---------------------------------------------------------------------------
uu_logs() {
    if ! uu_service_active && ! uu_service_enabled; then
        warn "服务未启用，无日志；先运行 install"
        return 1
    fi
    exec journalctl --user -u uuremote-native.service -f
}

# ---------------------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------------------
uu_remove() {
    if ! uu_installed && ! uu_service_enabled; then
        warn "未检测到已安装的 UU 远程"
        return 0
    fi
    if ! dt_confirm "确认卸载 UU 远程？（停止并删除用户服务与 ~/.local 程序，ffmpeg 保留）"; then
        return 0
    fi
    systemctl --user disable --now uuremote-native.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/uuremote-native.service" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
    rm -f "$UU_BIN" "$UU_VIEWER" 2>/dev/null || true
    rm -rf "$HOME/.local/lib/uu-remote-linux" 2>/dev/null || true
    rm -f "$HOME/.local/share/applications/uu-remote-linux.desktop" \
          "$HOME/.local/share/applications/uu-remote-linux-viewer.desktop" 2>/dev/null || true
    rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/uu-remote-linux.svg" 2>/dev/null || true
    log "已卸载。配置保留在 ~/.config/uuremote（如需彻底删除：rm -rf ~/.config/uuremote）"
}

# ---------------------------------------------------------------------------
# 菜单 / 分发
# ---------------------------------------------------------------------------
uu_menu() {
    while true; do
        local c
        c=$(dt_menu "UU 远程（Linux 被控端）" "社区开源实现，官方客户端可远程控制本机：" \
            "install|1. 安装 / 更新|镜像下载 + 校验 + ffmpeg + 服务（需 sudo 装 ffmpeg）" \
            "login|2. 扫码登录|手机 UU 远程 App 扫码（需终端）" \
            "status|3. 查看状态|程序/编码器/服务/设备连接" \
            "doctor|4. 体检修复|一键检测并修复常见问题" \
            "logs|5. 实时日志|journalctl 跟踪（需终端）" \
            "remove|6. 卸载|删除程序与用户服务（保留 ffmpeg）" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            install) uu_install ;;
            login) uu_login ;;
            status) uu_status ;;
            doctor) uu_doctor ;;
            logs) uu_logs ;;
            remove) uu_remove ;;
        esac
        echo
    done
}

case "${1:-}" in
    "")      uu_menu ;;
    install) uu_install ;;
    login)   uu_login ;;
    status)  uu_status ;;
    doctor)  uu_doctor ;;
    logs)    uu_logs ;;
    remove)  uu_remove ;;
    -h|--help|help)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) err "未知参数：$1（--help 查看用法）"; exit 2 ;;
esac
