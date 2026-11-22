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
# 用法: bash qemu-installer.sh [install|create|doctor|usage]
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
    echo "    · Windows 客户机建议 UEFI + virtio 驱动（virtio-win ISO）"
}

q_menu() {
    while true; do
        local c
        c=$(dt_menu "QEMU 虚拟化工具链" "一键装好即可添加虚拟机（本机为虚拟机，KVM 可能受限）：" \
            "install|1. 一键安装全部|QEMU+libvirt+UEFI+virt-install+网络+用户组（勾选可选件）" \
            "create|2. 建虚拟机向导|virt-install 参数向导（名/内存/CPU/磁盘/ISO）" \
            "doctor|3. 环境体检|KVM/组件/UEFI/用户组/默认网络" \
            "usage|4. 使用说明|怎么添加虚拟机 + 组件作用 + 常见坑" \
            "back|← 返回|") || return 0
        [ "$c" = __quit ] && exit 0
        case "$c" in
            install) q_install ;;
            create) q_create ;;
            doctor) q_doctor ;;
            usage) q_usage ;;
            back) return 0 ;;
        esac
    done
}

case "${1:-}" in
    install) q_install ;;
    create) q_create ;;
    doctor) q_doctor ;;
    usage) q_usage ;;
    *) q_menu ;;
esac