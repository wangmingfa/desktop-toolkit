#!/usr/bin/env bash
# =============================================================================
# niri-ime.sh —— niri 下的输入法一键配置（fcitx5 或 IBus，默认 fcitx5）
#
# 背景: 装完 niri+Noctalia 后发现按 Ctrl+空格切不出中文 —— 通常不是键位问题，
#       而是 niri 根本不认识这套配置里的注释/节点导致整个 config.kdl 没加载
#       （详见 AGENTS §9.3：`#` 注释无效、没有 autostart{} 节点）。
#       另外 niri 不跑 XDG autostart，输入法必须由 niri 的 spawn-at-startup 拉起，
#       且环境变量要走 niri 的 environment{}（不是 ~/.bashrc）。
#
# 用法:
#   bash niri-ime.sh                      # fcitx5 一键安装+配置
#   bash niri-ime.sh --ime ibus           # 用系统已有的 IBus（不装 fcitx5）
#   bash niri-ime.sh status               # 查看输入法 / 环境 / 配置状态
#   bash niri-ime.sh remove               # 停输入法、撤掉 ime.kdl 与 include
# =============================================================================
set -euo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
source "$DT_ROOT/lib/niri.sh"   # niri_kdl_sanitize / niri_validate_cfg / niri_reload_config

log() { echo "  [niri-ime] $*"; }
err() { echo "  [niri-ime] 错误: $*" >&2; }

# ---------------------------------------------------------------------------
# 配置参数（--ime ibus|fcitx5）
# ---------------------------------------------------------------------------
IME_IM="${NIRI_IME:-fcitx5}"          # fcitx5 | ibus
IME_NCONF="$HOME/.config/niri/ime.kdl"
IME_MAIN="$HOME/.config/niri/config.kdl"
IME_INCLUDE='include optional=true "ime.kdl"'
IME_PROFILE="$HOME/.config/fcitx5/profile"

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

# ---- 各后端的包 / 环境 / 自启命令 / 引擎启用 ----
ime_backend_pkgs() {
    case "$IME_IM" in
        ibus)
            case "$(ime_distro)" in
                fedora) echo "ibus ibus-libpinyin ibus-gtk3 ibus-qt ibus-setup" ;;
                arch)   echo "ibus ibus-libpinyin ibus-gtk ibus-qt" ;;
                *)      echo "ibus ibus-libpinyin ibus-gtk3 ibus-qt4" ;;
            esac ;;
        *)  # fcitx5
            case "$(ime_distro)" in
                fedora) echo "fcitx5 fcitx5-chinese-addons fcitx5-gtk4 fcitx5-qt6 fcitx5-configtool" ;;
                arch)   echo "fcitx5 fcitx5-chinese-addons fcitx5-gtk fcitx5-qt fcitx5-configtool" ;;
                *)      echo "fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk4 fcitx5-frontend-qt6 fcitx5-config-qt" ;;
            esac ;;
    esac
}

ime_backend_env() {
    if [ "$IME_IM" = ibus ]; then
        cat <<'EOF'
environment {
    GTK_IM_MODULE "ibus";
    QT_IM_MODULE "ibus";
    XMODIFIERS "@im=ibus";
    SDL_IM_MODULE "ibus";
    GLFW_IM_MODULE "ibus";
}
EOF
    else
        cat <<'EOF'
environment {
    GTK_IM_MODULE "fcitx";
    QT_IM_MODULE "fcitx";
    XMODIFIERS "@im=fcitx";
    SDL_IM_MODULE "fcitx";
    GLFW_IM_MODULE "fcitx";
}
EOF
    fi
}

ime_backend_spawn() {
    if [ "$IME_IM" = ibus ]; then
        echo 'spawn-at-startup "ibus-daemon" "-dr"'
    else
        echo 'spawn-at-startup "fcitx5"'
    fi
}

ime_backend_bin() { [ "$IME_IM" = ibus ] && echo ibus-daemon || echo fcitx5; }
ime_backend_running() { [ "$IME_IM" = ibus ] && pgrep -x ibus-daemon >/dev/null 2>&1 || pgrep -x fcitx5 >/dev/null 2>&1; }

# 启用具体引擎（fcitx5 写 profile；ibus 设 preload-engines）
ime_backend_enable() {
    if [ "$IME_IM" = ibus ]; then
        if gsettings set org.freedesktop.ibus.general preload-engines "['libpinyin']" 2>/dev/null; then
            gsettings set org.freedesktop.ibus.general engines-order "['libpinyin']" 2>/dev/null || true
            log "IBus 已启用 libpinyin 引擎（preload-engines）"
        else
            log "无法写 IBus gsettings（无 schema？），请手动 ibus-setup 启用 libpinyin"
        fi
    else
        ime_fcitx_profile
    fi
}

# ---------------------------------------------------------------------------
# 安装（发行版感知；IBus 若已装则跳过）
# ---------------------------------------------------------------------------
ime_installed() {
    command -v "$(ime_backend_bin)" >/dev/null 2>&1
}

ime_install_pkgs() {
    local pkgs bin
    pkgs=$(ime_backend_pkgs)
    bin=$(ime_backend_bin)
    [ -n "$pkgs" ] || { err "不支持的发行版（$(ime_distro)）"; return 1; }
    if command -v "$bin" >/dev/null 2>&1; then
        log "$bin 已安装，跳过（补装缺的引擎/前端，幂等）"
        case "$(ime_distro)" in
            fedora) sudo dnf install -y $pkgs 2>/dev/null || true ;;
            arch)   sudo pacman -S --needed --noconfirm $pkgs 2>/dev/null || true ;;
            *)      sudo apt-get install -y $pkgs 2>/dev/null || true ;;
        esac
        return 0
    fi
    echo "==> 安装输入法依赖（需要 sudo 密码）：$pkgs"
    case "$(ime_distro)" in
        fedora) sudo dnf install -y $pkgs ;;
        arch)   sudo pacman -S --needed --noconfirm $pkgs ;;
        ubuntu|debian)
            sudo apt-get update || true
            sudo apt-get install -y $pkgs ;;
        *) return 1 ;;
    esac
    command -v "$bin" >/dev/null 2>&1 || { err "$bin 仍未安装成功"; return 1; }
    log "$bin 安装完成"
}

# ---------------------------------------------------------------------------
# fcitx5 profile（仅 fcitx5 后端用）
# ---------------------------------------------------------------------------
ime_fcitx_profile() {
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
    if ! grep -q '^Name=pinyin$' "$IME_PROFILE"; then
        local n
        n=$(grep -c '^Name=' "$IME_PROFILE" || true)
        cat >> "$IME_PROFILE" <<EOF

[Groups/0/Items/${n}]
Name=pinyin
Layout=
EOF
        log "已在 $IME_PROFILE 追加 pinyin"
    fi
}

# ---------------------------------------------------------------------------
# 生成 ime.kdl + 在 config.kdl 里加 include
# ---------------------------------------------------------------------------
ime_ensure_config() {
    mkdir -p "$HOME/.config/niri"
    if [ ! -f "$IME_NCONF" ] || ! grep -q "$(ime_backend_spawn)" "$IME_NCONF" 2>/dev/null; then
        {
            printf '// desktop-toolkit (niri-ime.sh) 生成\n'
            printf '// 输入法(中文/日文/韩文等) —— 后端: %s。\n' "$IME_IM"
            printf '// 修改后执行 `niri msg action load-config-file` 即时生效；已开的程序需重开才继承环境。\n'
            printf '// 回退: 删掉 config.kdl 里的 `include optional=true "ime.kdl"` 与本文件即可。\n\n'
            ime_backend_env
            echo
            ime_backend_spawn
        } > "$IME_NCONF"
        log "已写 $IME_NCONF（后端 $IME_IM）"
    fi
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
    niri_kdl_sanitize "$IME_NCONF"
    [ -f "$IME_MAIN" ] && niri_kdl_sanitize "$IME_MAIN"
    if ! niri_validate_cfg "$IME_MAIN"; then
        err "niri 配置校验失败，回滚 include"
        awk -v inc="$IME_INCLUDE" '$0==inc{next} {print}' "$IME_MAIN" > "$IME_MAIN.tmp" \
            && mv "$IME_MAIN.tmp" "$IME_MAIN"
        return 1
    fi
    log "niri 配置校验通过"
}

# ---------------------------------------------------------------------------
# 热重载 + 启动输入法
# ---------------------------------------------------------------------------
ime_apply() {
    niri_reload_config && log "已触发热重载（niri msg action load-config-file）" \
        || log "未能在本会话热重载（可能不在 niri 会话里）；重新登录即可生效"
    local bin
    bin=$(ime_backend_bin)
    if ! ime_backend_running; then
        if command -v niri >/dev/null 2>&1 \
            && timeout 5 niri msg action spawn "$bin" >/dev/null 2>&1; then
            log "已通过 niri 启动 $bin"
        else
            if [ "$IME_IM" = ibus ]; then
                setsid ibus-daemon -dr >/dev/null 2>&1 || true
            else
                setsid fcitx5 -d >/dev/null 2>&1 || true
            fi
            sleep 1
            ime_backend_running && log "已启动 $bin（后台）" || echo "  [niri-ime] 警告: $bin 启动未确认，可手动: $bin -d"
        fi
    else
        log "$bin 已在运行"
    fi
}

ime_status() {
    local bin
    bin=$(ime_backend_bin)
    echo "发行版: $(ime_distro)      后端: $IME_IM      $bin: $(command -v "$bin" >/dev/null 2>&1 && echo 已装 || echo 未装)"
    ime_backend_running && log "$bin 运行中" || echo "  [niri-ime] 警告: $bin 未运行"
    if [ "$IME_IM" = ibus ]; then
        gsettings get org.freedesktop.ibus.general preload-engines 2>/dev/null | grep -q libpinyin \
            && log "IBus preload-engines 含 libpinyin" \
            || echo "  [niri-ime] 警告: IBus 未启用 libpinyin（ibus-setup 里启用）"
    else
        grep -q '^Name=pinyin$' "$IME_PROFILE" 2>/dev/null \
            && log "fcitx5 profile 含 pinyin" \
            || echo "  [niri-ime] 警告: profile 里没有 pinyin"
    fi
    [ -f "$IME_NCONF" ] && grep -q "$(ime_backend_spawn)" "$IME_NCONF" \
        && log "ime.kdl 已生成（$IME_IM）" || echo "  [niri-ime] 警告: 缺少 ime.kdl"
    [ -f "$IME_MAIN" ] && grep -qxF "$IME_INCLUDE" "$IME_MAIN" \
        && log "config.kdl 已 include ime.kdl" || echo "  [niri-ime] 警告: config.kdl 未 include ime.kdl"
}

ime_remove() {
    if ime_backend_running; then
        pkill -x "$(ime_backend_bin)" 2>/dev/null || true
        log "已停止 $(ime_backend_bin)"
    fi
    if [ -f "$IME_MAIN" ]; then
        awk -v inc="$IME_INCLUDE" '$0==inc{next} {print}' "$IME_MAIN" > "$IME_MAIN.tmp" \
            && mv "$IME_MAIN.tmp" "$IME_MAIN"
        log "已从 config.kdl 移除 include ime.kdl"
    fi
    rm -f "$IME_NCONF" && log "已删除 $IME_NCONF"
    niri_reload_config >/dev/null 2>&1 || true
    echo "  完成。输入法不再由 niri 管理（包本身保留）。"
}

ime_setup() {
    echo "══════════════════════════════════════════"
    echo " 配置 niri 输入法（后端: $IME_IM）"
    echo "══════════════════════════════════════════"
    ime_install_pkgs || return 1
    ime_backend_enable
    ime_ensure_config || return 1
    ime_apply
    echo
    echo "  ✅ 完成！现在："
    echo "    1) 重新打开终端/应用（继承 GTK_IM_MODULE 等环境）"
    echo "    2) Ctrl+空格 切换中/英"
    if [ "$IME_IM" = ibus ]; then
        echo "    3) 细节调整: ibus-setup"
    else
        echo "    3) 细节调整: fcitx5-configtool"
    fi
}

ime_menu() {
    while true; do
        local c
        c=$(dt_menu "niri 输入法" \
            "后端: $IME_IM｜$(ime_backend_bin): $(command -v "$(ime_backend_bin)" >/dev/null 2>&1 && echo 已装 || echo 未装)｜运行: $(ime_backend_running && echo 是 || echo 否)" \
            "setup|1. 安装并配置（$IME_IM）|装包 + 启用引擎 + 生成 ime.kdl + 热重载" \
            "ibus|2. 切换到 IBus（不装 fcitx5）|使用系统已有的 IBus(libpinyin 等)" \
            "fcitx|3. 切换到 fcitx5|拼音引擎 fcitx5-chinese-addons" \
            "status|4. 查看状态|输入法 / 环境变量 / config include" \
            "remove|5. 移除 niri 侧配置|停输入法、撤 ime.kdl（保留包）" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            setup) ime_setup || true ;;
            ibus) IME_IM=ibus; ime_setup || true ;;
            fcitx) IME_IM=fcitx5; ime_setup || true ;;
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
    --ime)
        shift
        case "${1:-}" in
            ibus|fcitx5) IME_IM="$1"; shift ;;
            *) err "--ime 需要 ibus 或 fcitx5"; exit 1 ;;
        esac
        case "${1:-setup}" in
            setup) ime_setup ;;
            status) ime_status ;;
            remove) ime_remove ;;
            menu) ime_menu ;;
            *) ime_setup ;;
        esac
        ;;
    *) echo "用法: bash niri-ime.sh [--ime ibus|fcitx5] [menu|setup|status|remove]" >&2; exit 1 ;;
esac
