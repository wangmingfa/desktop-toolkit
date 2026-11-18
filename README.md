# desktop-toolkit

统一管理电脑相关脚本的工具箱。目标：**拉下仓库 → 运行一个总入口 → 菜单选择 → 开始执行**。

目前包含 macOS Tahoe Liquid KDE 桌面美化的全套脚本，后续可继续按分类往里加系统/网络/开发/备份脚本。

## 快速开始

```bash
# 克隆
git clone https://github.com/wangmingfa/desktop-toolkit.git ~/code/desktop-toolkit
cd ~/code/desktop-toolkit

# 唯一入口：图形菜单，选择对应选项即可
./main.sh
```

脚本会自动识别 GUI 工具：**容器里用 zenity，宿主机 KDE 上用 kdialog**。菜单里选中「外观美化 → 桌面外观配置中心」就能交互式调整全部配置，不需要记命令。

> 首次部署建议顺序：
> 1. `主菜单 → 外观美化 → 安装 macOS Tahoe 主题`
> 2. `主菜单 → 外观美化 → 桌面外观配置中心`（调圆角/透明度/Dock/Logo/窗口动画）
> 3. VMware 软件渲染环境下选 `切换到性能模式`，卡顿会明显缓解

## 目录结构

```
desktop-toolkit/
├── main.sh                  # ← 唯一总入口（菜单选择）
├── lib/
│   ├── common.sh            # 仓库路径、DBUS 环境、备份、GUI 检测
│   └── ui.sh                # 通用菜单/滑块/确认框（zenity/kdialog 自适应）
├── modules/
│   ├── appearance/          # 外观美化
│   │   ├── kde-scheme.sh         # KDE 统一入口：macOS 26 / 16 安装切换 + 微调
│   │   ├── config-center.sh      # 桌面外观配置中心（macOS 26 微调）
│   │   ├── adjust-window.sh      # 底层调节工具（圆角/透明度/Dock/Logo/动画…）
│   │   ├── install-theme.sh      # 安装 macOS 26 Tahoe Liquid KDE 主题
│   │   ├── install-kde-sequoia.sh # KDE 安装 macOS 16 经典 (WhiteSur-kde)
│   │   ├── toggle-glass.sh       # 性能 / 完整模式切换
│   │   ├── install-logo.sh       # 安装纯白 CachyOS 顶部栏 Logo
│   │   └── gnome/                # GNOME 桌面 macOS 美化
│   │       ├── install.sh              # 安装器：macos26 / macos16
│   │       ├── gnome-config-center.sh  # GNOME 配置中心（GUI）
│   │       └── lib-gnome.sh            # GNOME 公共库
│   ├── system/              # 系统配置（待扩展）
│   ├── network/             # 网络工具（待扩展）
│   ├── dev/                 # 开发环境（待扩展）
│   └── backup/              # 备份与恢复（待扩展）
└── assets/                  # 图标、SVG 等资源
    ├── cachyos-logo-symbolic.svg
    └── cachyos-logo-symbolic-dark.svg
```

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
2. 脚本开头加上：

```bash
DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh"
source "$DT_ROOT/lib/ui.sh"
```

3. 在 `main.sh` 对应分类菜单里加一个选项调用它；如果做成自动扫描，也可以直接放进目录即可见。

## 支持的桌面环境与 macOS 版本

| 桌面环境 | macOS 26 (Tahoe 液态玻璃) | macOS 16 (经典 Sequoia) |
|----------|---------------------------|-------------------------|
| KDE Plasma | `MacTahoe Liquid KDE`（默认方案） | `WhiteSur-kde` |
| GNOME      | `MacTahoe-gtk-theme` | `WhiteSur-gtk-theme` |

- **macOS 26（Tahoe）**：最新液态玻璃风格，对应上游仓库 `vinceliuice/MacTahoe-*`。
- **macOS 16（经典）**：Big Sur / Sequoia 风格（注：Apple 版本号由 15 直接跳到 26，这里沿用「16」称呼经典系列），对应 `vinceliuice/WhiteSur-*`。

GNOME 侧使用：
```bash
./modules/appearance/gnome/install.sh macos26   # 或 macos16
./modules/appearance/gnome/gnome-config-center.sh   # 交互式
```

KDE 侧统一入口（安装时选版本，两套二选一）：
```bash
./modules/appearance/kde-scheme.sh
# 或从 main.sh：外观美化 -> KDE 外观美化
```

> 注意：同一桌面环境里两套主题会互相覆盖，请二选一。

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

VMware `vmwgfx` + `llvmpipe` 软件渲染下，液态玻璃全屏模糊会让 plasmashell CPU 飙到 ~67%。工具箱默认使用**性能模式**（关闭 liquidglass）。窗口动画依赖 KWin 的 `KWIN_EFFECTS_FORCE_ANIMATIONS=1`（由脚本写入 systemd drop-in），因为是按需动画，平时不耗资源。

## 环境

- 宿主机：CachyOS / Arch-like，KDE Plasma 6，Wayland
- 容器：distrobox（`coding`），家目录与宿主机共享
- 仓库本身不绑定特定机器，脚本里用户相关路径都用 `$HOME` 动态解析
