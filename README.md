# desktop-toolkit

[![self-check](https://github.com/wangmingfa/desktop-toolkit/actions/workflows/self-check.yml/badge.svg?branch=main)](https://github.com/wangmingfa/desktop-toolkit/actions/workflows/self-check.yml)

统一管理电脑相关脚本的工具箱。目标：**拉下仓库 → 运行一个总入口 → 菜单选择 → 开始执行**；
同时每个功能都能**单独一条命令直接跑**（`bash modules/<分类>/<脚本>.sh`），不必进菜单。

## 快速开始

```bash
# 克隆
git clone https://github.com/wangmingfa/desktop-toolkit.git ~/code/desktop-toolkit
cd ~/code/desktop-toolkit

# 唯一入口：图形菜单，选择对应选项即可（无 GUI 时自动转为命令行 TUI）
./main.sh
```

脚本会自动识别 GUI 工具：**容器里用 zenity，宿主机 KDE 上用 kdialog**。
菜单里选中「外观美化 → KDE 外观美化 → 桌面外观配置中心」就能交互式调整全部配置，不需要记命令。

> **无 GUI（headless/SSH/纯 TTY）自动进入命令行(TUI)模式**：检测不到 zenity/kdialog 时，
> `main.sh` 不再退出，而是用文本菜单，并把**需要 GUI 的选项（外观美化等）自动隐藏**，
> 只保留纯命令行可用的（网络镜像、Niri+DMS、占位分类、关于）。所有交互在终端完成。
> 判定为"GUI 环境"的依据是 zenity/kdialog 是否存在；有 GUI 但没装它们时也会走 TUI，
> 装任一即可恢复图形菜单（`sudo dnf install zenity` / `sudo pacman -S zenity`）。

> 配置中心现在默认打开**单窗口版（GTK4）**：左侧分类、右侧内容，切换分类只换页面，
> 窗口不会关闭重开，Dock 上始终只有一个图标。GTK4 不可用时自动退回 zenity/kdialog 菜单版
> （想强制用旧版：`DT_CONFIG_CLI=1 ./main.sh`）。

> 首次部署建议顺序（KDE）：
> 1. `主菜单 → 外观美化 → ① KDE 外观美化 → ① 安装 macOS 26 (Tahoe 液态玻璃)`
> 2. `主菜单 → 外观美化 → ① KDE 外观美化 → ④ 桌面外观配置中心`（调圆角/透明度/Dock/Logo/窗口动画）
> 3. VMware 软件渲染环境下选 `⑤ 切换到性能模式`，卡顿会明显缓解
>
> 不想进菜单的话，这三步等价于 `install-theme.sh` → `config-center.sh` → `toggle-glass.sh perf`。

---

## 直接运行（不进菜单）

约定很简单，记这三条就够：

1. **所有功能都在 `modules/<分类>/` 下**，直接用 `bash` 跑，例如 `bash modules/appearance/toggle-glass.sh full`。
2. **不带参数 = 交互菜单**（GUI/TUI 自适应）；**带参数 = 纯命令行**，可写进脚本、SSH 一行搞定。
3. 公共能力在 `lib/`，脚本自己会 `source`，不需要先 `cd` 或设环境变量。仓库放哪都能跑。

### 命令速查

| 分类 | 功能 | 直接命令 |
|------|------|----------|
| 外观 | KDE 外观总入口（三套风格 + 微调） | `bash modules/appearance/kde-scheme.sh` |
| 外观 | KDE 安装 macOS 26 Tahoe（液态玻璃） | `bash modules/appearance/install-theme.sh` |
| 外观 | KDE 安装 macOS 15 经典（WhiteSur） | `bash modules/appearance/install-kde-sequoia.sh` |
| 外观 | KDE 安装 Windows 11（Fluent） | `bash modules/appearance/install-kde-fluent.sh` |
| 外观 | KDE 桌面外观配置中心（单窗口） | `bash modules/appearance/config-center.sh` |
| 外观 | KDE 底层调节（圆角/透明度/Dock/Logo/动画） | `bash modules/appearance/adjust-window.sh help` |
| 外观 | 性能模式 / 完整模式切换 | `bash modules/appearance/toggle-glass.sh perf` |
| 外观 | 安装白色 CachyOS 顶栏 Logo | `bash modules/appearance/install-logo.sh` |
| 外观 | 修 GTK 4.14 主题（窗口全透明） | `bash modules/appearance/fix-gtk-theme.sh fix` |
| 外观 | 窗口按钮位置（macOS 左 / Windows 右） | `bash modules/appearance/window-buttons.sh left` |
| 外观 | 配置弹窗不进 Dock（KWin 规则） | `bash modules/appearance/kwin-rule.sh install` |
| 外观 | GNOME 外观配置中心 | `bash modules/appearance/gnome/gnome-config-center.sh` |
| 外观 | GNOME 安装 macOS 26 / 15 / Fluent | `bash modules/appearance/gnome/install.sh macos26` |
| 桌面 | 一键装 Niri + DMS | `bash modules/wm/niri-dms.sh` |
| 桌面 | 一键配 Niri + Noctalia | `bash modules/wm/niri-noctalia.sh` |
| 桌面 | 桌面外壳切换（DMS ↔ Noctalia） | `bash modules/wm/niri-shell-switch.sh noctalia` |
| 桌面 | Niri 可视化配置 | `bash modules/wm/niri-config.sh` |
| 诊断 | Niri 环境体检 / 一键修复 | `bash modules/system/niri-doctor.sh` |
| 诊断 | 通用环境体检（磁盘/内存/服务/更新） | `bash modules/system/env-doctor.sh` |
| 网络 | GitHub 国内镜像（全局 git） | `bash modules/network/github-mirror.sh on` |
| 网络 | 代理一键配置（git/dnf/pip/npm/cargo） | `bash modules/network/proxy-setup.sh on` |
| 应用 | UU 远程被控端 安装/登录/体检/卸载 | `bash modules/apps/uu-remote.sh install` |
| 应用 | WowType 输入法 安装/体检/卸载 | `bash modules/apps/wowtype.sh install` |
| 开发 | git 配置 / 开发工具安装 | `bash modules/dev/setup-dev.sh` |
| 备份 | 配置备份/恢复/清理 | `bash modules/backup/backup-config.sh` |

---

## 1. 外观美化

### 1.1 总入口（KDE）

```bash
bash modules/appearance/kde-scheme.sh
```

菜单里包含：安装三套风格、打开配置中心、性能/完整模式切换、窗口调整滑块、装 Logo、查看当前可调项。
下面的安装器也都可以单独跑。

### 1.2 KDE 三套风格（同一桌面环境**二选一**，会互相覆盖）

| 风格 | 命令 | 说明 |
|------|------|------|
| macOS 26（Tahoe 液态玻璃） | `bash modules/appearance/install-theme.sh` | `MacTahoe Liquid KDE`，当前默认方案，仅 Arch 系（`pacman` 装 cmake/extra-cmake-modules） |
| macOS 15（经典 Sequoia） | `bash modules/appearance/install-kde-sequoia.sh` | `WhiteSur-kde`，克隆上游仓库后跑其安装器，需要 git |
| Windows 11（Fluent） | `bash modules/appearance/install-kde-fluent.sh` | `Fluent-kde`，圆角/Mica 质感，非 macOS 风格 |

克隆走 `dt_clone` 的镜像回退（直连 → gh-proxy → ghfast → fastgit），受限网络下无需手动改 remote。
装完在 `系统设置 → 外观` 里选择对应主题；Kvantum 若没生效，到 `颜色 → Kvantum` 里选同名方案。

### 1.3 桌面外观配置中心（KDE）

```bash
bash modules/appearance/config-center.sh          # 默认：GTK4 单窗口版
DT_CONFIG_CLI=1 bash modules/appearance/config-center.sh   # 强制旧版 zenity/kdialog 菜单
```

可调：圆角、整体/单组件透明度、玻璃质感（模糊/折射/色散）、渐变与装饰、GTK 应用透明度、
Dock 尺寸与悬停放大、顶栏 Logo、窗口动画（神灯 genie / 滑入 / 速度 / 预设）。
启动时会自动跑一次 `fix-gtk-theme.sh`，修掉 GTK4 主题兼容问题（否则 GTK4 窗口全透明）。

### 1.4 底层调节工具（不进界面，一条命令改一项）

```bash
bash modules/appearance/adjust-window.sh help          # 完整帮助与组件名
bash modules/appearance/adjust-window.sh list          # 打印全部可调项及当前值
bash modules/appearance/adjust-window.sh gui           # 滑块界面
bash modules/appearance/adjust-window.sh corner 18     # 窗口圆角 0-40（default 恢复）
bash modules/appearance/adjust-window.sh transparency 60        # 全部组件透明度
bash modules/appearance/adjust-window.sh transparency dock 85   # 单组件
bash modules/appearance/adjust-window.sh dock-height 56         # Dock 高度 40-140
bash modules/appearance/adjust-window.sh dock-zoom 125          # 图标悬停放大 %
bash modules/appearance/adjust-window.sh logo apple             # cachy|apple|plasma|图标名
bash modules/appearance/adjust-window.sh winanim preset macos   # macos|windows|balanced|fast|off
bash modules/appearance/adjust-window.sh winanim genie on       # 最小化神灯
bash modules/appearance/adjust-window.sh winanim speed 1.0      # 0.25 快 ~ 2.0 慢
bash modules/appearance/adjust-window.sh glass BlurStrength 3   # 玻璃参数（full 模式可见）
bash modules/appearance/adjust-window.sh reset                  # 全部恢复默认
```

组件名：`general finder menus popups apps search control-center about dock panel`。

### 1.5 性能模式 / 完整模式

```bash
bash modules/appearance/toggle-glass.sh perf   # 关液态玻璃+降模糊/折射（VMware 软件渲染推荐）
bash modules/appearance/toggle-glass.sh full   # 恢复液态玻璃（需硬件加速）
```

改的是 `~/.config/kwinrc`，**注销重登后生效**。首次切 `perf` 会备份原配置为 `kwinrc.bak-glass`。

### 1.6 顶栏白色 CachyOS Logo

```bash
bash modules/appearance/install-logo.sh
```

把 `assets/cachyos-logo-symbolic.svg` 装进 macOS 26 主题的图标目录并应用为顶部菜单 Logo，
可重复运行（主题需先安装）。

### 1.7 修复 GTK 4.14 主题兼容

```bash
bash modules/appearance/fix-gtk-theme.sh fix      # 默认就是 fix
bash modules/appearance/fix-gtk-theme.sh status   # 只检查
```

GTK 4.14 不支持把 `@import` 写在 `@media` 里、也不支持 `color-mix()`，主题一旦这么写整个 CSS 不加载，
GTK4 应用窗口只剩文字。脚本把这两处改写成等价写法，首次修改前备份为 `*.bak-gtkfix`。

### 1.8 窗口按钮布局（GTK/Electron 全局）

```bash
bash modules/appearance/window-buttons.sh left      # macOS：close,minimize,maximize:（左）
bash modules/appearance/window-buttons.sh right     # Windows：:minimize,maximize,close（右）
bash modules/appearance/window-buttons.sh status    # 打印当前布局
bash modules/appearance/window-buttons.sh           # 交互菜单（含自定义 + 校验）
```

⚠ 这是**全局**设置，作用于所有带客户端装饰的 GTK/Electron 应用（Capy、浏览器、设置等）。
macOS 左侧布局会把关闭键顶到左上角，正好压住 Capy 折叠侧栏后的展开按钮；遇到遮挡就切 `right`。
改后**应用要重启窗口**才生效。GNOME 侧同一个脚本也能用。

### 1.9 配置弹窗不进 Dock（KWin 规则）

```bash
bash modules/appearance/kwin-rule.sh install   # 写入 skipTaskbar 规则并立即生效
bash modules/appearance/kwin-rule.sh status    # 查看
bash modules/appearance/kwin-rule.sh remove    # 移除
```

写入 `~/.config/kwinrulesrc`，由 KWin 自动匹配 zenity/kdialog 窗口，开机永久生效，无常驻进程。

### 1.10 GNOME 侧

```bash
bash modules/appearance/gnome/gnome-config-center.sh        # 配置中心（安装/切换/状态）
bash modules/appearance/gnome/install.sh macos26            # macOS 26 Tahoe
bash modules/appearance/gnome/install.sh macos15            # macOS 15 经典（WhiteSur）
bash modules/appearance/gnome/install.sh fluent             # Windows 11（Fluent）
GN_FORCE_RESUME=1 bash modules/appearance/gnome/install.sh macos26   # 跳过"继续/重来"询问
```

- 安装器是**断点续装**状态机（6 步）：中断后重跑会问"继续上次进度（默认）还是重新开始"，
  进度记录在 `$GN_SRC_DIR/.install-state-<版本>`，装完自动清除。
- `main.sh` 启动时会扫描未完成的进度，直接在终端列出来让你一键续装。
- 依赖走发行版包管理器（`dnf`/`apt-get`/`pacman`/`zypper` 都支持），扩展走 `gnome-extensions`
  真实命令；`extensions.gnome.org` 拉不到的扩展尽力而为、失败只提示。
- **扩展装完自动启用并配置**：`dash-to-dock` 自动装成 macOS 风格 Dock（底部悬浮 + 自动隐藏 +
  点击最小化 + 圆点指示；Fluent 风格则为常驻居中任务栏），`blur-my-shell` 仅 macOS 26 自动启用
  （顶栏/Dock 毛玻璃）；`user-themes` 由系统包提供并自动启用，Shell 主题随风格设置好。
  下载地址按当前 GNOME Shell 版本向 EGO API 现问，不会因版本升级失效。
- **装完自动校验**：读回 gsettings 检查 GTK/图标/光标/Shell 主题目录是否真实存在、扩展是否已加载；
  Shell 主题值失效时自动改回正确主题名。新装的扩展通常需**注销重登**一次才加载。
- 装完自动创建启动器「GNOME macOS 美化」，并提示**注销重登**（GNOME 45+ 没有 Alt+F2 的 `r`）。

---

## 2. 窗口管理器 / 桌面方案

### 2.1 Niri + DMS（Dux Modular Shell）

```bash
bash modules/wm/niri-dms.sh                                   # 默认 alacritty
bash modules/wm/niri-dms.sh --terminal kitty                  # alacritty|kitty|ghostty
bash modules/wm/niri-dms.sh --skip-systemd                    # 不起 systemd 用户服务
bash modules/wm/niri-dms.sh --force                           # 忽略已装检查重跑
bash modules/wm/niri-dms.sh --uninstall                       # 卸载（保留 niri 本体）
```

走发行版包管理器（Fedora COPR `duxlabs/dms` / Arch extra `dux-shell` / Debian、Ubuntu PPA），
COPR 大包（`dms-cli` ~83MB）弱网下用 `dnf download` 续传兜底，中断可重跑。
同时修好系统级 Wayland 会话文件（`X-GDM-CanRunHeadless=true`），并自动 mask `mako`
避免它抢走 DMS 的通知总线名（否则顶栏起不来）。收尾会问要不要**立即重启显示管理器**。

### 2.2 Niri + Noctalia（第二种桌面外壳）

```bash
bash modules/wm/niri-noctalia.sh                              # 最省事
bash modules/wm/niri-noctalia.sh --wallpaper wallpaper        # backdrop|wallpaper|flat
bash modules/wm/niri-noctalia.sh --terminal ghostty --no-reload
bash modules/wm/niri-noctalia.sh --uninstall
```

niri 没装会**连带把 niri 装上**（只装合成器本体，不碰 DMS 那套），niri 已装则只叠 Noctalia。
配置写成独立模块文件 `~/.config/niri/noctalia.kdl`，主配置只加一行 `include`，回退干净。
**Fedora 45+ 官方源 / Arch 官方源**有包；更老的 Fedora 会主动拦下并说明原因。

### 2.3 外壳切换（DMS ↔ Noctalia）

```bash
bash modules/wm/niri-shell-switch.sh noctalia   # dms|noctalia|none
bash modules/wm/niri-shell-switch.sh            # 交互选择
```

两个都是完整桌面壳，同时开会抢顶栏/程序坞/Alt+Tab。切换 = 关一个的自启、开另一个的自启；
首次切换会把**原始配置**存到固定路径 `config.kdl.orig-shellswitch`，之后每次都从它整体重建，
所以来回切多少次都不会丢配置。`none` 只留 niri 本体。生效：注销重登，或
`niri msg action config-reload`。

### 2.4 Niri 可视化配置

```bash
bash modules/wm/niri-config.sh              # 交互菜单：改完自动生成 KDL + validate + 热重载
bash modules/wm/niri-config.sh --show       # 看当前设置与校验结果
bash modules/wm/niri-config.sh --dump       # 打印生成的 KDL 原文
bash modules/wm/niri-config.sh --uninstall  # 移除 include 与本工具生成的文件
```

菜单覆盖：搜索配置项、布局与外观（间距/焦点列居中/背景/焦点环/边框/阴影/窗口装饰）、
输入与焦点（键盘/触摸板/鼠标/焦点跟随）、光标与杂项（光标/截图/概览/模糊）、显示器输出（缩放/旋转/开关）。
本工具**独占** `~/.config/niri/dt-settings.kdl`，只写你显式改过的项，不动主配置里其它设置。

---

## 3. 系统诊断

```bash
bash modules/system/niri-doctor.sh          # 体检（只读）
bash modules/system/niri-doctor.sh --fix    # 能自动修的项直接修
```

逐项检查本仓库真实踩过的坑：niri 包是否装、系统级会话文件是否存在/是否被放到用户级目录、
`Exec` 是否绝对路径、是否缺 `X-GDM-CanRunHeadless=true`（GDM 静默丢弃会话的根因）、
niri 版本是否够 Noctalia 的模糊规则（≥ 26.04）、显示管理器单元能否探测到、
DMS 用户服务是否激活、DMS 与 Noctalia 是否在同时自启抢顶栏。

> `modules/system/` 是**自动扫描目录**：往里面丢一个 `.sh`，主菜单「系统诊断」里就自动出现，不用改 `main.sh`。

---

## 4. 网络工具

### 4.1 GitHub 国内镜像（全局 git）

```bash
bash modules/network/github-mirror.sh on       # 启用（写 ~/.gitconfig 的 insteadOf 重写）
bash modules/network/github-mirror.sh status   # 查看
bash modules/network/github-mirror.sh off      # 关闭
GH_PROXY=https://ghfast.top bash modules/network/github-mirror.sh on   # 换镜像前缀
```

启用后**所有** `git clone https://github.com/...`（包括仓库外的）都会走镜像，不必逐个改 remote。
镜像站地址会变动，失效时换 `GH_PROXY` 后重跑 `on`。

### 4.2 代理一键配置（受限网络）

```bash
bash modules/network/proxy-setup.sh on                          # 默认 http://127.0.0.1:7890
bash modules/network/proxy-setup.sh on http://127.0.0.1:1080    # 自定义
bash modules/network/proxy-setup.sh status
bash modules/network/proxy-setup.sh off
```

一次配好 git / dnf / pip / npm / cargo 的代理 + `no_proxy`，并写
`~/.config/environment.d/dt-proxy.conf` 让下次登录对所有用户会话生效（git/cargo 走 libcurl 读环境变量）。
没装某个工具就跳过并提示，不算失败；每项都幂等（`on` 覆盖、`off` 全清）。

---

## 5. 应用安装

### 5.1 UU 远程 Linux 被控端

```bash
bash modules/apps/uu-remote.sh              # 菜单
bash modules/apps/uu-remote.sh install      # 安装/更新（镜像下载 + SHA256 校验 + 用户服务）
bash modules/apps/uu-remote.sh login        # 扫码登录（需终端 + 手机 UU 远程 App）
bash modules/apps/uu-remote.sh status       # 服务/编码器/设备连接状态
bash modules/apps/uu-remote.sh doctor       # 体检 + 一键修复
bash modules/apps/uu-remote.sh logs         # 实时日志
bash modules/apps/uu-remote.sh remove       # 卸载（可保留 ffmpeg）
```

网易 UU 远程官方没有 Linux 版，这里装社区纯 Rust 实现（`VallierDev/uu-remote-linux`，
GPL-3.0，非官方，无 Wine）。装完用官方手机/Mac/Windows 客户端即可远程控制本机。

### 5.2 WowType 输入法（fcitx5 插件）

```bash
bash modules/apps/wowtype.sh                # 菜单
bash modules/apps/wowtype.sh install        # 安装/更新（镜像下载 + SHA256 + 发行版包）
bash modules/apps/wowtype.sh status         # 安装 / fcitx5 / 输入法配置状态
bash modules/apps/wowtype.sh doctor         # 体检 + 一键修复
bash modules/apps/wowtype.sh remove         # 卸载
```

词库内置，不需要联网训练。Fedora（dnf）为完整支持与实测环境，apt/pacman 为尽力而为分支。
`install` 会顺带带上 fcitx5 并写输入法配置。

两个应用脚本都支持：`UU_VERSION` / `WT_VERSION` 指定版本，`UU_MIRROR` / `WT_MIRROR`
切换下载镜像策略（`auto|ghproxy|ghfast|off`）。

---

## 6. 待扩展分类

`modules/system/` 是**自动扫描目录**（丢 `.sh` 即出现在主菜单「系统诊断」）；`modules/dev/`（开发环境）、`modules/backup/`（备份与恢复）已在 `main.sh` 注册对应子菜单。新增分类需在 `main.sh` 里加一行菜单项。

---

## 环境与支持矩阵

**基础要求**：bash 4+、git、`sudo`；交互界面需要 zenity 或 kdialog（都没有则自动 TUI）。

| 功能 | Arch / CachyOS | Fedora | Debian / Ubuntu | 其它 |
|------|----------------|--------|-----------------|------|
| GNOME 美化（3 套风格） | ✅ pacman | ✅ dnf | ✅ apt | ✅ zypper |
| KDE macOS 26（Tahoe） | ✅ pacman | ⚠️ 安装器写的是 pacman | ⚠️ 同左 | — |
| KDE macOS 15 / Fluent | ✅ | ✅ | ✅ | ✅（需 git，跑上游安装器） |
| KDE 配置中心 / 微调 | ✅ Plasma 6 | ✅ Plasma 6 | ✅ Plasma 6 | ✅ Plasma 6 |
| Niri + DMS | ✅ extra（`dux-shell`） | ✅ COPR `duxlabs/dms` | ✅ PPA `ppa:duxlabs/*` | ⚠️ openSUSE 未实测 |
| Niri + Noctalia | ✅ 官方源 | ✅ 45+ 官方源 | ❌ 源里没有 | — |
| Niri 可视化配置 / 体检 | ✅ | ✅ | ✅ | ✅（纯配置读写） |
| 窗口按钮 / GTK 修复 | ✅ | ✅ | ✅ | ✅（gsettings / GTK 配置） |
| UU 远程 / WowType | ✅ | ✅ 实测 | ✅ 尽力而为 | — |

`gsettings` 相关功能需要 GNOME 会话；KWin/Plasma 相关功能需要 KDE Plasma 6 会话。

---

## 支持的桌面环境与 macOS 版本

| 桌面环境 | macOS 26 (Tahoe 液态玻璃) | macOS 15 (经典 Sequoia) | Windows 11 (Fluent) |
|----------|---------------------------|-------------------------|---------------------|
| KDE Plasma | `MacTahoe Liquid KDE`（默认方案） | `WhiteSur-kde` | `Fluent-kde` |
| GNOME      | `MacTahoe-gtk-theme` | `WhiteSur-gtk-theme` | `Fluent-gtk-theme` |

- **macOS 26（Tahoe）**：最新液态玻璃风格，对应上游仓库 `vinceliuice/MacTahoe-*`。
- **macOS 15（经典 Sequoia）**：Big Sur / Sequoia 风格，对应 `vinceliuice/WhiteSur-*`。（说明：Apple 版本号由 15 直接跳到 26，**不存在 macOS 16~25**；「经典」指 Sequoia 及之前的连续版本系列。）
- **Windows 11（Fluent）**：非 macOS 的圆角 / Mica 质感风格，对应 `vinceliuice/Fluent-*`。

> 同一桌面环境里多套主题会互相覆盖，请二选一。

---

## 目录结构

```
desktop-toolkit/
├── main.sh                  # ← 唯一总入口（启动恢复检测 + 菜单选择）
├── lib/
│   ├── common.sh            # DT_ROOT、DBUS 环境、备份、GUI 检测、dt_clone/dt_download（镜像回退）
│   ├── ui.sh                # 通用菜单/滑块/确认框（zenity/kdialog/TUI 自适应）
│   ├── niri.sh              # Niri 系方案共享库：dnf 弱网兜底 / GDM 会话文件 / 收尾横幅
│   └── git-credential-dt    # 用 gh token 给 git 提供 HTTPS 凭据（可选，见"推送改动"）
├── scripts/
│   └── self-check.sh        # 仓库自检：静态拦住反复踩过的 bug 模式（提交前/CI 用）
├── modules/
│   ├── appearance/          # 外观美化
│   │   ├── kde-scheme.sh         # KDE 统一入口：三套风格安装切换 + 微调
│   │   ├── install-theme.sh      # KDE macOS 26 Tahoe 液体玻璃
│   │   ├── install-kde-sequoia.sh # KDE macOS 15 经典 (WhiteSur-kde)
│   │   ├── install-kde-fluent.sh  # KDE Windows 11 (Fluent-kde)
│   │   ├── config-center.sh      # 配置中心入口（优先 GTK 单窗口版）
│   │   ├── config-center-gtk.py  # 单窗口版配置中心（GTK4）
│   │   ├── adjust-window.sh      # 底层调节（圆角/透明度/Dock/Logo/动画/玻璃）
│   │   ├── toggle-glass.sh       # 性能 / 完整模式切换
│   │   ├── install-logo.sh       # 白色 CachyOS 顶栏 Logo
│   │   ├── fix-gtk-theme.sh      # 修 GTK 4.14 主题兼容
│   │   ├── window-buttons.sh     # 窗口按钮布局（macOS 左 / Windows 右 / 自定义）
│   │   ├── kwin-rule.sh          # 让配置弹窗不进任务栏/Dock（KWin 规则）
│   │   └── gnome/                # GNOME 桌面 macOS 美化
│   │       ├── install.sh             # 安装器（断点续装状态机）
│   │       ├── gnome-config-center.sh # GNOME 配置中心（GUI）
│   │       └── lib-gnome.sh           # GNOME 公共库
│   ├── wm/                  # 窗口管理器 / 桌面方案
│   │   ├── niri-dms.sh           # 一键装 Niri + DMS
│   │   ├── niri-noctalia.sh      # 一键配 Niri + Noctalia
│   │   ├── niri-shell-switch.sh  # DMS ↔ Noctalia 外壳切换
│   │   └── niri-config.sh        # Niri 可视化配置（生成 KDL + 校验 + 热重载）
│   ├── system/             # 系统诊断（自动扫描）
│   │   ├── niri-doctor.sh       # Niri 环境体检 + 一键修复
│   │   └── env-doctor.sh        # 通用环境体检（磁盘/内存/服务/更新/输入法）
│   ├── network/
│   │   ├── github-mirror.sh     # 全局 git 镜像
│   │   └── proxy-setup.sh       # git/dnf/pip/npm/cargo 代理 + no_proxy
│   ├── apps/
│   │   ├── uu-remote.sh         # UU 远程 Linux 被控端
│   │   └── wowtype.sh           # WowType 输入法（fcitx5 插件）
│   ├── dev/
│   │   └── setup-dev.sh         # git 配置 + 常用开发工具安装
│   └── backup/
│       └── backup-config.sh     # 用户级配置备份/恢复/清理
└── assets/                  # 图标、SVG 等资源
    ├── cachyos-logo-symbolic.svg
    └── cachyos-logo-symbolic-dark.svg
```

---

## 国内网络 / 镜像加速

大陆网络下，**GitHub 仓库克隆**（主题 / 图标 / 光标 / Release 资产）可能很慢或不可达。
本项目已内置镜像回退，无需手动改 remote。

### 自动回退（默认）

所有克隆走 `lib/common.sh` 的 `dt_clone`，所有 Release 下载走 `dt_download`，
默认 `DT_MIRROR=auto`：**先直连，失败自动切国内镜像**（`gh-proxy.com` → `ghfast.top` → `fastgit.org`）。

```bash
# 可覆盖镜像与策略（环境变量）
DT_MIRROR=auto       # auto(默认) | ghproxy | ghfast | fastgit | off
GH_PROXY=https://gh-proxy.com       # 镜像前缀，失效时更换
DT_GHFAST=https://ghfast.top       # 第二前缀镜像（auto 回退时用）
DT_GIT_KILL=60       # 单个源的硬上限（秒）；大包慢网可放宽 DT_DL_KILL（默认 300）
```

例：强制走 ghproxy 镜像安装 GNOME Tahoe：

```bash
DT_MIRROR=ghproxy bash modules/appearance/gnome/install.sh macos26
```

### 一键全局镜像（更省心）

想让**所有** `git clone https://github.com/...`（含仓库外的）都走镜像，用：

```bash
bash modules/network/github-mirror.sh on    # 启用（写入 ~/.gitconfig）
bash modules/network/github-mirror.sh off   # 关闭
bash modules/network/github-mirror.sh status
```

### 注意事项

- `ghproxy` 类镜像站地址会变动，失效时换 `GH_PROXY`（如 `https://gh-proxy.com`、`https://ghfast.top`）。
- `extensions.gnome.org`（GNOME 扩展）**没有稳定国内镜像** → 相关扩展尽力而为，失败只提示、不会让安装失败；
  卡顿时建议开代理（如 FlClash）。
- 已开代理且直连顺畅的机器，保持默认 `auto` 即可，直连优先不额外绕路。
- 走 COPR/S3 的大包（如 DMS 的 `dms-cli`）弱网下会被 dnf 的 low-speed 判定掐断，
  脚本用 `dnf download` 续传 + 本地 rpm 安装兜底，中断后重跑会继续下载。

---

## 主要可调项（在「桌面外观配置中心」里）

| 分类 | 内容 |
|------|------|
| 圆角 | KWin shapecorners 半径，实时生效 |
| 透明度 | 全局 + 10 个组件独立调节 |
| 玻璃质感 | 模糊 / 折射 / 色散（完整模式可见） |
| 渐变与装饰 | 渐变透明度、模糊范围 |
| GTK 应用透明度 | Nautilus 侧栏 / GTK3 / GTK4 |
| Dock 尺寸 | 高度 + 图标悬停放大 |
| 顶部任务栏 Logo | CachyOS（纯白）/ 苹果 / Plasma / 自定义 |
| 窗口动画 | macOS 神灯 genie 最小化 + 滑入 + 速度 + 预设 |

## 关于性能

VMware `vmwgfx` + `llvmpipe` 软件渲染下，液态玻璃全屏模糊会让 plasmashell CPU 飙到 ~67%。
工具箱默认使用**性能模式**（关闭 liquidglass），需要时用
`bash modules/appearance/toggle-glass.sh full` 切回完整模式。
窗口动画依赖 KWin 的 `KWIN_EFFECTS_FORCE_ANIMATIONS=1`（由脚本写入 systemd drop-in），
因为是按需动画，平时不耗资源。

---

## 常见问题

**GTK4 应用窗口完全透明（只剩文字）？**
GTK 4.14 不支持 `@import` 写在 `@media` 里，也不支持 `color-mix()`。主题生成的
`~/.config/gtk-4.0/gtk.css` 一旦用了这两种写法，整个主题不会加载，窗口就没有背景。
运行一次即可修复（配置中心启动时也会自动执行）：

```bash
bash modules/appearance/fix-gtk-theme.sh fix     # 修复
bash modules/appearance/fix-gtk-theme.sh status  # 检查
```

原文件会备份为 `gtk.css.bak-gtkfix`。

**Dock 上配置窗口图标来回闪？**
旧菜单版每翻一页都会开新窗口。现在默认使用单窗口版；如需旧版可用
`DT_CONFIG_CLI=1` 启动，并已通过 KWin 规则让这些弹窗不计入任务栏：

```bash
bash modules/appearance/kwin-rule.sh install
```

**左上角按钮把 Capy 的展开按钮压住了？**
macOS 左侧布局的关闭键在左上角，和侧栏折叠后的展开按钮重叠，没有"既左又避开"的布局。
把按钮移到右边：

```bash
bash modules/appearance/window-buttons.sh right
```

**登录界面看不到 Niri 会话（连齿轮都没有）？**
GDM 只放行带 `X-GDM-CanRunHeadless=true` 的会话文件，且只扫系统级目录。
先跑体检看它指哪一条：

```bash
bash modules/system/niri-doctor.sh          # 或 --fix 自动修
```

改完会话文件必须 `sudo systemctl restart <显示管理器>`，单纯"注销"无效。

**顶栏起不来 / DMS 服务没加载？**
多半是 `mako` 抢了通知总线名（`org.freedesktop.Notifications`）。体检会指出来，
`niri-dms.sh` 也会自动 `systemctl --user mask mako.service`（卸载时对称解除）。

**改了配置中心 / 主题设置后没生效？**
KWin 配置（圆角、玻璃、动画、按钮布局）通常**注销重登**后完全生效；niri 配置可以
`niri msg action config-reload` 热重载。

---

## 推送改动（凭据）

容器里没有可直接用的 git 凭据助手，本仓库提供了一个：用 `gh auth token` 自动提供 token。

```bash
# 换机器后执行一次
cp lib/git-credential-dt ~/.local/bin/
chmod +x ~/.local/bin/git-credential-dt
git config --global credential.helper dt

# 之后正常 push 即可，无需手动带 token
git add -A && git commit -m "..." && git push
```

## 如何新增脚本

1. 按分类放进 `modules/<分类>/`，例如 `modules/network/proxy.sh`
   （`modules/system/` 会被主菜单自动扫描，其它分类需要在 `main.sh` 里注册）。
2. 脚本开头加上：

```bash
DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
```

3. 在 `main.sh` 对应分类菜单里加一个选项调用它；GUI 专属项在菜单行第 4 字段加 `|gui`（TUI 下自动隐藏）。
4. 提交前跑一次自检（`bash -n` + 仓库踩坑模式检查）：

```bash
bash scripts/self-check.sh
```

同一个脚本也挂在 CI 上（`.github/workflows/self-check.yml`）：push 到 `main` 和 PR 都会跑，
跑不过就是红叉。本地先过一次能省一个来回。

详细约定（断点续装步骤同步、stdout/stderr 规范、镜像下载、GDM 会话文件等）见 `AGENTS.md`。

## 实测环境

- 宿主机：CachyOS / Arch-like，KDE Plasma 6，Wayland
- 容器：distrobox（`coding`），家目录与宿主机共享
- 仓库本身不绑定特定机器，脚本里用户相关路径都用 `$HOME` 动态解析
