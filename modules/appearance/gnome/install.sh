#!/usr/bin/env bash
# =============================================================================
# GNOME macOS 美化安装器
# 用法:
#   ./install.sh macos26   安装 macOS 26 (Tahoe 液态玻璃)
#   ./install.sh macos15   安装 macOS 15 (经典 Sequoia 风格)
#   ./install.sh           不带参数则显示用法
# 在 GNOME 桌面的终端中运行；需已装 git。
#
# 支持断点续装: 上次中断后重跑会提示"继续上次进度(默认)还是重新开始"。
# 进度记录在 $GN_SRC_DIR/.install-state-<版本>。完成或选择重新开始则清除。
# =============================================================================
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-gnome.sh"

VERSION="${1:-}"

case "$VERSION" in
    macos26|macos15) ;;
    *)
        cat <<'EOF'
用法: ./install.sh <macos26|macos15>

  macos26  安装 macOS 26 (Tahoe 液态玻璃)  -> MacTahoe-gtk-theme
  macos15  安装 macOS 15 (经典 Sequoia 风格) -> WhiteSur-gtk-theme

示例:
  ./install.sh macos26
EOF
        exit 1 ;;
esac

echo "════════════════════════════════════════════"
echo " 安装: $(gn_version_label "$VERSION")  (GNOME)"
echo "════════════════════════════════════════════"

if ! gn_is_gnome; then
    echo "警告: 当前未检测到 GNOME 会话。请确认在 GNOME 桌面的终端中运行。"
    echo "      (若已安装 gnome-shell 只是桌面未用，可忽略)"
fi

read -r GTK_REPO GTK_BRANCH GTK_THEME ICON_REPO ICON_BRANCH ICON_THEME CURSOR_REPO < <(gn_version_info "$VERSION")
GTK_DIR="$GN_SRC_DIR/$(basename "$GTK_REPO")"
ICON_DIR="$GN_SRC_DIR/$(basename "$ICON_REPO")"

# ---------------------------------------------------------------------------
# 断点续装: 状态文件记录"下一步该跑哪个步骤"。
# 每步开始时写入当前步骤号, 成功后写入 步骤号+1。某步失败(set -e 中止)时
# 文件停留在失败步骤, 下次从那里续跑。
# ---------------------------------------------------------------------------
GN_STATE_FILE="$GN_SRC_DIR/.install-state-$VERSION"

gn_step_label() {
    case "$1" in
        1) echo "安装 GTK 主题" ;;
        2) echo "安装图标主题" ;;
        3) echo "安装光标主题" ;;
        4) echo "应用主题设置 (gsettings)" ;;
        5) echo "安装 GNOME 扩展" ;;
        *) echo "" ;;
    esac
}

gn_state_next() { # -> 下一步骤号(无状态则 1)
    [ -f "$GN_STATE_FILE" ] || { echo 1; return 0; }
    local n
    n=$(sed -n 's/^next_step=//p' "$GN_STATE_FILE" | head -1)
    case "${n:-}" in
        [2-5]) echo "$n" ;;
        *) echo 1 ;;
    esac
}

gn_state_write() { # n
    printf 'version=%s\nnext_step=%s\n' "$VERSION" "$1" > "$GN_STATE_FILE"
}

gn_state_clear() {
    rm -f "$GN_STATE_FILE"
}

gn_resume_confirm() { # saved_next -> 0 继续, 1 重头
    local n="$1" label msg
    label=$(gn_step_label "$n")
    msg="检测到上次 $(gn_version_label "$VERSION") 安装进行到步骤 $n/5（$label）。\n\n是否继续上次进度？\n（选“否”则从头重新开始）"
    GUI="$(dt_detect_gui)"
    if [ "$GUI" = zenity ]; then
        zenity --question --title="继续上次安装？" --text="$msg" 2>/dev/null && return 0 || return 1
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "继续上次安装？" --yesno "$msg" 2>/dev/null && return 0 || return 1
    else
        local ans
        read -r -p "继续上次进度(步骤 $n/5: $label)? [Y/n] " ans || true
        case "${ans:-y}" in y|Y|"") return 0 ;; *) return 1 ;; esac
    fi
}

# ---------------------------------------------------------------------------
# 各步骤(函数内各自打印 [n/5] 头部)
# ---------------------------------------------------------------------------
step_gtk() {
    echo "==> [1/5] 安装 GTK 主题 ($GTK_REPO)"
    GTK_DIR=$(gn_clone "$GTK_REPO" "$GTK_BRANCH")
    # 缺 sassc 时 WhiteSur 会走 prepare_deps 的网络探测(连 iana.org),
    # 本网络下探测失败直接退出；先装好 sassc 可完全跳过探测。
    gn_ensure_deps || true
    gn_install_gtk "$GTK_DIR" -l
}

step_icons() {
    echo "==> [2/5] 安装图标主题 ($ICON_REPO)"
    ICON_DIR=$(gn_clone "$ICON_REPO" "$ICON_BRANCH")
    gn_install_icons "$ICON_DIR"
}

step_cursors() {
    echo "==> [3/5] 安装光标主题"
    gn_install_cursors "$ICON_DIR" "$CURSOR_REPO" || echo "  (光标主题可选，可稍后手动安装)"
}

step_apply() {
    echo "==> [4/5] 应用主题设置 (gsettings)"
    gn_apply "$VERSION"
}

step_ext() {
    echo "==> [5/5] 安装 GNOME 扩展 (user-themes / dash-to-dock / blur-my-shell)"
    gn_install_extensions "$VERSION"
}

run_step() { # n fn
    local n="$1" fn="$2"
    gn_state_write "$n"
    "$fn"
    gn_state_write "$((n + 1))"
}

# ---------------------------------------------------------------------------
# 断点续装提示
# ---------------------------------------------------------------------------
START_STEP=1
SAVED_NEXT=$(gn_state_next)
if [ "$SAVED_NEXT" -gt 1 ]; then
    if gn_resume_confirm "$SAVED_NEXT"; then
        START_STEP="$SAVED_NEXT"
        echo "==> 继续上次进度：从步骤 $START_STEP/5（$(gn_step_label "$START_STEP")）开始"
    else
        echo "==> 重新开始安装（清除上次进度）"
        gn_state_clear
    fi
fi

# ---------------------------------------------------------------------------
# 执行
# ---------------------------------------------------------------------------
for (( n = START_STEP; n <= 5; n++ )); do
    case "$n" in
        1) run_step 1 step_gtk ;;
        2) run_step 2 step_icons ;;
        3) run_step 3 step_cursors ;;
        4) run_step 4 step_apply ;;
        5) run_step 5 step_ext ;;
    esac
done
gn_state_clear

echo
echo "============================================================"
echo "完成！已应用 $(gn_version_label "$VERSION") 风格。"
echo "若 Shell/顶栏未变化："
echo "  1) 安装并启用 user-themes 扩展（GNOME Extensions 商店搜 'User Themes'）"
echo "  2) 在 设置->外观 里把 Shell 主题选为 $GTK_THEME"
echo "  3) 注销重登一次"
echo "手动重跑: $0 $VERSION"
echo "============================================================"
