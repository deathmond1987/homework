set -xe
# POC
# fully working arch linux builded from RHEL-like command line on RAW IMAGE with uefi, grub, root partition in lvm with ext4, oh-my-zsh and modern apps
. /etc/os-release
#path where we build new arch linux system
MOUNT_PATH=/mnt/arch

prepare_dependecies () {
    #installing dependencies
    #arch-install-scripts - pacman and his dependencies
    #e2fsprogs - for making fs in image
    #dosfstools - for making fat32 fs in image
    #qemu-kvm-core - for run builded image in qemu-kvm
    #edk2-ovmf - uefi bios for run image in qemu with uefi
    dnf install arch-install-scripts e2fsprogs dosfstools qemu-kvm-core edk2-ovmf
}

prepare_dependecies_arch () {
    pacman -S --needed lvm2 dosfstools
}

prepare_dependecies_debian () {
    apt install arch-install-scripts e2fsprogs dosfstools qemu-utils qemu-system-x86 ovmf pacman-package-manager lvm2  -y
}

pacman_init () {
    #initialize keyring and load archlinux keys
    pacman-key --init
    pacman-key --populate archlinux
}

create_image () {
    #creating empty image 
    dd if=/dev/zero of=./vhd.img bs=1M count=10000
    #creating in image gpt table and 3 partitions
    #first one - EFI partinion. we will mount it to /boot/efi later with filesystem fat32
    #second one - "boot" partition. we will mount it to /boot later with filesystem fat32
    #third one - "root" partition. we will mount it to / later with lvm and ext4 partition
    fdisk ./vhd.img << EOF
g
n
1
2048
+50M
t
1
n
2
104448
+1G
t
2
20
n
3
2201600
20477951
t
3
44
w
EOF
}

mount_image () {
    #mount img file to loop to interact with created partitions 
    #they will be available in /dev/loop_loop-number_partition-number
    #like /dev/loop0p1 or /dev/loop20p3
    export DISK=$(losetup -P -f --show vhd.img)
}

exit_trap () {
    #if script fail - we need to umnount all mounts to clear host machine
    on_exit () {
        umount "$MOUNT_PATH"/boot || true
        umount "$MOUNT_PATH"/boot/efi || true
        umount "$MOUNT_PATH" || true
        #vgremove arch || true
        losetup -d "$DISK" || true
        echo "trap finished"
    }
trap "on_exit" EXIT
}

format_image () {
    #formatting boot partition
    mkfs.fat -F 32 "$DISK"p1
    #formatting efi partition
    mkfs.fat -F 32 "$DISK"p2
    #creating root pv
    pvcreate "$DISK"p3
    #creating root vg
    vgcreate arch "$DISK"p3
    #creating root lv
    lvcreate -l 100%FREE arch -n root
    #formatting root lv
    mkfs.ext4 /dev/arch/root
}

mount_root () {
    #create mount dirs
    mkdir -p "$MOUNT_PATH"
    #mount formatted root disk to /
    mount /dev/arch/root "$MOUNT_PATH"
}

pacstrap_base () {
    #installing base arch files and devel apps
    pacstrap -K "$MOUNT_PATH" base base-devel
}

pacstrap_base_debian () {
    #installing base arch files and devel apps
    cd "$MOUNT_PATH"
    wget -O archlinux.tar.gz https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.gz
    tar xzf ./archlinux.tar.gz --numeric-owner --strip-components=1
    arch-chroot "$MOUNT_PATH" << EOF
    pacman-key --init
    pacman-key --populate archlinux
    sed -i 's/#Server =/Server =/g' /etc/pacman.d/mirrorlist
    pacman -Syu --noconfirm base base-devel
    rm -f /archlinux.tar.gz
    rm -f /pkglist.x86_64.txt
    rm -f /version

EOF
    cd -
}

mount_boot () {
    #mount boot partition
    mount "$DISK"p2 "$MOUNT_PATH"/boot
    #creating dir for efi
    mkdir -p "$MOUNT_PATH"/boot/efi
    #mount efi partition
    mount "$DISK"p1 "$MOUNT_PATH"/boot/efi
    #if we not remove swap from host machine he will appear in arch fstab
    swapoff -a
    #partition tree finished. generating fstab
    genfstab -U -t PARTUUID "$MOUNT_PATH" > "$MOUNT_PATH"/etc/fstab
}

chroot_arch () {
    #go to arch
    arch-chroot "$MOUNT_PATH" << EOF

    set -e
    sudo_config () {
        sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
    }

    mkinitcpio_install () {
        #install kernel and firmware
        pacman -S --noconfirm mkinitcpio
    }

    remove_autodetect_hook () {
        #to run arch in most any environment we need build init image with all we can add to it
        sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base systemd modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
    }

    kernel_install () {
        #installing kernel and firmware
        pacman -S --noconfirm linux linux-firmware
    }

    #we can not use systemd to configure locales, time and so on cause we are in chroot environment
    time_config () {
        #config localtime
        ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
        #config hardware clocks
        hwclock --systohc
    }

    locale_config () {
        #add locales
        sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/g' /etc/locale.gen
        sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
        #generating locale
        locale-gen
    }

    language_config () {
        #set default language
        echo -e 'LANG=en_US.UTF-8
LANGUAGE=en_US.UTF-8
LC_ADDRESS=en_US.UTF-8
LC_COLLATE=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_IDENTIFICATION=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_TIME=en_US.UTF-8' > /etc/locale.conf
    }

    hostname_config () {
        #set hostname
        echo 'home' > /etc/hostname
    }

    user_config () {
        #create user and add it to wheel group
        useradd -m -G wheel -s /bin/bash kosh
        #changing password
        echo "root:qwe" |chpasswd
        echo "kosh:qwe" |chpasswd
        usermod -s /usr/bin/bash root
    }

    git_install () {
        #adding git
        pacman -S --noconfirm git
    }

    yay_install () {
        #dropping root user bacause makepkg and yay not working from root user
        su - kosh -c "git clone https://aur.archlinux.org/yay-bin && \
                      cd yay-bin && \
                      yes | makepkg -si && \
                      cd .. && \
                      rm -rf yay-bin && \
                      yay -Y --gendb && \
                      yes | yay -Syu --devel && \
                      yay -Y --devel --save && \
                      yay --editmenu --nodiffmenu --save"
    }

    apps_install () {
        #installing needed packages
        su - kosh -c "echo y | LANG=C yay -S \
                                          --noprovides \
                                          --answerdiff None \
                                          --answerclean None \
                                          --mflags \" --noconfirm\" \
                                          lvm2 docker docker-compose dive mc wget curl openssh pigz docker-buildx grub efibootmgr polkit"
        #админу локалхоста дозволено:)
        sudo usermod -aG docker kosh
    }

    init_modules_install () {
            su - kosh -c "yes | LANG=C yay -S \
                                          --noprovides \
                                          --answerdiff None \
                                          --answerclean None \
                                          --mflags \" --noconfirm\" \
                                          mkinitcpio-firmware"
    }

    generate_init () {
        mkinitcpio -P
    }

    zsh_install () {
        su - kosh -c "wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh | bash"
    }

    systemd_units_enable () {
        #enabling units
        systemctl enable docker
        systemctl enable sshd
    }

    grub_install () {
        #installin grub. extra config needed because we dont have efivars in container
        mkdir -p /boot/efi
        grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --force \
            --no-nvram \
            --removable
        grub-mkconfig -o /boot/grub/grub.cfg
    }

    systemd_boot_install () {
        bootctl install --esp-path=/boot/efi
        ENTRIES=/boot/loader/entries
        mkdir -p "$ENTRIES"
        echo "title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=\"$(blkid | grep $DISKp1 | awk '{ print $5 }')=Arch OS\" rw" > "$ENTRIES"/arch.conf
    }
    

    postinstall_config () {
        #for now we have large initramfs and strange-installed-grub. 
        #in this block we generate initrd image with autodetect hook, reinstall grub and fixing sudo permissions
        #after that remove this helper script
        sed -i '1s|^|sudo /home/kosh/postinstall.sh\n|' /home/kosh/.zshrc
            echo -e "sed -i 's/HOOKS=(base systemd modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/HOOKS=(base systemd autodetect modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
            echo generationg initrd image...
            mkinitcpio -P
            echo done
            echo re-installing grub...
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
            echo done...
            echo changing sudoers...
            sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
            sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
            echo done
            sed -i '1d' /home/kosh/.zshrc
            rm /home/kosh/postinstall.sh
            sudo reboot" > /home/kosh/postinstall.sh
            chmod 755 /home/kosh/postinstall.sh
    }

    main () {
        sudo_config
        mkinitcpio_install
        remove_autodetect_hook
        kernel_install
        time_config
        locale_config
        language_config
        hostname_config
        user_config
        git_install
        yay_install
   #pkgbuild for modules currently broken in aur
   #     init_modules_install
        apps_install
        generate_init
        zsh_install
        systemd_units_enable
   #not implemented
   #     systemd_boot_install
        grub_install
        postinstall_config
    }

    main

EOF
}

unmounting_all () {
    # unmount all mounts
    # we need this to stop grub in vm dropping in grub-shell due first run
    umount "$MOUNT_PATH"/boot/efi 
    umount "$MOUNT_PATH"/boot
    umount "$MOUNT_PATH"
    losetup -d "$DISK" 
}

run_in_qemu () {
    qemu-system-x86_64 \
        -enable-kvm \
        -smp cores=4 \
        -m 8G \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
        -device nvme,drive=drive0,serial=badbeef \
        -drive if=none,id=drive0,file=./vhd.img
}

run_in_qemu_arch () {
    qemu-system-x86_64 \
        -enable-kvm \
        -smp cores=4 \
        -m 8G \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.fd \
        -device nvme,drive=drive0,serial=badbeef \
        -drive if=none,id=drive0,file=./vhd.img
}

main () {
    case "$ID" in 
          fedora) prepare_dependecies
                  pacman_init
                  create_image
                  mount_image
                  exit_trap
                  format_image
                  mount_root
                  pacstrap_base
                  mount_boot
                  chroot_arch
                  unmounting_all
                  run_in_qemu
                  ;;

            arch) prepare_dependecies_arch
                  create_image
                  mount_image
                  exit_trap
                  format_image
                  mount_root
                  pacstrap_base
                  mount_boot
                  chroot_arch
                  unmounting_all
                  run_in_qemu_arch
                  ;;
          debian) prepare_dependecies_debian
                  pacman_init
                  create_image
                  mount_image
                  exit_trap
                  format_image
                  mount_root
                  pacstrap_base_debian
                  mount_boot
                  chroot_arch
                  unmounting_all
                  run_in_qemu
    esac
}

main
