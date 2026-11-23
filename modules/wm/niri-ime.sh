#!/usr/bin/env bash
# =============================================================================
# niri-ime.sh —— niri 下的输入法（fcitx5 + 拼音）一键配置
#
# 背景: 装完 niri+Noctalia 后发现按 Ctrl+空格切不出中文 —— 通常不是键位问题，
#       而是 niri 根本不认识这套配置里的注释/节点导致整个 config.kdl 没加载
#       （详见 AGENTS §9.3：`#` 注释无效、没有 autostart{} 节点）。
#       另外 niri 不跑 XDG autostart，fcitx5 必须由 niri 的 spawn-at-startup 拉起，
#       且环境变量要走 niri 的 environment{}（不是 ~/.bashrc）。
#
# 本脚本做四件事（幂等）:
#   1. 安装 fcitx5 + 拼音引擎 + GTK/Qt 前端（发行版感知，需要 sudo）
#   2. 写 ~/.config/fcitx5/profile 启用拼音（保留已有配置）
#   3. 生成 ~/.config/niri/ime.kdl（environment + spawn-at-startup fcitx5）
#      并给 config.kdl 加 `include optional=true "ime.kdl"`（awk -v，幂等）
#   4. 校验 + 热重载 + 启动 fcitx5
#
# 用法:
#   bash niri-ime.sh              # 一键安装+配置
#   bash niri-ime.sh status       # 查看 fcitx5 / 环境 / 配置状态
#   bash niri-ime.sh remove       # 停 fcitx5、撤掉 ime.kdl 与 include
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
source "$DT_ROOT/lib/niri.sh"   # niri_kdl_sanitize / niri_validate_cfg / niri_reload_config

log() { echo "  [niri-ime] $*"; }
err() { echo "  [niri-ime] 错误: $*" >&2; }

IME_NCONF="$HOME/.config/niri/ime.kdl"
IME_MAIN="$HOME/.config/niri/config.kdl"
IME_INCLUDE='include optional=true "ime.kdl"'
IME_PROFILE="$HOME/.config/fcitx5/profile"
IME_PKGS_DNF="fcitx5 fcitx5-chinese-addons fcitx5-gtk4 fcitx5-qt6 fcitx5-configtool"
IME_PKGS_APT="fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk4 fcitx5-frontend-qt6 fcitx5-config-qt"
IME_PKGS_PACMAN="fcitx5 fcitx5-chinese-addons fcitx5-gtk fcitx5-qt fcitx5-configtool"

ime_distro() {
    local id=""
    . /etc/os-release 2>/dev/null || true
    id="${ID:-}"
    case "$id" in
        fedora|rhel|centos|rocky|almalinux) echo fedora ;;
        ubuntu) echo ubuntu ;;
        debian|linuxmint|pop) echo debian ;;
        arch|manjaro|endeavouros|cachyos|garuda) echo arch ;;
        *) echo other ;;
    esac
}

ime_pkgs() {
    case "$(ime_distro)" in
        fedora) echo "$IME_PKGS_DNF" ;;
        ubuntu|debian) echo "$IME_PKGS_APT" ;;
        arch) echo "$IME_PKGS_PACMAN" ;;
        *) echo "" ;;
    esac
}

ime_fcitx_running() { pgrep -x fcitx5 >/dev/null 2>&1; }
ime_installed() { command -v fcitx5 >/dev/null 2>&1; }

# 安装 fcitx5 + 拼音 + 前端（发行版感知）
ime_install_pkgs() {
    local pkgs
    pkgs=$(ime_pkgs)
    if [ -z "$pkgs" ]; then
        err "不支持的发行版（$(ime_distro)）。请手动安装 fcitx5 与拼音引擎，例如:"
        err "  sudo dnf install $IME_PKGS_DNF"
        return 1
    fi
    if ime_installed; then
        log "fcitx5 已安装，跳过安装"
        # 拼音引擎可能没装全，补齐一下（幂等）
        case "$(ime_distro)" in
            fedora) sudo dnf install -y $pkgs 2>/dev/null || true ;;
            arch)   sudo pacman -S --needed --noconfirm $pkgs 2>/dev/null || true ;;
            *)      sudo apt-get install -y $pkgs 2>/dev/null || true ;;
        esac
        return 0
    fi
    echo "==> 安装 fcitx5 + 拼音引擎 + GTK/Qt 前端（需要 sudo 密码）…"
    case "$(ime_distro)" in
        fedora) sudo dnf install -y $pkgs ;;
        arch)   sudo pacman -S --needed --noconfirm $pkgs ;;
        ubuntu|debian)
            sudo apt-get update || true
            sudo apt-get install -y $pkgs ;;
        *) return 1 ;;
    esac
    if ! ime_installed; then
        err "fcitx5 仍未安装成功。可手动: sudo dnf install $IME_PKGS_DNF"
        return 1
    fi
    log "fcitx5 安装完成"
}

# 在 fcitx5 profile 里启用拼音（保留已有分组；没有 profile 就写默认+拼音）
ime_ensure_profile() {
    mkdir -p "$(dirname "$IME_PROFILE")"
    if [ ! -f "$IME_PROFILE" ]; then
        cat > "$IME_PROFILE" <<'EOF'
[Groups/0]
Name=默认
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=默认
EOF
        log "已写 $IME_PROFILE（keyboard-us + pinyin）"
        return 0
    fi
    # 已有 profile：若 group 0 还没拼音就追加（保留用户其它输入法）
    if ! grep -q '^Name=pinyin$' "$IME_PROFILE"; then
        local n
        n=$(grep -c '^Name=' "$IME_PROFILE" || true)
        cat >> "$IME_PROFILE" <<EOF

[Groups/0/Items/${n}]
Name=pinyin
Layout=
EOF
        log "已在 $IME_PROFILE 追加 pinyin"
    else
        log "pinyin 已在 fcitx5 配置里"
    fi
}

# 生成 ime.kdl + 在 config.kdl 里加 include
ime_ensure_config() {
    mkdir -p "$HOME/.config/niri"
    if [ ! -f "$IME_NCONF" ] || ! grep -q 'spawn-at-startup "fcitx5"' "$IME_NCONF"; then
        cat > "$IME_NCONF" <<'EOF'
// desktop-toolkit (niri-ime.sh) 生成
// 输入法(中文/日文/韩文等)的 fcitx5 环境 + 自启动。
// 修改后执行 `niri msg action load-config-file` 即时生效；已开的程序需重开才继承环境。
// 回退: 删掉 config.kdl 里的 `include optional=true "ime.kdl"` 与本文件即可。

environment {
    GTK_IM_MODULE "fcitx";
    QT_IM_MODULE "fcitx";
    XMODIFIERS "@im=fcitx";
    SDL_IM_MODULE "fcitx";
    GLFW_IM_MODULE "fcitx";
}

spawn-at-startup "fcitx5"
EOF
        log "已写 $IME_NCONF"
    fi
    # include 幂等（awk -v，别把含双引号的行拼进 awk 程序）
    if [ -f "$IME_MAIN" ]; then
        if ! grep -qxF "$IME_INCLUDE" "$IME_MAIN"; then
            awk -v inc="$IME_INCLUDE" 'BEGIN{n=0} $0==inc{n++} {print} END{if(n==0) print inc}' "$IME_MAIN" \
                > "$IME_MAIN.tmp" && mv "$IME_MAIN.tmp" "$IME_MAIN"
            log "已把 include 加进 $IME_MAIN"
        fi
    else
        echo "$IME_INCLUDE" > "$IME_MAIN"
        log "已创建 $IME_MAIN"
    fi
    # 洗一遍（# → //、autostart{} → spawn-at-startup），并校验
    niri_kdl_sanitize "$IME_NCONF"
    if [ -f "$IME_MAIN" ]; then niri_kdl_sanitize "$IME_MAIN"; fi
    if ! niri_validate_cfg "$IME_MAIN"; then
        err "niri 配置校验失败，未改配置回滚："
        # 回滚 include（避免把坏配置留在用户机器上）
        if [ -f "$IME_MAIN" ]; then
            awk -v inc="$IME_INCLUDE" '$0==inc{next} {print}' "$IME_MAIN" > "$IME_MAIN.tmp" \
                && mv "$IME_MAIN.tmp" "$IME_MAIN"
        fi
        return 1
    fi
    log "niri 配置校验通过"
}

# 热重载 + 启动 fcitx5
ime_apply() {
    niri_reload_config && log "已触发热重载（niri msg action load-config-file）" \
        || log "未能在本会话热重载（可能不在 niri 会话里）；重新登录即可生效"
    if ! ime_fcitx_running; then
        # 优先让 niri 拉起（继承 environment{}），失败则直接后台起
        if command -v niri >/dev/null 2>&1 \
            && timeout 5 niri msg action spawn "fcitx5" >/dev/null 2>&1; then
            log "已通过 niri 启动 fcitx5"
        else
            setsid fcitx5 -d >/dev/null 2>&1 || true
            sleep 1
            ime_fcitx_running && log "已启动 fcitx5（后台）" || warn_none
        fi
    else
        log "fcitx5 已在运行"
    fi
}

warn_none() {
    echo "  [niri-ime] 警告: fcitx5 启动未确认，可手动: fcitx5 -d"
}

ime_status() {
    local d
    d=$(ime_distro)
    echo "发行版: $d      fcitx5: $(ime_installed && echo 已装 || echo 未装)"
    if ime_fcitx_running; then
        log "fcitx5 运行中"
    else
        echo "  [niri-ime] 警告: fcitx5 未运行"
    fi
    grep -q '^Name=pinyin$' "$IME_PROFILE" 2>/dev/null \
        && log "fcitx5 profile 含 pinyin" \
        || echo "  [niri-ime] 警告: profile 里没有 pinyin"
    [ -f "$IME_NCONF" ] && grep -q 'spawn-at-startup "fcitx5"' "$IME_NCONF" \
        && log "ime.kdl 已生成（含 spawn-at-startup fcitx5）" \
        || echo "  [niri-ime] 警告: 缺少 ime.kdl"
    [ -f "$IME_MAIN" ] && grep -qxF "$IME_INCLUDE" "$IME_MAIN" \
        && log "config.kdl 已 include ime.kdl" \
        || echo "  [niri-ime] 警告: config.kdl 未 include ime.kdl"
}

ime_remove() {
    if ime_fcitx_running; then
        pkill -x fcitx5 2>/dev/null || true
        log "已停止 fcitx5"
    fi
    if [ -f "$IME_MAIN" ]; then
        awk -v inc="$IME_INCLUDE" '$0==inc{next} {print}' "$IME_MAIN" > "$IME_MAIN.tmp" \
            && mv "$IME_MAIN.tmp" "$IME_MAIN"
        log "已从 config.kdl 移除 include ime.kdl"
    fi
    rm -f "$IME_NCONF" && log "已删除 $IME_NCONF"
    niri_reload_config >/dev/null 2>&1 || true
    echo "  完成。fcitx5 及其环境变量不再由 niri 管理（包本身保留）。"
}

ime_setup() {
    echo "══════════════════════════════════════════"
    echo " 配置 niri 输入法（fcitx5 + 拼音）"
    echo "══════════════════════════════════════════"
    ime_install_pkgs || return 1
    ime_ensure_profile
    ime_ensure_config || return 1
    ime_apply
    echo
    echo "  ✅ 完成！现在："
    echo "    1) 重新打开终端/应用（继承 GTK_IM_MODULE 等环境）"
    echo "    2) Ctrl+空格 切换中/英（拼音）"
    echo "    3) 想调输入法: fcitx5-configtool"
}

ime_menu() {
    while true; do
        local c
        c=$(dt_menu "niri 输入法（fcitx5）" \
            "发行版: $(ime_distro)｜fcitx5: $(ime_installed && echo 已装 || echo 未装)｜运行: $(ime_fcitx_running && echo 是 || echo 否)" \
            "setup|1. 安装并配置 fcitx5 + 拼音|安装包 + 写 profile + 生成 ime.kdl + 热重载" \
            "status|2. 查看状态|fcitx5 / 环境变量 / config include" \
            "remove|3. 移除 niri 侧配置|停 fcitx5、撤 ime.kdl（保留包）" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            setup) ime_setup || true ;;
            status) ime_status ;;
            remove) ime_remove || true ;;
        esac
    done
}

case "${1:-menu}" in
    menu) ime_menu ;;
    setup) ime_setup || exit 1 ;;
    status) ime_status ;;
    remove) ime_remove ;;
    *) echo "用法: bash niri-ime.sh [menu|setup|status|remove]" >&2; exit 1 ;;
esac
