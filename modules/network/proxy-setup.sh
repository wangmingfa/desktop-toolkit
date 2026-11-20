#!/usr/bin/env bash
# =============================================================================
# proxy-setup.sh — 代理一键配置
#
# 背景: 本仓库面向受限网络, 但此前对代理只有一行提示(lib/niri.sh 的
#   "HTTPS_PROXY=http://127.0.0.1:7890 重跑"), 用户每次都要手动配。
#   本脚本把 git / dnf / pip / npm / cargo 的代理一次性配好, 并写 no_proxy。
#
# 用法:  ./proxy-setup.sh on [URL] | off | status
#   on       为各工具写入代理(URL 默认 http://127.0.0.1:7890)
#   off      移除各工具代理
#   status   查看当前各工具代理状态
#
# 写入位置(每个工具可选: 未安装则跳过并提示, 不算失败):
#   git   全局 ~/.gitconfig        http.proxy / https.proxy
#   dnf   /etc/dnf/dnf.conf        proxy=(需 sudo; dnf5 只认这个, env 不过 sudo)
#   pip   ~/.config/pip/pip.conf   global.proxy + global.no_proxy
#   npm   ~/.npmrc                 proxy / https-proxy / noproxy
#   cargo ~/.cargo/config.toml     [http] proxy
#   环境  ~/.config/environment.d/dt-proxy.conf  HTTP(S)_PROXY + no_proxy
#         (git/cargo 经 libcurl 读环境变量, 写这里下次登录全局生效)
#
# 实现注意: 配置文件按行改写一律用 awk(正则与数据分离), 不用 sed 拼引号
# (AGENTS.md 9.2 铁律 2); 每项操作幂等(重跑 on 覆盖, off 全清)。
# =============================================================================
set -uo pipefail

# 默认代理与本仓库 lib/niri.sh 提示的 7890 一致; no_proxy 只排除本机
DEFAULT_URL="${DT_PROXY_URL:-http://127.0.0.1:7890}"
NO_PROXY="${DT_NO_PROXY:-localhost,127.0.0.1,::1}"

log() { echo "[proxy] $*"; }
err() { echo "[proxy] 错误: $*" >&2; }

# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------
git_set() {
    command -v git >/dev/null 2>&1 || { log "跳过 git: 未安装"; return 0; }
    git config --global http.proxy "$URL" 2>/dev/null \
        && git config --global https.proxy "$URL" 2>/dev/null \
        && log "git: http.proxy / https.proxy = $URL" \
        || { err "git 设置代理失败"; return 1; }
}
git_unset() {
    command -v git >/dev/null 2>&1 || return 0
    git config --global --unset-all http.proxy 2>/dev/null || true
    git config --global --unset-all https.proxy 2>/dev/null || true
    log "git: 已移除代理"
}

# ---------------------------------------------------------------------------
# dnf(INI 按行改写; 用 sudo 写 /etc/dnf/dnf.conf)
# ---------------------------------------------------------------------------
DNF_CONF=/etc/dnf/dnf.conf
dnf_set() {
    command -v dnf >/dev/null 2>&1 || { log "跳过 dnf: 未安装"; return 0; }
    [ -f "$DNF_CONF" ] || { err "无 $DNF_CONF(非 dnf 发行版?)"; return 1; }
    local tmp; tmp=$(mktemp)
    # 去掉旧 proxy= 行, 在 [main] 后重写一行; 无 [main] 则末尾补
    awk -v p="$URL" '
        /^proxy[[:space:]]*=/ { next }
        { print }
        /^\[main\]$/ { print "proxy=" p; ins=1 }
        END { if (!ins) print "proxy=" p }
    ' "$DNF_CONF" > "$tmp"
    if sudo install -m 644 "$tmp" "$DNF_CONF" 2>/dev/null; then
        log "dnf: $DNF_CONF proxy=$URL(需 sudo 已写入)"
    else
        err "dnf 写入 $DNF_CONF 失败(需要 sudo 密码)"
        rm -f "$tmp"; return 1
    fi
    rm -f "$tmp"
}
dnf_unset() {
    command -v dnf >/dev/null 2>&1 || return 0
    [ -f "$DNF_CONF" ] || return 0
    local tmp; tmp=$(mktemp)
    awk '/^proxy[[:space:]]*=/ { next } { print }' "$DNF_CONF" > "$tmp"
    if sudo install -m 644 "$tmp" "$DNF_CONF" 2>/dev/null; then
        log "dnf: 已移除 $DNF_CONF 的 proxy"
    else
        err "dnf 写入 $DNF_CONF 失败(需要 sudo 密码)"
    fi
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# pip(用户级 ~/.config/pip/pip.conf, 无需 sudo)
# ---------------------------------------------------------------------------
pip_set() {
    command -v pip3 >/dev/null 2>&1 || { log "跳过 pip: 未安装 pip3"; return 0; }
    pip3 config set global.proxy "$URL" 2>/dev/null \
        && pip3 config set global.no_proxy "$NO_PROXY" 2>/dev/null \
        && log "pip: global.proxy = $URL, global.no_proxy = $NO_PROXY" \
        || { err "pip 设置代理失败"; return 1; }
}
pip_unset() {
    command -v pip3 >/dev/null 2>&1 || return 0
    pip3 config unset global.proxy 2>/dev/null || true
    pip3 config unset global.no_proxy 2>/dev/null || true
    log "pip: 已移除代理"
}

# ---------------------------------------------------------------------------
# npm(用户级 ~/.npmrc, 无需 sudo)
# ---------------------------------------------------------------------------
npm_set() {
    command -v npm >/dev/null 2>&1 || { log "跳过 npm: 未安装"; return 0; }
    npm config set proxy "$URL" 2>/dev/null \
        && npm config set https-proxy "$URL" 2>/dev/null \
        && npm config set noproxy "$NO_PROXY" 2>/dev/null \
        && log "npm: proxy / https-proxy = $URL, noproxy = $NO_PROXY" \
        || { err "npm 设置代理失败"; return 1; }
}
npm_unset() {
    command -v npm >/dev/null 2>&1 || return 0
    npm config delete proxy 2>/dev/null || true
    npm config delete https-proxy 2>/dev/null || true
    npm config delete noproxy 2>/dev/null || true
    log "npm: 已移除代理"
}

# ---------------------------------------------------------------------------
# cargo(TOML ~/.cargo/config.toml; 用 awk 按行改写, 不拼引号)
# ---------------------------------------------------------------------------
CARGO_CFG="$HOME/.cargo/config.toml"
cargo_set() {
    command -v cargo >/dev/null 2>&1 || { log "跳过 cargo: 未安装"; return 0; }
    mkdir -p "$(dirname "$CARGO_CFG")"
    local tmp; tmp=$(mktemp)
    if [ -f "$CARGO_CFG" ]; then
        awk -v p="$URL" '
            /^proxy[[:space:]]*=[[:space:]]*"/ { next }
            { print }
            /^\[http\]$/ { print "proxy = \"" p "\""; ins=1 }
            END { if (!ins) { print "[http]"; print "proxy = \"" p "\"" } }
        ' "$CARGO_CFG" > "$tmp"
    else
        printf '[http]\nproxy = "%s"\n' "$URL" > "$tmp"
    fi
    if cp "$tmp" "$CARGO_CFG" 2>/dev/null; then
        log "cargo: $CARGO_CFG [http] proxy = $URL"
    else
        err "cargo 写入 $CARGO_CFG 失败"
        rm -f "$tmp"; return 1
    fi
    rm -f "$tmp"
}
cargo_unset() {
    command -v cargo >/dev/null 2>&1 || return 0
    [ -f "$CARGO_CFG" ] || return 0
    local tmp; tmp=$(mktemp)
    awk '/^proxy[[:space:]]*=[[:space:]]*"/ { next } { print }' "$CARGO_CFG" > "$tmp"
    cp "$tmp" "$CARGO_CFG" 2>/dev/null && log "cargo: 已移除代理" || err "cargo 写入失败"
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# 环境变量(下次登录对所有用户会话生效; git/cargo 经 libcurl 读这里)
# ---------------------------------------------------------------------------
ENVD="$HOME/.config/environment.d/dt-proxy.conf"
envd_set() {
    mkdir -p "$(dirname "$ENVD")"
    cat > "$ENVD" <<EOF
HTTP_PROXY=$URL
HTTPS_PROXY=$URL
http_proxy=$URL
https_proxy=$URL
NO_PROXY=$NO_PROXY
no_proxy=$NO_PROXY
EOF
    log "环境变量: $ENVD(下次登录全局生效, 当前会话请重开终端或 source)"
}
envd_unset() {
    rm -f "$ENVD" 2>/dev/null && log "环境变量: 已移除 $ENVD" || true
}

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
status() {
    echo "── 当前代理状态 ──────────────────────────"
    local s
    if command -v git >/dev/null 2>&1; then
        s=$(git config --global --get http.proxy 2>/dev/null || true)
        [ -n "$s" ] && echo "  git:    $s" || echo "  git:    (未设置)"
    else
        echo "  git:    (未安装)"
    fi
    if command -v dnf >/dev/null 2>&1; then
        s=$(awk '/^proxy[[:space:]]*=/ { print $0; exit }' "$DNF_CONF" 2>/dev/null || true)
        [ -n "$s" ] && echo "  dnf:    $s" || echo "  dnf:    (未设置)"
    else
        echo "  dnf:    (未安装)"
    fi
    if command -v pip3 >/dev/null 2>&1; then
        s=$(pip3 config get global.proxy 2>/dev/null || true)
        [ -n "$s" ] && echo "  pip:    $s" || echo "  pip:    (未设置)"
    else
        echo "  pip:    (未安装)"
    fi
    if command -v npm >/dev/null 2>&1; then
        s=$(npm config get proxy 2>/dev/null || true)
        [ -n "$s" ] && echo "  npm:    $s" || echo "  npm:    (未设置)"
    else
        echo "  npm:    (未安装)"
    fi
    if command -v cargo >/dev/null 2>&1; then
        s=$(awk '/^proxy[[:space:]]*=[[:space:]]*"/ { print $0; exit }' "$CARGO_CFG" 2>/dev/null || true)
        [ -n "$s" ] && echo "  cargo:  $s" || echo "  cargo:  (未设置)"
    else
        echo "  cargo:  (未安装)"
    fi
    if [ -f "$ENVD" ]; then
        s=$(awk '/^(HTTP_PROXY|https_proxy)=/ { print; exit }' "$ENVD" 2>/dev/null || true)
        [ -n "$s" ] && echo "  环境:   $s" || echo "  环境:   $ENVD 存在"
    else
        echo "  环境:   (未设置)"
    fi
}

usage() {
    cat <<'EOF'
用法: ./proxy-setup.sh <on|off|status> [URL]

  on      为 git/dnf/pip/npm/cargo 配置代理, 并写 no_proxy(URL 默认 http://127.0.0.1:7890)
  off     移除上述所有代理
  status  查看当前各工具代理

环境变量:
  DT_PROXY_URL=http://127.0.0.1:7890   # 默认代理, 也可用第 2 个参数
  DT_NO_PROXY=localhost,127.0.0.1,::1   # no_proxy 列表

注意: dnf 需 sudo 写 /etc/dnf/dnf.conf; 未安装的工具自动跳过。
EOF
    exit 1
}

# ---------------------------------------------------------------------------
# 分发
# ---------------------------------------------------------------------------
case "${1:-}" in
    on)
        URL="${2:-$DEFAULT_URL}"
        case "$URL" in
            http://*|https://*) ;;
            *) err "代理地址需以 http(s):// 开头(收到: $URL)"; exit 1 ;;
        esac
        echo "==> 为各工具配置代理: $URL (no_proxy: $NO_PROXY)"
        rc=0
        git_set || rc=1
        dnf_set || rc=1
        pip_set || rc=1
        npm_set || rc=1
        cargo_set || rc=1
        envd_set
        echo
        if [ "$rc" -eq 0 ]; then
            log "完成。dnf 立即生效; git/pip/npm/cargo 新命令生效; 环境变量下次登录全局生效。"
        else
            err "部分工具配置失败, 请按上方错误信息排查(重跑 on 幂等)。"
        fi
        exit "$rc"
        ;;
    off)
        echo "==> 移除各工具代理"
        git_unset; dnf_unset; pip_unset; npm_unset; cargo_unset; envd_unset
        echo
        log "已全部移除。"
        ;;
    status)
        status
        ;;
    *)
        usage
        ;;
esac
