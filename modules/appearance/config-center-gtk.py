#!/usr/bin/env python3
# =============================================================================
# 桌面外观配置中心 · 单窗口版 (GTK4)
#
# 与 zenity 版本的区别：
#   * 只有一个常驻窗口，切换分类是「左侧选择 + 右侧换页」，不会关窗/开新窗，
#     Dock / 任务栏上始终只有一个图标，不再闪烁。
#   * 所有滑块/开关都就地生效，结果显示在窗口底部状态栏，不弹对话框。
#
# 仍复用同目录的 adjust-window.sh 完成实际修改；若 GTK4 不可用，
# config-center.sh 会自动退回 zenity/kdialog 菜单版本。
# =============================================================================
import json
import os
import re
import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk, Pango  # noqa: E402

HOME = os.path.expanduser("~")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KWINRC = os.path.join(HOME, ".config", "kwinrc")
PLASMASHELLRC = os.path.join(HOME, ".config", "plasmashellrc")
APPLETSRC = os.path.join(HOME, ".config", "plasma-org.kde.plasma.desktop-appletsrc")
GTK4_CSS = os.path.join(HOME, ".config", "gtk-4.0", "gtk.css")
GTK3_CSS = os.path.join(HOME, ".config", "gtk-3.0", "gtk.css")
DBUS_ENV = {
    "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
    "XDG_RUNTIME_DIR": "/run/user/1000",
}

MATERIAL_KEYS = [
    ("general", "常规窗口"),
    ("finder", "文件管理器"),
    ("menus", "菜单"),
    ("popups", "弹窗"),
    ("apps", "应用"),
    ("search", "搜索"),
    ("control-center", "控制中心"),
    ("about", "关于"),
    ("dock", "Dock 栏"),
    ("panel", "顶部菜单栏"),
]

GLASS_PARAMS = [
    ("BlurStrength", "模糊强度", 0, 10, 0.5, "越大背景越模糊"),
    ("RefractionWidth", "折射宽度", 0, 60, 1, "玻璃边缘折射"),
    ("RgbDriftStrength", "色散强度", 0, 30, 1, "RGB 分离效果"),
    ("MagnifyGlassStrength", "放大玻璃", 0, 0.5, 0.01, "放大镜效果"),
    ("HighlightWidth", "高光宽度", 0, 40, 1, "玻璃边缘高光"),
    ("HighlightStrength", "高光强度", 0, 1, 0.05, "高光亮度"),
    ("Saturation", "饱和度", 0, 3, 0.1, "色彩鲜艳度"),
    ("Brightness", "亮度", 0, 2, 0.1, "整体亮度"),
    ("Contrast", "对比度", 0, 2, 0.1, "整体对比度"),
    ("NoiseStrength", "噪点强度", 0, 100, 1, "玻璃噪点"),
    ("BlurCoverage", "模糊覆盖范围", 0, 1, 0.05, "模糊覆盖比例"),
]

GRAD_PARAMS = [
    ("GradientTopOpacity", "顶部渐变透明度", 0, 1, 0.01),
    ("GradientCenterOpacity", "中部渐变透明度", 0, 1, 0.01),
    ("GradientBottomOpacity", "底部渐变透明度", 0, 1, 0.01),
]


# ---------------------------------------------------------------------------
# 底层读写
# ---------------------------------------------------------------------------
def ini_get(path, group, key, default=""):
    inside = False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                s = line.strip()
                if s.startswith("["):
                    inside = s == "[" + group + "]"
                    continue
                if inside and s.startswith(key + "="):
                    return s.split("=", 1)[1]
    except FileNotFoundError:
        pass
    return default


def ini_set(path, group, key, value):
    g = "[" + group + "]"
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except FileNotFoundError:
        lines = []
    out, inside, done = [], False, False
    for line in lines:
        s = line.strip()
        if s.startswith("["):
            if inside and not done:
                out.append(f"{key}={value}")
                done = True
            inside = s == g
        if inside and line.startswith(key + "="):
            if not done:
                out.append(f"{key}={value}")
                done = True
            continue
        out.append(line)
    if inside and not done:
        out.append(f"{key}={value}")
        done = True
    if not done:
        out += ["", g, f"{key}={value}"]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def find_adjust():
    for cand in (
        os.path.join(SCRIPT_DIR, "adjust-window.sh"),
        os.path.join(HOME, "adjust-macos-window.sh"),
    ):
        if os.path.exists(cand):
            return cand
    return None


ADJUST = find_adjust()


def run_adjust(*args, timeout=180):
    """调用 adjust-window.sh，返回 (成功?, 输出文本)。"""
    if not ADJUST:
        return False, "找不到 adjust-window.sh"
    try:
        r = subprocess.run(
            [ADJUST, *[str(a) for a in args]],
            capture_output=True, text=True, timeout=timeout,
        )
        out = (r.stdout or "").strip() or (r.stderr or "").strip()
        return r.returncode == 0, out
    except subprocess.TimeoutExpired:
        return False, "执行超时"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def busctl(*args):
    try:
        subprocess.run(
            ["busctl", "--user", *args], env={**os.environ, **DBUS_ENV},
            capture_output=True, timeout=20,
        )
    except Exception:  # noqa: BLE001
        pass


def reload_corner():
    busctl("call", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects",
           "reconfigureEffect", "s", "kwin4_effect_shapecorners")


def reload_liquidglass_if_on():
    if ini_get(KWINRC, "Plugins", "liquidglassEnabled") == "true":
        busctl("call", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects",
               "reconfigureEffect", "s", "liquidglass")


def set_effect(name, enabled):
    busctl("call", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects",
           "loadEffect" if enabled else "unloadEffect", "s", name)


def get_materials():
    raw = ini_get(KWINRC, "Effect-liquidglass", "ComponentMaterials")
    try:
        return json.loads(raw) if raw else {}
    except Exception:  # noqa: BLE001
        return {}


def mat_val(key, default="?"):
    return get_materials().get(key, {}).get("SurfaceTransparencyLight", default)


def launcher_opacity():
    ok, out = run_adjust("launcher-transparency", "get")
    if not ok:
        return "?"
    m = re.search(r"/ 透明度 (\d+)%", out)
    return m.group(1) if m else "?"


def gtk_opacity_get():
    try:
        s = open(GTK4_CSS, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return "?"
    m = re.search(r"@window_bg_color (\d+)%", s)
    return m.group(1) if m else "?"


def gtk_opacity_set(value):
    for path, color in ((GTK4_CSS, "@window_bg_color"), (GTK3_CSS, "@theme_bg_color")):
        if not os.path.exists(path):
            continue
        s = open(path, encoding="utf-8", errors="replace").read()
        s = re.sub(
            r"(color-mix\(in srgb, " + re.escape(color) + r" )\d+(%)",
            lambda m: m.group(1) + str(value) + m.group(2), s,
        )
        if "macos-config" not in s:
            s += (
                "\n/* == macos-config: GTK 窗口不透明度 == */\n"
                ".window-bg, .sidebar, .sidebar-bg, GtkPlacesSidebar {\n"
                f"  background-color: color-mix(in srgb, {color} {value}%, transparent);\n"
                "}\n/* == end macos-config == */\n"
            )
        open(path, "w", encoding="utf-8").write(s)
    subprocess.run(["systemctl", "--user", "restart", "org.gnome.Nautilus.service"],
                   env={**os.environ, **DBUS_ENV}, capture_output=True)


# ---------------------------------------------------------------------------
# 界面构件
# ---------------------------------------------------------------------------
def fmt(value, digits):
    try:
        f = float(value)
    except (TypeError, ValueError):
        return str(value)
    return f"{f:.{digits}f}" if digits else str(int(round(f)))


def str_or(value, default):
    return value if value not in (None, "") else default


def num(value, default):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float(default)


class Page(Gtk.Box):
    def __init__(self, center, title, desc):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.center = center
        self.set_margin_top(22)
        self.set_margin_bottom(22)
        self.set_margin_start(26)
        self.set_margin_end(26)
        head = Gtk.Label(xalign=0, wrap=True)
        head.set_markup(f"<span size='large' weight='bold'>{GLib.markup_escape_text(title)}</span>")
        self.append(head)
        if desc:
            sub = Gtk.Label(xalign=0, wrap=True)
            sub.add_css_class("dim-label")
            sub.set_text(desc)
            self.append(sub)
        self.listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.listbox.add_css_class("boxed-list")
        self.listbox.set_valign(Gtk.Align.START)
        self.append(self.listbox)

    # ---- 行 ----
    def _row(self, title, subtitle=""):
        row = Gtk.ListBoxRow(activatable=False, selectable=False)
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        box.set_margin_top(9)
        box.set_margin_bottom(9)
        box.set_margin_start(14)
        box.set_margin_end(14)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        t = Gtk.Label(xalign=0, label=title)
        texts.append(t)
        if subtitle:
            s = Gtk.Label(xalign=0, wrap=True)
            s.add_css_class("dim-label")
            s.add_css_class("caption")
            s.set_text(subtitle)
            texts.append(s)
        box.append(texts)
        row.set_child(box)
        self.listbox.append(row)
        return row, box

    def section(self, text):
        lbl = Gtk.Label(xalign=0, label=text)
        lbl.add_css_class("dim-label")
        lbl.add_css_class("caption")
        lbl.set_margin_top(10)
        self.append(lbl)

    def note(self, text):
        lbl = Gtk.Label(xalign=0, wrap=True, label=text)
        lbl.add_css_class("dim-label")
        self.append(lbl)

    def scale(self, title, subtitle, lo, hi, step, current, on_apply, digits=0,
              suffix=""):
        row, box = self._row(title, subtitle)
        value_lbl = Gtk.Label(label=fmt(current, digits) + suffix)
        value_lbl.set_width_chars(7)
        value_lbl.add_css_class("numeric")
        scale = Gtk.Scale(
            orientation=Gtk.Orientation.HORIZONTAL,
            adjustment=Gtk.Adjustment(
                value=num(current, lo), lower=float(lo),
                upper=float(hi), step_increment=float(step),
                page_increment=float(step) * 10,
            ),
            hexpand=True, width_request=260,
        )
        scale.set_digits(digits)
        scale.set_draw_value(False)
        box.append(scale)
        box.append(value_lbl)

        state = {"timer": 0}

        def apply_now():
            state["timer"] = 0
            self.center.timers.discard(apply_now_id[0])
            val = round(scale.get_value(), max(digits, 0) + 2)
            on_apply(fmt(val, digits))
            return False

        apply_now_id = [0]

        def on_change(sc):
            value_lbl.set_text(fmt(sc.get_value(), digits) + suffix)
            if state["timer"]:
                GLib.source_remove(state["timer"])
                self.center.timers.discard(state["timer"])
            state["timer"] = GLib.timeout_add(450, apply_now)
            apply_now_id[0] = state["timer"]
            self.center.timers.add(state["timer"])

        scale.connect("value-changed", on_change)
        return row

    def switch(self, title, subtitle, current, on_apply):
        row, box = self._row(title, subtitle)
        sw = Gtk.Switch(active=(str(current).strip().lower() == "true"),
                        valign=Gtk.Align.CENTER)
        sw.connect("state-set", lambda _s, state: (on_apply("true" if state else "false"), False)[1])
        box.append(sw)
        return row

    def button(self, title, subtitle, label, on_click):
        row, box = self._row(title, subtitle)
        btn = Gtk.Button(label=label, valign=Gtk.Align.CENTER)
        btn.connect("clicked", lambda _b: on_click())
        box.append(btn)
        return row

    def buttons(self, items):
        """items: [(按钮文字, 说明, 回调)] 横向排列。"""
        row, box = self._row("快捷操作", "")
        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        inner.set_halign(Gtk.Align.END)
        inner.set_hexpand(True)
        for label, tip, cb in items:
            btn = Gtk.Button(label=label)
            btn.set_tooltip_text(tip)
            btn.connect("clicked", lambda _b, f=cb: f())
            inner.append(btn)
        box.append(inner)
        return row


class Center(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="桌面外观配置中心")
        self.set_default_size(1020, 760)
        self.set_default_icon_name("preferences-desktop-theme")

        header = Gtk.HeaderBar()
        header.set_show_title_buttons(True)
        title = Gtk.Label(label="桌面外观配置中心")
        title.add_css_class("title")
        header.set_title_widget(title)
        self.set_titlebar(header)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_child(outer)

        split = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        split.set_vexpand(True)
        outer.append(split)

        # ---- 左侧分类 ----
        side_scroll = Gtk.ScrolledWindow()
        side_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        side_scroll.set_size_request(238, -1)
        side_scroll.add_css_class("sidebar")
        self.sidebar = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.sidebar.add_css_class("navigation-sidebar")
        self.sidebar.set_margin_top(8)
        self.sidebar.set_margin_bottom(8)
        self.sidebar.set_margin_start(8)
        self.sidebar.set_margin_end(8)
        side_scroll.set_child(self.sidebar)
        split.append(side_scroll)

        # ---- 右侧内容 ----
        self.stack = Gtk.Stack()
        self.stack.set_hexpand(True)
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(120)
        split.append(self.stack)

        # ---- 底部状态栏 ----
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        bar.set_margin_top(6)
        bar.set_margin_bottom(6)
        bar.set_margin_start(14)
        bar.set_margin_end(14)
        self.status = Gtk.Label(xalign=0, label="就绪")
        self.status.add_css_class("dim-label")
        self.status.set_ellipsize(Pango.EllipsizeMode.END)
        bar.append(self.status)
        outer.append(Gtk.Separator())
        outer.append(bar)

        self.timers = set()
        self._status_timer = 0
        self.nav_rows = {}
        self.builders = {
            "corner": self.build_corner,
            "transparency": self.build_transparency,
            "glass": self.build_glass,
            "effects": self.build_effects,
            "gradient": self.build_gradient,
            "gtk": self.build_gtk,
            "dock": self.build_dock,
            "logo": self.build_logo,
            "winanim": self.build_winanim,
            "misc": self.build_misc,
        }
        self.page_specs = [
            ("corner", "窗口圆角"),
            ("transparency", "透明度"),
            ("glass", "玻璃质感"),
            ("effects", "特效开关"),
            ("gradient", "渐变与装饰"),
            ("gtk", "GTK 应用透明度"),
            ("dock", "Dock 尺寸"),
            ("logo", "顶部任务栏 Logo"),
            ("winanim", "窗口动画"),
            ("misc", "其他 / 恢复默认"),
        ]
        self.page_names = dict(self.page_specs)
        self.build_pages()
        self.sidebar.connect("row-selected", self.on_select)
        self.sidebar.select_row(self.sidebar.get_row_at_index(0))

    # ---- 状态栏 ----
    def say(self, text, error=False):
        self.status.set_text(text)
        self.status.remove_css_class("error")
        if error:
            self.status.add_css_class("error")
        if self._status_timer:
            GLib.source_remove(self._status_timer)

        def clear():
            self._status_timer = 0
            self.status.set_text("就绪")
            self.status.remove_css_class("error")
            return False

        self._status_timer = GLib.timeout_add(9000, clear)

    def report(self, ok, out, success_text):
        first = (out or "").strip().splitlines()
        detail = first[-1] if first else ""
        self.say(f"{success_text}" + (f" · {detail}" if detail else ""), error=not ok)

    # ---- 页面 ----
    def add_page(self, key, name, page):
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_child(page)
        self.stack.add_named(scroller, key)

        # 只在首次注册时添加左侧分类项，刷新页面时不会重复
        if self.nav_rows.get(key):
            return
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)
        lbl = Gtk.Label(xalign=0, label=name, hexpand=True)
        box.append(lbl)
        row.set_child(box)
        row.page_key = key
        self.sidebar.append(row)
        self.nav_rows[key] = row

    def on_select(self, _lb, row):
        if row is None:
            return
        self.stack.set_visible_child_name(row.page_key)
        self.rebuild(row.page_key)

    def register(self, key, name, builder):
        page = builder()
        self.add_page(key, name, page)
        return page

    # ---- 各分类 ----
    def build_pages(self):
        for key, name in self.page_specs:
            self.register(key, name, self.builders[key])

    def set_kwin(self, group, key, value):
        ini_set(KWINRC, group, key, value)

    def build_corner(self):
        p = Page(self, "窗口圆角", "0 = 直角，建议 12-28。拖动后立即生效。")

        def corner_row(group, key, title, subtitle):
            cur = str_or(ini_get(KWINRC, group, key), "0")

            def apply(v):
                self.set_kwin(group, key, v)
                reload_corner()
                self.say(f"{title} = {v}px（已生效）")

            p.scale(title, subtitle, 0, 40, 1, cur, apply, 0, " px")

        corner_row("Effect-liquidglass", "WindowCornerRadius", "窗口圆角半径", "液态玻璃的窗口外框")
        corner_row("Round-Corners", "Size", "特效圆角（激活窗口）", "shapecorners 特效")
        corner_row("Round-Corners", "InactiveCornerRadius", "非激活窗口圆角", "未聚焦窗口")
        corner_row("Effect-liquidglass", "DockCornerRadius", "Dock 圆角", "Dock 栏外形")
        corner_row("Effect-liquidglass", "PopupCornerRadius", "弹窗圆角", "菜单 / 弹窗")

        def set_all():
            cur = str_or(ini_get(KWINRC, "Round-Corners", "Size"), "18")
            ok, out = run_adjust("corner", cur)
            self.report(ok, out, f"常用圆角已设为 {cur}px")

        p.buttons([("常用圆角…", "同时设置窗口 + 特效 + 非激活窗口",
                    lambda: self.prompt_number("常用圆角半径", 0, 40, 1,
                                               str_or(ini_get(KWINRC, "Round-Corners", "Size"), "18"),
                                               lambda v: self.report(*run_adjust("corner", v),
                                                                     f"圆角已设为 {v}px")))])

    def build_transparency(self):
        p = Page(self, "透明度",
                 "0 = 完全不透明，100 = 完全透明。修改后由 adjust-window.sh 重生成主题，稍等片刻生效。")
        self.tr_rows = {}

        def component_row(label, key, cur, apply):
            p.scale(label, f"组件 [{key}]", 0, 100, 1, cur or 50, apply, 0, " %")

        def set_comp(key, v):
            ok, out = run_adjust("transparency", key, v)
            self.report(ok, out, f"组件 [{key}] 透明度 = {v}")

        component_row("全部组件统一", "all", mat_val("general"),
                      lambda v: self.report(*run_adjust("transparency", "all", v),
                                            f"全部组件透明度 = {v}"))
        component_row("全局顶层值", "global", str_or(ini_get(KWINRC, "Effect-liquidglass", "SurfaceTransparencyLight"), "50"),
                      lambda v: (self.set_kwin("Effect-liquidglass", "SurfaceTransparencyLight", v),
                                 self.set_kwin("Effect-liquidglass", "SurfaceTransparencyDark", v),
                                 self.say(f"全局透明度 = {v}")))
        for key, label in MATERIAL_KEYS:
            component_row(label, key, mat_val(key), lambda v, k=key: set_comp(k, v))
        component_row("启动器 / 弹窗背景", "launcher", launcher_opacity(),
                      lambda v: self.report(*run_adjust("launcher-transparency", v),
                                            f"启动器/弹窗透明度 = {v}%"))

        p.note("提示：启动器背景 0-20 之间比较接近 macOS 的实心观感；"
               "40 以上会明显透出后面的窗口。")
        p.buttons([("恢复主题默认", "各组件恢复原始值",
                    lambda: self.report(*run_adjust("transparency", "default"), "已恢复主题默认透明度")),
                   ("启动器恢复默认", "恢复背景 SVG 原始不透明度",
                    lambda: self.report(*run_adjust("launcher-transparency", "default"), "启动器已恢复默认"))])

    def build_glass(self):
        p = Page(self, "玻璃质感",
                 "仅在完整模式（liquidglass 开启）下可见；性能模式下数值会保存但不渲染。")
        for key, label, lo, hi, step, desc in GLASS_PARAMS:
            cur = str_or(ini_get(KWINRC, "Effect-liquidglass", key), lo)
            digits = 0 if step >= 1 else (2 if step < 0.1 else 1)

            def apply(v, k=key, lbl=label):
                ok, out = run_adjust("glass", k, v)
                reload_liquidglass_if_on()
                self.report(ok, out, f"{lbl} = {v}")

            p.scale(label, desc, lo, hi, step, cur, apply, digits)

    def build_effects(self):
        p = Page(self, "特效开关", "性能模式请保持液态玻璃关闭，软件渲染下开启会明显卡顿。")

        def liquid_title():
            return "液态玻璃 liquidglass"

        def toggle_liquid(v):
            on = v == "true"
            self.set_kwin("Plugins", "liquidglassEnabled", v)
            set_effect("liquidglass", on)
            self.say("液态玻璃已开启（可能卡顿）" if on else "液态玻璃已关闭")

        def toggle_corner(v):
            on = v == "true"
            self.set_kwin("Plugins", "shapecornersEnabled", v)
            set_effect("kwin4_effect_shapecorners", on)
            self.say("圆角特效已开启" if on else "圆角特效已关闭")

        p.switch(liquid_title(), "液态玻璃模糊/折射，软件渲染下较重",
                 str_or(ini_get(KWINRC, "Plugins", "liquidglassEnabled"), "false"),
                 toggle_liquid)
        p.switch("圆角特效 shapecorners", "让窗口四个角变圆",
                 str_or(ini_get(KWINRC, "Plugins", "shapecornersEnabled"), "true"),
                 toggle_corner)
        p.note("切换后若个别效果没变化，注销并重新登录一次即可完全生效。")

    def build_gradient(self):
        p = Page(self, "渐变与装饰", "玻璃表面的渐变强度与模糊覆盖范围。")
        for key, label, lo, hi, step in GRAD_PARAMS:
            cur = str_or(ini_get(KWINRC, "Effect-liquidglass", key), "0")

            def apply(v, k=key, lbl=label):
                ok, out = run_adjust("set", "Effect-liquidglass", k, v)
                reload_liquidglass_if_on()
                self.report(ok, out, f"{lbl} = {v}")

            p.scale(label, key, lo, hi, step, cur, apply, 2)

        def bool_row(key, label, desc):
            def apply(v, k=key, lbl=label):
                ok, out = run_adjust("set", "Effect-liquidglass", k, v)
                reload_liquidglass_if_on()
                self.report(ok, out, f"{lbl} = {v}")

            p.switch(label, desc, str_or(ini_get(KWINRC, "Effect-liquidglass", key), "false"), apply)

        bool_row("BlurDecorations", "装饰栏模糊", "标题栏 / 工具栏参与模糊")
        bool_row("BlurNonMatching", "非匹配窗口模糊", "不匹配玻璃材质的窗口也模糊")

    def build_gtk(self):
        p = Page(self, "GTK 应用透明度",
                 "Nautilus 等 GTK 应用的窗口与侧栏，独立于 Plasma 的 Qt 透明度。"
                 "性能模式建议 ≥85，否则会透视后面的窗口。")
        cur = gtk_opacity_get()

        def apply(v):
            gtk_opacity_set(v)
            self.say(f"GTK 不透明度 = {v}%，Nautilus 正在重启生效")

        p.scale("窗口 / 侧栏不透明度", f"当前 {cur}%（100 = 完全不透明）",
                0, 100, 1, str_or(cur, 90), apply, 0, " %")

    def build_dock(self):
        p = Page(self, "Dock 尺寸", "修改后等离子桌面会重启一次（约 2 秒），属于正常现象。")
        cur_h = read_plasmashell_thickness() or "68"
        cur_z = ini_get(APPLETSRC, "Containments][124][Applets][126][Configuration][General",
                        "dockMagnification") or "110"

        def apply_h(v):
            ok, out = run_adjust("dock-height", v)
            self.report(ok, out, f"Dock 高度 = {v}px，桌面重启中")

        def apply_z(v):
            ok, out = run_adjust("dock-zoom", v)
            self.report(ok, out, f"图标悬停放大 = {v}%，桌面重启中")

        p.scale("Dock 栏高度", "默认 68，建议 56-96（px）", 40, 140, 4, cur_h, apply_h, 0, " px")
        p.scale("图标悬停放大", "100 = 不放大，建议 110-135（%）", 100, 150, 5, cur_z, apply_z, 0, " %")

    def build_logo(self):
        p = Page(self, "顶部任务栏 Logo", "左上角菜单按钮图标，切换后桌面自动重启。")
        cur = "?"
        ok, out = run_adjust("list")
        m = re.search(r"左上角菜单图标 \(menuIcon\) = (\S+)", out or "")
        if m:
            cur = m.group(1)
        names = {
            "cachyos-logo-symbolic": "CachyOS（白色，推荐）",
            "start-here-kde-symbolic": "苹果（原版）",
            "start-here-kde-plasma-symbolic": "KDE Plasma",
        }
        p.note(f"当前：{cur} —— {names.get(cur, '自定义')}")

        def choose(icon):
            ok2, out2 = run_adjust("logo", icon)
            self.report(ok2, out2, f"顶部 Logo 已切换为 {names.get(icon, icon)}")

        p.button("CachyOS 标志", "纯白色剪影，与 Tahoe 顶栏最协调", "使用",
                 lambda: choose("cachyos-logo-symbolic"))
        p.button("苹果标志", "恢复 macOS 默认苹果剪影", "使用",
                 lambda: choose("start-here-kde-symbolic"))
        p.button("KDE Plasma 标志", "Plasma 官方 logo", "使用",
                 lambda: choose("start-here-kde-plasma-symbolic"))
        p.button("自定义图标名", "输入图标主题 places/scalable 下的图标名（不含 .svg）", "输入…",
                 lambda: self.prompt_text("自定义 Logo", "图标名", cur, choose))

    def build_winanim(self):
        p = Page(self, "窗口动画",
                 "神灯 genie 是 macOS 的最小化动画。软件渲染已强制开启动画，极少数场景可能轻微掉帧。")
        st = ""
        ok, out = run_adjust("winanim", "status")
        if ok:
            st = out

        def status_of(pattern, default="false"):
            m = re.search(pattern, st)
            return m.group(1) if m else default

        genie = status_of(r"magiclamp\) = (\w+)")
        glide = status_of(r"\(glide\)\s*= (\w+)")
        slide = status_of(r"\(slide\)\s*= (\w+)")
        speed = status_of(r"全局动画速度\s*= ([0-9.]+)", "1.0")

        def preset(name, text):
            def run():
                ok2, out2 = run_adjust("winanim", "preset", name)
                self.report(ok2, out2, text)
                GLib.idle_add(self.refresh)

            return run

        p.buttons([("macOS 风格", "神灯 + 滑入 + 标准速度", preset("macos", "已应用 macOS 风格动画")),
                   ("均衡", "神灯 + 稍快速度", preset("balanced", "已应用均衡动画")),
                   ("快速", "关闭动画，性能优先", preset("fast", "已应用快速动画")),
                   ("全部关闭", "关闭所有窗口动画", preset("off", "已关闭所有窗口动画"))])

        def toggle(name, label):
            def apply(v):
                ok2, out2 = run_adjust("winanim", name, "on" if v == "true" else "off")
                self.report(ok2, out2, f"{label} = {v}")

            return apply

        p.switch("最小化神灯 genie", "macOS 的小窗口吸进 Dock 动画", genie, toggle("genie", "神灯动画"))
        p.switch("窗口打开 / 关闭滑入", "glide 动画", glide, toggle("glide", "滑入动画"))
        p.switch("桌面切换滑动", "slide 动画", slide, toggle("slide", "桌面滑动"))

        def apply_speed(v):
            ok2, out2 = run_adjust("winanim", "speed", v)
            self.report(ok2, out2, f"动画速度 = {v}x")

        p.scale("全局动画速度", "0.25 = 快，1.0 = 标准，2.0 = 慢", 0.25, 2.0, 0.05,
                speed, apply_speed, 2, "x")

    def build_misc(self):
        p = Page(self, "其他", "查看当前配置、恢复默认、切换性能 / 完整模式。")

        def show_config():
            ok, out = run_adjust("list")
            dialog = Gtk.Window(transient_for=self, modal=True, title="当前配置")
            dialog.set_default_size(800, 620)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            scroller = Gtk.ScrolledWindow()
            scroller.set_vexpand(True)
            view = Gtk.TextView(editable=False, monospace=True)
            view.get_buffer().set_text(out if ok else "读取失败")
            view.set_margin_top(10)
            view.set_margin_bottom(10)
            view.set_margin_start(10)
            view.set_margin_end(10)
            scroller.set_child(view)
            box.append(scroller)
            close = Gtk.Button(label="关闭")
            close.set_margin_bottom(10)
            close.set_halign(Gtk.Align.CENTER)
            close.connect("clicked", lambda _b: dialog.close())
            box.append(close)
            dialog.set_child(box)
            dialog.present()

        def reset_all():
            self.confirm("恢复圆角与透明度为默认值？", lambda: self.report(
                *run_adjust("reset"), "已恢复默认"))

        def toggle_mode():
            cur = ini_get(KWINRC, "Plugins", "liquidglassEnabled") == "true"
            mode = "性能模式（流畅）" if cur else "完整模式（液态玻璃，可能卡）"
            self.confirm(f"当前 {'完整' if cur else '性能'} 模式，切换到 {mode}？",
                         lambda: self.report(*run_adjust_toggle("perf" if cur else "full"),
                                             f"已切换到 {mode}，重新登录后完全生效"))

        def run_adjust_toggle(mode):
            toggle = os.path.join(SCRIPT_DIR, "toggle-glass.sh")
            if not os.path.exists(toggle):
                toggle = os.path.join(HOME, "toggle-macos-glass.sh")
            try:
                r = subprocess.run(["bash", toggle, mode], capture_output=True,
                                   text=True, timeout=180)
                return r.returncode == 0, (r.stdout or r.stderr or "").strip()
            except Exception as exc:  # noqa: BLE001
                return False, str(exc)

        p.button("查看当前配置", "在窗口内显示全部可调项的当前值", "查看", show_config)
        p.button("恢复默认", "圆角与透明度恢复主题初始值", "恢复", reset_all)
        p.button("切换性能 / 完整模式", "性能模式关闭液态玻璃，适合虚拟机软件渲染", "切换", toggle_mode)
        p.button("配置弹窗不进 Dock", "写入 KWin 规则，避免配置窗口在 Dock 来回出现",
                 "启用", lambda: self.report(*run_kwin_rule("install"), "已启用弹窗不进 Dock"))

    # ---- 小工具 ----
    def prompt_number(self, title, lo, hi, step, current, cb):
        win = Gtk.Window(transient_for=self, modal=True, title=title)
        win.set_default_size(420, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{side}")(16)
        scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL,
                          adjustment=Gtk.Adjustment(
                              value=float(current), lower=float(lo), upper=float(hi),
                              step_increment=float(step)))
        scale.set_digits(0 if step >= 1 else 2)
        scale.set_draw_value(True)
        box.append(scale)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.END)
        cancel = Gtk.Button(label="取消")
        ok_btn = Gtk.Button(label="应用")
        ok_btn.add_css_class("suggested-action")
        actions.append(cancel)
        actions.append(ok_btn)
        box.append(actions)
        cancel.connect("clicked", lambda _b: win.close())

        def apply(_b):
            v = scale.get_value()
            cb(str(int(round(v))) if step >= 1 else f"{v:g}")
            win.close()

        ok_btn.connect("clicked", apply)
        win.set_child(box)
        win.present()

    def prompt_text(self, title, placeholder, current, cb):
        win = Gtk.Window(transient_for=self, modal=True, title=title)
        win.set_default_size(460, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{side}")(16)
        entry = Gtk.Entry(text=current or "", placeholder_text=placeholder)
        box.append(entry)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.END)
        cancel = Gtk.Button(label="取消")
        ok_btn = Gtk.Button(label="应用")
        ok_btn.add_css_class("suggested-action")
        actions.append(cancel)
        actions.append(ok_btn)
        box.append(actions)
        cancel.connect("clicked", lambda _b: win.close())

        def apply(_b):
            text = entry.get_text().strip()
            if text:
                cb(text)
            win.close()

        ok_btn.connect("clicked", apply)
        win.set_child(box)
        win.present()

    def confirm(self, text, on_yes):
        win = Gtk.Window(transient_for=self, modal=True, title="确认")
        win.set_default_size(440, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        for side in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{side}")(18)
        lbl = Gtk.Label(label=text, wrap=True, xalign=0)
        box.append(lbl)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.END)
        cancel = Gtk.Button(label="取消")
        ok_btn = Gtk.Button(label="确定")
        ok_btn.add_css_class("destructive-action")
        actions.append(cancel)
        actions.append(ok_btn)
        box.append(actions)
        cancel.connect("clicked", lambda _b: win.close())

        def yes(_b):
            win.close()
            on_yes()

        ok_btn.connect("clicked", yes)
        win.set_child(box)
        win.present()

    def rebuild(self, key):
        """切换分类时只重建这个页面，窗口本身不关闭（Dock 只有一个图标）。"""
        for t in list(self.timers):
            GLib.source_remove(t)
        self.timers.clear()
        old = self.stack.get_child_by_name(key)
        if old is not None:
            self.stack.remove(old)
        builder = self.builders.get(key)
        if builder is None:
            return
        self.register(key, self.page_names[key], builder)
        self.stack.set_visible_child_name(key)

    def refresh(self):
        key = self.stack.get_visible_child_name()
        if key:
            self.rebuild(key)


def read_plasmashell_thickness():
    inside = False
    try:
        for line in open(PLASMASHELLRC, encoding="utf-8", errors="replace"):
            s = line.strip()
            if s.startswith("["):
                inside = s == "[PlasmaViews][Panel 124][Defaults]"
                continue
            if inside and s.startswith("thickness="):
                return s.split("=", 1)[1].strip()
    except FileNotFoundError:
        pass
    return None


def run_kwin_rule(action):
    script = os.path.join(SCRIPT_DIR, "kwin-rule.sh")
    if not os.path.exists(script):
        return False, "缺少 kwin-rule.sh"
    try:
        r = subprocess.run(["bash", script, action], capture_output=True,
                           text=True, timeout=60)
        return r.returncode == 0, (r.stdout or r.stderr or "").strip()
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="io.github.desktoptoolkit.ConfigCenter")

    def do_activate(self):
        win = self.props.active_window or Center(self)
        win.present()


def main():
    if not ADJUST:
        print("找不到 adjust-window.sh", file=sys.stderr)
        return 1
    GLib.set_prgname("io.github.desktoptoolkit.ConfigCenter")
    GLib.set_application_name("桌面外观配置中心")
    app = App()
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
