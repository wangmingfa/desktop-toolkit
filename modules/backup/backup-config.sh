#!/usr/bin/env bash
# =============================================================================
# backup-config.sh —— 配置备份 / 恢复（无需 sudo）
#
# 把常用配置（fcitx5 / uuremote / niri / git / shell / environment.d）打包到
# ~/backups/，可列出、恢复、按数量清理。只处理用户级文件，不碰系统配置。
#
# 用法: bash backup-config.sh         菜单
#       bash backup-config.sh backup  创建备份（带时间戳）
#       bash backup-config.sh list    列出所有备份
#       bash backup-config.sh restore <文件>   恢复指定备份（先确认）
#       bash backup-config.sh prune [N]       只保留最近 N 份（默认 10）
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'; DT_CYAN=$'\033[0;36m'
    DT_RED=$'\033[0;31m';   DT_BOLD=$'\033[1m';       DT_NC=$'\033[0m'
else
    DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_BOLD=""; DT_NC=""
fi

log() { echo -e "  ${DT_CYAN}[backup]${DT_NC} $*"; }
warn() { echo -e "  ${DT_YELLOW}[backup] 注意:${DT_NC} $*" >&2; }
err() { echo -e "  ${DT_RED}[backup] 错误:${DT_NC} $*" >&2; }

BK_DIR="$HOME/backups"
BK_PREFIX="config"

# 要备份的用户级配置（存在才收）
bk_sources() {
    local -a items=()
    for p in \
        "$HOME/.config/fcitx5" \
        "$HOME/.config/uuremote" \
        "$HOME/.config/niri" \
        "$HOME/.config/environment.d" \
        "$HOME/.config/autostart" \
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
        "$HOME/.gitconfig" "$HOME/.git-credentials"; do
        [ -e "$p" ] && items+=("$p")
    done
    printf '%s\n' "${items[@]}"
}

# ---------------------------------------------------------------------------
# 创建备份
# ---------------------------------------------------------------------------
bk_create() {
    mkdir -p "$BK_DIR"
    local -a items
    mapfile -t items < <(bk_sources)
    if [ "${#items[@]}" -eq 0 ]; then
        warn "没有可备份的配置"
        return 1
    fi
    local stamp file
    stamp=$(date +%Y%m%d-%H%M%S)
    file="$BK_DIR/${BK_PREFIX}-${stamp}.tar.gz"

    # 用 --transform 去掉绝对路径前缀，保留相对结构（~/.config/... -> .config/...）
    log "备份 ${#items[@]} 项配置 → $file"
    if tar czf "$file" --transform 's|^'"$HOME"'/||' "${items[@]}" 2>/dev/null; then
        log "完成：$(du -h "$file" | awk '{print $1}')"
        return 0
    fi
    err "备份失败"
    return 1
}

# ---------------------------------------------------------------------------
# 列出备份
# ---------------------------------------------------------------------------
bk_list() {
    echo -e "${DT_BOLD}═══ 备份列表（$BK_DIR）═══${DT_NC}"
    local -a files
    mapfile -t files < <(ls -1t "$BK_DIR"/${BK_PREFIX}-*.tar.gz 2>/dev/null || true)
    if [ "${#files[@]}" -eq 0 ]; then
        warn "暂无备份。运行 backup 创建。"
        return 0
    fi
    local i f size
    i=1
    for f in "${files[@]}"; do
        size=$(du -h "$f" 2>/dev/null | awk '{print $1}')
        log "[$i] $(basename "$f")（${size}）"
        i=$((i+1))
    done
    log "共 ${#files[@]} 份"
}

# ---------------------------------------------------------------------------
# 恢复
# ---------------------------------------------------------------------------
bk_restore() {
    local file="$1"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        # 交互式：列出并选一份
        local -a files
        mapfile -t files < <(ls -1t "$BK_DIR"/${BK_PREFIX}-*.tar.gz 2>/dev/null || true)
        [ "${#files[@]}" -eq 0 ] && { warn "无备份可恢复"; return 1; }
        local -a rows=()
        local f i=1
        for f in "${files[@]}"; do
            rows+=("$(basename "$f")|[$i] $(basename "$f")")
            i=$((i+1))
        done
        local c
        c=$(dt_menu "恢复配置" "选择要恢复的备份：" "${rows[@]}" "back|← 取消|") || return 1
        [ "$c" = back ] && return 1
        file="$BK_DIR/$c"
    fi
    if ! dt_confirm "恢复会覆盖当前配置，确认从 $(basename "$file") 恢复？"; then
        return 1
    fi
    log "解压 ${file} 到 $HOME ..."
    if tar xzf "$file" -C "$HOME" 2>/dev/null; then
        log "恢复完成。建议重启相关服务（fcitx5 -r / systemctl --user restart ...）或注销重登。"
        return 0
    fi
    err "恢复失败"
    return 1
}

# ---------------------------------------------------------------------------
# 清理：只保留最近 N 份
# ---------------------------------------------------------------------------
bk_prune() {
    local keep="${1:-10}"
    local -a files
    mapfile -t files < <(ls -1t "$BK_DIR"/${BK_PREFIX}-*.tar.gz 2>/dev/null || true)
    if [ "${#files[@]}" -le "$keep" ]; then
        log "现有 ${#files[@]} 份，无需清理（保留 $keep）"
        return 0
    fi
    local -a old=("${files[@]:$keep}")
    if ! dt_confirm "删除 ${#old[@]} 份旧备份，保留最近 $keep 份？"; then
        return 1
    fi
    local f
    for f in "${old[@]}"; do rm -f "$f" && log "已删 $(basename "$f")"; done
    log "清理完成"
}

# ---------------------------------------------------------------------------
# 菜单 / 分发
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 定时备份（systemd 用户 timer）
# ---------------------------------------------------------------------------
bk_timer_setup() { # <daily|hourly|weekly>
    local when="$1"
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"
    cat > "$unit_dir/backup-config.service" <<EOF
[Unit]
Description=Backup user configs (desktop-toolkit)
[Service]
Type=oneshot
ExecStart=$DT_ROOT/modules/backup/backup-config.sh backup
EOF
    cat > "$unit_dir/backup-config.timer" <<EOF
[Unit]
Description=Backup user configs ${when}
[Timer]
OnCalendar=${when}
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now backup-config.timer
    log "已开启定时备份（${when}）"
}

bk_timer_disable() {
    systemctl --user disable --now backup-config.timer 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/backup-config.service" \
          "$HOME/.config/systemd/user/backup-config.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    log "已关闭定时备份"
}

bk_timer_status() {
    if systemctl --user is-enabled backup-config.timer >/dev/null 2>&1; then
        echo -e "  ${DT_GREEN}✅${DT_NC} 定时备份 timer 已启用"
        systemctl --user list-timers backup-config.timer --no-pager 2>/dev/null \
            | tail -2 | head -1 | sed 's/^/  /'
    else
        echo -e "  ${DT_YELLOW}❌${DT_NC} 定时备份 timer 未启用"
    fi
}

bk_menu_timer() {
    while true; do
        local c
        c=$(dt_menu "定时备份" "systemd 用户 timer 自动备份配置到 ~/backups：" \
            "hourly|1. 每小时|OnCalendar=hourly" \
            "daily|2. 每天|OnCalendar=daily（推荐）" \
            "weekly|3. 每周|OnCalendar=weekly" \
            "off|4. 关闭定时备份|停 timer + 删单元" \
            "status|5. 状态|timer 启用情况" \
            "back|← 返回|") || return 0
        case "$c" in
            hourly) bk_timer_setup hourly ;;
            daily) bk_timer_setup daily ;;
            weekly) bk_timer_setup weekly ;;
            off) bk_timer_disable ;;
            status) bk_timer_status ;;
            __quit) exit 0 ;;
            back) return 0 ;;
        esac
    done
}

bk_menu() {
    while true; do
        local c
        c=$(dt_menu "配置备份 / 恢复" "用户级配置打包备份（无需 sudo）：" \
            "backup|1. 创建备份|打包 fcitx5/uuremote/niri/git 等配置" \
            "list|2. 列出备份|显示 ~/backups 下的备份" \
            "restore|3. 恢复|选择备份并覆盖还原" \
            "prune|4. 清理旧备份|只保留最近 N 份（默认 10）" \
            "timer|5. 定时备份|systemd timer 自动备份（每小时/每天/每周）" \
            "back|← 返回|") || return 0
        case "$c" in
            __quit) exit 0 ;;
            back) return 0 ;;
            backup) bk_create ;;
            list) bk_list ;;
            restore) bk_restore "" ;;
            prune) bk_prune ;;
            timer) bk_menu_timer ;;
        esac
        echo
    done
}

case "${1:-}" in
    "")      bk_menu ;;
    backup)  bk_create ;;
    list)    bk_list ;;
    restore) bk_restore "${2:-}" ;;
    prune)   bk_prune "${2:-10}" ;;
    -h|--help|help)
        sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) err "未知参数：$1（--help 查看用法）"; exit 2 ;;
esac
