#!/usr/bin/env bash
# =============================================================================
# GitHub 国内镜像一键配置（全局 git）
# 对大陆网络下 github.com 慢/不可达的场景，把所有 github.com 的 git 操作
# 重写到国内镜像，无需逐个仓库改 remote。
#
# 用法:  ./github-mirror.sh on|off|status
#   on      启用（写入 ~/.gitconfig 的 url.<镜像>/https://github.com/.insteadOf）
#   off     关闭（移除上述重写）
#   status  查看当前状态
# 镜像可通过环境变量覆盖: GH_PROXY=https://gh-proxy.com
# 注意: 启用后 git clone https://github.com/xxx 会走镜像；失效时换 GH_PROXY 或 off。
# =============================================================================
set -euo pipefail

GH_PROXY="${GH_PROXY:-https://gh-proxy.com}"
BASE="$GH_PROXY/https://github.com/"
TARGET="https://github.com/"

git_has_mirror() {
    git config --global --get-regexp '^url\..*\.insteadof$' 2>/dev/null \
        | awk -v t="$TARGET" '$2 == t { print $1 }' | head -1 || true
}

case "${1:-}" in
    on)
        key=$(git_has_mirror)
        if [ -n "$key" ]; then
            base=${key#url.}; base=${base%.insteadof}
            echo "已启用镜像: $base -> $TARGET"
            exit 0
        fi
        git config --global "url.$BASE.insteadOf" "$TARGET"
        echo "已启用 GitHub 镜像: $BASE -> $TARGET"
        echo "  以后 git clone https://github.com/xxx 会自动走镜像。"
        ;;
    off)
        key=$(git_has_mirror)
        if [ -z "$key" ]; then
            echo "当前未配置 GitHub 镜像重写。"
        else
            git config --global --unset-all "$key"
            echo "已关闭 GitHub 镜像重写: $key"
        fi
        ;;
    status)
        key=$(git_has_mirror)
        if [ -n "$key" ]; then
            base=${key#url.}; base=${base%.insteadof}
            echo "镜像已启用: $base -> $TARGET"
        else
            echo "未启用 GitHub 镜像重写。"
        fi
        ;;
    *)
        cat <<'EOF'
用法: ./github-mirror.sh <on|off|status>

  on      启用 GitHub 国内镜像（写入全局 git config）
  off     关闭
  status  查看状态

环境变量:
  GH_PROXY=https://gh-proxy.com        # 镜像前缀, 失效时更换
  DT_GHFAST=https://ghfast.top        # 第二前缀镜像(dt_clone auto 回退用)
EOF
        exit 1
        ;;
esac
