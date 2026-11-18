#!/usr/bin/env bash
# =============================================================================
# 桌面外观配置中心 —— 统一交互式入口
# 运行后全部用菜单/滑块操作，不需要记住任何命令。
# 底层复用同目录的 adjust-window.sh 与 toggle-glass.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADJUST="$SCRIPT_DIR/adjust-window.sh"
TOGGLE="$SCRIPT_DIR/toggle-glass.sh"
KWINRC="$HOME/.config/kwinrc"
DBUS_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000"

[ -x "$ADJUST" ] || { echo "缺少 $ADJUST" >&2; exit 1; }

# ---------- 通用交互控件 (自适应: 宿主机用 kdialog, 容器用 zenity) ----------
if command -v zenity >/dev/null 2>&1; then
    GUI=zenity
elif command -v kdialog >/dev/null 2>&1; then
    GUI=kdialog
else
    GUI=none
fi

menu() { # title text "key|label|desc" ...
    local title="$1" text="$2"; shift 2
    if [ "$GUI" = zenity ]; then
        local args=() row key label desc
        for row in "$@"; do
            IFS='|' read -r key label desc <<< "$row"
            args+=("$key" "$label" "$desc")
        done
        zenity --list --title="$title" --text="$text" --width=560 --height=560 \
            --column="键" --column="配置项" --column="当前值 / 说明" \
            --print-column=1 "${args[@]}" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        local args=() row key label desc
        for row in "$@"; do
            IFS='|' read -r key label desc <<< "$row"
            [ -n "$desc" ] && args+=("$key" "$label — $desc") || args+=("$key" "$label")
        done
        kdialog --title "$title" --menu "$text" "${args[@]}" 2>/dev/null
    fi
}

ask_num() { # title text value min max step
    if [ "$GUI" = zenity ]; then
        zenity --scale --title="$1" --text="$2" --value="$3" \
            --min-value="$4" --max-value="$5" --step="$6" --width=480 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "$1" --inputbox "$2 ($4-$5)" "$3" 2>/dev/null
    fi
}

ask_text() { # title text default_value
    if [ "$GUI" = zenity ]; then
        zenity --entry --title="$1" --text="$2" --entry-text="${3:-}" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "$1" --inputbox "$2" "${3:-}" 2>/dev/null
    fi
}

ask_bool() { # title text current(true/false)
    if [ "$GUI" = zenity ]; then
        if [ "$3" = "false" ]; then
            zenity --list --radiolist --column="" --column="值" \
                FALSE true TRUE false --print-column=2 --title="$1" --text="$2" 2>/dev/null
        else
            zenity --list --radiolist --column="" --column="值" \
                TRUE true FALSE false --print-column=2 --title="$1" --text="$2" 2>/dev/null
        fi
    elif [ "$GUI" = kdialog ]; then
        if [ "$3" = "false" ]; then
            kdialog --title "$1" --radiolist "$2" false "否(关闭)" off true "是(开启)" on 2>/dev/null
        else
            kdialog --title "$1" --radiolist "$2" true "是(开启)" on false "否(关闭)" off 2>/dev/null
        fi
    fi
}

info() {
    [ "$GUI" = zenity ] && zenity --info --title="完成" --text="$1" 2>/dev/null || true
    [ "$GUI" = kdialog ] && kdialog --title "完成" --msgbox "$1" 2>/dev/null || true
}
err() {
    [ "$GUI" = zenity ] && zenity --error --title="错误" --text="$1" 2>/dev/null || true
    [ "$GUI" = kdialog ] && kdialog --title "错误" --error "$1" 2>/dev/null || true
}
confirm() {
    if [ "$GUI" = zenity ]; then
        zenity --question --title="确认" --text="$1" 2>/dev/null
    elif [ "$GUI" = kdialog ]; then
        kdialog --title "确认" --yesno "$1" 2>/dev/null
    fi
}

# ---------- 底层读写 ----------
kw_get() {
    python3 - "$KWINRC" "$1" "$2" <<'PY'
import sys
p,g,k=sys.argv[1],"["+sys.argv[2]+"]",sys.argv[3]; inside=False
for line in open(p,encoding="utf-8",errors="replace"):
    s=line.strip()
    if s.startswith("["): inside=(s==g); continue
    if inside and s.startswith(k+"="): print(s.split("=",1)[1]); break
PY
}
kw_set() {
    python3 - "$KWINRC" "$1" "$2" "$3" <<'PY'
import sys
p,g,k,v=sys.argv[1],"["+sys.argv[2]+"]",sys.argv[3],sys.argv[4]
lines=open(p,encoding="utf-8",errors="replace").read().splitlines()
out,inside,done=[],False,False
for line in lines:
    s=line.strip()
    if s.startswith("["):
        if inside and not done: out.append(f"{k}={v}"); done=True
        inside=(s==g)
    if inside and line.startswith(k+"="):
        if not done: out.append(f"{k}={v}"); done=True
        continue
    out.append(line)
if inside and not done: out.append(f"{k}={v}"); done=True
if not done: out+=["",g,f"{k}={v}"]
open(p,"w",encoding="utf-8").write("\n".join(out)+"\n")
PY
}
get_materials() { kw_get 'Effect-liquidglass' 'ComponentMaterials'; }

# ---------- 重载特效 ----------
reload_corner() {
    env $DBUS_ENV busctl --user call org.kde.KWin /Effects \
        org.kde.kwin.Effects reconfigureEffect s kwin4_effect_shapecorners >/dev/null 2>&1 || true
}
reload_effect() { # id
    env $DBUS_ENV busctl --user call org.kde.KWin /Effects \
        org.kde.kwin.Effects reconfigureEffect s "$1" >/dev/null 2>&1 || true
}
set_effect() { # id on/off
    local id="$1" state="$2"
    if [ "$state" = "true" ]; then
        env $DBUS_ENV busctl --user call org.kde.KWin /Effects \
            org.kde.kwin.Effects loadEffect s "$id" >/dev/null 2>&1 || true
    else
        env $DBUS_ENV busctl --user call org.kde.KWin /Effects \
            org.kde.kwin.Effects unloadEffect s "$id" >/dev/null 2>&1 || true
    fi
}

# ---------- 子菜单: 圆角 ----------
sub_corner() {
    while true; do
        local c
        c=$(menu "窗口圆角" "选择要调整的圆角项（当前值见右列）：" \
            "win|窗口圆角半径|$(kw_get 'Effect-liquidglass' 'WindowCornerRadius') px" \
            "size|特效圆角(激活窗口)|$(kw_get 'Round-Corners' 'Size') px" \
            "inactive|非激活窗口圆角|$(kw_get 'Round-Corners' 'InactiveCornerRadius') px" \
            "dock|Dock 圆角|$(kw_get 'Effect-liquidglass' 'DockCornerRadius') px" \
            "popup|弹窗圆角|$(kw_get 'Effect-liquidglass' 'PopupCornerRadius') px" \
            "all|一键设置常用圆角|同时设置窗口+特效+非激活" \
            "back|← 返回主菜单|") || return 0
        case "$c" in
            back) return 0 ;;
            all)
                local v; v=$(ask_num "窗口圆角" "常用圆角半径 (建议 12-28)：" \
                    "$(kw_get 'Round-Corners' 'Size')" 0 40 1) || continue
                "$ADJUST" corner "$v"; info "圆角已设为 ${v}px（实时生效）" ;;
            win|size|inactive|dock|popup)
                local key grp label cur v
                case "$c" in
                    win)     key=WindowCornerRadius; grp='Effect-liquidglass'; label="窗口圆角半径" ;;
                    size)    key=Size;               grp='Round-Corners';     label="特效圆角" ;;
                    inactive)key=InactiveCornerRadius;grp='Round-Corners';   label="非激活窗口圆角" ;;
                    dock)    key=DockCornerRadius;   grp='Effect-liquidglass';label="Dock 圆角" ;;
                    popup)   key=PopupCornerRadius;  grp='Effect-liquidglass';label="弹窗圆角" ;;
                esac
                cur=$(kw_get "$grp" "$key")
                v=$(ask_num "$label" "$label（0=直角，建议 12-28）：" "$cur" 0 40 1) || continue
                kw_set "$grp" "$key" "$v"
                reload_corner
                info "$label = ${v}px（已生效）" ;;
        esac
    done
}

# ---------- 子菜单: 透明度 ----------
sub_transparency() {
    local mats_cur
    mats_cur=$(python3 - "$(get_materials)" <<'PY'
import json,sys
try: m=json.loads(sys.argv[1])
except Exception: print("?"); raise SystemExit
print(m.get("general",{}).get("SurfaceTransparencyLight","?"))
PY
)
    while true; do
        local c
        c=$(menu "透明度" "0 = 完全不透明，100 = 完全透明。选择组件调整：" \
            "dock|① Dock 栏透明度|当前 $(mat_val dock)% (已调低40%→58.5)" \
            "all|全部组件统一|当前常规窗口: ${mats_cur}" \
            "global|全局顶层值|$(kw_get 'Effect-liquidglass' 'SurfaceTransparencyLight')" \
            "general|常规窗口 general|$(mat_val general)" \
            "finder|文件管理器 finder|$(mat_val finder)" \
            "menus|菜单 menus|$(mat_val menus)" \
            "popups|弹窗 popups|$(mat_val popups)" \
            "apps|应用 apps|$(mat_val apps)" \
            "search|搜索 search|$(mat_val search)" \
            "control-center|控制中心 control-center|$(mat_val control-center)" \
            "about|关于 about|$(mat_val about)" \
            "panel|顶部菜单栏 panel|$(mat_val panel)" \
            "default|恢复主题默认|各组件恢复原始值" \
            "back|← 返回主菜单|") || return 0
        case "$c" in
            back) return 0 ;;
            default)
                "$ADJUST" transparency default; info "已恢复主题默认透明度" ;;
            all|global)
                local cur v
                [ "$c" = all ] && cur="$mats_cur" || cur=$(kw_get 'Effect-liquidglass' 'SurfaceTransparencyLight')
                v=$(ask_num "透明度" "设置透明度 (0-100，建议 40-70)：" "$cur" 0 100 5) || continue
                if [ "$c" = all ]; then
                    "$ADJUST" transparency all "$v"
                else
                    kw_set 'Effect-liquidglass' 'SurfaceTransparencyLight' "$v"
                    kw_set 'Effect-liquidglass' 'SurfaceTransparencyDark' "$v"
                fi
                info "透明度已设为 $v" ;;
            *)
                local v; v=$(ask_num "透明度 - $c" "组件 [$c] 透明度 (0-100)：" "$(mat_val "$c")" 0 100 5) || continue
                "$ADJUST" transparency "$c" "$v"; info "组件 [$c] 透明度 = $v" ;;
        esac
    done
}
mat_val() {
    python3 - "$(get_materials)" "$1" <<'PY'
import json,sys
try: m=json.loads(sys.argv[1]); print(m.get(sys.argv[2],{}).get("SurfaceTransparencyLight","?"))
except Exception: print("?")
PY
}

# ---------- 子菜单: 玻璃质感 ----------
GLASS_PARAMS=(
    "BlurStrength|模糊强度|0|10|0.5|越大背景越模糊"
    "RefractionWidth|折射宽度|0|60|1|玻璃边缘折射"
    "RgbDriftStrength|色散强度|0|30|1|RGB 分离效果"
    "MagnifyGlassStrength|放大玻璃|0|0.5|0.01|放大镜效果"
    "HighlightWidth|高光宽度|0|40|1|玻璃边缘高光"
    "HighlightStrength|高光强度|0|1|0.05|高光亮度"
    "Saturation|饱和度|0|3|0.1|色彩鲜艳度"
    "Brightness|亮度|0|2|0.1|整体亮度"
    "Contrast|对比度|0|2|0.1|整体对比度"
    "NoiseStrength|噪点强度|0|100|1|玻璃噪点"
    "BlurCoverage|模糊覆盖范围|0|1|0.05|模糊覆盖比例"
)
sub_glass() {
    while true; do
        local rows=() p key label min max step desc cur
        for p in "${GLASS_PARAMS[@]}"; do
            IFS='|' read -r key label min max step desc <<< "$p"
            cur=$(kw_get 'Effect-liquidglass' "$key")
            rows+=("$key|$label|$cur  ($desc)")
        done
        rows+=("back|← 返回主菜单|")
        local c; c=$(menu "玻璃质感" "仅完整模式(liquidglass开启)可见；性能模式调了不显示：" "${rows[@]}") || return 0
        [ "$c" = back ] && return 0
        for p in "${GLASS_PARAMS[@]}"; do
            IFS='|' read -r key label min max step desc <<< "$p"
            if [ "$c" = "$key" ]; then
                local v; v=$(ask_num "$label" "$label —— $desc" "$(kw_get 'Effect-liquidglass' "$key")" "$min" "$max" "$step") || continue 2
                "$ADJUST" glass "$key" "$v"
                if [ "$(kw_get 'Plugins' 'liquidglassEnabled')" = "true" ]; then reload_effect liquidglass; fi
                info "$label = $v（完整模式下生效）"
            fi
        done
    done
}

# ---------- 子菜单: 特效开关 ----------
sub_effects() {
    while true; do
        local c
        c=$(menu "特效开关" "开启液态玻璃会重新引入卡顿（软件渲染）：" \
            "liquidglass|液态玻璃 liquidglass|$(kw_get 'Plugins' 'liquidglassEnabled')" \
            "shapecorners|圆角特效 shapecorners|$(kw_get 'Plugins' 'shapecornersEnabled')" \
            "back|← 返回主菜单|") || return 0
        case "$c" in
            back) return 0 ;;
            liquidglass|shapecorners)
                local cur label id
                [ "$c" = liquidglass ] && { label="液态玻璃"; id=liquidglass; } || { label="圆角特效"; id=kwin4_effect_shapecorners; }
                cur=$(kw_get 'Plugins' "$c")
                [ "$cur" != "true" ] && cur=false
                if confirm "$label 当前为 $cur，是否切换？"; then
                    local new=false; [ "$cur" = false ] && new=true
                    if [ "$c" = liquidglass ] && [ "$new" = true ]; then
                        confirm "警告：开启液态玻璃在虚拟机软件渲染下会明显卡顿。确定开启？" || continue
                    fi
                    kw_set 'Plugins' "$c" "$new"
                    set_effect "$id" "$new"
                    info "$label 已设为 $new（部分变化需重新登录）"
                fi ;;
        esac
    done
}

# ---------- 子菜单: 渐变与装饰 ----------
GRAD_PARAMS=(
    "GradientTopOpacity|顶部渐变透明度|0|1|0.01"
    "GradientCenterOpacity|中部渐变透明度|0|1|0.01"
    "GradientBottomOpacity|底部渐变透明度|0|1|0.01"
)
sub_gradient() {
    while true; do
        local rows=() p key label min max step cur
        for p in "${GRAD_PARAMS[@]}"; do
            IFS='|' read -r key label min max step <<< "$p"
            cur=$(kw_get 'Effect-liquidglass' "$key")
            rows+=("$key|$label|$cur")
        done
        rows+=("BlurDecorations|装饰栏模糊|$(kw_get 'Effect-liquidglass' 'BlurDecorations')")
        rows+=("BlurNonMatching|非匹配窗口模糊|$(kw_get 'Effect-liquidglass' 'BlurNonMatching')")
        rows+=("back|← 返回主菜单|")
        local c; c=$(menu "渐变与装饰" "玻璃渐变的透明度与模糊范围：" "${rows[@]}") || return 0
        [ "$c" = back ] && return 0
        if [ "$c" = BlurDecorations ] || [ "$c" = BlurNonMatching ]; then
            local cur v
            cur=$(kw_get 'Effect-liquidglass' "$c"); [ "$cur" != true ] && cur=false
            v=$(ask_bool "$c" "是否启用 $c？" "$cur") || continue
            "$ADJUST" set 'Effect-liquidglass' "$c" "$v"
            info "$c = $v"
        else
            for p in "${GRAD_PARAMS[@]}"; do
                IFS='|' read -r key label min max step <<< "$p"
                if [ "$c" = "$key" ]; then
                    local v; v=$(ask_num "$label" "$label (0-1)：" "$(kw_get 'Effect-liquidglass' "$key")" "$min" "$max" "$step") || continue 2
                    "$ADJUST" set 'Effect-liquidglass' "$key" "$v"
                    if [ "$(kw_get 'Plugins' 'liquidglassEnabled')" = "true" ]; then reload_effect liquidglass; fi
                    info "$label = $v"
                fi
            done
        fi
    done
}

# ---------- 子菜单: GTK 应用透明度 (Nautilus 等, 独立于 Qt/Plasma) ----------
GTK4_CSS="$HOME/.config/gtk-4.0/gtk.css"
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"
gtk_opacity_get() {
    grep -oE '@window_bg_color [0-9]+%' "$GTK4_CSS" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "?"
}
gtk_opacity_set() { # 0-100
    local v="$1"
    for pair in "$GTK4_CSS|@window_bg_color" "$GTK3_CSS|@theme_bg_color"; do
        local f="${pair%%|*}" color="${pair##*|}"
        [ -f "$f" ] || continue
        python3 - "$f" "$color" "$v" <<'PY'
import sys, re
p, color, v = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
s = re.sub(r'(color-mix\(in srgb, ' + re.escape(color) + r' )\d+(%', r'\g<1>' + v + r'\g<2>', s)
# 若缺少受管标记则追加一段覆盖规则
if 'macos-config' not in s:
    s += "\n/* == macos-config: GTK 窗口不透明度 == */\n.window-bg, .sidebar, .sidebar-bg, GtkPlacesSidebar {\n  background-color: color-mix(in srgb, " + color + " " + v + "%, transparent);\n}\n/* == end macos-config == */\n"
open(p, "w", encoding="utf-8").write(s)
PY
    done
    # 重启 Nautilus 生效
    env $DBUS_ENV systemctl --user restart org.gnome.Nautilus.service >/dev/null 2>&1 || \
        pkill -f nautilus >/dev/null 2>&1 || true
}
sub_gtk() {
    while true; do
        local c cur
        cur=$(gtk_opacity_get)
        c=$(menu "GTK 应用透明度" "Nautilus 等 GTK 应用（独立于前面的 Qt 透明度）。性能模式建议 ≥85，否则会透视后面窗口：" \
            "set|窗口/侧栏不透明度|当前 ${cur}% (100=完全不透明)" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        local v; v=$(ask_num "GTK 透明度" "窗口/侧栏不透明度 (100=不透明, 建议≥85)：" "$cur" 0 100 1) || continue
        gtk_opacity_set "$v"
        info "GTK 透明度已设为 ${v}%，Nautilus 正在重启生效"
    done
}

# ---------- 子菜单: Dock 尺寸 (高度 + 图标悬停放大) ----------
sub_dock_size() {
    while true; do
        local c cur_h cur_z
        cur_h=$(python3 - "$HOME/.config/plasmashellrc" <<'PY'
import sys
sec=False
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    line=line.rstrip("\n")
    if line.startswith("["):
        sec=(line=="[PlasmaViews][Panel 124][Defaults]"); continue
    if sec and line.startswith("thickness="):
        print(line.split("=",1)[1].strip()); break
else: print("68")
PY
)
        cur_z=$(python3 - "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" <<'PY'
import sys
sec="[Containments][124][Applets][126][Configuration][General]"
inside=False
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    line=line.rstrip("\n")
    if line.startswith("["):
        inside=(line==sec); continue
    if inside and line.startswith("dockMagnification="):
        print(line.split("=",1)[1].strip()); break
else: print("110")
PY
)
        c=$(menu "Dock 尺寸" "调整 Dock 栏高度与图标大小（改完自动重启桌面，闪一下即可）：" \
            "height|① Dock 栏高度|当前 ${cur_h}px (默认68, 范围40-140)" \
            "zoom|② 图标悬停放大|当前 ${cur_z}% (默认110, 范围100-150)" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        if [ "$c" = height ]; then
            local v; v=$(ask_num "Dock 栏高度" "Dock 栏高度 px（默认68, 建议 56-96）：" "$cur_h" 40 140 4) || continue
            "$ADJUST" dock-height "$v"; info "Dock 高度已设为 ${v}px，桌面重启中"
        elif [ "$c" = zoom ]; then
            local v; v=$(ask_num "图标悬停放大" "鼠标悬停时的放大倍数 %（100=不放大, 建议 110-135）：" "$cur_z" 100 150 5) || continue
            "$ADJUST" dock-zoom "$v"; info "图标悬停放大已设为 ${v}%，桌面重启中"
        fi
    done
}

# ---------- 子菜单: 顶部任务栏 Logo ----------
sub_logo() {
    local PRESETS
    PRESETS=$(python3 - <<'PY'
import os
base=os.path.expanduser("~/.local/share/icons/MacTahoeLiquidKde-Icons/places/scalable")
out=[]
for name in ("cachyos-logo-symbolic","start-here-kde-symbolic","start-here-kde-plasma-symbolic"):
    if os.path.exists(os.path.join(base,name+".svg")): out.append(name)
print(" ".join(out))
PY
)
    local cur label
    while true; do
        cur=$("$ADJUST" list 2>/dev/null | sed -n 's/.*左上角菜单图标 (menuIcon) = //p' | head -1)
        case "$cur" in
            cachyos-logo-symbolic)       label="CachyOS" ;;
            start-here-kde-symbolic)     label="苹果 (原版)" ;;
            start-here-kde-plasma-symbolic) label="Plasma" ;;
            *) label="$cur" ;;
        esac
        local c
        c=$(menu "顶部任务栏 Logo" "左上角菜单按钮图标（当前: ${label}）。切换后桌面自动重启：" \
            "cachy|① CachyOS 标志|推荐, 纯白色" \
            "apple|② 苹果标志 (原版)|恢复 macOS 默认苹果剪影" \
            "plasma|③ KDE Plasma 标志|Plasma 官方 logo" \
            "custom|④ 自定义图标名|输入图标主题里的图标名" \
            "back|← 返回主菜单|") || return 0
        case "$c" in
            back) return 0 ;;
            cachy|apple|plasma)
                "$ADJUST" logo "$c"
                info "顶部 Logo 已切换为 $label，桌面重启中" ;;
            custom)
                local v; v=$(ask_text "自定义 Logo" "输入图标名 (在图标主题 places/scalable 下，不含 .svg)：" "$cur") || continue
                [ -n "$v" ] || continue
                "$ADJUST" logo "$v"
                info "顶部 Logo 已设为 $v，桌面重启中" ;;
        esac
    done
}

# ---------- 子菜单: 窗口动画 ----------
sub_winanimi() {
    while true; do
        local st genie glide slide speed
        st=$("$ADJUST" winanim status 2>/dev/null)
        genie=$(echo "$st"  | sed -n 's/.*magiclamp) = //p' | head -1)
        glide=$(echo "$st"  | sed -n 's/.*(glide)     = //p' | head -1)
        slide=$(echo "$st"  | sed -n 's/.*(slide)     = //p' | head -1)
        speed=$(echo "$st"  | sed -n 's/.*全局动画速度 *= //p' | head -1 | cut -dx -f1)
        local c
        c=$(menu "窗口动画" "当前: 神灯最小化=${genie} 滑入=${glide} 桌面滑动=${slide} 速度=${speed}x。（软件渲染下已强制开启动画，极少数场景可能轻微掉帧）" \
            "preset-macos|① 预设 · macOS 风格|神灯最小化 + 滑入 + 标准速度(推荐)" \
            "preset-balanced|② 预设 · 均衡|神灯 + 稍快速度" \
            "preset-fast|③ 预设 · 快速|关闭动画, 性能优先" \
            "preset-off|④ 预设 · 全部关闭|关闭所有窗口动画" \
            "genie|⑤ 最小化神灯 genie (单独)|当前 ${genie} — macOS 的神奇效果" \
            "glide|⑥ 窗口打开/关闭滑入 (单独)|当前 ${glide}" \
            "slide|⑦ 桌面切换滑动 (单独)|当前 ${slide}" \
            "speed|⑧ 全局动画速度|当前 ${speed}x" \
            "back|← 返回主菜单|") || return 0
        [ "$c" = back ] && return 0
        case "$c" in
            preset-macos)    "$ADJUST" winanim preset macos; info "已应用 macOS 风格动画（神灯最小化已开启）" ;;
            preset-balanced) "$ADJUST" winanim preset balanced; info "已应用均衡动画" ;;
            preset-fast)     "$ADJUST" winanim preset fast; info "已应用快速动画" ;;
            preset-off)      "$ADJUST" winanim preset off; info "已关闭所有窗口动画" ;;
            genie|glide|slide)
                local cur v
                case "$c" in genie) cur=$genie;; glide) cur=$glide;; slide) cur=$slide;; esac
                local label; case "$c" in genie) label="最小化神灯 genie";; glide) label="窗口滑入 glide";; slide) label="桌面滑动 slide";; esac
                v=$(ask_bool "$label" "$label 当前为 $cur，是否开启？" "$cur") || continue
                "$ADJUST" winanim "$c" "$([ "$v" = true ] && echo on || echo off)"
                info "$label = $v" ;;
            speed)
                local v; v=$(ask_num "动画速度" "全局动画速度（0.25=快, 1.0=标准, 2.0=慢）：" "$speed" 0.25 2.0 0.05) || continue
                "$ADJUST" winanim speed "$v"; info "动画速度 = ${v}x" ;;
        esac
    done
}

# ---------- 主菜单 ----------
main() {
    while true; do
        local c
        c=$(menu "桌面外观配置中心" "全部配置都在这里交互式调整，无需记命令：" \
            "corner|① 窗口圆角|窗口/ Dock / 弹窗圆角半径" \
            "transparency|② 透明度|全局与 10 个组件的透明程度" \
            "glass|③ 玻璃质感|模糊/折射/色散等（完整模式可见）" \
            "effects|④ 特效开关|液态玻璃 / 圆角特效 开关" \
            "gradient|⑤ 渐变与装饰|渐变透明度、模糊范围" \
            "gtk|⑥ GTK 应用透明度|Nautilus 侧栏/窗口" \
            "docksize|⑦ Dock 尺寸|高度 + 图标悬停放大" \
            "logo|⑧ 顶部任务栏 Logo|CachyOS / 苹果 / Plasma" \
            "winanim|⑨ 窗口动画|神灯 genie + 滑入 + 速度（本次新增）" \
            "list|⑩ 查看当前配置|打印所有可调项" \
            "reset|⑪ 恢复默认|圆角与透明度恢复默认" \
            "mode|⑫ 性能 / 完整模式|切换（完整模式可能卡顿）" \
            "exit|⑬ 退出|") || exit 0
        case "$c" in
            exit) exit 0 ;;
            corner)       sub_corner ;;
            transparency) sub_transparency ;;
            glass)        sub_glass ;;
            effects)      sub_effects ;;
            gradient)     sub_gradient ;;
            gtk)          sub_gtk ;;
            docksize)     sub_dock_size ;;
            logo)         sub_logo ;;
            winanim)      sub_winanimi ;;
            list)
                if [ "$GUI" = zenity ]; then
                    "$ADJUST" list | zenity --text-info --title="当前配置" --width=760 --height=640 2>/dev/null || true
                elif [ "$GUI" = kdialog ]; then
                    "$ADJUST" list | kdialog --title "当前配置" --textbox - 760 640 2>/dev/null || true
                fi ;;
            reset)
                confirm "恢复圆角与透明度为默认值？" && { "$ADJUST" reset; info "已恢复默认"; } ;;
            mode)
                local cur new
                cur=$(kw_get 'Plugins' 'liquidglassEnabled')
                if [ "$cur" = true ]; then new="性能模式(流畅)"; extra=perf; else new="完整模式(液态玻璃,可能卡)"; extra=full; fi
                if confirm "当前 $([ "$cur" = true ] && echo 完整 || echo 性能) 模式，切换到 $new ？" && [ -x "$TOGGLE" ]; then
                    "$TOGGLE" "$extra"
                    info "已切换到 $new。KWin 配置需重新登录才完全生效。"
                elif [ ! -x "$TOGGLE" ]; then
                    err "找不到 $TOGGLE"
                fi ;;
        esac
    done
}

main "$@"
