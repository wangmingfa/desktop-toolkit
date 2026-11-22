# desktop-toolkit 开发规则（AGENTS.md）

> 本文件沉淀本项目在**受限网络 + GNOME/KDE 美化**场景下反复验证过的约定与踩坑经验。
> **新增任何功能 / 脚本 / 安装步骤时，按下述规则走，避免遗漏。**
> 规则优先级：本文档是**必须遵守的 checklist**，不是建议。

---

## 0. 项目结构速览

```
desktop-toolkit/
├── main.sh                  # 唯一总入口：启动恢复检测 + 图形主菜单
├── scripts/
│   └── self-check.sh        # 仓库自检：静态拦住反复踩过的 bug 模式(提交前/CI 用)
├── lib/
│   ├── common.sh            # DT_ROOT、DBUS 环境、备份、GUI 检测、dt_clone 镜像克隆、dt_download 镜像下载
│   ├── ui.sh                # dt_menu / dt_confirm / dt_info / dt_ask_*（zenity/kdialog 自适应）
│   └── niri.sh              # Niri 系方案共享库：dnf 弱网兜底 / GDM 会话文件修正 / 彩色收尾横幅
└── modules/
    ├── appearance/gnome/    # GNOME 桌面 macOS 美化
    │   ├── install.sh           # 安装器 + 断点续装状态机（macos26 / macos15）
    │   ├── gnome-config-center.sh  # GNOME 配置中心（GUI 菜单）
    │   └── lib-gnome.sh         # GNOME 公共库（步骤函数、gsettings、扩展、启动器）
    ├── appearance/…         # KDE 侧同类模块
    ├── network/             # 网络相关
    │   ├── github-mirror.sh     # 全局 git 镜像
    │   └── proxy-setup.sh       # git/dnf/pip/npm/cargo 代理 + no_proxy 一键配置
    ├── wm/                  # 窗口管理器 / 桌面方案
    │   ├── niri-dms.sh          # 一键安装 Niri + DMS (Dux Modular Shell)
    │   ├── niri-noctalia.sh     # 一键配置 Niri + Noctalia 桌面外壳
    │   └── niri-shell-switch.sh # DMS ↔ Noctalia 外壳切换(避免双壳抢顶栏)
    ├── system/              # 系统诊断(由 main.sh 的 sub_system 自动扫描)
    │   ├── niri-doctor.sh       # Niri 环境体检 + 一键修复
    │   └── env-doctor.sh        # 通用环境体检(磁盘/内存/服务/更新/输入法)
    ├── apps/                # 应用安装(由 main.sh 的 sub_apps 列出)
    │   ├── uu-remote.sh         # UU 远程 Linux 被控端 安装/登录/体检/卸载
    │   └── wowtype.sh           # WowType 输入法(fcitx5 插件) 安装/体检/卸载
    ├── dev/                 # 开发环境(由 main.sh 的 sub_dev 列出)
    │   └── setup-dev.sh         # git 配置 + 常用开发工具安装
    └── backup/              # 备份与恢复(由 main.sh 的 sub_backup 列出)
        └── backup-config.sh     # 用户级配置备份/恢复/清理
```

- 入口只认 `main.sh`；模块通过 `source lib/common.sh` / `source lib/ui.sh` 取公共能力。
- 模块路径：`DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"`（lib 里已定 `DT_ROOT`）。
- **同一合成器/平台的多个方案**要把公共部分抽成 `lib/<平台>.sh`（例：`lib/niri.sh` 被
  `niri-dms.sh` 与 `niri-noctalia.sh` 共用），别在每个方案里各复制一份 dnf 兜底/会话文件/横幅。

---

## 1. 新增一个"脚本/模块"的固定套路（checklist）

1. **放对位置**：`modules/<分类>/<名字>.sh`（分类：appearance / system / network / dev / backup）。
2. **取公共能力**：开头 `source "$DT_ROOT/lib/common.sh"` 和 `source "$DT_ROOT/lib/ui.sh"`；如依赖模块内公共库（如 GNOME 的 `lib-gnome.sh`）也要 source。
3. **GUI 自适应**：交互一律走 `dt_detect_gui` + `dt_menu` / `dt_confirm` / `dt_info` / `dt_ask_num` / `dt_ask_text`；**不要直接调 zenity/kdialog**（容器/宿主机两套工具要通用）。纯终端兜底用 `read -p`。
   - **TUI 兜底已内置**：`dt_detect_gui` 找不到 zenity/kdialog 时（`GUI=none`），`ui.sh` 的 `dt_menu`/`dt_confirm`/`dt_info`/`dt_ask_*` 自动退化为**文本交互**，无需额外 `read -p` 分支。
   - **菜单行第 4 字段 `|gui`**：表示"需要 GUI 环境"的选项，TUI 下由 `dt_menu` 自动隐藏（如 `main.sh` 的"外观美化"）。新增 GUI 专属菜单项时**必须**加 `|gui` 后缀，否则 headless 机器上会误显示。
   - **stdout/stderr**：TUI 的菜单文本/提示一律走 **stderr**，`dt_menu` 的 stdout 只输出所选 key（它常被 `c=$(dt_menu ...)` 捕获；若提示打到 stdout 会被吞掉，且前导换行会让 `case` 匹配失败）。
   - **ui.sh 无多选，勾选-确认模式要自建**：`dt_menu` 是单选；需要"多选/复选框"（如 de-installer 可选依赖去掉勾选）时，用"**点击切换 + 确认安装**"模式：
     - 可选依赖**默认全勾选**（一键语义），数组 `sel` 存勾选 id；`de_in_sel <id> "${sel[@]}"` 判断，选中即从数组移除（重建数组），未选则加入。
     - 行标签 `[*]`=必须（key 加 `req-` 前缀，case `req-*)` 为 no-op 不可取消）/ `[x]`/`[ ]`=可选；`__install`/`back` 用 `__` 前缀特殊 key，避免与包 id 冲突。
     - 每行可加 `✓已装` 标记（`rpm -q "$pkg"` 判断），用户能看到哪些已装。
     - 安装只装**必须 + 勾选的可选**，`dnf install -y`；装完提示注销登录界面选会话。
   - **取消语义**：TUI 下回车/无效/EOF 返回**非零**（与 GUI 分支 zenity 取消一致），调用方用 `|| return 0`（回上级）/ `|| exit 0`（退出）；`|| continue` 在 `while true` 菜单循环里会死循环，**不要用**。
4. **注册入口**：在 `main.sh` 对应分类菜单加一个选项；需要自动扫描的放对应目录。
5. **可执行**：`chmod +x`（`.desktop` 启动器/`main.sh` 调用需要）。
6. **自检后再提交**：`bash -n <file>` 语法通过，且跑一次关键路径验证，再 `git commit` + `push`。

---

## 2. 新增"安装步骤"到状态机（断点续装）—— 最容易遗漏

安装器用**状态文件 + 步骤号**支持断点续装（GNOME 例：`$GN_SRC_DIR/.install-state-<version>`，字段 `version=` / `next_step=`）。

**新增/调整一个步骤时，必须同步改以下所有地方，否则恢复流程错位：**

1. **步骤标签**：`gn_step_label()` 加 `N) echo "说明"`。
2. **状态机合法范围**：`install.sh` 的 `gn_state_next()` 里 `case "${n:-}" in [2-N])`。
3. **执行循环上界**：`install.sh` 的 `for (( n = START_STEP; n <= N; n++ ))`。
4. **总步骤数提示**：把硬编码的 `/5`、`/6` 改成 `/N` —— 在 **`install.sh`（`gn_resume_confirm` 两处）** 和 **`main.sh`（`dt_resume_gnome` 的列表行与恢复提示行）**。
5. **步骤函数**：`step_xxx()` 打印 `==> [k/N] 说明`，调用 lib 函数；在循环 `case` 里加 `k) run_step k step_xxx`。
6. **恢复列表过滤**：`main.sh` 的 `gn_scan_pending` 里 `case "$next" in [2-N])`。

**步骤函数必须是幂等/可重入的**（中断后重跑不报错、不重复副作用）：
- 克隆到已存在目录要能继续（`dt_clone` 内部 `rm -rf` 后重建，天然幂等）。
- 已装好的包/扩展/主题要跳过（`grep -q` 判断存在即返回）。

> 状态机骨架（`run_step` 先写当前步、成功写下一步）已封装，新步骤只需写函数 + 注册，**别自造状态逻辑**。

---

## 3. 网络 / 下载（受限网络必备）

### 3.0 代理统一配置
- `modules/network/proxy-setup.sh on|off|status [URL]` 一次性配好 git/dnf/pip/npm/cargo 的代理 + no_proxy；未装工具自动跳过，dnf 走 sudo 写 `/etc/dnf/dnf.conf`。
- 默认 URL `http://127.0.0.1:7890`（与 lib/niri.sh 的弱网提示一致）；每项幂等（on 覆盖 / off 全清）。
- 配置文件按行改写一律用 awk（dnf.conf 的 `[main]`、cargo 的 `[http]`），不拼 sed 引号。
- 环境变量写入 `~/.config/environment.d/dt-proxy.conf`，下次登录对所有用户会话生效。

### 3.0b 下载 release 资产一律走 `dt_download`（不要裸 `curl -o`）
- `dt_download <github_asset_url> <dest>` 已实现：与 `dt_clone` 同一套镜像回退（直连 → gh-proxy.com → ghfast.top），单源硬上限用外部 `timeout`（`DT_DL_KILL`，默认 300s，大包慢网可放宽）。
- 成功 `0` / 失败 `1`；**stdout 不输出**（进度/错误全走 stderr），避免被 `$( )` 捕获污染。
- 适用：GitHub Release 的 `tar.gz` / `deb` / `rpm` / `.sha256` 等**文件**下载（与克隆仓库的 `dt_clone` 互补）。

### 3.1 克隆一律走 `dt_clone`（不要裸 `git clone`）
- `dt_clone <github_url> <dest> [branch]` 已实现：**直连 → gh-proxy.com → ghfast.top → fastgit.org** 自动回退。
- 单源**硬上限**用外部 `timeout`（`DT_GIT_KILL`，默认 60s）；git 内部的 `lowSpeedTime`/`connectTimeout` 在断连时会内部重试拖很久，**不可靠**，别依赖它们兜底。
- 已强制 `HTTP/1.1`（规避部分代理对 HTTP/2 流重置）、`GIT_TERMINAL_PROMPT=0`（卡住不弹凭据，直接判失败换下一源）。
- 可调环境变量：`DT_MIRROR=auto|ghproxy|ghfast|fastgit|off`、`GH_PROXY`、`DT_GHFAST`、`DT_GIT_STALL`、`DT_GIT_CONNECT`、`DT_GIT_KILL`。

### 3.2 别做外部"可达性探测"
- 主题安装脚本会探测 `iana.org` 等外网，受限网络下探测失败**直接退出**。**预装依赖绕过探测**（如 GNOME 装 `sassc` 跳过 WhiteSur 的 `prepare_deps` 网络探测）。
- `extensions.gnome.org` 无稳定国内镜像 → 相关扩展（dash-to-dock/blur-my-shell）**尽力而为**：失败只提示、`|| true`，**不能**让整个安装失败。

### 3.3 非关键下载"尽力而为"
- 返回值约定：成功 `0`，失败 `1`；但调用方对**可选件**（光标、联网扩展）用 `|| echo "提示"` 容错。

### 3.4 COPR / S3 大包下载超时的兜底（实测，必知）
- **COPR 的包体存在 AWS S3（`copr-pulp-prod.s3.amazonaws.com`），弱网下极慢且会断流。**
  dnf 按 **low-speed 判定**（30 秒内少于 1000 B/s）掐断连接，**且 `dnf install` 不能断点续传**，
  于是大包（如 DMS 的 `dms-cli` ~83MB）**永远卡在 3%**。
- 关键差异：**`dnf download` 支持续传**（重跑会在已下部分上继续）。
  所以兜底路径 = 循环 `dnf download --resolve --destdir=$DIR <包名>` 累积下载，再用**本地 rpm 安装**。
  `niri-dms.sh` 的 `dnf_install_resumable` 即此实现；`$DIR` 持久化，中断后重跑继续。
- **完整性判据用 `rpm2cpio`**（全量解包，截断必失败）。**不要用 `rpm -qp`**（截断文件仍带完整
  rpm 头，会误判为完整）；COPR 包未签名，`rpm -K` 也无输出，不可用。
- dnf5 **只认** `--setopt=timeout=` 与 `--setopt=retries=`；**不认** dnf4 的
  `transfer_timeout` / `retrycount` / `retry`（会报 `Option "..." not found`）。
- 低带宽阈值 dnf 不暴露、改不了，所以只能靠"续传 + 重试"兜底；`dnf download` **不要加 sudo**
  （实测非 root 可行，且避免 root 属主）。

---

## 4. stdout / stderr 约定（最容易踩、最难查）

> **stdout 只留"返回值"，一切进度/诊断/报错走 stderr。**
> 否则函数输出被 `$( )` 捕获时，诊断信息会污染返回值，造成"看似成功实为空值"的静默失败。

- `dt_clone` / `gn_clone`：stdout **只打印目录路径**；`[git] 尝试/超时/报错` 全部 `>&2`。
- 任何被 `var=$(func)` 捕获的函数，**禁止**在函数体内 `echo` 进度到 stdout。
- 报错用 `dt_err` 或 `echo "..." >&2`；日志用 `dt_log`。
- **`dt_info`/`dt_confirm` 只接收一个参数**：`dt_info "$title" "$body"` 传两个会**丢掉 body**（函数只用 `$1`）。多行文本必须拼成单参数：`dt_info "$title\n$body"`。

---

## 5. `set -euo pipefail` 安全

脚本统一 `set -euo pipefail`，以下几点必须注意：

- **管道命令替换静默退出**：`ls ... | head -1` 在 `$( )` 里，若 `ls` 无匹配会返回非零 → `set -e` 下整个脚本**静默退出**。必须 `|| true`：`found=$(ls -d ... | head -1 || true)`。
- **"尽力而为"命令加 `|| true`**（gsettings 设置失败、可选件安装、清理等）。
- **用进程替换取函数输出**：`read -r a b < <(func)`，避免命令替换在 `set -e` 下的隐性问题。
- **`local` 只在函数内用**；数组用 `local -a`。
- **函数返回非零要显式处理**：`"$fn"` 或 `|| return 1`，别让 `set -e` 在中间步意外中止。
- **systemctl 状态判断的非零陷阱**：`systemctl --user is-enabled/is-active` 对 masked/inactive/未启用返回非零，`if systemctl ... is-active; then` 会**误判**（masked 服务被判为"未运行"）。用 `$( )` 收集 + 字符串比较：`[ "$(systemctl --user is-active x 2>/dev/null)" = active ]`。
  - **`is-active` 对 inactive 会输出 "inactive" 且退出非零**：`x=$(systemctl is-active x 2>/dev/null || echo inactive)` 会**双写**（输出+追加 echo 各一个 "inactive"）。正确：`x=$(systemctl is-active x 2>/dev/null || true); echo "${x:-inactive}"`（`|| true` 保留输出不追加，再 `${x:-...}` 兜底空值）。
  - **`systemctl list-units` 的 UNIT 列有前导空格**：`grep '^[a-z0-9@_.-]+\.service'` 匹配不到（行首是空格）→ pipefail 下报"读取失败"。用 `grep -E '^\s+[a-z0-9@_.-]+\.service'` 或 awk 跳过含表头行。

---

## 6. 主题命名（gsettings 应用）—— 核心坑

> **主题安装器生成的目录带变体后缀（`WhiteSur-Dark`/`-Light`），基础名（`WhiteSur`）通常不存在。**
> 若把 gsettings 设成基础名，user-theme 扩展会回退默认 Adwaita → **顶栏/窗口不变**（本次真实事故）。

- **必须解析真实存在的目录名**：用 `gn_resolve_theme_name <base> [dark|light]`（默认深色，排除 solid/hdpi/xhdpi）。
- **目标色变体优先于基础名**：有的主题（Fluent）会同时生成"基础目录"（`Fluent`）且它对应**默认=浅色**；若把基础名放最优先，深色偏好会被误设成浅色基础版。`gn_resolve_theme_name` 已按"目标色变体 → 基础名 → 任意变体"顺序解析。
- 深浅色切换用 `gn_switch_color_scheme dark|light`（**同时**切 `color-scheme` 和主题变体，别只切一个）。
- 窗口按钮位置用 `gn_set_button_layout left|right` / `gn_button_layout`（macOS 红黄绿在左 / GNOME 在右）。
- 统一用 `gn_gs` 封装 `gsettings set`（失败走 stderr），别裸调 `gsettings set`。
- 光标实际安装名可能带 `-cursors` 后缀差异：**自动探测**（`ls -d ~/.local/share/icons/*[Cc]ursor* | head -1`），别硬编码。
- 图标变体：`-t blue` 先试、失败回退不带 `-t`（MacTahoe 认 blue，WhiteSur 不认）。
- 光标仓库要带 **owner 前缀**（`vinceliuice/WhiteSur-cursors`），否则克隆路径错误。

### 6.1 窗口按钮布局（GTK 客户端装饰全局）—— 踩坑

> **`org.gnome.desktop.wm.preferences button-layout` 是全局设置，作用于所有带客户端装饰(CSD)的 GTK/Electron 应用**（Capy / 浏览器 / 设置等），不只是 GNOME 主题。

- **macOS 左边风格（`close,minimize,maximize:`，冒号在末）会把关闭键顶到左上角**；像 Capy 这类应用在侧栏折叠后其"展开按钮"也出现在左上角，**两个按钮正好重叠**（本次真实事故，Capy v0.9.2）。
- **彻底解决只能把按钮移到右边**：`gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'`（关闭最右，Windows 风格）。**没有"既左又避开"的第三种布局**——只要关闭键在左上角，就必然压住左上角的展开控件。
- 改后 **GTK/Electron 应用必须重启才生效**（客户端装饰只在窗口创建时读布局）。
- 独立工具：`modules/appearance/window-buttons.sh`（GUI/TUI 自适应，macOS 左 / Windows 右 / GNOME 默认 / 自定义 + 校验），已注册 `main.sh` 外观子菜单第 ③ 项。
- `gsettings get/set` 的 **schema 和 key 必须拆成两个参数**（`gsettings get "$SCHEMA" "$GKEY"`），**别拼成一个带空格的字符串**（会当单参数永远失败）。
- 自定义 `button-layout` 校验：**恰好一个冒号**，两侧 token ∈ `close,minimize,maximize,appmenu`，**无重复**；非法值拒绝且不改动现状。

---

## 7. GNOME 扩展规则

- 用**真实命令** `gnome-extensions`（`install` / `enable` / `list`），不要只写配置文件。
- 系统自带扩展（user-themes / user-theme）走**发行版包**（Fedora 40+：`gnome-shell-extension-user-theme`，回退 `gnome-shell-extensions`；Debian/Arch 用 `gnome-shell-extensions`），**不联网下载**。
- **UUID 从 `metadata.json` 读取**，不要硬编码（不同发行版单复数/命名不同）。
- 启用：`gnome-extensions enable "$uuid"`；不行则 `gn_ext_force_enable "$uuid"`（写入 `org.gnome.shell enabled-extensions`，**保留现有**项）。
- Shell 主题生效依赖扩展加载；提示"注销重登 / Alt+F2+r（GNOME 45+ 已移除 `r`，需注销）"。

---

## 8. 安装完成收尾（不要遗漏）

1. **自动建启动器**：最后一步调 `gn_install_launcher`，生成 `.desktop`（应用列表可搜"GNOME macOS 美化"）+ macOS 风格 SVG 图标；`Terminal=true`（`sudo` 提权/进度需要 tty）。
2. **绿色完成横幅**：`$GREEN` 高亮"✅ 完成！已应用 …"，并提示注销重登注意事项。
3. **清状态文件**：`gn_state_clear`（否则 `main.sh` 启动仍会列出已完成进度）。
4. **恢复后不弹 GUI**：`main.sh` 恢复完成且状态清空 → `exit 0`，不再弹配置中心。
5. **"生效前提"要显式提示 + 代跑**：若装完必须重启服务/重登才生效（典型：装完 Wayland 合成器必须
   `sudo systemctl restart gdm`——GDM 只在启动时扫会话文件，单纯"注销"无效），收尾横幅里用**黄色加粗**
   把那条命令单独提出来，再用 `dt_confirm` 问"要现在重启吗"，答"是"就直接代跑。
   - 颜色变量（`DT_GREEN/DT_YELLOW/DT_CYAN/DT_BOLD/DT_NC`）**在非 tty 下退化为空串**，否则 ANSI 转义混进日志。
   - `dt_confirm` 需要 `source lib/ui.sh`；交互分支要受 `[ -t 0 ]` 保护，非交互环境（管道/CI）别卡在 `read`。
   - ⚠ **单测陷阱**：`dt_confirm` 在 `GUI=zenity` 时会**真的在桌面弹对话框**。测试时强制 `GUI=none`
     走 TUI 分支，否则会弹出若干窗口（本次踩过，弹了 7 个，事后用 `pkill -x zenity` 清）。
      **不只是 `dt_confirm`**：测试**任何**含 `dt_ask_text`/`dt_ask_num`/`dt_menu` 的模块都要 `GUI=none`
      （`echo | bash module.sh ...` 不设 GUI=none 会走 zenity 弹窗挂起 exit 124，如 fsearch 的
      `dt_ask_text` 踩过）。CLI 入口测试同理。
     另外**别用 `pkill -f` 带会出现在自己命令行里的 pattern**，会把自己的 shell 杀了。

---

## 9. 版本 / 仓库映射（新增风格/版本）

- 版本 → 仓库/主题/图标/光标映射集中在 `gn_version_info`；中文标签在 `gn_version_label`。**新增版本只改这两处 + 配置中心菜单项**。
- 同一桌面环境两套主题**互相覆盖**，菜单里明确"二选一"。
- 配置中心新增安装项：菜单加 `installXX|…`，case 里调 `install.sh <version>`。
- **新增非 macOS 风格**（如 Windows/Fluent）还需：
  - `install.sh` 的用法 `case "$VERSION"` 加新 id，并在 usage 文本加一行。
  - `main.sh` 恢复扫描的 glob **放宽**：`.install-state-macos*` → `.install-state-*`（否则新风格状态文件不被识别），且版本过滤 `case "$ver" in ...|新id)` 加新 id。
  - 光标源可为空：`gn_version_info` 第 7 字段留空，`gn_install_cursors` 已支持跳过（保留当前光标）。
  - **分支名不要想当然**：MacTahoe 用 `main`、WhiteSur/Fluent 用 `master`——先 `git ls-remote --symref <mirror>/<repo>.git HEAD` 确认默认分支，再写进映射。
- **KDE 侧新增风格**：镜像 `modules/appearance/install-kde-sequoia.sh` 建 `install-kde-<风格>.sh`（克隆用 `dt_clone`、**确认分支**、运行 `install.sh`、提示"系统设置->外观 选择主题"），并在 `kde-scheme.sh` 菜单加 `install<风格>` 项。KDE 主题仓库（`*-kde`）非 root 装到 `~/.local/share/{aurorae,color-schemes,plasma,Kvantum}`，**无需 sudo**。
- **KDE 配置中心（`config-center.sh`）对 KWin/Plasma 是通用微调**，不依赖主题；但要感知风格：`kde_active_style()` 按 `~/.local/share/plasma/desktoptheme/` 前缀判断（`MacTahoeLiquidKde*`→macos26，`Fluent*`→fluent，`WhiteSur*`→macos15）并在主菜单标题显示。**窗口动画预设**要按风格提供（如 `winanim preset windows` = 无神灯+滑入，非 macOS 风格用；macOS 用神灯 genie）。

- **给同一合成器加"第二种外壳"方案**（如 Niri + Noctalia，`modules/wm/niri-noctalia.sh`）时的约定：
  - **配置走"模块文件 + `include`"，不直接改主配置**：生成 `~/.config/niri/noctalia.kdl`，主配置只加
    `include "noctalia.kdl"`。**放在 `include` 列表末尾**才能让本模块的 `binds` 覆盖合成器内置绑定
    （如 `Alt+Tab`）；回退只需删掉那行 include + 删模块文件。
  - **桌面外壳类包先在发行版默认源找**：Noctalia 在 Fedora 45 默认源（5.5.0-3.fc45），无需 COPR/PPA；
    只有默认源没有时才走 COPR（那才需要 `lib/niri.sh` 的续传兜底）。**注意包往往只给最新发行版做**：
    Noctalia 的 RPM Fusion 页面标注 `Version: Fedora 45`，44 及更早的官方源里查不到这个包。
    所以 `preflight` 里要**读 `/etc/fedora-release` 把大版本号解析出来**，低于门槛直接 `exit 1` 并说明
    "官方包只给 Fedora 45"——否则会让 `dnf_install_retry` 空转三次重试才失败，用户只看到"安装失败"，
    看不出真正原因是发行版太旧。
  - **版本门槛要探测再写**：Noctalia 的模糊规则（`background-effect` / `blur`）要求 niri ≥ 26.04，
    老版本写进去会**直接报配置错误**。所以按 `niri --version` 探测，低于门槛就跳过该段并 `log` 说明。
  - **systemd 用户服务按发行版文档装**：Noctalia 包内 `assets/noctalia.service` 要拷到
    `~/.config/systemd/user/` 并**取消注释对应合成器的 `WantedBy=`**（Niri 用 `WantedBy=niri.service`），
    再 `systemctl --user daemon-reload` + `enable`。`WantedBy` 那几行是注释态，必须 `sed` 处理。
  - **合成器缺失要连带装上，别指望用户先跑别的脚本**：外壳方案（`niri-noctalia.sh`）的宿主是 niri，
    新机器上跑时不该要求"先去跑 niri-dms.sh"。做法是 `preflight` 检测到缺 niri 就置位 `NEED_NIRI=1`，
    由 `install_pkgs` 把 `niri` 与 `noctalia` 一起 `dnf install`，装完补 `niri_ensure_dm_session`
    （新装的 niri 还没有系统级会话文件，登录界面出不来）。**但只装合成器本体**，不要擅自连带 DMS 那套
    （COPR + 83MB 的 dms-cli）——那是另一个方案的意图，留给 `niri-dms.sh`。收尾横幅按 `NEED_NIRI`
    分两种文案（"已安装并配置" vs "已配置"）。
  - **包安装失败必须在写配置之前中止**：实测发现 sudo 要密码导致安装失败时，脚本仍继续生成配置，
    会留下"看似配置好实则跑不起来"的半装状态，`install_pkgs` 失败后直接 `exit 1`。


### 9.1 WM 方案（`modules/wm/`）的发行版支持矩阵

> **新增 WM 方案前先查这张表**，别以为包名在各发行版一致——外壳类包名几乎每个发行版都不同。

| 发行版 | Niri + DMS | Niri + Noctalia |
|---|---|---|
| Fedora 45 | ✅ 官方 COPR `duxlabs/dms`（主力目标） | ✅ 官方源 `noctalia` |
| Fedora ≤44 | ✅ | ❌ 包只给 45 做，`preflight` 主动拦下 |
| Arch | ✅ 官方 extra 源 | ✅ 官方源 |
| Debian / Ubuntu | ✅ 走官方 PPA `ppa:duxlabs/*` | ❌ 源里没有 noctalia，需源码编译 |
| openSUSE | ⚠️ 分支写了但没实测过 | ❌ |
| NixOS | ❌ | Noctalia 官方有专门 NixOS 页，脚本未做 |

- **包名在各发行版不一致，且会改名**：DMS 2.0 起在 Arch 上叫 **`dux-shell`**（旧名 `dms-shell`），
  在 Fedora/Debian/openSUSE/Void 上仍叫 `dms`。`niri-dms.sh` 的 pacman 分支必须写 `dux-shell`。
  Noctalia 则统一叫 `noctalia`。
- **`xwayland-satellite` 不必显式安装**：Dux 官方文档说明它是 niri 的依赖会**自动带上**，
  `niri-dms.sh` 清单里留着只是无害冗余（已装即 no-op）。
- **`mako` 会抢走 DMS 的通知总线名，导致顶栏起不来（实测）**：`dms.service` 与 `mako.service`
  的 `[Service]` 都声明 `BusName=org.freedesktop.Notifications`（DMS 自带通知中心）。mako 常被
  D-Bus 按需激活先占了这个名字，systemd 便拒绝加载 `dms.service`（日志
  `Two services allocated for the same bus name`），DMS 顶栏在重启后消失。`niri-dms.sh` 的
  `neutralize_mako` 在绑定后 `systemctl --user mask mako.service`（幂等，卸载时对称解除）；
  这与 waybar 的处理一致——DMS 方案里通知/顶栏都由 DMS 负责，mako/waybar 只装不用、避免冲突。
- **Noctalia 有 niri 版本门槛**：模糊规则（`background-effect` / `blur`）要求 niri ≥ 26.04，
  老版本写进去直接报配置错误。所以脚本按 `niri --version` 探测，低于门槛跳过该段。
  本机 Fedora 45 的 niri 是 `26.04-2.fc45`，刚好够。
- **显示管理器不能硬编码 `gdm`**：收尾必须提示"重启显示管理器"并支持代跑，但单元名各发行版不同——
  Fedora `gdm.service`、Arch/**CachyOS** `sddm.service`、Debian `gdm3.service`/`lightdm.service`、
  CachyOS 2026-01 版起 Plasma 用户可迁到 `plasmalogin.service`。
  统一走 `lib/niri.sh` 的 `niri_dm_unit()`（逐个 `systemctl is-enabled` 探测，回退
  `display-manager.service` 别名）+ `niri_restart_dm()`。**踩过的真实报错**：
  在 CachyOS 上硬编码 `sudo systemctl restart gdm` →
  `Failed to restart gdm.service: Unit gdm.service not found`。

### 9.2 配置切换/卸载类脚本的三条铁律（`niri-shell-switch.sh` / `--uninstall` 踩过）

1. **别用"增量注释 + 多次开关"做状态切换**。实测踩坑：`disable` 用 while-read 重写文件、
   `enable` 再还原，两次切换落在**不同秒**时备份路径带时间戳会各存一份，第二份存的是
   "已被切换过的"配置，重建基准被污染 → 切回原态少行。
   **正确做法：首次改动时存一份原始配置到【固定路径】（如 `config.kdl.orig-shellswitch`），
   之后每次切换都从原始配置按目标状态整体重建**（`build_shell_cfg keep_dms keep_noctalia`）。
   天然幂等，且中间态不可能丢失。
2. **别用 sed 做含空格/括号的替换**。`sed 's|...|...'"$MARK"'|'` 这类嵌套引号极易写错成
   "未闭合引号"而直接语法报错（实测踩过，且错误信息指向无关行号难定位）。
   **需要按行改写就用 awk**，正则与数据分离，无引号地狱。
3. **卸载必须放在安装动作之前处理**。脚本主流程是 `install_pkgs → 生成配置`，
   `--uninstall` 若放在末尾会"卸载时又去装包"。要在 install 之前 `if [ "$UNINSTALL" = 1 ]; then ...; exit 0; fi`。
   卸载保留合成器本体（niri 可继续给别的方案当宿主），只清本方案的配置/服务/包。

- **`modules/system/` 由 `sub_system()` 自动扫描**：新增诊断工具只需往该目录丢一个 `.sh`，
  主菜单会自动出现，**不需要改 `main.sh`**。目录为空时回退 `sub_placeholder` 提示。

### 9.3 niri 生态脚本踩坑（`niri-config.sh` / `niri-tools.sh` / `niri-wallpaper.sh` / `niri-dms-theme.sh` 实测）

**niri 26.04 原生能力（实测 validate，优先用原生少装外部进程）：**
- `binds { Print { screenshot-ui-open; } }` / `{ screenshot; }`：**截图动作内置**，`screenshot-ui-open` 开截图 UI（区域/全屏/窗口），`screenshot` 全屏；配 `screenshot-path "~/Pictures/..."`。
- **无名字 `output { background-image "<path>" }` = 应用到所有输出**，**无需 swaybg/swww 额外进程**（per-output 才要写 `output "名字" {}`）。
- `animation { window-movement|window-open|window-close|workspace-switch { spring damping-ratio=… stiffness=… epsilon=… } }`：内联 spring 语法，字段可 `niri validate` 验证。
- **`niri validate` 从 stdin 读**，**不接受文件位置参数**（`niri validate < file`，写 `niri validate file` 会报 `unexpected argument`）；片段（仅 binds/output 等）也能 validate，不必拼完整配置。

**多工具各自用独立 include 文件（避免互相覆盖）：**
- niri-config 独占 `dt-settings.kdl`、niri-tools 用 `tools.kdl`、niri-wallpaper 用 `wallpaper.kdl`，各自在主配置末尾加 `include optional=true "xxx.kdl"`（awk 幂等，别拼 sed 引号）。
- include 是**合并语义 + 末尾优先**：主配置里的 `animation{}`/`binds{}` 被各自 include 文件覆盖；删除某工具只需 `awk` 移除它的 include 行 + `rm` 它的 .kdl，不碰别的。

**DMS 顶栏/全局主题机制（不是随便改 shell.qml）：**
- 顶栏 QML 颜色来自 **`dms matugen generate --kind hex|image --value <hex|壁纸> --mode dark|light --spec dms`** 生成的 Material 主题，**同步 niri `colors.kdl` + gtk/fcitx5/终端等**（`dms matugen check` 输出 JSON 探测哪些应用可同步）。
- 自定义整个 UI 才用 `dms -c <含 shell.qml 的目录>` / `env DMS_SHELL_DIR`；一般美化只用 matugen。

**shell 脚本两个易踩坑（`set -euo pipefail` 下）：**
- **`cmd | head` 会让上游收到 SIGPIPE 非零 → pipefail 下整个管道返回非零**，`|| echo 失败` 会**误判**。要显示前 N 行：先 `out=$(cmd)` 收集，再 `echo "$out" | head`（echo 写完无 SIGPIPE）。
- **python f-string 内复用同一种引号会语法报错**（`f"  {"✅" if x else "  "} "` 内层又用双引号，部分 python 版本报 `SyntaxError`）。改用字符串拼接 `"  " + ("✅" if x else "  ") + " " + x["id"]`。

**include 行含双引号不能拼进 awk 程序（`niri-tools/audio/wlsunset/wallpaper` 同源 bug，已修）：**
- `TOOLS_INCLUDE='include optional=true "tools.kdl"'` 直接 `awk '{...; print "'"$TOOLS_INCLUDE"'"}'` 会让**awk 语法错误、include 从未写入**（快捷键/配置不生效且无报错）。必须 `awk -v inc="$TOOLS_INCLUDE" '{...; print inc}'` 传变量。改 include 一律 `awk -v`，别拼引号。

**测试 source 模块去 case 块：awk 模式必须匹配实际 case 模式：**
- 模块入口多用 `case "${1:-menu}" in`（niri-tools/wallpaper/app-installer/cliphist），若 awk 按 `^case "\$\{1:-\}" in` 去 case，**case 块没去掉** → source 时 `$1` 空走 `*) menu` 弹 GUI（zenity）**挂起 exit 124 无输出**。统一 `awk '/^case "\$\{1:-menu\}" in/{exit} {print}'`（模块用啥模式就匹配啥）。

**DMS 顶栏组件（barConfigs）—— 只存非默认值 + JS 默认解析：**
- `~/.config/dms/settings.json` 是 DMS UI 设置（`configVersion` 与 `SettingsData.qml` 的 `settingsConfigVersion` 一致，当前 42），但**只存改过的键**（没改过就没有 `barConfigs`，DMS 用 `SettingsSpec.js` 的默认）。所以 status 要先看 settings 有没有 barConfigs，没有就回退 SPEC 默认。
- **改 barConfigs 要写完整结构**（DMS 不深合并缺省字段），且**先备份 `.bak`、保留其他键**（`dmsWindowsFloatingSeeded`/`configVersion`）。组件 id 从 `BarWidgetCatalog.qml` 的 `"id":` 运行时解析；监控组件 id：`cpuUsage/memUsage/diskUsage/cpuTemp/gpuTemp/network_speed_monitor/battery`。
- **解析 SettingsSpec.js 的 JS 对象字面量**（`def: [{ id: "default", ... }]` 键无引号）→ 先正则给键补引号、去 `//` 注释、去尾逗号，再 `json.loads`；`ast.literal_eval` 会因裸键名失败。

---

## 10. GDM / Wayland 会话文件（"登录界面没有会话切换项"= 这几个坑）

> 场景：装完 niri 等 Wayland 合成器，登录界面**连左下角的齿轮都没有**。
> 结论经 GDM 51.1.1 源码（`libgdm/gdm-sessions.c` 的 `key_file_is_relevant`）逐条验证。

- **必须先有 `X-GDM-CanRunHeadless=true`（niri 上游包缺失，这是根因）**。GDM 的过滤条件是：
  ```c
  only_headless_allowed = (get_systemd_seat() == NULL);
  if (no_display || hidden || tryexec_failed ||
      (only_headless_allowed && !can_run_headless))
      return FALSE;                    /* 该会话被静默丢弃 */
  ```
  `gdm.service` 跑在 `system.slice`、**没有 logind session**（可用 `cat /proc/$(cat /run/gdm/gdm.pid)/cgroup`
  与 `/run/systemd/sessions/*` 验证），所以 `get_systemd_seat()` 恒为 NULL → `only_headless_allowed`
  **恒为 TRUE** → **只放行带该键的会话**。Fedora 的 `gnome.desktop` / `gnome-classic.desktop`
  都带这个键，niri 上游的 `resources/niri.desktop` 不带，于是被丢弃；丢弃后若只剩一个会话，
  **齿轮按钮整个不画**，现象就是"完全看不到任何切换项"。
- **会话文件必须放系统级目录**。GDM 只扫 `<system_data_dir>/wayland-sessions` 与
  `<system_data_dir>/xsessions`（`collect_sessions` 用 `g_get_system_data_dirs()` 拼，
  **不含用户目录**）。用户级 `~/.local/share/wayland-sessions/` 对 greeter 无效，别拿它当兜底
  （`niri-dms.sh` 早期版本踩过，现已改为写系统级）。
- **`Exec` / `TryExec` 用绝对路径**：`g_find_program_in_path()` 对绝对路径只做 `access(X_OK)`，
  裸命令名则依赖 PATH，绝对路径更稳。
- **不要照抄 GNOME 的 `X-GDM-SessionRegisters=true`**：它表示"会话程序自己向 DisplayManager 注册"。
  判定 `strings /usr/bin/<合成器> | grep -c DisplayManager`——niri 结果为 0（从不注册），
  照抄反而让 GDM 空等一个永远不来的注册。
- **改完必须 `sudo systemctl restart gdm`**：GDM 只在**启动时**扫一次会话文件，单纯"注销"无效。
- 排查顺序：`cat /usr/share/wayland-sessions/niri.desktop` → `systemctl show gdm -p ActiveEnterTimestamp`
  （会话文件必须早于 GDM 启动）→ `/etc/gdm/custom.conf` 的 `[debug]` 下开 `Enable=true` 后 restart，
  看 `journalctl -u gdm | grep -iE 'session|headless|hidden|Command not found'`。
- **拿源码一锤定音的办法**（本项目受限网络下实测可行，走 Fedora 镜像不走慢速 S3）：
  ```bash
  dnf5 download --source gdm && rpm2cpio gdm-*.src.rpm | cpio -idm && tar -xf gdm-*.tar.xz
  grep -n 'key_file_is_relevant' -A 60 gdm-*/libgdm/gdm-sessions.c
  ```

---

## 11. 提交规范

- 一个 commit 一件事，信息中文说明，前缀 `fix(scope):` / `feat(scope):`（scope 如 `gnome`、`network`）。
- 提交前：`bash -n` 全部改动文件 + `bash scripts/self-check.sh`（静态拦住反复踩过的 bug 模式）；关键路径实测；`git add -A && git commit && git push origin main`。
- 改动涉及镜像/主题名/步骤数等**跨文件**约定时，同步更新本 AGENTS.md。
