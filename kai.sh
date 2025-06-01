#!/bin/bash
source ./config
echo "───────────────────────────────────────────────────────"
echo "KAI: Kota's Arch Installer"
echo "───────────────────────────────────────────────────────"
echo "Please partition your disks before proceeding."
echo "───────────────────────────────────────────────────────"
# Y/n to open cfdisk
read -p "Do you want to open cfdisk? (Y/n): " open_cfdisk
if [[ "$open_cfdisk" =~ ^[Yy]$ ]]; then
  cfdisk /dev/"$disk1"
  cfdisk /dev/"$disk2"
else
  echo "Skipping cfdisk."
fi
echo "Your current configuration"
echo "───────────────────────────────────────────────────────"
echo "Disk1: $disk1"
echo "Disk2: $disk2"
echo "Username: $username"
echo "Hostname: $hostname"
echo "Timezone: $timezone"
echo "Locale": "$locale"
echo "Swap Size: $swap_size"
echo "Root Password: $root_password"
echo "User Password: $user_password"
echo "Install GRUB: $install_grub"
echo "Install EFI: $install_efi"
echo "───────────────────────────────────────────────────────"
echo "Important System Information"
echo "───────────────────────────────────────────────────────"
echo "EFI Platform Size: $(cat /sys/firmware/efi/fw_platform_size)"
ping google.com -c 1
if [ $? -ne 0 ]; then
  echo "Network Status: Not Connected"
  echo "Please check your network connection and try again."
    echo "Exiting setup..."
    exit 1
  exit 1
fi
echo "Network Status: Connected"
echo "───────────────────────────────────────────────────────"
echo "Please confirm your config matches your system."
echo "───────────────────────────────────────────────────────"

change_config_value() {
  local var_name="$1"
  local current_value="${!var_name}"
  read -p "Enter new value for $var_name (current: $current_value): " new_value
  if [ -n "$new_value" ]; then
    eval "$var_name=\"$new_value\""
    echo "$var_name updated to: ${!var_name}"
    # Update the variable in config file
    sed -i "s/^$var_name=.*/$var_name=\"${!var_name//\//\\/}\"/" ./config
  else
    echo "$var_name unchanged."
  fi
}

options=("start" "config" "quit")
select opt in "${options[@]}"; do
  case $REPLY in
    1) echo "starting...";
    mkfs.fat -F32 /dev/"$disk1"
    mkfs.ext4 /dev/"$disk2"
    mount /dev/"$disk2" /mnt
    mount --mkdir /dev/"$disk1" /mnt/boot
    pacstrap /mnt base linux linux-firmware vim
    genfstab -U /mnt >> /mnt/etc/fstab

    # Create chroot script
    cat <<EOF > /mnt/kai-chroot.sh
#!/bin/bash
fallocate -l "$swap_size" /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
hwclock --systohc
echo "$locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf
echo $hostname > /etc/hostname
echo "127.0.0.1 $hostname.localdomain $hostname" >> /etc/hosts
echo "root:$root_password" | chpasswd
pacman -S --noconfirm grub efibootmgr networkmanager wpa_supplicant dialog os-prober base-devel linux-headers reflector git
if [[ "$install_grub" == "true" ]]; then
  if [[ "$install_efi" == "true" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  else
    grub-install /dev/"$disk2"
  fi
  grub-mkconfig -o /boot/grub/grub.cfg
fi
systemctl enable NetworkManager
useradd -mG wheel "$username"
echo "$username:$user_password" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
EOF

    chmod +x /mnt/kai-chroot.sh
    arch-chroot /mnt /kai-chroot.sh
    rm /mnt/kai-chroot.sh

    umount -a
    echo "Configuration complete. You can now reboot your system."
    reboot
    break ;;
    2) echo "configuring...";
    config_vars=("disk1" "disk2" "username" "hostname" "timezone" "locale" "swap_size" "root_password" "user_password" "install_grub" "install_efi")
    select var in "${config_vars[@]}" "back"; do
      if [[ "$var" == "back" ]]; then
        break
      elif [[ " ${config_vars[*]} " == *" $var "* ]]; then
        change_config_value "$var"
      else
        echo "invalid option!"
      fi
    done
    break ;;
    3) echo "quitting...";
    break ;;
    *) echo "invalid option!";;
  esac
done
