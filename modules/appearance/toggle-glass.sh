#!/usr/bin/env bash
# 切换 macOS Tahoe 主题的"液态玻璃特效"开关
#   bash ~/toggle-macos-glass.sh perf   -> 性能模式：关闭高开销特效（解决软件渲染卡顿）
#   bash ~/toggle-macos-glass.sh full   -> 完整模式：恢复液态玻璃特效（需要 GPU 硬件加速才流畅）
# 修改后需要注销并重新登录才生效。
set -euo pipefail

KWINRC="$HOME/.config/kwinrc"
MODE="${1:-perf}"

case "$MODE" in
  perf)
    [ -f "$KWINRC" ] || { echo "找不到 $KWINRC" >&2; exit 1; }
    cp -n "$KWINRC" "$KWINRC.bak-glass" 2>/dev/null || true
    sed -i 's/^liquidglassEnabled=true/liquidglassEnabled=false/' "$KWINRC"
    sed -i 's/^shapecornersEnabled=true/shapecornersEnabled=false/' "$KWINRC"
    # 进一步降低残留的模糊/折射参数（即使特效被重新启用也不会那么重）
    sed -i 's/^BlurStrength=.*/BlurStrength=1.0/' "$KWINRC"
    sed -i 's/^RefractionWidth=.*/RefractionWidth=0.0/' "$KWINRC"
    sed -i 's/^RgbDriftStrength=.*/RgbDriftStrength=0.0/' "$KWINRC"
    sed -i 's/^MagnifyGlassStrength=.*/MagnifyGlassStrength=0.0/' "$KWINRC"
    sed -i 's/^BlurCoverage=.*/BlurCoverage=0.35/' "$KWINRC"
    sed -i 's/^BlurDecorations=.*/BlurDecorations=false/' "$KWINRC"
    sed -i 's/^BlurNonMatching=.*/BlurNonMatching=false/' "$KWINRC"
    echo "已切换到【性能模式】：液态玻璃特效已关闭，模糊/折射参数已降低。"
    echo "请注销并重新登录（或重启）后生效。"
    ;;
  full)
    [ -f "$KWINRC.bak-glass" ] && cp "$KWINRC.bak-glass" "$KWINRC"
    sed -i 's/^liquidglassEnabled=false/liquidglassEnabled=true/' "$KWINRC"
    echo "已切换到【完整模式】：液态玻璃特效已恢复。"
    echo "注意：当前是虚拟机软件渲染，完整模式很可能再次卡顿。"
    echo "请注销并重新登录（或重启）后生效。"
    ;;
  *)
    echo "用法: bash ~/toggle-macos-glass.sh perf|full" >&2
    exit 1
    ;;
esac
