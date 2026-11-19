#!/usr/bin/env bash
# =============================================================================
# 修复 GTK 主题在 GTK 4.14（Ubuntu 24.04 / 容器）下的两个兼容性问题
#
#   1) ~/.config/gtk-4.0/gtk.css 把 @import 写在 @media 里
#      -> GTK 4.14 不支持，整个主题不会加载，窗口变成完全透明
#   2) 透明度用了 color-mix()
#      -> GTK < 4.16 不支持，相关颜色规则被丢弃
#
# 处理方式：
#   * 把 @media 分支改成直接 @import 当前主题（深色/浅色按 settings.ini 判断）
#   * 把 color-mix(... 92%, transparent) 改写为等价的 alpha(..., 0.92)
#   * 只改受管部分，首次修改前备份为 *.bak-gtkfix
#
# 用法: fix-gtk-theme.sh [status]
# =============================================================================
set -euo pipefail

GTK4_DIR="$HOME/.config/gtk-4.0"
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"

has_color_mix() { grep -vE '^[[:space:]]*(\*|/\*)' "$1" 2>/dev/null | grep -q 'color-mix'; }
gtk4_import_broken() { grep -qE '^[[:space:]]*@media' "$1" 2>/dev/null; }

fix_gtk4_entry() {
    local f="$GTK4_DIR/gtk.css"
    [ -f "$f" ] || return 0

    local broken=0
    gtk4_import_broken "$f" && broken=1

    # 已经是修复后的结构，只处理可能残留的 color-mix
    if [ "$broken" -eq 0 ]; then
        if has_color_mix "$f"; then
            python3 - "$f" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="replace").read()
s = re.sub(r'color-mix\(in srgb,\s*@window_bg_color\s+(\d+)%,\s*transparent\)',
           lambda m: f'alpha(@window_bg_color, {int(m.group(1))/100:.2f})', s)
open(p, "w", encoding="utf-8").write(s)
PY
            echo "  GTK4: color-mix -> alpha() 已转换"
        fi
        return 0
    fi

    # 选择当前主题（默认深色）
    local theme="gtk-Dark.css"
    if [ -f "$GTK4_DIR/settings.ini" ] && \
       grep -q 'gtk-application-prefer-dark-theme=false' "$GTK4_DIR/settings.ini"; then
        theme="gtk-Light.css"
    fi
    [ -f "$GTK4_DIR/$theme" ] || theme="gtk-Dark.css"

    # 保留用户已有的不透明度设置
    local opacity
    opacity=$(python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'alpha\(@window_bg_color,\s*([0-9.]+)\)', s)
if m:
    print(f"{float(m.group(1)):.2f}"); raise SystemExit
m = re.search(r'@window_bg_color\s+(\d+)%', s)
if m:
    print(f"{int(m.group(1))/100:.2f}"); raise SystemExit
print("0.92")
PY
)

    [ -f "$f.bak-gtkfix" ] || cp -a "$f" "$f.bak-gtkfix"
    cat > "$f" <<EOF
/* mac-tahoe-liquid-kde: GTK 4 主题入口（desktop-toolkit 修复）
 *
 * GTK 4.14 不支持：@import 写在 @media 内（会导致主题完全不加载、窗口全透明），
 * 以及 color-mix()。这里直接引入当前主题，用 alpha() 表示不透明度。
 * 原始文件：gtk.css.bak-gtkfix
 */
@import url("$theme");
@import url("colors.css");

/* == macos-config: GTK 窗口/侧栏不透明度 (由此标记管理, 勿手动删) == */
/* 100% = 完全不透明; 数值越低越透明。性能模式无模糊, 建议 >=85 避免透视 */
.background, .background.view, .sidebar, .navigation-sidebar {
  background-color: alpha(@window_bg_color, $opacity);
}
/* == end macos-config == */
EOF
    echo "  GTK4: 已修复 @media/@import 结构（主题 $theme，不透明度 $opacity）"
}

fix_gtk3() {
    [ -f "$GTK3_CSS" ] || return 0
    has_color_mix "$GTK3_CSS" || return 0
    [ -f "$GTK3_CSS.bak-gtkfix" ] || cp -a "$GTK3_CSS" "$GTK3_CSS.bak-gtkfix"
    python3 - "$GTK3_CSS" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="replace").read()
s = re.sub(r'color-mix\(in srgb,\s*@theme_bg_color\s+(\d+)%,\s*transparent\)',
           lambda m: f'alpha(@theme_bg_color, {int(m.group(1))/100:.2f})', s)
s = re.sub(r'color-mix\(in srgb,\s*@window_bg_color\s+(\d+)%,\s*transparent\)',
           lambda m: f'alpha(@window_bg_color, {int(m.group(1))/100:.2f})', s)
open(p, "w", encoding="utf-8").write(s)
PY
    echo "  GTK3: color-mix -> alpha() 已转换"
}

case "${1:-fix}" in
    status)
        if gtk4_import_broken "$GTK4_DIR/gtk.css"; then
            echo "GTK4: 仍有 @media 嵌套 @import（会导致透明）"
        else
            echo "GTK4: 结构正常"
        fi
        has_color_mix "$GTK4_DIR/gtk.css" 2>/dev/null && echo "GTK4: 仍有 color-mix" || true
        has_color_mix "$GTK3_CSS" 2>/dev/null && echo "GTK3: 仍有 color-mix" || true
        ;;
    fix|"")
        fix_gtk4_entry
        fix_gtk3
        ;;
    *)
        echo "用法: $0 [fix|status]" >&2
        exit 1 ;;
esac
