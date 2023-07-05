#!/usr/bin/env bash
set -xe

MOUNT_PATH=/mnt/arch

#for testing. enshure that first loop device is free to mount img there
losetup --detach-all

#installing dependencies
dnf install arch-install-scripts e2fsprogs dosfstools

#initialize keys and load archlinux keys
pacman-key --init
pacman-key --populate archlinux

#create image
dd if=/dev/zero of=./vhd.img bs=1M count=40000

#in img wa add gpt table and 2 partitions "boot" and "root"
#in EOF answers for fdisk
fdisk ./vhd.img << EOF
g
n
1
2048
+1G
t
1
n
2
2099200
81917951
t
2
20
w
EOF

#mount img file to loop and get loop path
DISK=$(losetup -P -f --show vhd.img)
echo -e "USING $DISK <-----------------"
#formatting root partition
mkfs.ext4 "$DISK"p2
#formatting boot partition
mkfs.fat -F 32 "$DISK"p1

#create mount dirs
mkdir -p "$MOUNT_PATH"
#mount formatted root disk to /
mount "$DISK"p2 "$MOUNT_PATH"
#installing base arch files and devel apps
pacstrap "$MOUNT_PATH" base base-devel
#mount boot partition
mount "$DISK"p1 "$MOUNT_PATH"/boot
# partition tree finished. generating fstab
genfstab -U -t PARTUUID "$MOUNT_PATH" >> "$MOUNT_PATH"/etc/fstab

#go to arch
sudo arch-chroot "$MOUNT_PATH" << EOF
#install kernel and firmware
pacman -S --noconfirm mkinitcpio
sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev modconf kms keyboard keymap consolefont block filesystems fsck)/g' /etc/mkinitcpio.conf
pacman -S --noconfirm linux linux-firmware

#config localtime
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
#config hardware clocks
hwclock --systohc

#add ru locale
sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/g' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
#generating locale
locale-gen

#set default language
echo 'LANG=en_US.UTF-8,
LANGUAGE=en_US.UTF-8,
LC_ALL=en_US.UTF-8' > /etc/locale.conf

#set hostname
echo 'myhostname' > /etc/hostname
sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
useradd -m -G wheel -s /bin/bash kosh
echo "-----------------------------------------CHANGING PASSWORDS--------------------------------------------------"
echo "root:qwe" |chpasswd
echo "kosh:qwe" |chpasswd
pacman -S --noconfirm git
#dropping root user bacause makepkg and yay not working from root user
su - kosh
git clone https://aur.archlinux.org/yay-bin && cd yay-bin && yes | makepkg -si
yay -Y --gendb && yay -Syu --devel && yay -Y --devel --save && yay --editmenu --nodiffmenu --save
echo y | LANG=C yay -S --noprovides --answerdiff None --answerclean None --mflags " --noconfirm" docker docker-compose dive mc wget curl openssh pigz docker-buildx grub efibootmgr systemd-networkd

#enabling units
sudo systemctl enable docker
sudo systemctl enable sshd
sudo systemctl enable systemd-networkd

#installin grub. extra config needed because we don`t have efivars
sudo mkdir -p /boot/efi
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --force --no-nvram --removable
sudo grub-mkconfig -o /boot/grub/grub.cfg
wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh | bash

#make things normal
su -c "sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers"
su -c "sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers"

EOF

losetup -d "$DISK"
