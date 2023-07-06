#!/usr/bin/env bash
set -xe
#path where we build new arch linux system
MOUNT_PATH=/mnt/arch
#for testing. enshure that first loop device is free to mount img there
losetup --detach-all

prepare_dependecies () {
    #installing dependencies
    dnf install arch-install-scripts e2fsprogs dosfstools
}

pacman_init () {
    #initialize keys and load archlinux keys
    pacman-key --init
    pacman-key --populate archlinux
}

create_image () {
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
}

mount_image () {
    #mount img file to loop and get loop path
    DISK=$(losetup -P -f --show vhd.img)
    echo -e "USING $DISK <-----------------"
}

format_image ()
    #formatting root partition
    mkfs.ext4 "$DISK"p2
    #formatting boot partition
    mkfs.fat -F 32 "$DISK"p1
}

mount_root () {
    #create mount dirs
    mkdir -p "$MOUNT_PATH"
    #mount formatted root disk to /
    mount "$DISK"p2 "$MOUNT_PATH"
}

pacstrap_base () {
    #installing base arch files and devel apps
    pacstrap "$MOUNT_PATH" base base-devel
}

mount_boot () {
    #mount boot partition
    mount "$DISK"p1 "$MOUNT_PATH"/boot
    # partition tree finished. generating fstab
    genfstab -U -t PARTUUID "$MOUNT_PATH" > "$MOUNT_PATH"/etc/fstab
}
chroot_arch () {
    #go to arch
    sudo arch-chroot "$MOUNT_PATH" << EOF
    mkinitcpio_install () {
        #install kernel and firmware
        pacman -S --noconfirm mkinitcpio
    }

    remove_autodetect_hook () {
        #to run arch in most any environment we need build init image with all we can add to it
        sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev modconf kms keyboard keymap consolefont block filesystems fsck)/g' /etc/mkinitcpio.conf
    }

    kernel_install () {
        #installing kernel and firmware
        pacman -S --noconfirm linux linux-firmware
    }

    time_config () {
        #config localtime
        ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
        #config hardware clocks
        hwclock --systohc
    }

    locale_config () {
        #add ru locale
        sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/g' /etc/locale.gen 
        sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen 
        #generating locale
        locale-gen 
    }

    language_config () {
        #set default language
        echo -e 'LANG=en_US.UTF-8,\nLANGUAGE=en_US.UTF-8,\nLC_ALL=en_US.UTF-8' > /etc/locale.conf
    }

    hostname_config () {
        #set hostname
        echo 'home' > /etc/hostname
    }
 
    sudo_config () {
        #allow grup wheel to sudo
        sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
    }

    user_config () {
        #create user and add it to wheel group
        useradd -m -G wheel -s /bin/bash kosh
        #changing password
        echo "root:qwe" |chpasswd
        echo "kosh:qwe" |chpasswd
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
                      yay -Syu --devel && \
                      yay -Y --devel --save && \
                      yay --editmenu --nodiffmenu --save && \
    apps_install () {
        echo y | LANG=C yay -S \
                            --noprovides \
                            --answerdiff None \
                            --answerclean None \
                            --mflags \" --noconfirm\" \
                                   docker docker-compose dive mc wget curl openssh pigz docker-buildx grub efibootmgr polkit"
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
        #installin grub. extra config needed because we dont have efivars
        mkdir -p /boot/efi
        grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --force \
            --no-nvram \
            --removable
        grub-mkconfig -o /boot/grub/grub.cfg
    }

    postinstall_config () {
        ex /home/kosh/.zshrc << EOH
            echo -e "Finishing installing..."
            echo -e "Enabling autodetect in mkinitcpio..."
            sed -i 's/HOOKS=(base udev modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/g' /etc/mkinitcpio.conf
            echo -e "Reinstaliing grub loader..."
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
EOH
}

    main () {
        mkinitcpio_install
        remove_autodetect_hook
        kernel_install
        time_config
        locale_config
        language_config
        hostname_config
        sudo_config
        user_config
        git_install
        yay_install
        apps_install
        zsh_install
        systemd_units_enable
        grub_install
        postinstall_config
    }

    main

EOF
}

umount_all () {
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

main () {
    prepare_dependecies
    pacman_init
    create_image
    mount_image
    format_image
    mount_root
    chroot_arch
    umount_all
    run_in_qemu
}

main "$@"
