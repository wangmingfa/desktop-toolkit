#!/usr/bin/env bash
# =============================================================================
# wowtype.sh —— WowType 输入法（fcitx5 插件）一键安装与管理
#
# 说明：WowType 是运行在 fcitx5 上的输入法插件（词库已内置），GitHub:
#   Gloridust/WowType。安装后需 fcitx5 作为输入法框架（缺失时自动带上），
#   并保证 libx264 无关——它不需要 ffmpeg，但与 fcitx5 及 GTK4/libadwaita 绑定。
#
# 功能：安装/更新（镜像下载 + SHA256 校验 + 发行版包管理器安装 + fcitx5 设置）、
#       状态、体检一键修复、卸载。
#
# 用法：
#   bash wowtype.sh            菜单
#   bash wowtype.sh install    安装/更新（走 gh-proxy.com / ghfast.top 镜像）
#   bash wowtype.sh status     查看安装/fcitx5/输入法配置状态
#   bash wowtype.sh doctor     体检并可一键修复
#   bash wowtype.sh remove     卸载
#
# 环境变量：
#   WT_VERSION=<v0.x.y>   指定版本（默认自动查最新，查不到用已知默认）
#   WT_MIRROR=auto|ghproxy|ghfast|off   下载镜像策略（默认 auto，复用 lib/common.sh）
#
# 说明：Fedora（dnf）为完整支持与实测环境；apt-get / pacman 提供尽力而为分支。
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 常量与颜色
# ---------------------------------------------------------------------------
WT_REPO="Gloridust/WowType"
WT_API="https://api.github.com/repos/$WT_REPO"
WT_VERSION_DEFAULT="v0.6.0"           # 已知可用版本，自动查最新失败时的兜底
WT_PREFIX="https://github.com/$WT_REPO/releases/download"
WT_PROFILE="$HOME/.config/fcitx5/profile"

if [ -t 1 ]; then
    DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'; DT_CYAN=$'\033[0;36m'
    DT_RED=$'\033[0;31m';   DT_BOLD=$'\033[1m';       DT_NC=$'\033[0m'
else
    DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_BOLD=""; DT_NC=""
fi

log() { echo -e "  ${DT_CYAN}[wowtype]${DT_NC} $*"; }
warn() { echo -e "  ${DT_YELLOW}[wowtype] 注意:${DT_NC} $*" >&2; }
err() { echo -e "  ${DT_RED}[wowtype] 错误:${DT_NC} $*" >&2; }

# ---------------------------------------------------------------------------
# 检测辅助（pipefail 下"命令 | grep -q"会因上游 SIGPIPE 误判，一律先捕获再 grep）
# ---------------------------------------------------------------------------
wt_fcitx_running() { pgrep -x fcitx5 >/dev/null 2>&1; }

wt_installed_version() { # -> 已装版本号(无 v) 或 ""
    if command -v rpm >/dev/null 2>&1 && rpm -q wowtype >/dev/null 2>&1; then
        rpm -q --qf '%{VERSION}' wowtype 2>/dev/null || true
    elif command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W wowtype >/dev/null 2>&1; then
        dpkg-query -W -f='${Version}' wowtype 2>/dev/null | cut -d- -f1 || true
    elif command -v pacman >/dev/null 2>&1 && pacman -Q wowtype >/dev/null 2>&1; then
        pacman -Q wowtype 2>/dev/null | awk '{print $2}' | cut -d- -f1 || true
    else
        echo ""
    fi
}

wt_im_configured() { # fcitx5 profile 里默认输入法是否为 wowtype
    [ -f "$WT_PROFILE" ] || return 1
    local out
    out=$(cat "$WT_PROFILE" 2>/dev/null || true)
    grep -q '^DefaultIM=wowtype' <<<"$out"
}

wt_env_ok() { # fcitx 环境变量是否已配（~/.config/environment.d）
    local f="$HOME/.config/environment.d/fcitx.conf"
    [ -f "$f" ] || return 1
    local out
    out=$(cat "$f" 2>/dev/null || true)
    grep -q '^GTK_IM_MODULE=fcitx' <<<"$out"
}

wt_autostart_ok() {
    [ -f "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop" ]
}

# ---------------------------------------------------------------------------
# 版本：自动查最新（走镜像 API），失败回退已知默认
# ---------------------------------------------------------------------------
wt_detect_version() {
    local v=""
    v=$(timeout -k 5 25 curl -fsSL --http1.1 --connect-timeout 10 --max-time 20 \
        "$GH_PROXY/$WT_API/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
    if [ -z "$v" ]; then
        warn "自动查询最新版本失败（网络受限？），使用已知默认 $WT_VERSION_DEFAULT"
        echo "$WT_VERSION_DEFAULT"
        return 0
    fi
    echo "$v"
}

# ---------------------------------------------------------------------------
# 发行版 / 包文件名
# ---------------------------------------------------------------------------
wt_detect() { # 设置 WT_MANAGER WT_DISTRO WT_DEB_ARCH WT_RPM_ARCH WT_VER_ID；失败返回 1
    local id="" version_id="" codename="" machine
    id=$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | head -1 || true)
    version_id=$(sed -n 's/^VERSION_ID=//p' /etc/os-release 2>/dev/null | tr -d '"' | head -1 || true)
    codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release 2>/dev/null | head -1 || true)
    machine=$(uname -m 2>/dev/null)
    case "$machine" in
        x86_64|amd64) WT_DEB_ARCH=amd64; WT_RPM_ARCH=x86_64 ;;
        aarch64|arm64) WT_DEB_ARCH=arm64; WT_RPM_ARCH=aarch64 ;;
        *) err "当前架构 $machine 不受支持（仅 x86_64/aarch64）"; return 1 ;;
    esac
    if command -v dnf >/dev/null 2>&1 && [ "$id" = fedora ]; then
        WT_MANAGER=dnf; WT_VER_ID="$version_id"
    elif command -v apt-get >/dev/null 2>&1; then
        WT_MANAGER=apt-get
        case "$id $codename" in
            "ubuntu jammy") WT_DISTRO=ubuntu22.04 ;;
            "ubuntu noble") WT_DISTRO=ubuntu24.04 ;;
            "ubuntu resolute") WT_DISTRO=ubuntu26.04 ;;
            "debian trixie") WT_DISTRO=debian13 ;;
            "deepin beige"|"Deepin beige") WT_DISTRO=deepin23 ;;
            "deepin crimson"|"Deepin crimson") WT_DISTRO=deepin25 ;;
            *) err "未识别的 apt 发行版基线（id=$id codename=$codename）"; return 1 ;;
        esac
    elif command -v pacman >/dev/null 2>&1; then
        WT_MANAGER=pacman
        [ "$WT_RPM_ARCH" = x86_64 ] || { err "Arch 预编译包只有 x86_64"; return 1; }
    else
        err "未识别的包管理器（需要 dnf / apt-get / pacman）"
        return 1
    fi
}

wt_package_name() { # <version> -> 包文件名
    local v="${1#v}"
    case "$WT_MANAGER" in
        dnf)     echo "wowtype-${v}-1.fc${WT_VER_ID}.${WT_RPM_ARCH}.rpm" ;;
        apt-get) echo "wowtype_${v}_${WT_DISTRO}_${WT_DEB_ARCH}.deb" ;;
        pacman)  echo "wowtype-${v}-1-x86_64.pkg.tar.zst" ;;
    esac
}

# ---------------------------------------------------------------------------
# 下载 + SHA256 校验
# ---------------------------------------------------------------------------
wt_fetch_asset() { # <version> <asset> <dest>
    if ! dt_download "$WT_PREFIX/$1/$2" "$3"; then
        err "下载 $2 失败"
        return 1
    fi
    log "已下载 $2"
}

wt_verify_sha256() { # <asset> <file>
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
# fcitx5 环境补全（自启动 + 环境变量；幂等，已有则跳过）
# ---------------------------------------------------------------------------
wt_ensure_fcitx_env() {
    local ad="$HOME/.config/autostart" sd="$HOME/.config/environment.d"
    if ! wt_autostart_ok; then
        if [ -f /usr/share/applications/org.fcitx.Fcitx5.desktop ]; then
            mkdir -p "$ad"
            cp /usr/share/applications/org.fcitx.Fcitx5.desktop "$ad/" 2>/dev/null && log "已补 fcitx5 自启动项" || true
        fi
    fi
    if ! wt_env_ok; then
        mkdir -p "$sd"
        printf 'GTK_IM_MODULE=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\nSDL_IM_MODULE=fcitx\n' > "$sd/fcitx.conf" \
            && log "已补 fcitx 环境变量（$sd/fcitx.conf）" || true
    fi
}

# ---------------------------------------------------------------------------
# 安装主体
# ---------------------------------------------------------------------------
wt_install() {
    local version asset tmp
    wt_detect || return 1
    version="${WT_VERSION:-$(wt_detect_version)}"
    [ "${version#v}" != "$version" ] || version="v$version"
    asset=$(wt_package_name "$version")

    if ! command -v curl >/dev/null 2>&1; then
        err "需要 curl"
        return 1
    fi

    echo -e "${DT_BOLD}═══ WowType 安装 ${version}（${WT_MANAGER}）═══${DT_NC}"
    log "仓库：$WT_REPO"

    tmp=$(mktemp -d) || { err "创建临时目录失败"; return 1; }
    trap 'rm -rf "$tmp"' EXIT

    # 1) 校验清单 + 包
    wt_fetch_asset "$version" SHA256SUMS "$tmp/SHA256SUMS" || return 1
    wt_fetch_asset "$version" "$asset" "$tmp/$asset" || return 1
    wt_verify_sha256 "$asset" "$tmp/$asset" || return 1
    chmod 644 "$tmp/$asset" 2>/dev/null || true

    # 2) 装依赖 + 包（需要 sudo）
    log "安装（需要时会要求输入密码）"
    case "$WT_MANAGER" in
        dnf)
            sudo dnf install -y "$tmp/$asset" \
                fcitx5-configtool fcitx5-gtk3 fcitx5-gtk4 fcitx5-qt5 fcitx5-qt6 fcitx5-autostart \
                python3-gobject gtk4 libadwaita gobject-introspection || { err "dnf 安装失败"; return 1; } ;;
        apt-get)
            sudo apt-get update -qq || warn "apt-get update 失败，继续用现有源"
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/$asset" \
                fcitx5-config-qt fcitx5-frontend-all im-config \
                python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 || { err "apt-get 安装失败"; return 1; } ;;
        pacman)
            sudo pacman -S --needed --noconfirm fcitx5 fcitx5-gtk fcitx5-qt \
                fcitx5-configtool python-gobject gtk4 libadwaita || { err "pacman 依赖安装失败"; return 1; }
            sudo pacman -U --noconfirm "$tmp/$asset" || { err "pacman 包安装失败"; return 1; } ;;
    esac
    log "软件包安装完成"

    # 3) fcitx5 环境补全 + 输入法列表
    wt_ensure_fcitx_env
    if command -v wowtype-config >/dev/null 2>&1; then
        log "配置 fcitx5 输入法（wowtype-config --setup）"
        wowtype-config --setup --yes 2>&1 || warn "自动设置未成功，可在「WowType 设置」第一页点「一键设置」"
    else
        warn "未找到 wowtype-config，请在「Fcitx 5 配置」里手动添加 WowType"
    fi

    # 4) 若 fcitx5 在跑，提醒重启生效
    echo
    echo -e "${DT_GREEN}${DT_BOLD}✅ WowType 安装完成！${DT_NC}"
    if wt_fcitx_running; then
        echo -e "  ${DT_YELLOW}重启 fcitx5 生效：${DT_NC}${DT_CYAN}fcitx5 -r${DT_NC}，然后按 Ctrl+空格 切换输入法，打 nihao 试试。"
    else
        echo -e "  ${DT_YELLOW}启动 fcitx5 后生效：${DT_NC}${DT_CYAN}fcitx5 -d${DT_NC}，再按 Ctrl+空格 切换。"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
wt_status() {
    echo -e "${DT_BOLD}═══ WowType 状态 ═══${DT_NC}"
    local ver
    ver=$(wt_installed_version)
    if [ -n "$ver" ]; then
        log "软件包：已安装（wowtype $ver）"
    else
        warn "软件包：未安装"
    fi
    if wt_fcitx_running; then
        log "fcitx5：运行中（$(pgrep -x fcitx5 | head -1)）"
    else
        warn "fcitx5：未运行"
    fi
    if wt_autostart_ok; then log "fcitx5 自启动：已配置"; else warn "fcitx5 自启动：未配置"; fi
    if wt_env_ok; then log "fcitx 环境变量：已配置"; else warn "fcitx 环境变量：未配置"; fi
    if wt_im_configured; then log "输入法列表：已包含 WowType（默认）"; else warn "输入法列表：未配置 WowType"; fi
    log "下载镜像策略：${DT_MIRROR:-auto}"
}

# ---------------------------------------------------------------------------
# 体检 + 一键修复
# ---------------------------------------------------------------------------
wt_doctor() {
    local n=0 fail=0 warn=0
    local -a fixes=()
    ok()  { n=$((n+1)); echo -e "  ${DT_GREEN}✔${DT_NC} $*"; }
    bad() { n=$((n+1)); fail=$((fail+1)); echo -e "  ${DT_RED}✘${DT_NC} $*"; }
    wrn() { n=$((n+1)); warn=$((warn+1)); echo -e "  ${DT_YELLOW}⚠${DT_NC} $*"; }

    echo -e "${DT_BOLD}═══ WowType 体检 ═══${DT_NC}"
    local ver
    ver=$(wt_installed_version)
    if [ -n "$ver" ]; then ok "软件包已安装（wowtype $ver）"; else bad "软件包未安装（可修复：install）"; fixes+=(wt_install); fi
    if wt_fcitx_running; then ok "fcitx5 运行中"; else bad "fcitx5 未运行（可修复：启动）"; fixes+=(wt_start_fcitx); fi
    if wt_autostart_ok; then ok "fcitx5 自启动已配置"; else bad "fcitx5 自启动未配置（可修复）"; fixes+=(wt_ensure_fcitx_env); fi
    if wt_env_ok; then ok "fcitx 环境变量已配置"; else bad "fcitx 环境变量未配置（可修复）"; fixes+=(wt_ensure_fcitx_env); fi
    if wt_im_configured; then ok "输入法列表已含 WowType"; else bad "输入法未设为 WowType（可修复：setup）"; fixes+=(wt_setup_im); fi

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

wt_start_fcitx() {
    if command -v fcitx5 >/dev/null 2>&1; then
        fcitx5 -d 2>/dev/null && { log "fcitx5 已启动"; return 0; }
    fi
    warn "启动 fcitx5 失败"
    return 1
}

wt_setup_im() {
    if command -v wowtype-config >/dev/null 2>&1; then
        wowtype-config --setup --yes 2>&1 && { log "fcitx5 输入法已配置"; return 0; }
    fi
    warn "自动配置失败，可在「WowType 设置」第一页点「一键设置」"
    return 1
}

# ---------------------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------------------
wt_remove() {
    local ver
    ver=$(wt_installed_version)
    if [ -z "$ver" ]; then
        warn "未检测到已安装的 WowType"
        return 0
    fi
    if ! dt_confirm "确认卸载 WowType（wowtype $ver）？"; then
        return 0
    fi
    case "$WT_MANAGER:-" in
        dnf) sudo dnf remove -y wowtype ;;
        apt-get) sudo apt-get remove -y wowtype ;;
        pacman) sudo pacman -R --noconfirm wowtype ;;
        *) sudo dnf remove -y wowtype 2>/dev/null || sudo apt-get remove -y wowtype ;;
    esac && log "已卸载" || warn "卸载未完全成功"
    if wt_im_configured; then
        warn "fcitx5 输入法列表仍含 WowType，可在「Fcitx 5 配置」移除"
    fi
}

# ---------------------------------------------------------------------------
# 菜单 / 分发
# ---------------------------------------------------------------------------
wt_menu() {
    while true; do
        local c
        c=$(dt_menu "WowType 输入法" "fcitx5 输入法插件，镜像下载 + 校验 + fcitx5 配置：" \
            "install|安装 / 更新|下载 + 校验 + 包管理器安装 + fcitx5 设置（需 sudo）" \
            "status|查看状态|包/fcitx5/自启动/环境变量/输入法" \
            "doctor|体检修复|一键检测并修复常见问题" \
            "remove|卸载|删除软件包（保留 fcitx5）" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            install) wt_install ;;
            status) wt_status ;;
            doctor) wt_doctor ;;
            remove) wt_remove ;;
        esac
        echo
    done
}

case "${1:-}" in
    "")      wt_menu ;;
    install) wt_install ;;
    status)  wt_status ;;
    doctor)  wt_doctor ;;
    remove)  wt_remove ;;
    -h|--help|help)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) err "未知参数：$1（--help 查看用法）"; exit 2 ;;
esac
