#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

TARGET_DISK=""
EFI_PART=""
ROOT_PART=""
CHOSEN_DE=""
NEW_USER=""
HOSTNAME="nulllinux"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYMAP="us"
ENABLE_SWAP="no"
INSTALL_YAY="no"
MICROCODE=""

die() { echo "${RED}ERROR:${RESET} $*" >&2; exit 1; }
info() { echo "${CYAN}$*${RESET}"; }
ok() { echo "${GREEN}$*${RESET}"; }
warn() { echo "${YELLOW}$*${RESET}"; }

cleanup() {
    if mountpoint -q /mnt; then
        umount -R /mnt 2>/dev/null || true
    fi
}
trap cleanup EXIT

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run this installer as root."
}

check_uefi() {
    [[ -d /sys/firmware/efi/efivars ]] || die "UEFI boot mode is required."
}

check_internet() {
    info "Checking internet connectivity..."
    ping -c 1 -W 2 archlinux.org >/dev/null 2>&1 || die "No internet connection."
    ok "Internet connection verified."
}

print_banner() {
    clear || true
    echo -e "${CYAN}${BOLD}"
    cat <<'EOF'
  ███╗   ██╗██╗   ██╗██╗     ██╗
  ████╗  ██║██║   ██║██║     ██║
  ██╔██╗ ██║██║   ██║██║     ██║
  ██║╚██╗██║██║   ██║██║     ██║
  ██║ ╚████║╚██████╔╝███████╗███████╗
  ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚══════╝

       I N S T A L L E R   v3.0
EOF
    echo -e "${RESET}"
}

select_disk() {
    echo
    info "Available disks:"
    lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk"{printf "%s (%s)\n", $1, $2}'
    echo
    mapfile -t DISKS < <(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk"{print $1 " (" $2 ")"}')
    (( ${#DISKS[@]} > 0 )) || die "No disks found."

    PS3="Select target disk: "
    select choice in "${DISKS[@]}"; do
        if [[ -n "${choice:-}" ]]; then
            TARGET_DISK="${choice%% *}"
            break
        fi
        echo "Invalid selection."
    done

    [[ -b "$TARGET_DISK" ]] || die "Invalid disk selected."
    ok "Selected disk: $TARGET_DISK"
}

confirm_wipe() {
    echo
    warn "ALL DATA on ${TARGET_DISK} will be destroyed."
    read -rp "Type WIPE to continue: " ans
    [[ "$ans" == "WIPE" ]] || die "Aborted by user."
    ok "Wipe confirmed."
}

select_desktop() {
    echo
    PS3="Select a desktop environment: "
    select choice in \
        "Hyprland" \
        "KDE Plasma" \
        "GNOME" \
        "XFCE" \
        "LXQt" \
        "MangoWC" \
        "Cinnamon"
    do
        if [[ -n "${choice:-}" ]]; then
            CHOSEN_DE="$choice"
            break
        fi
        echo "Invalid selection."
    done
    ok "Selected DE: $CHOSEN_DE"
}

get_username() {
    echo
    read -rp "Enter a username: " NEW_USER
    while [[ -z "$NEW_USER" || ! "$NEW_USER" =~ ^[a-z0-9_-]+$ ]]; do
        warn "Invalid username. Use lowercase letters, numbers, underscore, or hyphen."
        read -rp "Enter a username: " NEW_USER
    done
    ok "Username set to: $NEW_USER"
}

detect_microcode() {
    local vendor=""
    vendor="$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
    case "$vendor" in
        GenuineIntel) MICROCODE="intel-ucode" ;;
        AuthenticAMD) MICROCODE="amd-ucode" ;;
        *) MICROCODE="" ;;
    esac
}

build_de_packages() {
    local packages=()
    local login_manager="sddm"
    local login_service="sddm"
    local sddm_wayland="false"

    case "$CHOSEN_DE" in
        "Hyprland")
            packages=(hyprland xdg-desktop-portal-hyprland waybar wofi foot polkit-gnome pipewire wireplumber pipewire-pulse pipewire-alsa qt5-wayland qt6-wayland dunst)
            sddm_wayland="true"
            ;;
        "KDE Plasma")
            packages=(plasma kde-applications plasma-wayland-session pipewire wireplumber pipewire-pulse pipewire-alsa)
            ;;
        "GNOME")
            packages=(gnome gnome-extra pipewire wireplumber pipewire-pulse pipewire-alsa)
            ;;
        "XFCE")
            packages=(xfce4 xfce4-goodies pipewire wireplumber pipewire-pulse pipewire-alsa)
            ;;
        "LXQt")
            packages=(lxqt breeze-icons pipewire wireplumber pipewire-pulse pipewire-alsa)
            ;;
        "MangoWC")
            packages=(mangowc xorg-server xorg-xinit pipewire wireplumber pipewire-pulse pipewire-alsa)
            login_manager="lightdm"
            login_service="lightdm"
            ;;
        "Cinnamon")
            packages=(cinnamon pipewire wireplumber pipewire-pulse pipewire-alsa)
            ;;
        *)
            die "Unknown desktop selection."
            ;;
    esac

    DE_PACKAGES=("${packages[@]}")
    LOGIN_MANAGER="$login_manager"
    LOGIN_SERVICE="$login_service"
    SDDM_WAYLAND="$sddm_wayland"
}

partition_disk() {
    info "Partitioning ${TARGET_DISK}..."

    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary 513MiB 100%

    partprobe "$TARGET_DISK"
    sleep 2

    case "$TARGET_DISK" in
        *nvme*|*mmcblk*)
            EFI_PART="${TARGET_DISK}p1"
            ROOT_PART="${TARGET_DISK}p2"
            ;;
        *)
            EFI_PART="${TARGET_DISK}1"
            ROOT_PART="${TARGET_DISK}2"
            ;;
    esac

    [[ -b "$EFI_PART" ]] || die "EFI partition not found."
    [[ -b "$ROOT_PART" ]] || die "Root partition not found."

    ok "Partitions ready: EFI=$EFI_PART ROOT=$ROOT_PART"
}

format_partitions() {
    info "Formatting partitions..."
    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"
    ok "Partitions formatted."
}

mount_partitions() {
    info "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
    ok "Partitions mounted."
}

verify_mounts() {
    mountpoint -q /mnt || die "/mnt is not mounted."
    mountpoint -q /mnt/boot/efi || die "/mnt/boot/efi is not mounted."
}

create_swapfile() {
    [[ "$ENABLE_SWAP" == "yes" ]] || return 0
    info "Creating swapfile..."
    arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
dd if=/dev/zero of=/swapfile bs=1M count=8192 status=none
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
EOF
    ok "Swapfile created."
}

install_base() {
    info "Installing base system..."
    local extra_pkgs=(base linux linux-firmware base-devel networkmanager grub efibootmgr sudo)
    [[ -n "${MICROCODE:-}" ]] && extra_pkgs+=("$MICROCODE")
    pacstrap -K /mnt "${extra_pkgs[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
    [[ -s /mnt/etc/fstab ]] || die "Failed to generate fstab."
    ok "Base system installed and fstab verified."
}

configure_chroot() {
    info "Entering chroot configuration..."

    local sddm_block=""
    if [[ "$SDDM_WAYLAND" == "true" ]]; then
        sddm_block=$(cat <<'EOF'
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/wayland.conf <<'SDDMEOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
SDDMEOF
EOF
)
    fi

    local de_packages_str=""
    de_packages_str="${DE_PACKAGES[*]}"

    arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<HOSTSEOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTSEOF

echo "Set the root password:"
passwd

pacman -S --noconfirm --needed ${de_packages_str} ${LOGIN_MANAGER} pipewire wireplumber pipewire-pulse pipewire-alsa

${sddm_block}

useradd -m -G wheel,audio,video,optical,storage -s /bin/bash ${NEW_USER}
echo "Set the password for user ${NEW_USER}:"
passwd ${NEW_USER}

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || true
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers || true

systemctl enable NetworkManager
systemctl enable ${LOGIN_SERVICE}

if [[ -f /etc/pacman.d/mirrorlist ]]; then
    pacman -S --noconfirm --needed reflector || true
fi

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Null Linux"
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
EOF

    ok "Chroot configuration complete."
}

install_yay_optional() {
    echo
    read -rp "Install yay AUR helper now? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || return 0

    arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail
pacman -S --noconfirm --needed git base-devel
su - ${NEW_USER} -c 'cd /tmp && rm -rf yay-bin && git clone https://aur.archlinux.org/yay-bin.git'
su - ${NEW_USER} -c 'cd /tmp/yay-bin && makepkg -si --noconfirm'
rm -rf /tmp/yay-bin
EOF
    ok "yay installed."
}

finish_install() {
    info "Unmounting filesystems..."
    umount -R /mnt
    ok "Install complete."
}

main() {
    require_root
    print_banner
    check_uefi
    check_internet
    detect_microcode
    select_disk
    confirm_wipe
    select_desktop
    get_username
    build_de_packages
    partition_disk
    format_partitions
    mount_partitions
    verify_mounts
    install_base
    create_swapfile
    configure_chroot
    install_yay_optional
    finish_install

    echo
    echo -e "${GREEN}${BOLD}INSTALL COMPLETE — Welcome to Null Linux${RESET}"
    echo "Remove installation media before rebooting."
    echo
    PS3="What would you like to do now? "
    select action in "Reboot now" "Exit to shell"; do
        case "$action" in
            "Reboot now") reboot ;;
            "Exit to shell") exit 0 ;;
        esac
    done
}

main "$@"
