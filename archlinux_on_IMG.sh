# POC
# fully working arch linux builded from RHEL-like command line on RAW IMAGE
# with uefi, grub, root partition in lvm with ext4, oh-my-zsh and modern apps
#
# Полностью работоспособный arch linux установленный из rhel, debian и alpine дистрибутивов.
# Кофигурация включает в себя uefi grub агрузчик, корневой раздел на lvm в ext4,
#предустановленный oh-my-zsh и некоторые замены в системных приложениях .
#
# в репозиториях fedora есть все для устновки arch в chroot: pacstrap, pacman,genfstab,
# arch-chroot (в пакете arch-install-scripts), archlinux-keyring - отдельно.
# При помощи этого набора через pacstrap устанавливается в /mnt/arch новый корень с arch,
# происходит chroot туда и уже оттуда донастраивается.
#
# В дебиан тоже есть arch-install-scripts пакет, но в нем нет pacstrap.
# то есть сходу нет простого инструмента сделать корневую систему arch в /mnt/arch.
# Мы просто дергаем bootstrap архив с корневой системой арча и распаковвываем ее в /mnt/arch.
# А потом уже донастраиваем из окружение chroot.
#
# В alpine есть все скрипты для установки но нет archlinux-keyring
# https://gitlab.alpinelinux.org/alpine/aports/-/merge_requests/42040
# Поэтому для установки корневой системы мы выключаем временно проверку подписей пакетов,
# ставим и делаем chroot. Донастраиваем изнутри.
# Так же в alpine изкоробки поломан genfstab так как некоторых стандартных приложений
# нет в дефолтной поставке alpine либо используются busybox варианты.

# dnf подобные дистрибутивы можно ставить через sudo dnf  --installroot=/mnt/rocky group install core
# создав /mnt/rocky/etc/yum.repos.d/rocky.conf файл с описанием репозитория:
# [baseos]
# name=Rocky Linux $releasever - BaseOS
# mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=$basearch&repo=BaseOS-$releasever
# #baseurl=http://dl.rockylinux.org/$contentdir/$releasever/BaseOS/$basearch/os/
# gpgcheck=1
# enabled=1
# countme=1
# gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial

# Для apt подобных debootstrap
# debootstrap --include=sudo,nano,wget buster /mnt/debian  http://deb.debian.org/debian

set -oe noglob

reset="\033[0m"

red="\033[0;31m"
green="\033[0;32m"
white="\033[0;37m"
tan="\033[0;33m"

info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { >&2 printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}

# source distrib info
. /etc/os-release
# path where we build new arch linux system
MOUNT_PATH=/mnt/arch

############################################################################################
############################### PREPARE HOST TO BUILD IMAGE ################################
############################################################################################
prepare_dependecies () {
    if [ "$ID" = "fedora" ]; then
        success "Installing dependencies for fedora..."
        # installing dependencies
        # arch-install-scripts - pacman and his dependencies
        # e2fsprogs - for making fs in image
        # dosfstools - for making fat32 fs in image
        # qemu-kvm-core - for run builded image in qemu-kvm
        # edk2-ovmf - uefi bios for run image in qemu with uefi
        dnf install -y arch-install-scripts \
                       e2fsprogs \
                       dosfstools \
                       qemu-kvm-core \
                       edk2-ovmf \
                       lvm2
    elif [ "$ID" = "arch" ]; then
        warn "in arch linux i create lvm mountpoint as /dev/arch/root for root filesystem"
        warn "script can do unknown effects on host if thereis already that lvm mountpoint!!!"
        sleep 10

        success "Installing dependencies for arch..."
        pacman -S --needed lvm2 \
                           dosfstools \
                           arch-install-scripts \
                           edk2-ovmf \
                           e2fsprogs
        # on my arch laptop qemu-desktop is installed
        # qemu-desktop and qemu-base conflicts
        if ! pacman -Qi qemu-desktop > /dev/null 2>&1 ; then
            pacman -S qemu-base
        fi
    elif [ "$ID" = "debian" ]; then
        warn "in debian fdisk tolds me that alias 44 for filesystem is Linux /usr verity (x86-64)"
        warn "in fedora alias 44 - LVM filesystem. I dont know what can be broken. At least it loading filesystem, anyway."
        sleep 10

        success "Installing dependencies for debian..."
        apt install -y arch-install-scripts \
                       e2fsprogs \
                       dosfstools \
                       qemu-utils \
                       qemu-system-x86 \
                       ovmf \
                       lvm2
    elif [ "$ID" = "alpine" ]; then
        success "Installing dependencies for alpine..."
        #busybox-losetup dont know about --show flag
        #installing losetup
        #installing findmnt dependency for genfstab. not installing default
        #20 min of my life gone before i understand that genfstab not generating PARTUUID because there is no lsblk in alpine. fuk...
        #installing gawk because busybox-awk not working with this script
        #installing grep
        apk add pacman \
                arch-install-scripts \
                losetup \
                dosfstools \
                lvm2 \
                e2fsprogs \
                qemu-system-x86_64 \
                qemu-img \
                findmnt \
                gawk \
                grep \
                ovmf \
                lsblk
    else
        exit 1
    fi
}

create_image () {
    success "Creating image..."
    # creating empty image
    dd if=/dev/zero of=./vhd.img bs=1M count=10000

    if [ "$WSL_INSTALL" = "true" ]; then
        success "Creating image for wsl..."
        fdisk ./vhd.img <<-EOF
            g
            n
            1
            2048
            20477951
            t
            23
            w
EOF

    else
        # creating in image gpt table and 3 partitions
        # first one - EFI partinion. we will mount it to /boot/efi later with filesystem fat32
        # second one - "boot" partition. we will mount it to /boot later with filesystem fat32
        # third one - "root" partition. we will mount it to / later with lvm and ext4 partition
        fdisk ./vhd.img <<-EOF
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
    fi
}

mount_image () {

    success "Mounting image..."
    # mount img file to loop to interact with created partitions
    # they will be available in /dev/loop_loop-number_partition-number
    # like /dev/loop0p1 or /dev/loop20p3
    export DISK=$(losetup -P -f --show vhd.img)
}

exit_trap () {
    # if script fail - we need to umnount all mounts to clear host machine
    on_exit () {
        if [ "$WSL_INSTALL" = "true" ]; then
            umount "$MOUNT_PATH" || true
        else
            sync
            sleep 5
            fuser -km "$MOUNT_PATH"/boot/efi || true
            umount "$MOUNT_PATH"/boot/efi || true
            sleep 1
            fuser -km "$MOUNT_PATH"/boot || true
            umount "$MOUNT_PATH"/boot || true
            sleep 1
            fuser -km "$MOUNT_PATH" || true
            umount "$MOUNT_PATH" || true
            sleep 5
            lvchange -an /dev/arch/root || true
        fi
        losetup -d "$DISK" || true
        echo "trap finished"
    }
trap "on_exit" EXIT
}

format_image () {
    if [ "$WSL_INSTALL" = "true" ]; then
        mkfs.ext4 "$DISK"p1
    else
        success "Formatting image..."
        # formatting boot partition
        mkfs.fat -F 32 "$DISK"p1
        # formatting efi partition
        mkfs.fat -F 32 "$DISK"p2
        # creating root pv
        pvcreate "$DISK"p3
        # creating root vg
        vgcreate arch "$DISK"p3
        # creating root lv
        lvcreate -l 100%FREE arch -n root
        # formatting root lv
        mkfs.ext4 /dev/arch/root
    fi
}

mount_root () {
    success "Mount root tree"
    # create mount dirs
    mkdir -p "$MOUNT_PATH"
    # mount formatted root disk to /
    if [ "$WSL_INSTALL" = "true" ]; then
        mount "$DISK"p1 "$MOUNT_PATH"
    else
        mount /dev/arch/root "$MOUNT_PATH"
    fi
}

pacstrap_base () {
    # workaround to create wsl in debian way
    if [ "$WSL_INSTALL" = "true" ] ; then 
        ID=debian
    fi
    if [ "$ID" = "fedora" ] ; then
        success "Initializing pacman..."
        # initialize keyring and load archlinux keys for host pacman
        pacman-key --init
        pacman-key --populate archlinux
        success "Install base files..."
        # installing base arch files and devel apps
        pacstrap -K "$MOUNT_PATH" base base-devel

    elif [ "$ID" = "debian" ] ; then
        success "Download bootstrap arch archive..."
        # installing base arch files and devel apps
        # in debian arch-install-scripts package thereis no pacstrap script, so...
        # we can wget pacstrap script from net or...
        # ...full bootstrap image... for example
        cd "$MOUNT_PATH"
        #donwloading tar archive with bootstrap image to build dir
        wget -O archlinux.tar.gz https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.gz
        #extracting archive in current dir with cut root dir
        tar xzf ./archlinux.tar.gz --numeric-owner --strip-components=1
        #chrooting to bootstrap root
        success "Init pacman from base image system..."
        arch-chroot "$MOUNT_PATH" <<-EOF
            #usually pacstrap script populating keys but we doing it manually
            pacman-key --init
            pacman-key --populate archlinux
            #configuring mirrorlist
            sed -i 's/#Server =/Server =/g' /etc/pacman.d/mirrorlist
            #installing root
            pacman -Syu --noconfirm base base-devel
            #ckeaning up root dir. thereis tar archive, list installed packages in root and version file.
            rm -f /archlinux.tar.gz
            rm -f /pkglist.x86_64.txt
            rm -f /version
EOF
            cd -

    elif [ "$ID" = "alpine" ]; then
        success "Init pacman from Alpine system"
        #pacman in alpine has no configured repositories
        #and it has no archlinux-keyring in repo, so temporary disabling PGP check to install base packages before chroot
        echo "
[core]
SigLevel = Never
Include = /etc/pacman.d/mirrorlist

[community]
SigLevel = Never
Include = /etc/pacman.d/mirrorlist

[extra]
SigLevel = Never
Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
        #...and no mirrorlist
        mkdir -p /etc/pacman.d
        wget -O /etc/pacman.d/mirrorlist https://archlinux.org/mirrorlist/all/http/
        #configuring mirrors
        sed -i 's/#Server =/Server =/g' /etc/pacman.d/mirrorlist
        pacstrap -K "$MOUNT_PATH" base base-devel

    else
        exit 1
    fi
}

mount_boot () {
    if [ "$WSL_INSTALL" = "true" ]; then
        true
    else
        success "Mounting partitions..."
        # mount boot partition
        mount "$DISK"p2 "$MOUNT_PATH"/boot
        # creating dir for efi
        mkdir -p "$MOUNT_PATH"/boot/efi
        # mount efi partition
        mount "$DISK"p1 "$MOUNT_PATH"/boot/efi
    fi
    # if we not remove swap from host machine he will appear in arch fstab
    swapoff -a
    # partition tree finished. generating fstab
    genfstab -U -t PARTUUID "$MOUNT_PATH" > "$MOUNT_PATH"/etc/fstab
}

############################################################################################
##################################### CHROOT ###############################################
############################################################################################
chroot_arch () {
    success "Chrooting arch-linux..."
    # tell the environment that this is install for wsl
    if [ "$WSL_INSTALL" = "true" ]; then
        echo "WSL_INSTALL=true" >> "$MOUNT_PATH"/etc/environment
    fi
    # go to arch
    arch-chroot "$MOUNT_PATH" <<-EOF
        #!/usr/bin/env bash
        set -e
        sudo_config () {
            # temporary disabling ask password
            sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
        }

        mkinitcpio_install () {
            # install kernel and firmware
            pacman -S --noconfirm mkinitcpio
        }

        remove_autodetect_hook () {
            # to run arch in most any environment we need build init image with all we can add to it
            sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base systemd modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
        }

        kernel_install () {
            # installing kernel and firmware
            pacman -S --noconfirm linux linux-firmware
        }

        #we can not use systemd to configure locales, time and so on cause we are in chroot environment
        time_config () {
            # config localtime
            ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
        }

        locale_config () {
            # add locales
            sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/g' /etc/locale.gen
            sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
            # generating locale
            locale-gen
        }

        language_config () {
            # set default language
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
            # set hostname
            echo 'home' > /etc/hostname
        }

        user_config () {
            # create user and add it to wheel group
            useradd -m -G wheel -s /bin/bash kosh
            # changing password
            echo "root:qwe" |chpasswd
            echo "kosh:qwe" |chpasswd
            usermod -s /usr/bin/bash root
        }

        git_install () {
            # adding git
            pacman -S --noconfirm git
        }

        yay_install () {
            # dropping root user bacause makepkg and yay not working from root user
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
            # installing needed packages to working properly
            su - kosh -c "LANG=C yay -S \
                                      --noprovides \
                                      --answerdiff None \
                                      --answerclean None \
                                      --mflags \" --noconfirm\" \
                                                               lvm2 \
                                                               wget \
                                                               openssh \
                                                               grub \
                                                               efibootmgr \
                                                               parted \
                                                               networkmanager \
                                                               modemmanager \
                                                               usb_modeswitch \
                                                         --noconfirm"
            systemctl enable NetworkManager
            systemctl enable ModemManager
            systemctl enable sshd
        }

        grub_install () {
            # installin grub. extra config needed because we dont have efivars in container
            mkdir -p /boot/efi
            grub-install \
                --target=x86_64-efi \
                --efi-directory=/boot/efi \
                --force \
                --no-nvram \
                --removable
            grub-mkconfig -o /boot/grub/grub.cfg
        }

        other_config () {
            wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/custom_config.sh | bash
    }

    main () {
        if ! [ "$WSL_INSTALL" = "true" ]; then
            sudo_config
            mkinitcpio_install
            remove_autodetect_hook
            time_config
            locale_config
            language_config
            hostname_config
            user_config
            git_install
            yay_install
            apps_install
            kernel_install
            grub_install
            other_config
        else

            # wsl is container so we need minimal install to work in wsl
            # do not need:
            # mkinitcpio (cause thereis no kernel)
            # kernel (cause container using wsl kernel)
            # grub (cause thereis no bios or uefi)

            sudo_config
            time_config
            locale_config
            language_config
            hostname_config
            user_config
            git_install
            yay_install
            apps_install
            other_config
        fi
    }

    main

EOF

}

postinstall_config () {
    success "Create postinstall script..."
    # for now we have large initramfs and strange-installed-grub.
    # in this block we generate initrd image with autodetect hook, reinstall grub, fixing sudo permissions,
    # resizing partition / to full disk and creating swap
    # after that remove this helper script

    # adding this script to autoboot after first load arch linux
    sed -i '1s#^#sudo /home/kosh/postinstall.sh\n#' "$MOUNT_PATH"/home/kosh/.zshrc

    # script body
    cat <<'EOL' >> "$MOUNT_PATH"/home/kosh/postinstall.sh
#!/usr/bin/env bash
        set -x
        if [ "$WSL_INSTALL" = "true" ]; then
            # removing helper script from autoload
            sed -i '1d' /home/kosh/.zshrc
            # removing helper script itself
            rm /home/kosh/postinstall.sh
            
            # Removing packages from wsl instance
            su - kosh -c "LANG=C yay -Rscn --noconfirm\
                                                    lvm2 \
                                                    grub \
                                                    efibootmgr \
                                                    parted"

            # Alter user to kosh in wsl
            # enable systemd in wsl
            # alter default login dir in wsl
                                                    
            # changing sudo rules to disable executing sudo without password
            sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
            # allow wheel group using sudo with password
            sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
        else
            # adding autodetect hook to mkinicpio to generate default arch init image
            sed -i 's/HOOKS=(base systemd modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/HOOKS=(base systemd autodetect modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
            # creating initrd image
            mkinitcpio -P

            # reinstalling grub
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
            grub-mkconfig -o /boot/grub/grub.cfg

            # check memory available
            memory=$(free -m | grep Mem | awk '{print $2}')
            # creating swap file with size equal to memory
            dd if=/dev/zero of=/swapfile bs=1M count=$memory
            # changing swap file permissions
            chmod 0600 /swapfile
            # formatting swap file
            mkswap -U clear /swapfile
            # enabling swap
            swapon /swapfile
            # adding swap file entry to fstab to automount
            echo "/swapfile none swap defaults 0 0" >> /etc/fstab
            echo done

            # default disk size in this script 10G
            # after install we want to use all disk space
            echo resizing disk
            # searching name of partition with mounted root FS
            ROOT_PARTITION=$(sudo pvs | grep arch | awk '{print $1}')
            # searching disk name with founded root partition
            ROOT_DISK=$(lsblk -n -o NAME,PKNAME -f "$ROOT_PARTITION" | awk '{ print $2 }' | head -1)
            # adding all free disk space on founded disk to root FS partition
            echo ", +" | sfdisk -N 3 /dev/"$ROOT_DISK" --force
            # reloading hard disk info
            partprobe

            # we have lvm on root partition. after resizing disk we need add new space to lvm
            # extend physical volume to use all free space on partition
            pvresize "$ROOT_PARTITION"
            # extend logical volume to use all free space from physical volume
            lvextend -l +100%FREE /dev/arch/root
            # we have ext4 fs on lvm. resizing ext4 fs
            resize2fs /dev/arch/root

            # removing helper script from autoload
            sed -i '1d' /home/kosh/.zshrc
            # removing helper script itself
            rm /home/kosh/postinstall.sh

            # changing sudo rules to disable executing sudo without password
            sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
            # allow wheel group using sudo with password
            sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers

            # rebooting OS after reconfiguring
            sudo reboot
        fi
EOL
        # marking helper script executable
        chmod 777 "$MOUNT_PATH"/home/kosh/postinstall.sh

}

unmounting_all_and_wsl_copy () {
    success "Unmount partitions..."
    # unmount all mounts
    # we need this to stop grub in vm dropping in grub-shell due first run
    if [ "$WSL_INSTALL" = "true" ]; then
        tar -cf /archfs.tar -C /mnt/arch .
        success "ARCH root filsystem exported to /archfs.tar"
        warn "You need to export this file to WSL. Example:"
        warn "wsl --import Arch-linux D:\arch\ .\archfs.tar"
        warn "Where: wsl - wsl command in windows"
        warn "       --import Arch-linux - import wsl machine with name Arch-linux"
        warn "       D:\arch - dir where will be placed image with filsesystem"
        warn "       .\archfs.tar - path to generated tar archive with filesystem"
        error "You must enable fonts in your terminal !"
        info "See here: https://github.com/romkatv/powerlevel10k#fonts <---"
        umount "$MOUNT_PATH" || true
    else
        sync
        sleep 5
        fuser -km "$MOUNT_PATH"/boot/efi || true
        umount "$MOUNT_PATH"/boot/efi || true
        sleep 1
        fuser -km "$MOUNT_PATH"/boot || true
        umount "$MOUNT_PATH"/boot || true
        sleep 1
        fuser -km "$MOUNT_PATH" || true
        umount "$MOUNT_PATH" || true
        sleep 5
        lvchange -an /dev/arch/root || true
    fi
    sleep 1
    losetup -d "$DISK" || true
    echo "Done"
}

run_in_qemu () {
    if  [ "$WSL_INSTALL" = "true" ]; then
        #qemu-img convert -p -f raw -O vhdx ./vhd.img ./vhd.vhdx
        #success "wsl image created !!!"
        true
    else
        qemu-img resize ./vhd.img 15G
        qemu-system-x86_64 \
            -enable-kvm \
            -smp cores=4 \
            -m 2G \
            -drive if=pflash,format=raw,readonly=on,file="$(find /usr/share -name OVMF_CODE.fd | head -n 1)" \
            -device nvme,drive=drive0,serial=badbeef \
            -drive if=none,id=drive0,file=./vhd.img
    fi
}

main () {
    if [ "$1" = "--wsl" ]; then
        export WSL_INSTALL=true
    fi

    prepare_dependecies
    create_image
    mount_image
    exit_trap
    format_image
    mount_root
    pacstrap_base
    mount_boot
    chroot_arch
    postinstall_config
    unmounting_all_and_wsl_copy
    run_in_qemu

}

main "$@"
