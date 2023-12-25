#!/usr/bin/env bash

set -xe 
KERNEL_VERSION=6.4.11
# get kernel
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-"$KERNEL_VERSION".tar.xz
tar -xvf linux-"$KERNEL_VERSION".tar.xz
cd ./linux-"$KERNEL_VERSION"
zcat /proc/config.gz > ./.config
sed -i 's/CONFIG_DEFAULT_HOSTNAME="archlinux"/CONFIG_DEFAULT_HOSTNAME=[KSB] torture"/g' ./.config
make -j4
make modules_install
cp -v arch/x86/boot/bzImage /boot/vmlinuz-linux$KERNEL_VERSION
mkinitcpio -k $KERNEL_VERSION -g /boot/initramfs-$KERNEL_VERSION.img

cd ~
rm -rf ./linux-"$KERNEL_VERSION"
rm -f /etc/hostname
rm -f /boot/vmlinuz-linux
grub-mkconfig -o /boot/grub/grub.cfg

