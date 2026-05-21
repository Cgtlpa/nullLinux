#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_banner() {
    clear
    echo -e "${RED}${BOLD}"
    echo "  ███╗   ██╗██╗   ██╗██╗     ██╗        "
    echo "  ████╗  ██║██║   ██║██║     ██║        "
    echo "  ██╔██╗ ██║██║   ██║██║     ██║        "
    echo "  ██║╚██╗██║██║   ██║██║     ██║        "
    echo "  ██║ ╚████║╚██████╔╝███████╗███████╗   "
    echo "  ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚══════╝   "
    echo ""
    echo "       I N S T A L L E R   v1.0"
    echo -e "${RESET}"
}

select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local num_options=${#options[@]}

    echo -e "${CYAN}${prompt}${RESET}"
    echo ""

    tput civis

    draw_menu() {
        for i in "${!options[@]}"; do
            tput el
            if [ "$i" -eq "$selected" ]; then
                echo -e "  ${GREEN}▶ ${options[$i]}${RESET}"
            else
                echo -e "    ${options[$i]}"
            fi
        done
    }

    draw_menu

    while true; do
        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key2
            key="${key}${key2}"
        fi

        case "$key" in
            $'\x1b[A')
                tput cuu "$num_options"
                selected=$(( (selected - 1 + num_options) % num_options ))
                draw_menu
                ;;
            $'\x1b[B')
                tput cuu "$num_options"
                selected=$(( (selected + 1) % num_options ))
                draw_menu
                ;;
            "")
                tput cnorm
                echo ""
                SELECTED_INDEX=$selected
                SELECTED_VALUE="${options[$selected]}"
                return 0
                ;;
        esac
    done
}

try_step() {
    local primary_cmd="$1"
    local fallback_cmd="$2"
    local step_name="$3"

    eval "$primary_cmd"
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Primary method failed for: ${step_name}. Trying fallback...${RESET}"
        eval "$fallback_cmd"
        if [ $? -ne 0 ]; then
            echo -e "${RED}ERROR: Both primary and fallback failed for step: ${step_name}${RESET}"
            echo -e "${RED}Re-run the installer with: bash /run/archiso/bootmnt/install.sh${RESET}"
            exit 1
        fi
    fi
}

check_internet() {
    echo -e "${CYAN}Checking internet connectivity...${RESET}"
    ping -c 3 -q archlinux.org > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: No internet connection. Please connect to the internet and re-run the installer.${RESET}"
        echo -e "${RED}Re-run the installer with: bash /run/archiso/bootmnt/install.sh${RESET}"
        exit 1
    fi
    echo -e "${GREEN}Internet connection verified.${RESET}"
}

select_disk() {
    echo -e "${CYAN}Detecting available disks...${RESET}"
    echo ""
    lsblk -d -o NAME,SIZE,TYPE | grep disk

    echo ""
    mapfile -t DISK_LIST < <(lsblk -d -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/"$1" ("$2")"}')

    if [ ${#DISK_LIST[@]} -eq 0 ]; then
        echo -e "${RED}ERROR: No disks found. Exiting.${RESET}"
        exit 1
    fi

    select_option "Select target disk for installation:" "${DISK_LIST[@]}"
    TARGET_DISK=$(echo "$SELECTED_VALUE" | awk '{print $1}')
    echo -e "${GREEN}Selected disk: ${TARGET_DISK}${RESET}"
}

confirm_wipe() {
    echo -e "${YELLOW}WARNING: All data on ${TARGET_DISK} will be destroyed!${RESET}"
    echo ""
    select_option "Are you sure you want to wipe ${TARGET_DISK}?" "Yes, wipe the disk" "No, go back and exit"
    if [ "$SELECTED_INDEX" -ne 0 ]; then
        echo -e "${YELLOW}Installation aborted by user.${RESET}"
        exit 0
    fi
    echo -e "${GREEN}Confirmed disk wipe.${RESET}"
}

partition_disk() {
    echo -e "${CYAN}Partitioning disk ${TARGET_DISK}...${RESET}"

    local primary="parted -s ${TARGET_DISK} mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart primary ext4 513MiB 100%"

    local fallback="sgdisk --zap-all ${TARGET_DISK} && \
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:'EFI' ${TARGET_DISK} && \
        sgdisk -n 2:0:0 -t 2:8300 -c 2:'root' ${TARGET_DISK}"

    try_step "$primary" "$fallback" "partition disk"

    sleep 1
    partprobe "${TARGET_DISK}" 2>/dev/null || true

    if [[ "${TARGET_DISK}" == *"nvme"* ]]; then
        EFI_PART="${TARGET_DISK}p1"
        ROOT_PART="${TARGET_DISK}p2"
    else
        EFI_PART="${TARGET_DISK}1"
        ROOT_PART="${TARGET_DISK}2"
    fi

    echo -e "${GREEN}Partitioning complete. EFI: ${EFI_PART}, Root: ${ROOT_PART}${RESET}"
}

format_partitions() {
    echo -e "${CYAN}Formatting partitions...${RESET}"

    try_step "mkfs.fat -F32 ${EFI_PART}" "mkfs.vfat -F 32 ${EFI_PART}" "format EFI partition"
    try_step "mkfs.ext4 -F ${ROOT_PART}" "mke2fs -t ext4 ${ROOT_PART}" "format root partition"

    echo -e "${GREEN}Partitions formatted.${RESET}"
}

mount_partitions() {
    echo -e "${CYAN}Mounting partitions...${RESET}"

    try_step "mount ${ROOT_PART} /mnt" "mount -t ext4 ${ROOT_PART} /mnt" "mount root partition"
    try_step "mkdir -p /mnt/boot/efi && mount ${EFI_PART} /mnt/boot/efi" \
        "mkdir -p /mnt/boot/efi && mount -t vfat ${EFI_PART} /mnt/boot/efi" \
        "mount EFI partition"

    echo -e "${GREEN}Partitions mounted.${RESET}"
}

install_base() {
    echo -e "${CYAN}Installing base system (this may take a while)...${RESET}"

    try_step \
        "pacstrap /mnt base linux linux-firmware base-devel networkmanager grub efibootmgr" \
        "nullpkg -S --noconfirm base linux linux-firmware base-devel networkmanager grub efibootmgr" \
        "pacstrap base system"

    echo -e "${GREEN}Base system installed.${RESET}"
}

generate_fstab() {
    echo -e "${CYAN}Generating fstab...${RESET}"

    try_step "genfstab -U /mnt >> /mnt/etc/fstab" \
        "genfstab -L /mnt >> /mnt/etc/fstab" \
        "generate fstab"

    echo -e "${GREEN}fstab generated.${RESET}"
}

select_desktop() {
    echo ""
    select_option "Select a Desktop Environment to install:" \
        "Hyprland" \
        "KDE Plasma" \
        "GNOME" \
        "XFCE" \
        "LXQt" \
        "MangoWC" \
        "Cinnamon"

    CHOSEN_DE="$SELECTED_VALUE"
    echo -e "${GREEN}Selected DE: ${CHOSEN_DE}${RESET}"
}

get_username() {
    echo ""
    echo -e "${CYAN}Enter a username for the new user:${RESET}"
    read -r NEW_USER
    while [[ -z "$NEW_USER" || "$NEW_USER" =~ [^a-z0-9_-] ]]; do
        echo -e "${RED}Invalid username. Use only lowercase letters, numbers, underscores, or hyphens.${RESET}"
        read -r NEW_USER
    done

    echo ""
    select_option "Confirm username: '${NEW_USER}'?" "Yes, use this username" "No, re-enter"
    if [ "$SELECTED_INDEX" -ne 0 ]; then
        get_username
    fi

    echo -e "${GREEN}Username set to: ${NEW_USER}${RESET}"
}

build_de_packages() {
    case "$CHOSEN_DE" in
        "Hyprland")
            DE_PACKAGES="hyprland xdg-desktop-portal-hyprland waybar wofi foot"
            LOGIN_MANAGER="sddm"
            LOGIN_SERVICE="sddm"
            SDDM_WAYLAND=true
            ;;
        "KDE Plasma")
            DE_PACKAGES="plasma plasma-wayland-session kde-applications"
            LOGIN_MANAGER="sddm"
            LOGIN_SERVICE="sddm"
            SDDM_WAYLAND=false
            ;;
        "GNOME")
            DE_PACKAGES="gnome gnome-extra"
            LOGIN_MANAGER="sddm"
            LOGIN_SERVICE="sddm"
            SDDM_WAYLAND=false
            ;;
        "XFCE")
            DE_PACKAGES="xfce4 xfce4-goodies"
            LOGIN_MANAGER="sddm"
            LOGIN_SERVICE="sddm"
            SDDM_WAYLAND=false
            ;;
        "LXQt")
            DE_PACKAGES="lxqt breeze-icons"
            LOGIN_MANAGER="sddm"
            LOGIN_SERVICE="sddm"
            SDDM_WAYLAND=false
            ;;
        "MangoWC")
            DE_PACKAGES="mangowc xorg-server xorg-xinit"
            LOGIN_MANAGER="lightdm"
            LOGIN_SERVICE="lightdm"
            SDDM_WAYLAND=false
            ;;
        "Cinnamon")
            DE_PACKAGES="cinnamon"
            LOGIN_MANAGER="sddm"
            LOGIN_SERVICE="sddm"
            SDDM_WAYLAND=false
            ;;
    esac
}

run_chroot() {
    echo -e "${CYAN}Running post-install configuration inside chroot...${RESET}"

    local SDDM_WAYLAND_BLOCK=""
    if [ "$SDDM_WAYLAND" = true ]; then
        SDDM_WAYLAND_BLOCK="mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/wayland.conf << 'SDDMEOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
SDDMEOF"
    fi

    # ---> 1. COPY LOGO (Must be outside the chroot so it moves from USB to the new drive)
    mkdir -p /mnt/usr/local/share/nullos
    if [ -f "logo.txt" ]; then
        cp logo.txt /mnt/usr/local/share/nullos/logo.txt
    else
        echo -e "${YELLOW}Warning: logo.txt not found, skipping custom fastfetch logo.${RESET}"
    fi
    # -----------------------------------------------------

    arch-chroot /mnt /bin/bash <<EOF
set -e

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

echo "nulllinux" > /etc/hostname
cat > /etc/hosts <<HOSTSEOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   nulllinux.localdomain nulllinux
HOSTSEOF

echo -e "${CYAN}Set the root password:${RESET}"
passwd

nullpkg -S --noconfirm ${DE_PACKAGES} ${LOGIN_MANAGER} || \
    pacman -S --noconfirm ${DE_PACKAGES} ${LOGIN_MANAGER}

${SDDM_WAYLAND_BLOCK}

# ---> 2. CREATE THE USER FIRST
useradd -m -G wheel,audio,video,optical,storage -s /bin/bash ${NEW_USER} || \
    useradd -m -G wheel -s /bin/bash ${NEW_USER}
echo -e "${CYAN}Set the password for user '${NEW_USER}':${RESET}"
passwd ${NEW_USER}

# ---> 3. INSTALL YAY (Now that the user exists, we can use them to install it!)
echo -e "${CYAN}Installing 'yay' (AUR Helper)...${RESET}"
pacman -S --noconfirm git base-devel
su - ${NEW_USER} -c "git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin"
su - ${NEW_USER} -c "cd /tmp/yay-bin && makepkg -si --noconfirm"
rm -rf /tmp/yay-bin
echo -e "${GREEN}yay installed successfully!${RESET}"
# ------------------------------------------------------------------------

# ---> 4. ADD THE ALIAS (Fixed to match the 'logo.txt' filename)
echo 'alias fastfetch="fastfetch --logo /usr/local/share/nullos/logo.txt"' >> /home/${NEW_USER}/.bashrc

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || \
    sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager
systemctl enable ${LOGIN_SERVICE}

sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Null Linux"/' /etc/default/grub || \
    echo 'GRUB_DISTRIBUTOR="Null Linux"' >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Null Linux" --recheck || \
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Null Linux"

grub-mkconfig -o /boot/grub/grub.cfg || \
    grub-mkconfig -o /boot/grub/grub.cfg --output=/boot/grub/grub.cfg

mkinitcpio -P || mkinitcpio -p linux

EOF

    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Chroot configuration failed.${RESET}"
        echo -e "${RED}Re-run the installer with: bash /run/archiso/bootmnt/install.sh${RESET}"
        exit 1
    fi

    echo -e "${GREEN}Chroot configuration complete.${RESET}"
}
unmount_partitions() {
    echo -e "${CYAN}Unmounting partitions...${RESET}"

    try_step "umount -R /mnt" "umount -l /mnt" "unmount partitions"

    echo -e "${GREEN}Partitions unmounted.${RESET}"
}

print_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║                                                                  ║"
    echo "  ║        INSTALL COMPLETE — Welcome to Null Linux                  ║"
    echo "  ║                                                                  ║"
    echo "  ║   Your system has been installed successfully.                   ║"
    echo "  ║   Remove the installation media before rebooting.                ║"
    echo "  ║                                                                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

prompt_reboot() {
    select_option "What would you like to do now?" "Reboot now" "Exit to shell"
    if [ "$SELECTED_INDEX" -eq 0 ]; then
        echo -e "${GREEN}Rebooting...${RESET}"
        reboot
    else
        echo -e "${CYAN}Exiting installer. You can reboot manually with: reboot${RESET}"
        exit 0
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}ERROR: This installer must be run as root.${RESET}"
    exit 1
fi

print_banner
check_internet
select_disk
confirm_wipe
select_desktop
get_username
build_de_packages
partition_disk
format_partitions
mount_partitions
install_base
generate_fstab
run_chroot
unmount_partitions
print_success
prompt_reboot
