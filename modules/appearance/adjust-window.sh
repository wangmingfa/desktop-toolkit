#!/usr/bin/env bash
# =============================================================================
# macOS Tahoe 窗口外观调整工具
# -----------------------------------------------------------------------------
# 圆角:     KWin shapecorners 特效 (轻量, 可实时生效, 不重启会话)
# 透明度:   主题 SVG 资源重生成 (零运行时开销, 不影响流畅度)
# 玻璃参数: liquidglass 特效参数 (仅在 full 模式开启时可见)
#
# 直接用 bash modules/appearance/adjust-window.sh gui 打开滑块界面最省事。
# =============================================================================
set -euo pipefail

KWINRC="$HOME/.config/kwinrc"
GLASS_TOOL="$HOME/.local/bin/mac-tahoe-glass-surfaces"
BAK="$HOME/.config/kwinrc.bak-glass"
DEFAULT_CORNER=28
DBUS_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000"

# 所有可调组件
COMPONENTS="general finder menus popups apps search control-center about dock panel"

# =============================================================================
# 基础读写: 直接改 kwinrc (避开宿主 kwriteconfig6 的库依赖问题)
# =============================================================================
kw_get() {
    python3 - "$KWINRC" "$1" "$2" <<'PY'
import sys
path, group, key = sys.argv[1], "["+sys.argv[2]+"]", sys.argv[3]
inside = False
for line in open(path, encoding="utf-8", errors="replace"):
    s = line.strip()
    if s.startswith("["):
        inside = (s == group); continue
    if inside and s.startswith(key + "="):
        print(s.split("=", 1)[1]); break
PY
}

kw_set() {
    python3 - "$KWINRC" "$1" "$2" "$3" <<'PY'
import sys
path, group, key, val = sys.argv[1], "["+sys.argv[2]+"]", sys.argv[3], sys.argv[4]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
out, inside, done = [], False, False
for line in lines:
    s = line.strip()
    if s.startswith("["):
        if inside and not done:
            out.append(f"{key}={val}"); done = True
        inside = (s == group)
    if inside and line.startswith(key + "="):
        if not done:
            out.append(f"{key}={val}"); done = True
        continue
    out.append(line)
if inside and not done:
    out.append(f"{key}={val}"); done = True
if not done:
    out += ["", group, f"{key}={val}"]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
}

get_materials() { kw_get 'Effect-liquidglass' 'ComponentMaterials'; }

set_materials() {
    python3 - "$KWINRC" "$1" <<'PY'
import sys
path, raw = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
out, inside, done = [], False, False
for line in lines:
    s = line.strip()
    if s.startswith("["):
        if inside and not done:
            out.append("ComponentMaterials=" + raw); done = True
        inside = (s == "[Effect-liquidglass]")
    if inside and line.startswith("ComponentMaterials="):
        if not done:
            out.append("ComponentMaterials=" + raw); done = True
        continue
    out.append(line)
if not done:
    out += ["", "[Effect-liquidglass]", "ComponentMaterials=" + raw]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
}

# 让 KWin 重新加载圆角特效 (无需注销)
kwin_reload_corner() {
    env $DBUS_ENV busctl --user call org.kde.KWin /Effects \
        org.kde.kwin.Effects reconfigureEffect s kwin4_effect_shapecorners >/dev/null 2>&1 || \
    env $DBUS_ENV busctl --user call org.kde.KWin /Effects \
        org.kde.kwin.Effects loadEffect s kwin4_effect_shapecorners >/dev/null 2>&1 || true
}

# 重启 plasmashell 让主题 SVG 生效
reload_plasma() {
    env $DBUS_ENV systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1 || true
}

apply_surfaces() {
    local mats
    mats=$(get_materials)
    [ -n "$mats" ] || { echo "错误: 找不到 ComponentMaterials" >&2; return 1; }
    printf '%s' "$mats" | "$GLASS_TOOL" --apply >/dev/null 2>&1 || {
        echo "错误: 玻璃表面重生成失败" >&2; return 1;
    }
}

# =============================================================================
# 具体调整
# =============================================================================
set_corner() {
    local n="$1"
    [ "$n" = "default" ] && n=$DEFAULT_CORNER
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -le 40 ] || { echo "错误: 圆角需为 0-40 整数" >&2; return 1; }
    kw_set 'Round-Corners' 'Size' "$n"
    kw_set 'Round-Corners' 'InactiveCornerRadius' "$n"
    kw_set 'Effect-liquidglass' 'WindowCornerRadius' "$n"
    kw_set 'Plugins' 'shapecornersEnabled' 'true'
    kwin_reload_corner
    echo "圆角 = ${n}px (已实时生效)"
}

set_transparency() {
    local comp="$1" val="${2:-}"
    if [ "$comp" = "default" ]; then
        [ -f "$BAK" ] || { echo "错误: 找不到备份 $BAK" >&2; return 1; }
        local raw
        raw=$(python3 - "$BAK" <<'PY'
import sys
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    if line.startswith("ComponentMaterials="):
        print(line.split("=",1)[1].strip()); break
PY
)
        [ -n "$raw" ] && set_materials "$raw"
        kw_set 'Effect-liquidglass' 'SurfaceTransparencyLight' '25.0'
        kw_set 'Effect-liquidglass' 'SurfaceTransparencyDark' '25.0'
        apply_surfaces; reload_plasma
        echo "透明度 = 主题默认 (plasmashell 重启中)"
        return 0
    fi
    [ -z "$val" ] && { val="$comp"; comp="all"; }
    [[ "$val" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || { echo "错误: 透明度需为 0-100 数字" >&2; return 1; }
    python3 - "$KWINRC" "$comp" "$val" <<'PY'
import sys, json
path, comp, val = sys.argv[1], sys.argv[2], float(sys.argv[3])
if not 0 <= val <= 100:
    raise SystemExit("错误: 透明度需在 0-100 之间")
raw = None
for line in open(path, encoding="utf-8", errors="replace"):
    if line.startswith("ComponentMaterials="):
        raw = line.split("=",1)[1].strip(); break
if not raw: raise SystemExit("错误: 找不到 ComponentMaterials")
m = json.loads(raw)
if comp == "all":
    targets = list(m.keys())
else:
    if comp not in m: raise SystemExit(f"错误: 未知组件 {comp}")
    targets = [comp]
for c in targets:
    m[c]["SurfaceTransparencyLight"] = val
    m[c]["SurfaceTransparencyDark"] = val
new = json.dumps(m, separators=(",", ":"), ensure_ascii=False)
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
open(path,"w",encoding="utf-8").write("\n".join(
    "ComponentMaterials=" + new if l.startswith("ComponentMaterials=") else l
    for l in lines) + "\n")
PY
    apply_surfaces; reload_plasma
    echo "透明度 = $val  (${comp}) — plasmashell 重启中"
}

set_glass_param() {
    local key="$1" val="$2"
    case "$key" in
        BlurStrength|RefractionWidth|RgbDriftStrength|MagnifyGlassStrength|HighlightWidth|HighlightStrength|Saturation|Brightness|Contrast|NoiseStrength)
            kw_set 'Effect-liquidglass' "$key" "$val"
            echo "玻璃参数 $key = $val (full 模式下生效)"
            ;;
        *)
            echo "错误: 未知玻璃参数 $key" >&2; echo "可用: BlurStrength RefractionWidth RgbDriftStrength MagnifyGlassStrength HighlightWidth HighlightStrength Saturation Brightness Contrast NoiseStrength" >&2
            return 1 ;;
    esac
}

# =============================================================================
# 启动器 / 弹窗背景透明度 (Plasma 桌面主题 dialogs/background.svgz)
#   语义与其它透明度一致: 0 = 完全不透明, 100 = 完全透明。默认约 52%/45%。
#   同时作用于 Dark / Light 两套主题；首次修改自动备份 *.bak-dialogopacity。
# =============================================================================
DIALOG_THEME_GLOB="$HOME/.local/share/plasma/desktoptheme/MacTahoeLiquidKde-*"

launcher_transparency_get() {
    python3 - "$DIALOG_THEME_GLOB" <<'PY'
import sys, glob, gzip, re, os
for d in sorted(glob.glob(os.path.expanduser(sys.argv[1]))):
    p=os.path.join(d,'dialogs','background.svgz')
    if not os.path.exists(p): continue
    try: data=gzip.open(p,'rt',encoding='utf-8',errors='replace').read()
    except Exception: continue
    m=re.search(r'id="center"[^>]*style="opacity:([0-9.]+)', data)
    if m:
        op=float(m.group(1))
        name=os.path.basename(d).replace('MacTahoeLiquidKde-','')
        print(f"{name}: 不透明度 {op*100:.0f}% / 透明度 {(1-op)*100:.0f}%")
PY
}

launcher_transparency_set() { # 0-100 (0=不透明, 100=完全透明) | default
    local v="$1"
    if [ "$v" = default ]; then
        python3 - "$DIALOG_THEME_GLOB" <<'PY'
import sys, glob, os, shutil
for d in sorted(glob.glob(os.path.expanduser(sys.argv[1]))):
    p=os.path.join(d,'dialogs','background.svgz'); b=p+'.bak-dialogopacity'
    if os.path.exists(b):
        shutil.copy2(b,p); print(f"  恢复 {os.path.basename(d)}")
PY
        reload_plasma; echo "已恢复主题默认启动器透明度"; return 0
    fi
    [[ "$v" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || { echo "错误: 透明度需为 0-100 数字" >&2; return 1; }
    python3 -c "import sys; sys.exit(0 if 0<=float('$v')<=100 else 1)" || { echo "错误: 透明度需在 0-100 之间" >&2; return 1; }
    python3 - "$v" "$DIALOG_THEME_GLOB" <<'PY'
import sys, glob, gzip, re, os, shutil
frac=(100.0-float(sys.argv[1]))/100.0   # 换算为不透明度
pat=re.compile(r'(<[^>]*id="(?:center|rect4152|rect4159)"[^>]*style="opacity:)[0-9.]+(;)')
for d in sorted(glob.glob(os.path.expanduser(sys.argv[2]))):
    p=os.path.join(d,'dialogs','background.svgz')
    if not os.path.exists(p): continue
    b=p+'.bak-dialogopacity'
    if not os.path.exists(b): shutil.copy2(p,b)
    data=gzip.open(p,'rt',encoding='utf-8',errors='replace').read()
    new,n=pat.subn(lambda m: f"{m.group(1)}{frac:.2f}{m.group(2)}", data)
    gzip.open(p,'wt',encoding='utf-8').write(new)
    print(f"  {os.path.basename(d)}: {n} 处 -> 不透明度 {frac*100:.0f}%")
PY
    reload_plasma
    echo "启动器/弹窗透明度 = ${v}% (0=不透明,100=透明；plasmashell 重启中)"
}

PLASMASHELLRC="$HOME/.config/plasmashellrc"
APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
DOCK_PANEL_ID=124
DOCK_APPLET_ID=126

# 顶部任务栏 Logo (globalmenu 的 menuIcon, 组 Appearance)
# 预设: cachyos-logo-symbolic(CachyOS 剪影) / start-here-kde-symbolic(苹果剪影, 主题默认) / start-here-kde-plasma-symbolic(Plasma)
topbar_logo_get() {
    python3 - "$APPLETSRC" <<'PY'
import sys
sec="[Containments][100][Applets][102][Configuration][Appearance]"
inside=False
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    line=line.rstrip("\n")
    if line.startswith("["):
        inside=(line==sec); continue
    if inside and line.startswith("menuIcon="):
        print(line.split("=",1)[1].strip()); break
else:
    print("start-here-kde-symbolic")
PY
}

topbar_logo_set() { # <图标名> | cachy | apple | plasma
    local key="$1"
    case "$key" in
        cachy|cachyos)      key="cachyos-logo-symbolic" ;;
        apple|mac|default)  key="start-here-kde-symbolic" ;;
        plasma|kde)         key="start-here-kde-plasma-symbolic" ;;
    esac
    python3 - "$APPLETSRC" "$key" <<'PY'
import sys
path,key=sys.argv[1],sys.argv[2]
sec="[Containments][100][Applets][102][Configuration][Appearance]"
lines=open(path,encoding="utf-8",errors="replace").read().splitlines()
out=[]; in_sec=False; done=False
for line in lines:
    if line.startswith("["):
        if in_sec and not done:
            out.append("menuIcon="+key); done=True
        in_sec=(line==sec)
        out.append(line); continue
    if in_sec and line.startswith("menuIcon="):
        if not done: out.append("menuIcon="+key); done=True
        continue
    out.append(line)
if in_sec and not done:
    out.append("menuIcon="+key)
if not done:
    # 该 applet 尚无 Configuration 段: 在 applet 段后插入
    applet="[Containments][100][Applets][102]"
    marker=applet+"\n"
    idx="\n".join(out).find(marker)
    text="\n".join(out)
    if idx>=0:
        ins=idx+len(marker)
        nxt=text.find("\n[",ins)
        block=sec+"\nmenuIcon="+key+"\n"
        if nxt==-1: text=text+"\n"+block
        else: text=text[:nxt+1]+block+text[nxt+1:]
        out=text.splitlines()
open(path,"w",encoding="utf-8").write("\n".join(out)+"\n")
PY
    reload_plasma
    echo "顶部 Logo = $key (plasmashell 重启中)"
}


# Dock 栏高度 (面板 thickness, 存在 plasmashellrc 的 [PlasmaViews][Panel 124][Defaults])
dock_height_get() {
    python3 - "$PLASMASHELLRC" <<'PY'
import sys,re
sec=False
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    line=line.rstrip("\n")
    if line.startswith("["):
        sec = (line == "[PlasmaViews][Panel %d][Defaults]" % 124)
        continue
    if sec and line.startswith("thickness="):
        print(line.split("=",1)[1].strip()); break
else:
    print("68")
PY
}

dock_height_set() { # 40-140
    local n="$1"
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 40 ] && [ "$n" -le 140 ] || {
        echo "错误: Dock 高度需为 40-140 整数" >&2; return 1; }
    python3 - "$PLASMASHELLRC" "$n" <<'PY'
import sys,re
path,n=sys.argv[1],sys.argv[2]
lines=open(path,encoding="utf-8",errors="replace").read().splitlines()
out=[]; in_sec=False; done=False
for line in lines:
    if line.startswith("["):
        if in_sec and not done:
            out.append("thickness="+n); done=True
        in_sec = (line == "[PlasmaViews][Panel 124][Defaults]")
        out.append(line); continue
    if in_sec and line.startswith("thickness="):
        if not done: out.append("thickness="+n); done=True
        continue
    out.append(line)
if in_sec and not done: out.append("thickness="+n)
open(path,"w",encoding="utf-8").write("\n".join(out)+"\n")
PY
    reload_plasma
    echo "Dock 高度 = ${n}px (plasmashell 重启中)"
}

# Dock 图标悬停放大倍数 (icontasks 的 dockMagnification, 100-150)
dock_zoom_get() {
    python3 - "$APPLETSRC" <<'PY'
import sys
sec="[Containments][124][Applets][126][Configuration][General]"
inside=False
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    line=line.rstrip("\n")
    if line.startswith("["):
        inside=(line==sec); continue
    if inside and line.startswith("dockMagnification="):
        print(line.split("=",1)[1].strip()); break
else:
    print("110")
PY
}

dock_zoom_set() { # 100-150
    local n="$1"
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 100 ] && [ "$n" -le 150 ] || {
        echo "错误: 图标放大需为 100-150 整数 (100=不放大)" >&2; return 1; }
    python3 - "$APPLETSRC" "$n" <<'PY'
import sys
path,n=sys.argv[1],sys.argv[2]
sec="[Containments][124][Applets][126][Configuration][General]"
lines=open(path,encoding="utf-8",errors="replace").read().splitlines()
out=[]; in_sec=False; done=False
for line in lines:
    if line.startswith("["):
        if in_sec and not done:
            out.append("dockMagnification="+n); done=True
        in_sec=(line==sec)
        out.append(line); continue
    if in_sec and line.startswith("dockMagnification="):
        if not done: out.append("dockMagnification="+n); done=True
        continue
    out.append(line)
if in_sec and not done:
    out.append("dockMagnification="+n)
open(path,"w",encoding="utf-8").write("\n".join(out)+"\n")
PY
    reload_plasma
    echo "Dock 图标悬停放大 = ${n}% (plasmashell 重启中)"
}

# =============================================================================
# 窗口动画 (KWin 6)
#   最小化动画 = magiclamp (神灯/genie, minimize 组唯一效果)
#   打开/关闭  = glide ; 桌面切换 = slide ; 全局速度 = kdeglobals AnimationDurationFactor
#   llvmpipe 软件渲染需 KWIN_EFFECTS_FORCE_ANIMATIONS=1 (已由 systemd drop-in 提供)
# =============================================================================
KDEGLOBALS="$HOME/.config/kdeglobals"

# 确保强制动画的 drop-in 存在 llvmpipe 下才需要; 首次调用时补建
ensure_force_animations() {
     local d="$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
     local f="$d/force-animations.conf"
     mkdir -p "$d"
     if [ ! -f "$f" ] || ! grep -q 'KWIN_EFFECTS_FORCE_ANIMATIONS' "$f"; then
         printf '[Service]\nEnvironment=KWIN_EFFECTS_FORCE_ANIMATIONS=1\n' > "$f"
         env $DBUS_ENV systemctl --user daemon-reload >/dev/null 2>&1 || true
     fi
}

anim_effect_get() { # magiclamp|glide|slide  -> true/false
     local key="${1}Enabled"
     local v
     v=$(kw_get 'Plugins' "$key")
     case "$v" in true|false) echo "$v" ;; *) echo "false" ;; esac
}

anim_effect_set() { # magiclamp|glide|slide  on|off
     local eff="$1" act="$2" val
     case "$eff" in magiclamp|glide|slide) ;; *) echo "错误: 未知动画效果 $eff" >&2; return 1 ;; esac
     [ "$act" = on ] && val=true || val=false
     kw_set 'Plugins' "${eff}Enabled" "$val"
     ensure_force_animations
     # 即时加载/卸载, 避免重启 KWin 造成会话中断
     if [ "$val" = true ]; then
         env $DBUS_ENV busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects loadEffect s "$eff" >/dev/null 2>&1 || true
     else
         env $DBUS_ENV busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects unloadEffect s "$eff" >/dev/null 2>&1 || true
     fi
     local label; case "$eff" in magiclamp) label="最小化神灯(genie)";; glide) label="窗口打开/关闭滑入";; slide) label="桌面切换滑动";; esac
     echo "$label = $val (已应用; 若未立即生效, 注销重登一次即可)"
}

anim_speed_get() {
     python3 - "$KDEGLOBALS" <<'PY'
import sys
inside=False
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    s=line.strip()
    if s.startswith("["): inside=(s=="[KDE]"); continue
    if inside and s.startswith("AnimationDurationFactor="):
        print(s.split("=",1)[1].strip()); break
else: print("1.0")
PY
}

anim_speed_set() { # 0.25-2.0
     local v="$1"
     python3 -c "import sys; sys.exit(0 if 0.25 <= float('$v') <= 2.0 else 1)" 2>/dev/null || {
         echo "错误: 动画速度需在 0.25-2.0 之间" >&2; return 1; }
     python3 - "$KDEGLOBALS" "$v" <<'PY'
import sys
p,v=sys.argv[1],sys.argv[2]
lines=open(p,encoding="utf-8",errors="replace").read().splitlines()
out=[]; inside=False; done=False
for line in lines:
    s=line.strip()
    if s.startswith("["):
        if inside and not done: out.append("AnimationDurationFactor="+v); done=True
        inside=(s=="[KDE]"); out.append(line); continue
    if inside and s.startswith("AnimationDurationFactor="):
        if not done: out.append("AnimationDurationFactor="+v); done=True
        continue
    out.append(line)
if inside and not done: out.append("AnimationDurationFactor="+v)
open(p,"w",encoding="utf-8").write("\n".join(out)+"\n")
PY
     echo "全局动画速度 = ${v}x (KConfigWatcher 自动即时生效)"
}

cmd_winanimi() {
     local sub="${1:-status}"; shift 2>/dev/null || true
     case "$sub" in
         status)
             echo "══════════════ 窗口动画状态 ══════════════"
             echo "  最小化神灯 genie (magiclamp) = $(anim_effect_get magiclamp)"
             echo "  打开/关闭滑入    (glide)     = $(anim_effect_get glide)"
             echo "  桌面切换滑动     (slide)     = $(anim_effect_get slide)"
             echo "  全局动画速度                = $(anim_speed_get)x  (0.25快 / 1.0标准 / 2.0慢)"
             echo "  强制动画环境变量            = $(grep -q KWIN_EFFECTS_FORCE_ANIMATIONS "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d/force-animations.conf" 2>/dev/null && echo 已配置 || echo 未配置)" ;;
         genie)   anim_effect_set magiclamp "$1" ;;
         glide)   anim_effect_set glide "$1" ;;
         slide)   anim_effect_set slide "$1" ;;
         speed)   anim_speed_set "$1" ;;
         preset)
             local p="${1:-}"
             case "$p" in
                 macos)    anim_effect_set magiclamp on; anim_effect_set glide on; anim_speed_set 1.0; echo "预设: macOS 风格 (神灯最小化+滑入+标准速度)" ;;
                 windows)  anim_effect_set magiclamp off; anim_effect_set glide on; anim_speed_set 1.0; echo "预设: Windows 11 (无神灯, 滑入+标准速度)" ;;
                 balanced) anim_effect_set magiclamp on; anim_effect_set glide off; anim_speed_set 0.8; echo "预设: 均衡 (神灯+稍快)" ;;
                 fast)     anim_effect_set magiclamp off; anim_effect_set glide off; anim_speed_set 0.5; echo "预设: 快速 (关动画, 性能优先)" ;;
                 off)      anim_effect_set magiclamp off; anim_effect_set glide off; anim_effect_set slide off; echo "预设: 全部关闭" ;;
                 *) echo "用法: winanim preset <macos|windows|balanced|fast|off>" >&2; return 1 ;;
             esac ;;
         *) echo "用法: winanim <status|genie|glide|slide|speed|preset> [参数]" >&2; return 1 ;;
     esac
}

# =============================================================================
# 显示所有可调项
# =============================================================================
cmd_list() {
    echo "══════════════ 圆角 (KWin shapecorners, 实时生效) ══════════════"
    echo "  窗口圆角半径        WindowCornerRadius      = $(kw_get 'Effect-liquidglass' 'WindowCornerRadius')"
    echo "  特效圆角            Size                    = $(kw_get 'Round-Corners' 'Size')"
    echo "  非激活窗口圆角      InactiveCornerRadius    = $(kw_get 'Round-Corners' 'InactiveCornerRadius')"
    echo "  Dock 圆角           DockCornerRadius        = $(kw_get 'Effect-liquidglass' 'DockCornerRadius')"
    echo "  弹窗圆角            PopupCornerRadius       = $(kw_get 'Effect-liquidglass' 'PopupCornerRadius')"
    local active
    active=$(env $DBUS_ENV busctl --user get-property org.kde.KWin /Effects org.kde.kwin.Effects activeEffects 2>/dev/null | grep -qi shapecorners && echo 运行中 || echo 未运行)
    echo "  特效状态                                    = $active"
    echo
    echo "══════════════ 透明度 (0=不透明, 100=全透明) ══════════════"
    echo "  全局(顶层)         Light=$(kw_get 'Effect-liquidglass' 'SurfaceTransparencyLight')  Dark=$(kw_get 'Effect-liquidglass' 'SurfaceTransparencyDark')"
    python3 - "$(get_materials)" <<'PY'
import json, sys
try: m = json.loads(sys.argv[1])
except Exception: print("  (无法解析)"); raise SystemExit
for k in ("general","finder","menus","popups","apps","search","control-center","about","dock","panel"):
    if k in m:
        print(f"  {k:<15} Light={m[k].get('SurfaceTransparencyLight')!s:<6} Dark={m[k].get('SurfaceTransparencyDark')}")
PY
    echo "  ── 启动器 / 弹窗背景 (Plasma 主题, 独立于 liquidglass) ──"
    launcher_transparency_get | sed 's/^/  /'
    echo
    echo "══════════════ 玻璃质感参数 (仅 full 模式 liquidglass 开启时可见) ══════════════"
    for k in BlurStrength RefractionWidth RgbDriftStrength MagnifyGlassStrength HighlightWidth HighlightStrength Saturation Brightness Contrast NoiseStrength BlurCoverage; do
        printf "  %-24s = %s\n" "$k" "$(kw_get 'Effect-liquidglass' "$k")"
    done
    echo "  BlurDecorations        = $(kw_get 'Effect-liquidglass' 'BlurDecorations')"
    echo "  BlurNonMatching        = $(kw_get 'Effect-liquidglass' 'BlurNonMatching')"
    echo "  渐变顶/中/底透明度     = $(kw_get 'Effect-liquidglass' 'GradientTopOpacity') / $(kw_get 'Effect-liquidglass' 'GradientCenterOpacity') / $(kw_get 'Effect-liquidglass' 'GradientBottomOpacity')"
    echo
    echo "══════════════ 特效开关 ══════════════"
    echo "  liquidglass (液态玻璃) = $(kw_get 'Plugins' 'liquidglassEnabled')  ← 性能模式为 false"
    echo "  shapecorners (圆角)    = $(kw_get 'Plugins' 'shapecornersEnabled')"
    echo
    echo "══════════════ Dock 尺寸 ══════════════"
    echo "  Dock 栏高度 (thickness)   = $(dock_height_get) px   (40-140)"
    echo "  图标悬停放大 (hover zoom) = $(dock_zoom_get) %     (100-150, 100=不放大)"
    echo
    echo "══════════════ 顶部任务栏 Logo ══════════════"
    echo "  左上角菜单图标 (menuIcon) = $(topbar_logo_get)"
    echo "    预设: cachyos-logo-symbolic(CachyOS) / start-here-kde-symbolic(苹果) / start-here-kde-plasma-symbolic"
    echo
    echo "══════════════ 窗口动画 (KWin 6) ══════════════"
    echo "  最小化神灯 genie (magiclamp) = $(anim_effect_get magiclamp)"
    echo "  打开/关闭滑入    (glide)     = $(anim_effect_get glide)"
    echo "  桌面切换滑动     (slide)     = $(anim_effect_get slide)"
    echo "  全局动画速度                = $(anim_speed_get)x"
    echo
    echo "用 'set <组> <键> <值>' 可改上面任意 kwinrc 键；改完按需要重新登录。"
}

# =============================================================================
# GUI (zenity 滑块)
# =============================================================================
cmd_gui() {
    command -v zenity >/dev/null || { echo "zenity 不可用，请用命令行" >&2; return 1; }
    local corner tr
    corner=$(zenity --scale --text="窗口圆角半径 (0=直角, 建议 12-28)" \
        --value="$(kw_get 'Round-Corners' 'Size')" --min-value=0 --max-value=40 --step=1 \
        --title="macOS 窗口调整 1/3" 2>/dev/null) || return 0
    tr=$(zenity --scale --text="表面透明度 (0=不透明, 100=全透明, 建议 40-70)" \
        --value=50 --min-value=0 --max-value=100 --step=5 \
        --title="macOS 窗口调整 2/3" 2>/dev/null) || return 0
    local mode
    mode=$(zenity --list --radiolist --column="" --column="透明度范围" \
        TRUE "全部组件" FALSE "仅菜单栏/Dock" FALSE "仅窗口/菜单" \
        --title="macOS 窗口调整 3/3" --text="选择应用范围:" 2>/dev/null) || return 0
    case "$mode" in
        "全部组件") set_transparency all "$tr" ;;
        "仅菜单栏/Dock") set_transparency dock "$tr"; set_transparency panel "$tr" ;;
        "仅窗口/菜单") set_transparency general "$tr"; set_transparency menus "$tr"; set_transparency apps "$tr" ;;
    esac
    set_corner "$corner"
    zenity --info --text="已应用：圆角 ${corner}px，透明度 ${tr}。\nplasmashell 正在重启使透明度生效。" --title="完成" 2>/dev/null || true
}

usage() {
    cat <<'EOF'
macOS Tahoe 窗口外观调整工具

用法:
  gui                          图形滑块界面（推荐）
  list                         列出全部可调配置及当前值
  corner <0-40|default>        窗口圆角半径
  dock <0-100>                 Dock 栏透明度（快捷命令，等同 transparency dock）
  dock-height <40-140>         Dock 栏高度 (px)
  dock-zoom <100-150>          Dock 图标悬停放大倍数 (%, 100=不放大)
  logo <cachy|apple|plasma|图标名>  顶部任务栏左上角 Logo
  winanim status               查看窗口动画当前状态
  winanim genie <on|off>       最小化神灯 genie 效果 (macOS 风格)
  winanim glide <on|off>       窗口打开/关闭滑入动画
  winanim slide <on|off>       桌面切换滑动动画
  winanim speed <0.25-2.0>     全局动画速度 (0.25快/1.0标准/2.0慢)
  winanim preset <macos|windows|balanced|fast|off>  一键动画预设
  transparency <0-100>         全部组件透明度 (liquidglass)
  launcher-transparency <0-100|default>  启动器/弹窗背景透明度 (0=不透明,100=透明)
  transparency <组件> <0-100>  单组件透明度
  transparency default         恢复主题默认透明度
  glass <参数> <值>            调整玻璃质感参数（full 模式可见）
  set <组> <键> <值>           通用: 改 kwinrc 任意键
  reset                        恢复全部默认
  help                         本帮助

组件: general finder menus popups apps search control-center about dock panel
玻璃参数: BlurStrength RefractionWidth RgbDriftStrength MagnifyGlassStrength
          HighlightWidth HighlightStrength Saturation Brightness Contrast NoiseStrength

示例:
  bash modules/appearance/adjust-window.sh gui
  bash modules/appearance/adjust-window.sh corner 18
  bash modules/appearance/adjust-window.sh transparency 60
  bash modules/appearance/adjust-window.sh transparency dock 85
  bash modules/appearance/adjust-window.sh glass BlurStrength 3
EOF
}

# =============================================================================
# 入口
# =============================================================================
mkdir -p "$HOME/.config"
[ "$#" -ge 1 ] || { cmd_gui; exit 0; }
cmd="$1"; shift
case "$cmd" in
    gui)            cmd_gui ;;
    list|show)      cmd_list ;;
    corner)         [ "$#" -ge 1 ] || { echo "缺少圆角参数" >&2; exit 1; }; set_corner "$@" ;;
    transparency)   [ "$#" -ge 1 ] || { echo "缺少透明度参数" >&2; exit 1; }; set_transparency "$@" ;;
    launcher-transparency)
        if [ "${1:-}" = get ]; then launcher_transparency_get
        else [ "$#" -ge 1 ] || { echo "缺少透明度参数 (0-100 或 default)" >&2; exit 1; }; launcher_transparency_set "$@"; fi ;;
    dock)           [ "$#" -ge 1 ] || { echo "缺少透明度参数" >&2; exit 1; }; set_transparency dock "$@" ;;
    dock-height)    [ "$#" -ge 1 ] || { echo "缺少高度参数" >&2; exit 1; }; dock_height_set "$@" ;;
    dock-zoom)      [ "$#" -ge 1 ] || { echo "缺少放大参数" >&2; exit 1; }; dock_zoom_set "$@" ;;
    logo)           [ "$#" -ge 1 ] || { echo "缺少 logo 参数" >&2; exit 1; }; topbar_logo_set "$@" ;;
    winanim)        cmd_winanimi "$@" ;;
    glass)          [ "$#" -ge 2 ] || { echo "用法: glass <参数> <值>" >&2; exit 1; }; set_glass_param "$@" ;;
    set)            [ "$#" -ge 3 ] || { echo "用法: set <组> <键> <值>" >&2; exit 1; }; kw_set "$1" "$2" "$3"; echo "已设置 [$1] $2=$3 (可能需要重新登录)" ;;
    reset)          set_corner default; set_transparency default; echo "已恢复默认" ;;
    help|-h|--help) usage ;;
    *)              echo "未知命令: $cmd" >&2; usage; exit 1 ;;
esac
