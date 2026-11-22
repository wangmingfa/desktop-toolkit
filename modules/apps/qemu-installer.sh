#!/usr/bin/env bash
# =============================================================================
# qemu-installer.sh —— QEMU / KVM / libvirt 一键安装（装完直接建虚拟机）
#
# 目标：装完即可"添加虚拟机"，覆盖一条完整链路：
#   QEMU 模拟器 + UEFI 固件 OVMF + libvirt 管理框架/守护进程 + virsh 命令行
#   + virt-install 快速建机 + 默认 NAT 网络 DHCP + 用户加入 libvirt 组
# 可选（勾选）：virt-manager 图形管理器 / virt-viewer 控制台 / 桥接工具 / libguestfs
#
# 发行版感知：Fedora / Ubuntu / Debian / Arch（包名矩阵见 qemu_catalog）。
#
# ⚠ 关键前提：虚拟机内无 /dev/kvm（嵌套虚拟化未开）时，QEMU 退化为 TCG 软模拟，
#   能跑但很慢；本模块体检会明确报出，不假装 KVM 可用。
#
# 另含：3. 虚拟机管理（virsh 开机/关机/重启/断电 + 快照备份与恢复，
#   当前用户在 libvirt 组则免 sudo，否则自动 sudo）
#   4. virtio 驱动 ISO 下载（精简版走 dt_download 镜像回退，完整版走官方 latest URL）
#
# 用法: bash qemu-installer.sh [install|create|manage|virtio|doctor|usage]
# =============================================================================
set -uo pipefail

DT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$DT_ROOT/lib/common.sh" 2>/dev/null || true
source "$DT_ROOT/lib/ui.sh" 2>/dev/null || true

if [ -t 1 ]; then
    DT_BOLD=$'\033[1m'; DT_GREEN=$'\033[0;32m'; DT_YELLOW=$'\033[0;33m'
    DT_CYAN=$'\033[0;36m'; DT_RED=$'\033[0;31m'; DT_NC=$'\033[0m'
else
    DT_BOLD=""; DT_GREEN=""; DT_YELLOW=""; DT_CYAN=""; DT_RED=""; DT_NC=""
fi

q_log() { echo -e "  ${DT_CYAN}[qemu]${DT_NC} $*"; }
q_err() { echo -e "  ${DT_RED}[qemu] 错误:${DT_NC} $*" >&2; }
q_has() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# 发行版检测（Fedora/Ubuntu/Debian/Arch）
# ---------------------------------------------------------------------------
q_distro() {
    . /etc/os-release 2>/dev/null || true
    case "${ID:-}" in
        fedora) echo fedora ;;
        ubuntu) echo ubuntu ;;
        debian) echo debian ;;
        arch|manjaro|endeavouros) echo arch ;;
        *) echo other ;;
    esac
}

# 组件目录：id|必须(1必/0选)|作用|fedora|ubuntu|debian|arch
q_catalog() {
    cat <<'EOF'
qemu|1|QEMU x86 模拟器——真正跑虚拟机的程序|qemu-kvm|qemu-system-x86|qemu-system-x86|qemu-system-x86
utils|1|qemu-img 虚拟磁盘工具（建/转换/扩容镜像）|qemu-utils|qemu-utils|qemu-utils|qemu-utils
libvirt|1|libvirt 管理框架 + 守护进程|libvirt|libvirt-daemon-system|libvirt-daemon-system|libvirt
client|1|virsh 命令行管理虚拟机|libvirt-client|libvirt-clients|libvirt-clients|libvirt
uefi|1|UEFI 固件 OVMF（装 Windows/新 Linux 必需）|edk-ovmf|ovmf|ovmf|edk2-ovmf
virtinstall|1|virt-install 命令行快速建虚拟机|virt-install|virtinst|virtinst|virt-install
dnsmasq|1|默认 NAT 网络 DHCP（VM 联网）|dnsmasq|dnsmasq|dnsmasq|dnsmasq
viewer|0|virt-viewer 虚拟机控制台查看器|virt-viewer|virt-viewer|virt-viewer|virt-viewer
manager|0|virt-manager 图形管理器（需 GNOME/KDE 桌面）|virt-manager|virt-manager|virt-manager|virt-manager
bridge|0|bridge-utils 网桥工具（桥接/共享网络）|bridge-utils|bridge-utils|bridge-utils|bridge-utils
guestfs|0|libguestfs 磁盘工具（挂载/拷贝 VM 磁盘）|libguestfs-tools|libguestfs-tools|libguestfs-tools|libguestfs-tools
EOF
}

q_field() { # q_field <id> <col>
    q_catalog | awk -F'|' -v i="$1" -v c="$2" '$1==i {print $c; exit}'
}

q_pkg() { # q_pkg <id> → 当前发行版包名（空=该发行版无此包）
    local distro col
    distro=$(q_distro)
    case "$distro" in
        fedora) col=4 ;; ubuntu) col=5 ;; debian) col=6 ;; arch) col=7 ;; *) echo ""; return 0 ;;
    esac
    q_field "$1" "$col"
}

# libvirtd 服务单元名（Fedora/Arch: libvirtd；Debian 用 dbus-... 别名）
q_libvirtd_unit() {
    if systemctl list-unit-files 'dbus-org.freedesktop.libvirtd.service' 2>/dev/null | grep -q dbus-org.freedesktop; then
        echo dbus-org.freedesktop.libvirtd
    else
        echo libvirtd
    fi
}

# 当前用户可用的 libvirt 组名（Fedora/Arch=libvirt，Debian/Ubuntu=libvirtd）
q_libvirt_group() {
    local g=""
    getent group libvirt >/dev/null 2>&1 && g="libvirt"
    [ -z "$g" ] && getent group libvirtd >/dev/null 2>&1 && g="libvirtd"
    echo "$g"
}

q_in_sel() {
    local x
    for x in "${@:2}"; do [ "$x" = "$1" ] && return 0; done
    return 1
}

# ---------------------------------------------------------------------------
# 收尾：启动 libvirtd + 当前用户加入 libvirt 组 + 启用默认 NAT 网络
# ---------------------------------------------------------------------------
q_post_install() {
    local unit grp st
    # 1) 启用并启动 libvirtd（Debian 单元名是 dbus-org.freedesktop.libvirtd）
    unit=$(q_libvirtd_unit)
    if sudo systemctl enable --now "$unit" 2>/dev/null \
        || sudo systemctl enable --now libvirtd 2>/dev/null; then
        st=$(systemctl is-active "$unit" 2>/dev/null || true); st="${st:-unknown}"
        if [ "$st" = active ]; then
            q_log "✅ libvirtd 已启用并运行（$unit）"
        else
            q_log "⚠ libvirtd 已 enable，当前状态 $st（重启后生效）"
        fi
    else
        q_err "libvirtd 启动失败（需确认包装上了）。手动: sudo systemctl enable --now $unit"
    fi
    # 2) 当前用户加入 libvirt 组（免 sudo 管理虚拟机）
    grp=$(q_libvirt_group)
    if [ -z "$grp" ]; then
        q_err "未找到 libvirt 组，跳过用户组设置"
    elif id -nG | tr ' ' '\n' | grep -qx "$grp"; then
        q_log "✅ 当前用户已在 $grp 组"
    else
        if sudo usermod -aG "$grp" "${USER:-$(logname 2>/dev/null || echo "$USER")}"; then
            q_log "✅ 已把当前用户加入 $grp 组（下次登录/注销登录后生效）"
        else
            q_err "加入 $grp 组失败。手动: sudo usermod -aG $grp \$USER"
        fi
    fi
    # 3) 启用默认 NAT 网络（虚拟机联网）
    if q_has virsh; then
        if virsh net-list 2>/dev/null | awk '{print $1,$NF}' | grep -q 'default running'; then
            q_log "✅ 默认 NAT 网络 default 运行中"
        else
            sudo virsh net-start default 2>/dev/null && sudo virsh net-autostart default 2>/dev/null \
                && q_log "✅ 默认 NAT 网络已启动并设为自启" \
                || q_err "默认 NAT 网络启用失败。手动: sudo virsh net-start default"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 一键安装（勾选-确认模式：必须项 + 可选默认全勾）
# ---------------------------------------------------------------------------
q_install() {
    local distro
    distro=$(q_distro)
    if [ "$distro" = other ]; then
        q_err "当前发行版 ${ID:-未知} 不在支持列表（Fedora/Ubuntu/Debian/Arch）。请手动安装 qemu + libvirt + ovmf。"
        return 1
    fi
    local -a sel=()
    while IFS='|' read -r i r _ _ _ _ _; do
        [ "$r" = 0 ] && sel+=("$i")
    done < <(q_catalog)

    while true; do
        local -a rows=()
        local i r desc pkg
        while IFS='|' read -r i r desc _ _ _ _; do
            pkg=$(q_pkg "$i")
            [ -z "$pkg" ] && continue
            local d="$desc"
            if [ "$r" = 1 ]; then
                rows+=("req-$i|[*] $pkg|$d（必须）")
            elif q_in_sel "$i" "${sel[@]}"; then
                rows+=("$i|[x] $pkg|$d")
            else
                rows+=("$i|[ ] $pkg|$d")
            fi
        done < <(q_catalog)
        rows+=("__install|▶ 安装所选|需 sudo，下载较大" "back|← 返回|")
        local c
        c=$(dt_menu "QEMU 虚拟化工具链（$distro）" "*必须(核心链路)；[x]可选勾选，点击切换。" "${rows[@]}") || return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            back) return 0 ;;
            __install) break ;;
            req-*) : ;;
            *)
                if q_in_sel "$c" "${sel[@]}"; then
                    local -a news=(); local x
                    for x in "${sel[@]}"; do [ "$x" != "$c" ] && news+=("$x"); done
                    sel=("${news[@]}")
                else
                    sel+=("$c")
                fi
                ;;
        esac
    done

    local -a pkgs=()
    local pkg
    while IFS='|' read -r i r _; do
        [ "$r" = 1 ] || continue
        pkg=$(q_pkg "$i"); [ -n "$pkg" ] && pkgs+=("$pkg")
    done < <(q_catalog)
    for i in "${sel[@]}"; do
        pkg=$(q_pkg "$i"); [ -n "$pkg" ] && pkgs+=("$pkg")
    done
    [ "${#pkgs[@]}" -eq 0 ] && { q_err "当前发行版无可用包"; return 1; }

    echo -e "  ${DT_YELLOW}⚠ 装完本脚本会代做: 启动 libvirtd + 把当前用户加入 $(q_libvirt_group) 组 + 启用默认 NAT 网络。${DT_NC}"
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        q_err "安装需 sudo 密码，但当前不是交互终端。请在终端里运行。"
        return 1
    fi
    dt_confirm "安装 ${#pkgs[@]} 个包（$distro）？\n需 sudo 密码，下载可能较大。\n\n继续？" || return 0
    q_log "安装 ${#pkgs[@]} 个包: ${pkgs[*]}"
    case "$distro" in
        fedora) sudo dnf install -y "${pkgs[@]}" || { q_err "安装失败。手动: sudo dnf install -y ${pkgs[*]}"; return 1; } ;;
        ubuntu|debian) sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}" || { q_err "安装失败。手动: sudo apt-get install -y ${pkgs[*]}"; return 1; } ;;
        arch) sudo pacman -S --needed --noconfirm "${pkgs[@]}" || { q_err "安装失败。手动: sudo pacman -S --needed ${pkgs[*]}"; return 1; } ;;
    esac
    q_log "✅ 包安装完成，执行收尾（libvirtd + 用户组 + 默认网络）..."
    q_post_install
    echo -e "  ${DT_YELLOW}⚠ 若当前在虚拟机内且无 /dev/kvm（嵌套虚拟化未开），虚拟机只能 TCG 软模拟，较慢。${DT_NC}"
    echo
    q_doctor
}

# ---------------------------------------------------------------------------
# 建虚拟机向导（virt-install）
# ---------------------------------------------------------------------------
q_create() {
    if ! q_has virt-install; then
        q_err "未装 virt-install，先执行 1. 一键安装。"
        return 1
    fi
    local name ram vcpu disk iso
    name=$(dt_ask_text "虚拟机名" "虚拟机名（英文，如 fedora-45）" "vm1") || return 0
    [ -n "$name" ] || return 0
    ram=$(dt_ask_num "内存" "内存（MB）" "4096" 1024 65536 1024) || return 0
    [ -n "$ram" ] && [ "$ram" -ge 1024 ] || { q_err "内存至少 1024 MB"; return 1; }
    vcpu=$(dt_ask_num "处理器" "CPU 核心数" "2" 1 32 1) || return 0
    [ -n "$vcpu" ] && [ "$vcpu" -ge 1 ] || { q_err "核心数至少 1"; return 1; }
    disk=$(dt_ask_num "磁盘" "磁盘（GB）" "40" 8 500 8) || return 0
    [ -n "$disk" ] && [ "$disk" -ge 8 ] || { q_err "磁盘至少 8 GB"; return 1; }
    iso=$(dt_ask_text "安装镜像" "系统 ISO 的本地路径（留空则手动补 --location）" "") || return 0
    local cmd
    cmd="virt-install --name $name --memory $ram --vcpus $vcpu --disk size=$disk,format=qcow2 --boot uefi"
    if [ -n "$iso" ]; then
        [ -f "$iso" ] || { q_err "ISO 不存在: $iso"; return 1; }
        cmd="$cmd --cdrom $iso"
    else
        cmd="$cmd --location <你的系统镜像下载链接>"
    fi
    q_log "将执行: $cmd"
    if dt_confirm "用上述参数创建虚拟机？\n（virt-install 会下载/引导安装，需 sudo 或已加入 libvirt 组）"; then
        if [ -n "$iso" ]; then
            if id -nG | tr ' ' '\n' | grep -qx "$(q_libvirt_group)"; then
                $cmd
            else
                sudo virt-install "${cmd#virt-install }"
            fi
            q_log "✅ 已创建: $name，用 virt-viewer $name 或 virt-manager 打开。"
        else
            echo -e "  ${DT_CYAN}请手动补全 --location 后执行：${DT_NC}"
            echo "  $cmd"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 虚拟机管理（virsh：开机/关机/断电/快照备份与恢复）
# ---------------------------------------------------------------------------
q_virsh() { # 已在 libvirt 组则免 sudo，否则 sudo
    local g
    g=$(q_libvirt_group)
    if [ -n "$g" ] && id -nG | tr ' ' '\n' | grep -qx "$g"; then
        virsh "$@"
    else
        sudo virsh "$@"
    fi
}

q_vm_list() { # 打印 "名字 状态" 两列
    q_virsh list --all 2>/dev/null | awk 'NR>1 && $2!="" {print $2, $3}'
}

# 选一台虚拟机；结果放全局 Q_PICK（不用 $( ) 捕获，否则 exit 杀不到本脚本）
Q_PICK=""
q_pick_vm() {
    Q_PICK=""
    local -a rows=() n st c
    while read -r n st; do
        [ -n "${n:-}" ] && rows+=("$n|$n|$st")
    done < <(q_vm_list)
    [ "${#rows[@]}" -gt 0 ] || { q_err "当前没有虚拟机，先用 2. 建虚拟机向导建一台"; return 1; }
    c=$(dt_menu "选择虚拟机" "运行中 / 已关机：" "${rows[@]}" "back|← 返回|") || return 1
    [ "$c" = __quit ] && exit 0
    [ "$c" = back ] && return 1
    Q_PICK="$c"
    return 0
}

q_snapshot_create() { # <vm>
    local vm="$1" tag
    tag=$(dt_ask_text "快照名" "快照标签（如 backup-2026-11-22）" "snapshot-$(date +%Y%m%d-%H%M)") || return 0
    [ -n "$tag" ] || return 0
    dt_confirm "为 $vm 创建快照 $tag ？\n（运行中的虚拟机创建瞬间会暂停）" || return 0
    if q_virsh snapshot-create-as "$vm" "$tag" --description "desktop-toolkit 快照备份" 2>/dev/null; then
        q_log "✅ 快照已创建: $vm → $tag"
    else
        q_err "创建失败。手动: sudo virsh snapshot-create-as $vm $tag"
        return 1
    fi
}

q_snapshot_revert() { # <vm>
    local vm="$1" c
    local -a rows=() sn
    while read -r sn; do
        [ -n "${sn:-}" ] && rows+=("$sn|$sn|")
    done < <(q_virsh snapshot-list "$vm" 2>/dev/null | awk 'NR>1 && $1!="" && $1!="-" {print $1}')
    [ "${#rows[@]}" -gt 0 ] || { q_err "$vm 没有快照（先 6. 快照备份）"; return 1; }
    c=$(dt_menu "恢复快照" "$vm 的快照：" "${rows[@]}" "back|← 返回|") || return 0
    [ "$c" = __quit ] && exit 0
    [ "$c" = back ] && return 0
    dt_confirm "恢复到快照 $c ？\n（会关闭 $vm 并还原到该快照，之后的更改会丢失）" || return 0
    if q_virsh snapshot-revert "$vm" "$c" 2>/dev/null; then
        q_log "✅ 已恢复: $vm → $c"
    else
        q_err "恢复失败。手动: sudo virsh snapshot-revert $vm $c"
        return 1
    fi
}

q_manage() {
    if ! q_has virsh; then
        q_err "未装 virsh，先执行 1. 一键安装。"
        return 1
    fi
    while true; do
        local c
        c=$(dt_menu "虚拟机管理" "对已建好的虚拟机操作：" \
            "list|1. 列出虚拟机|virsh list --all" \
            "start|2. 开机|" \
            "shutdown|3. 关机|优雅关机 ACPI" \
            "reboot|4. 重启|优雅重启" \
            "destroy|5. 强制断电|等同拔电源，会丢未保存数据" \
            "snap|6. 快照备份|保存当前状态，可随时回退" \
            "revert|7. 恢复快照|回退到某个快照" \
            "back|← 返回|") || return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            back) return 0 ;;
            list)
                echo -e "  ${DT_BOLD}═══ 虚拟机列表 ═══${DT_NC}"
                q_virsh list --all 2>/dev/null || q_err "virsh 连接失败（libvirtd 未运行？）"
                ;;
            start|shutdown|reboot)
                q_pick_vm || return 0
                q_virsh "$c" "$Q_PICK" 2>/dev/null && q_log "✅ 已 $c $Q_PICK" || q_err "$c $Q_PICK 失败（虚拟机可能已处于该状态）"
                ;;
            destroy)
                q_pick_vm || return 0
                dt_confirm "强制断电 $Q_PICK ？\n未保存的数据会丢失。" && \
                    { q_virsh destroy "$Q_PICK" 2>/dev/null && q_log "✅ 已断电 $Q_PICK" || q_err "断电 $Q_PICK 失败"; }
                ;;
            snap) q_pick_vm || return 0; q_snapshot_create "$Q_PICK" ;;
            revert) q_pick_vm || return 0; q_snapshot_revert "$Q_PICK" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# virtio 驱动 ISO 下载（Windows 客户机网卡/磁盘/显卡驱动）
# ---------------------------------------------------------------------------
VIRTIO_SLIM_FALLBACK="https://github.com/qemus/virtiso/releases/download/v0.1.302-1/virtio-win-0.1.302.iso"
VIRTIO_FULL_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"

q_virtio_slim_url() { # 先解析最新 release 资产(10s 超时)，失败回退稳定 tag
    local url=""
    if command -v curl >/dev/null 2>&1; then
        url=$(curl -sS --max-time 10 "https://api.github.com/repos/qemus/virtiso/releases/latest" 2>/dev/null \
            | grep -o 'https://[^"]*\.iso' | head -1 || true)
    fi
    [ -z "$url" ] && url="$VIRTIO_SLIM_FALLBACK"
    echo "$url"
}

q_virtio() {
    local dir="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
    if ! mkdir -p "$dir" 2>/dev/null; then dir="$HOME"; fi
    local c url file dest dtkill
    c=$(dt_menu "virtio 驱动 ISO" "Windows 客户机需 virtio 驱动（网卡/磁盘/显卡），下载后作为安装盘挂载：" \
        "slim|1. 精简版（约 25MB）|常用驱动，下载快（推荐）" \
        "full|2. 官方完整版（约 700MB）|全部驱动 + 更老系统支持" \
        "back|← 返回|") || return 0
    [ "$c" = __quit ] && exit 0
    [ "$c" = back ] && return 0
    case "$c" in
        slim) url=$(q_virtio_slim_url); file="virtio-win-slim.iso"; dtkill=600 ;;
        full) url="$VIRTIO_FULL_URL"; file="virtio-win-full.iso"; dtkill=3600 ;;
        *) return 0 ;;
    esac
    dest="$dir/$file"
    q_log "源: $url"
    q_log "保存到: $dest"
    dt_confirm "下载并保存到 $dest ？\n（大文件，慢网可能需要较久）" || return 0
    DT_DL_KILL="$dtkill" dt_download "$url" "$dest" || { q_err "下载失败。"; return 1; }
    if [ -s "$dest" ]; then
        q_log "✅ 完成: $dest（$(du -h "$dest" 2>/dev/null | awk '{print $1}')）"
        echo -e "  ${DT_CYAN}下一步:${DT_NC} 虚拟机设置 → 添加 CD/DVD 驱动器 → 选该 ISO → 安装 Windows 时从中装驱动"
    fi
}

# ---------------------------------------------------------------------------
# 环境体检
# ---------------------------------------------------------------------------
q_doctor() {
    local g unit st
    echo -e "  ${DT_BOLD}═══ QEMU / KVM 环境体检 ═══${DT_NC}"
    # KVM
    if [ -e /dev/kvm ]; then
        echo "  ${DT_GREEN}✓${DT_NC} KVM 加速: /dev/kvm 可用（硬件直通，性能好）"
    else
        echo "  ${DT_YELLOW}⚠${DT_NC} KVM 加速: ${DT_YELLOW}无 /dev/kvm${DT_NC}（当前在虚拟机内且未开嵌套虚拟化）"
        echo "      → QEMU 退化为 TCG 软模拟，能跑但很慢；建议在宿主开启 nested virtualization"
    fi
    # 核心组件（qemu-system-x86_64 是各发行版共有的二进制；Fedora 另有 qemu-kvm 别名）
    for t in qemu-system-x86_64 qemu-img virsh virt-install virt-viewer virt-manager; do
        if q_has "$t"; then echo "  ${DT_GREEN}✓${DT_NC} $t"; else echo "  ${DT_RED}✗${DT_NC} $t（未装）"; fi
    done
    # UEFI 固件
    local fw=""
    for p in /usr/share/edk2/ovmf/OVMF_CODE.4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF.fd; do
        [ -f "$p" ] && fw="$p" && break
    done
    if [ -n "$fw" ]; then echo "  ${DT_GREEN}✓${DT_NC} UEFI 固件: $fw"; else echo "  ${DT_RED}✗${DT_NC} UEFI 固件: 未找到 OVMF（装新系统必需）"; fi
    # libvirtd 服务（按 AGENTS.md: 用 || true 保留输出，避免双写）
    unit=$(q_libvirtd_unit)
    st=$(systemctl is-active "$unit" 2>/dev/null || true); st="${st:-inactive}"
    if [ "$st" = active ]; then
        echo "  ${DT_GREEN}✓${DT_NC} libvirtd: 运行中（$unit）"
    else
        echo "  ${DT_RED}✗${DT_NC} libvirtd: 未运行（$st，单元 $unit）→ 先 1. 一键安装"
    fi
    # 用户组
    g=$(q_libvirt_group)
    if [ -z "$g" ]; then
        echo "  ${DT_RED}✗${DT_NC} 用户组: 未找到 libvirt/libvirtd 组（libvirt 未装）"
    elif id -nG | tr ' ' '\n' | grep -qx "$g"; then
        echo "  ${DT_GREEN}✓${DT_NC} 用户组: 当前用户已在 $g（可免 sudo 管理虚拟机）"
    else
        echo "  ${DT_YELLOW}⚠${DT_NC} 用户组: 当前用户不在 $g（需 sudo 管理；1. 一键安装会加入）"
    fi
    # 默认 NAT 网络
    if q_has virsh && virsh net-list 2>/dev/null | awk '{print $1,$NF}' | grep -q 'default running'; then
        echo "  ${DT_GREEN}✓${DT_NC} 默认网络: default NAT 运行中（虚拟机可直接联网）"
    else
        echo "  ${DT_YELLOW}⚠${DT_NC} 默认网络: default NAT 未运行（1. 一键安装会启用）"
    fi
    # 磁盘空间（虚拟机镜像落盘位置）
    local av
    av=$(df -h "$DT_ROOT" 2>/dev/null | awk 'NR==2{print $4}')
    echo "  ${DT_CYAN}磁盘:${DT_NC} 本仓库所在分区可用 ${av:-未知}"
    echo
    echo -e "  ${DT_CYAN}下一步:${DT_NC} 下载系统 ISO → 2. 建虚拟机向导（或 virt-manager 图形界面添加）"
}

q_usage() {
    echo -e "  ${DT_BOLD}═══ 装完怎么用（添加虚拟机）═══${DT_NC}"
    echo
    echo -e "  ${DT_CYAN}方式一：图形界面（需 GNOME/KDE 桌面会话）${DT_NC}"
    echo "    · 打开 virt-manager（应用列表搜）→ 左上角 ▶ 新建虚拟机 → 选 ISO → 下一步到完成"
    echo -e "  ${DT_YELLOW}注意: 本机是 niri/DMS，GTK 图形程序要在 GNOME/KDE 会话里跑（注销选 GNOME 会话）。${DT_NC}"
    echo
    echo -e "  ${DT_CYAN}方式二：命令行（任何会话都能用）${DT_NC}"
    echo "    virt-install --name vm1 --memory 4096 --vcpus 2 --disk size=40,format=qcow2"
    echo "               --cdrom /path/to/system.iso --boot uefi"
    echo "    virt-viewer vm1                      # 打开虚拟机控制台"
    echo "    virsh list --all                     # 列出虚拟机"
    echo "    virsh start vm1 / virsh shutdown vm1 # 开机/关机"
    echo "    virsh snapshot-create-as vm1 tag     # 快照备份"
    echo "    virsh snapshot-revert vm1 tag         # 恢复快照"
    echo
    echo -e "  ${DT_CYAN}本菜单已内置:${DT_NC}"
    echo "    · 3. 虚拟机管理 —— 开机/关机/重启/强制断电 + 快照备份与恢复（免记 virsh 参数）"
    echo "    · 4. virtio 驱动下载 —— Windows 客户机驱动 ISO，安装时挂为 CD/DVD 装驱动"
    echo
    echo -e "  ${DT_CYAN}组件作用:${DT_NC}"
    local i r desc pkg
    while IFS='|' read -r i r desc _ _ _ _; do
        pkg=$(q_pkg "$i"); [ -z "$pkg" ] && continue
        local tag; [ "$r" = 1 ] && tag="必须" || tag="可选"
        printf '  %-6s %-22s %s\n' "$tag" "${pkg:-—}" "$desc"
    done < <(q_catalog)
    echo
    echo -e "  ${DT_YELLOW}常见坑:${DT_NC}"
    echo "    · 无 /dev/kvm（虚拟机内未开嵌套虚拟化）→ TCG 软模拟很慢，建议装轻量系统"
    echo "    · Ubuntu/Debian 需 universe/non-free 源才装得到 virt-manager/virt-viewer"
    echo "    · 极新的 Ubuntu 若 qemu-system-x86 报歧义，改装 qemu-system-x86-standard"
    echo "    · Windows 客户机建议 UEFI + virtio 驱动 → 菜单 4. 下载 virtio-win ISO"
}

q_menu() {
    while true; do
        local c
        c=$(dt_menu "QEMU 虚拟化工具链" "一键装好即可添加虚拟机（本机为虚拟机，KVM 可能受限）：" \
            "install|1. 一键安装全部|QEMU+libvirt+UEFI+virt-install+网络+用户组（勾选可选件）" \
            "create|2. 建虚拟机向导|virt-install 参数向导（名/内存/CPU/磁盘/ISO）" \
            "manage|3. 虚拟机管理|开机/关机/重启/断电 + 快照备份与恢复" \
            "virtio|4. virtio 驱动下载|Windows 客户机驱动 ISO（精简/官方完整）" \
            "doctor|5. 环境体检|KVM/组件/UEFI/用户组/默认网络" \
            "usage|6. 使用说明|怎么添加虚拟机 + 组件作用 + 常见坑" \
            "back|← 返回|") || return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            install) q_install ;;
            create) q_create ;;
            manage) q_manage ;;
            virtio) q_virtio ;;
            doctor) q_doctor ;;
            usage) q_usage ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    install) q_install ;;
    create) q_create ;;
    manage) q_manage ;;
    virtio) q_virtio ;;
    doctor) q_doctor ;;
    usage) q_usage ;;
    *) q_menu ;;
esac