#!/usr/bin/env bash
# =============================================================================
# Niri + Noctalia 一键配置
#   niri     : 滚动平铺 Wayland 合成器（横向无限卷轴式布局）
#   Noctalia : Wayland 桌面外壳（顶栏 / 程序坞 / 启动器 / 控制中心 / 桌面组件）
#
# 用法: bash niri-noctalia.sh [--terminal alacritty|kitty|ghostty]
#                               [--wallpaper backdrop|wallpaper|flat]
#                               [--no-systemd] [--force]
#
# 官方依据(2026-11 核过 docs.noctalia.dev 与 noctalia 5.5.0 rpm 内容):
#   * 包只装 /usr/bin/noctalia + 资源 + /usr/share/noctalia/assets/noctalia.service
#   * niri 自启: spawn-at-startup "noctalia"
#   * 服务方式: 包内 noctalia.service 需取消注释 WantedBy=niri.service
#   * blur 相关规则要求 niri >= 26.04（老版本会报配置错误）
# =============================================================================
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"
# ui.sh 提供 dt_confirm 等交互控件(含 TUI 兜底)，收尾时用来问"是否现在重启 GDM"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/ui.sh"
# niri.sh 提供 dnf 弱网兜底 / 会话文件修正 / 收尾横幅(Niri + DMS 两个方案共用)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/niri.sh"
export DT_DL_DIR="${DT_DL_DIR:-/tmp/dt-nirinoc-rpms}"

TERMINAL="alacritty"
WALLPAPER="flat"       # backdrop=毛玻璃总览壁纸 / wallpaper=常驻壁纸 / flat=纯色总览
NO_SYSTEMD=0
FORCE=0
NO_RELOAD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --terminal)    TERMINAL="${2:-alacritty}"; shift 2 ;;
        --wallpaper)   WALLPAPER="${2:-flat}"; shift 2 ;;
        --no-systemd)  NO_SYSTEMD=1; shift ;;
        --no-reload)   NO_RELOAD=1; shift ;;
        --force)       FORCE=1; shift ;;
        *) echo "用法: niri-noctalia.sh [--terminal alacritty|kitty|ghostty] [--wallpaper backdrop|wallpaper|flat] [--no-systemd] [--no-reload] [--force]" >&2; exit 1 ;;
    esac
done

log() { echo "  [niri-noctalia] $*"; }
err() { echo "  [niri-noctalia] 错误: $*" >&2; }

niri_color_init

NCFG="$HOME/.config/niri/config.kdl"
NMOD="$HOME/.config/niri/noctalia.kdl"
SVCDIR="$HOME/.config/systemd/user"

echo "══════════════════════════════════════════"
echo " 配置 Niri + Noctalia"
echo "══════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 0) 前置检查：niri 必须是合成的宿主，否则 Noctalia 无处启动
# ---------------------------------------------------------------------------
preflight() {
    if ! command -v niri >/dev/null 2>&1; then
        err "未检测到 niri。Noctalia 是桌面外壳，必须先有合成器。"
        err "请先跑: bash modules/wm/niri-dms.sh"
        err "装完 niri 后重跑本脚本即可（本脚本会自动补上外壳部分）。"
        exit 1
    fi
    mkdir -p "$HOME/.config/niri"
}

# ---------------------------------------------------------------------------
# 1) 安装包：niri 本体 + Noctalia + 终端
#    Noctalia 在 Fedora 45 默认源(5.5.0-3.fc45)，无需 COPR/PPA，下载量小
#    dnf 弱网兜底(重试/可续传下载/本地 rpm 复用)见 lib/niri.sh
# ---------------------------------------------------------------------------
install_pkgs() {
    if ! command -v noctalia >/dev/null 2>&1; then
        echo "==> 安装 Noctalia + 终端($TERMINAL)…"
        if command -v dnf >/dev/null 2>&1; then
            dnf_install_retry noctalia "$TERMINAL" \
                || dnf_install_resumable noctalia "$TERMINAL"
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm noctalia "$TERMINAL"
        else
            err "未识别的包管理器。请手动安装 noctalia，例如:"
            err "  sudo dnf install noctalia"
            return 1
        fi
    else
        log "Noctalia 已安装，跳过"
    fi
}

# ---------------------------------------------------------------------------
# 2) 生成 noctalia.kdl 模块（binds / window-rule / layer-rule / 壁纸 / blur）
#    用 include 方式接入，不直接改 config.kdl 主体，方便回退（删掉 include 行即可）
# ---------------------------------------------------------------------------
setup_module() {
    echo "==> 生成 $NMOD …"

    case "$WALLPAPER" in
        backdrop)  WP="backdrop" ;;
        wallpaper) WP="wallpaper" ;;
        *)         WP="flat" ;;
    esac

    cat > "$NMOD" <<EOF
# 由 desktop-toolkit (niri-noctalia.sh) 生成
# 修改后执行 \`niri msg action config-reload\` 即时生效
# 回退: 删掉 config.kdl 里的 \`include "noctalia.kdl"\` 与本文件即可
#
# 快捷键说明(Noctalia IPC):
#   Super+Space        启动器            Super+Shift+Comma   设置
#   Super+S            控制中心           Alt+Tab / Alt+Shift+Tab  窗口切换器
EOF

    cat >> "$NMOD" <<'EOF'

binds {
    Mod+Space        { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S            { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Shift+Comma  { spawn-sh "noctalia msg settings-toggle"; }
    # Alt+Tab / Alt+Shift+Tab：与 niri 自带的 recent-windows 冲突。
    # 想试 niri 原生窗口切换器就把下面两行删掉(本模块 include 在末尾, 会覆盖内置)。
    Alt+Tab         { spawn-sh "noctalia msg window-switcher hold"; }
    Alt+Shift+Tab   { spawn-sh "noctalia msg window-switcher hold reverse"; }
    # 音量/亮度 OSD 交给 Noctalia
    XF86AudioRaiseVolume   { spawn-sh "noctalia msg volume-up"; }
    XF86AudioLowerVolume   { spawn-sh "noctalia msg volume-down"; }
    XF86AudioMute          { spawn-sh "noctalia msg volume-mute"; }
    XF86MonBrightnessUp    { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown  { spawn-sh "noctalia msg brightness-down"; }
}

# 现代圆角；并允许 Noctalia 的通知动作与窗口激活
window-rule {
    geometry-corner-radius 20
    clip-to-geometry true
}

# Noctalia 设置窗口按浮动窗口处理（尺寸略小于 1080x920 的原值）
window-rule {
    match app-id="dev.noctalia.Noctalia"
    open-floating true
    default-column-width { fixed 1080; }
    default-window-height { fixed 920; }
}
EOF

    # ---- 壁纸 / 总览背景（三种方案三选一，官方 Niri 页） ----
    case "$WP" in
        backdrop)
            cat >> "$NMOD" <<'EOF'

# 方案1: 毛玻璃总览壁纸(Noctalia 专用 backdrop 层放进 niri 的 overview backdrop)
# 需要在 Noctalia 设置里打开 [niri/backdrop] 才会出效果
layer-rule {
    match namespace="^noctalia-backdrop"
    place-within-backdrop true
}
EOF
            ;;
        wallpaper)
            cat >> "$NMOD" <<'EOF'

# 方案2: 常驻壁纸(不随工作区滚动)。需 Noctalia 关闭 [niri/backdrop]
layer-rule {
    match namespace="^noctalia-wallpaper"
    place-within-backdrop true
}
layout {
    background-color "transparent"
}
EOF
            ;;
        *)
            cat >> "$NMOD" <<'EOF'

# 方案3: 纯色总览(最省资源, 不依赖 Noctalia 的 backdrop 设置)
# 想改颜色直接改下面这行; 方案1/2 见 Noctalia 官方 Niri 页
overview {
    backdrop-color "#26233a"
}
EOF
            ;;
    esac

    # ---- 模糊（仅 niri >= 26.04，老版本会报配置错误） ----
    NIRI_VER=$(niri --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    # niri 版本号格式: YY.MM(如 26.04 = 2026 年 4 月)。blur 规则需 >= 26.04
    if [ -z "$NIRI_VER" ]; then
        log "取不到 niri 版本，先按 blur 规则生成；若报配置错误请删掉 blur 段"
        BURST_OK=1
    else
        CURR=${NIRI_VER%.*}; NEXT=${NIRI_VER#*.}
        CURR=$((10#$CURR)); NEXT=$((10#$NEXT))
        if [ "$CURR" -gt 26 ] || { [ "$CURR" -eq 26 ] && [ "$NEXT" -ge 4 ]; }; then
            BURST_OK=1
        else
            BURST_OK=0
        fi
    fi

    if [ "$BURST_OK" = 1 ]; then
        cat >> "$NMOD" <<'EOF'

# 模糊(要求 niri >= 26.04, 实测 $(niri --version 2>/dev/null | head -1 | sed 's/^.* //'))
window-rule {
    background-effect {
        blur true
        xray false
    }
}
# Noctalia 顶栏/面板/通知坞: 关 xray 让模糊更真实
layer-rule {
    match namespace="^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"
    background-effect {
        xray false
    }
}
layer-rule {
    match namespace="noctalia-window-switcher"
    background-effect {
        blur true
        xray false
    }
}
EOF
    else
        log "niri ${NIRI_VER:-未知} 低于 26.04，跳过 blur 规则（加了会报配置错误）"
    fi

    # ---- 可选项：总览里直接输入即启动应用 ----
    cat >> "$NMOD" <<'EOF'

# 可选: 总览中直接打字即拉起启动器 / 启动后自动收起总览
# (也可在 Noctalia 设置 -> Niri -> Overview 里开, 不必改文件)
# [shell]
# niri_overview_type_to_launch_enabled = true
# niri_overview_close_on_launch_enabled = true
EOF

    # ---- 与 Noctalia 无关但推荐: 光标环境变量(供 systemd 启动的应用继承) ----
    cat >> "$NMOD" <<'EOF'

# Noctalia 若用 systemd 服务启动, 应用可能拿不到光标主题; 加这两行修好
autostart {
    commands "systemctl" "--user" "import-environment" "XCURSOR_THEME" "XCURSOR_SIZE"
}
EOF
}

# ---------------------------------------------------------------------------
# 3) 接入 config.kdl：include 模块 + 自启 + xdg 激活
#    幂等: 已存在的行不再重复追加
# ---------------------------------------------------------------------------
wire_config() {
    echo "==> 接入 $NCFG …"
    if [ ! -f "$NCFG" ]; then
        log "未发现 niri 配置，新建一个只含 Noctalia 的最小配置"
        : > "$NCFG"
    fi
    cp -a "$NCFG" "$NCFG.bak-nirinoc-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

    if [ "$FORCE" = 1 ]; then
        log "--force：先清掉旧的 Noctalia 接入行，稍后重新追加"
        sed -i -e '/^spawn-at-startup "noctalia"$/d' \
               -e '/^include "noctalia.kdl"$/d' "$NCFG" 2>/dev/null || true
    fi

    add_line() { # <行>  已存在(逐字匹配)则不重复追加
        grep -qF "$1" "$NCFG" 2>/dev/null || echo "$1" >> "$NCFG"
    }

    if ! grep -q 'honor-xdg-activation-with-invalid-serial' "$NCFG" 2>/dev/null; then
        cat >> "$NCFG" <<'EOF'

# Noctalia 需要: 允许通知动作与窗口激活
debug {
    honor-xdg-activation-with-invalid-serial
}
EOF
        log "已加 debug 块(honor-xdg-activation-with-invalid-serial)"
    fi
    add_line 'spawn-at-startup "noctalia"'
    add_line 'include "noctalia.kdl"'

    log "已接入: spawn-at-startup \"noctalia\" + include \"noctalia.kdl\"(放在末尾以覆盖内置绑定)"
}

# ---------------------------------------------------------------------------
# 4) systemd 用户服务: 比 spawn 更稳(Type=notify, 保证在 XDG autostart 之前就绪)
#    官方安装法: 拷 assets/noctalia.service -> ~/.config/systemd/user/ 并取消注释
#    对应合成器的 WantedBy。Niri 跑在 niri.service 下。
# ---------------------------------------------------------------------------
setup_service() {
    [ "$NO_SYSTEMD" = 1 ] && { log "--no-systemd 已指定，跳过 systemd 服务"; return 0; }
    local src=""
    for d in /usr/share/noctalia/assets "$HOME/.local/share/noctalia/assets" /usr/local/share/noctalia/assets; do
        [ -f "$d/noctalia.service" ] && { src="$d/noctalia.service"; break; }
    done
    if [ -z "$src" ]; then
        err "未找到 $src 候选目录里的 noctalia.service，跳过 systemd 服务（spawn 自启仍有效）"
        return 0
    fi

    local dst="$SVCDIR/noctalia.service"
    mkdir -p "$SVCDIR"
    if [ -f "$dst" ] && grep -q '^WantedBy=niri.service' "$dst" 2>/dev/null; then
        log "systemd 用户服务已配置好，跳过"
        return 0
    fi
    cp -a "$src" "$dst"
    sed -i 's/^# *\?WantedBy=niri.service/WantedBy=niri.service/' "$dst"
    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable noctalia.service 2>/dev/null; then
        log "已启用 systemd 用户服务 noctalia.service（WantedBy=niri.service）"
    else
        err "enable 失败（可手动: systemctl --user enable noctalia.service）"
        return 0
    fi
}

# ---------------------------------------------------------------------------
# 5) 应用后立即重载（若当前就在 niri 会话里）
# ---------------------------------------------------------------------------
reload_now() {
    [ "$NO_RELOAD" = 1 ] && { log "--no-reload 已指定，跳过即时重载"; return 0; }
    if [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
        log "不在 Wayland 会话里，配置将在下次登录后生效"
        return 0
    fi
    if ! command -v niri >/dev/null 2>&1; then
        return 0
    fi
    # niri 已起但 msg 通道不通时, reload 会非零返回, 用 || true 兜住
    if niri msg action config-reload 2>/dev/null; then
        log "已下发 config-reload，Noctalia 配置即时生效"
    else
        log "当前 niri 会话未就绪，配置将在下次登录后生效"
    fi
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
preflight

# 安装是前置条件：Noctalia 没装上就不该写配置，否则用户看到"完成"实则跑不起来
if ! install_pkgs; then
    echo
    echo "============================================================"
    echo "❌ Noctalia 未安装成功，已中止（未生成/未改动配置）。"
    echo "  常见原因: sudo 要密码 / 网络不通 / 版本低于 Fedora 45 无此包。"
    echo "  请手动执行后重跑本脚本:"
    echo "    sudo dnf install noctalia $TERMINAL"
    echo "============================================================"
    exit 1
fi

setup_module
wire_config
setup_service
niri_ensure_gdm_session
reload_now

# 收尾横幅 + 交互代跑"重启 GDM"见 lib/niri.sh 的 niri_finish_banner
niri_finish_banner "Niri + Noctalia 已配置。" \
    "1) 外壳自启: 已在 $NCFG 加 spawn-at-startup \"noctalia\"（systemd 服务也已启用）" \
    "2) 快捷键: Super+Space 启动器 · Super+S 控制中心 · Super+Shift+Comma 设置" \
    "3) 音量/亮度 OSD 走 Noctalia; Alt+Tab 用 Noctalia 窗口切换器(想换回原生见 noctalia.kdl 注释)" \
    "4) 壁纸/模糊想调整: 编辑 $NMOD 后跑 niri msg action config-reload" \
    "5) 日志: ~/.cache/noctalia/noctalia.log；排查层规则: niri msg layers"