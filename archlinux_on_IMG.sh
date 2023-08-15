# POC
# fully working arch linux builded from RHEL-like command line on RAW IMAGE
# with uefi, grub, root partition in lvm with ext4, oh-my-zsh and modern apps
#
# Полностью работоспособный arch linux установленный из rhel, debian и alpine дистрибутивов.
# Кофигурация включает в себя uefi grub агрузчик, корневой раздел на lvm в ext4,
# предустановленный oh-my-zsh и некоторые замены в системных приложениях .
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

set -oxe noglob

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

options_handler () {
    # declare variables for operate with options
    WSL_INSTALL=false
    WITH_CONFIG=true
    NSPAWN_CHECK=false
    QEMU_CHECK=false
    VMWARE_EXPORT=false
    HYPERV_EXPORT=false

    # help message
    options_message () {
        info " Usage: script_name.sh --wsl --clean --nspawn ( Create wsl rootfs with clean arch linux and check it in systemd-nspawn )"
        info "        script_name.sh --qemu --vmware ( Create uefi raw image with customizations, execute image in qemu and export image for vmware workstation)"
        info " Options:"
        info " --wsl - create tar archive for wsl."
        info " --clean - create clean Arch Linux image."
        info " --nspawn - check created image in nspawn container. ( Not working in Alpine Linux )"
        info " --qemu - check created image in qemu. ( Not working with --wsl key )"
        info " --vmware - gen image for VMWARE. ( Not working with --wsl key )"
        info " --hyperv - gen image for HYPER-V. ( Not working with --wsl key )"
    }

    # catch arguments from command line
    while [ "$1" != "" ]; do
        case "$1" in
            --wsl|-w) WSL_INSTALL=true
                   ;;
          --clean|-c) WITH_CONFIG=false
                   ;;
         --nspawn|-n) NSPAWN_CHECK=true
                   ;;
           --qemu|-q) QEMU_CHECK=true
                   ;;
         --vmware|-v) VMWARE_EXPORT=true
                   ;;
         --hyperv|-y) HYPERV_EXPORT=true
                   ;;
           --help|-h) options_message
                      exit 0
                   ;;
                   *) error "Unknown option: $1"
                      echo ""
                      options_message
                      exit 1
                  ;;
        esac
        shift
    done

    # catch mutually exclusive options
    if [ "$WSL_INSTALL" = "true" ] && [ "$QEMU_CHECK" = "true" ]; then
        error "We cannot check WSL image in QEMU. Abort"
        exit 1
    fi
        if [ "$WSL_INSTALL" = "true" ] && [ "$VMWARE_EXPORT" = "true" ]; then
        error "We cannot check WSL image in VWWARE. Abort"
        exit 1
    fi
    if [ "$WSL_INSTALL" = "true" ] && [ "$HYPERV_EXPORT" = "true" ]; then
        error "We cannot check WSL image in HYPERV. Abort"
        exit 1
    fi
    if [ "$NSPAWN_CHECK" = "true" ] && [ "$ID" = "true" ]; then
        error "Alpine Linux does not have systemd nspawn. Abort"
        exit 1
    fi
}



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
                       lvm2
    elif [ "$ID" = "arch" ]; then
        success "Installing dependencies for arch..."
        pacman -S --needed --disable-download-timeout \
                           lvm2 \
                           dosfstools \
                           arch-install-scripts \
                           e2fsprogs
    elif [ "$ID" = "debian" ]; then
        success "Installing dependencies for debian..."
        apt install -y arch-install-scripts \
                       e2fsprogs \
                       dosfstools \
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
                findmnt \
                gawk \
                grep \
                lsblk
    else
        error "This script not working in: $ID"
        exit 1
    fi
}

create_image_wsl () {
    success "Creating image for wsl..."
    # creating empty image
    dd if=/dev/zero of=./vhd.img bs=1M count=10000
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
}
    
create_image () {
    success "Creating image..."
    # creating empty image
    dd if=/dev/zero of=./vhd.img bs=1M count=10000
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
}

mount_image () {

    success "Mounting image..."
    # mount img file to loop to interact with created partitions
    # they will be available in /dev/loop_loop-number_partition-number
    # like /dev/loop0p1 or /dev/loop20p3
    export DISK=$(losetup -P -f --show vhd.img)
}

exit_trap_wsl () {
    # if script fail - we need to umnount all mounts to clear host machine
    # hmm. I can not use fuser to force unmount. This chashing wsl2
    on_exit () {
        error "trap start"
        pkill -en gpg-agent || true
        umount "$MOUNT_PATH" || true
        losetup -d "$DISK" || true
        error "trap finished"
    }
    trap "on_exit" EXIT
}

exit_trap () {
    # if script fail - we need to umnount all mounts to clear host machine
    on_exit () {
        pkill -en gpg-agent || true
        sync
        umount "$MOUNT_PATH"/boot/efi || true
        umount "$MOUNT_PATH"/boot || true
        umount "$MOUNT_PATH" || true
        lvchange -an /dev/arch/root || true
        losetup -d "$DISK" || true
        error "trap finished"
    }
    trap "on_exit" EXIT
}

format_image_wsl () {
    success "Formatting partition..."
    mkfs.ext4 "$DISK"p1
}

format_image () {
    success "Formatting partitions..."
    # formatting boot partition
    mkfs.fat -F 32 "$DISK"p1
    # formatting efi partition
    mkfs.fat -F 32 "$DISK"p2
    # creating root pv
    pvcreate "$DISK"p3
    # creating root vg
    vgcreate arch "$DISK"p3
    # creating root lv
    # fuck debian with custom lvm2 and udev
    if [ "$ID" = "debian" ]; then
        error "If you wee error below - you should blame Debian"
    fi
    lvcreate -l 100%FREE arch -n root
    # formatting root lv
    mkfs.ext4 /dev/arch/root
}

mkdir_root () {
    success "Mount root tree"
    # create mount dirs
    mkdir -p "$MOUNT_PATH"
}

mount_root_wsl () {
    # mount formatted root disk to /
        mount "$DISK"p1 "$MOUNT_PATH"
}

mount_root () {
    # mount formatted lvm disk to /
    mount /dev/arch/root "$MOUNT_PATH"
}

pacstrap_base () {
    if [ "$WSL_INSTALL" = "true" ]; then
        OLD_ID=$ID
        ID=debian
    fi
    if [ "$ID" = "fedora" ] || [ "$ID" = "arch" ]; then
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
        wget -qO archlinux.tar.gz https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.gz
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
            pacman -Syu --needed --noconfirm --disable-download-timeout base base-devel
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
    ID=$OLD_ID
}

mount_boot () {
    success "Mounting partitions..."
    # mount boot partition
    mount "$DISK"p2 "$MOUNT_PATH"/boot
    # creating dir for efi
    mkdir -p "$MOUNT_PATH"/boot/efi
    # mount efi partition
    mount "$DISK"p1 "$MOUNT_PATH"/boot/efi
}

disable_swap () {
    # if we not remove swap from host machine he will appear in arch fstab
    swapoff -a
}

fstab_gen () {
    # partition tree finished. generating fstab
    genfstab -U -t PARTUUID "$MOUNT_PATH" > "$MOUNT_PATH"/etc/fstab
}

############################################################################################
##################################### CHROOT ###############################################
############################################################################################
chroot_arch () {
    success "Chrooting arch-linux..."
    # tell the environment that this is install for wsl
    echo "WSL_INSTALL=$WSL_INSTALL" >> "$MOUNT_PATH"/etc/environment
    # tell the environment about unnessesary config
    echo "WITH_CONFIG=$WITH_CONFIG" >> "$MOUNT_PATH"/etc/environment

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
            pacman -S --needed --noconfirm --disable-download-timeout mkinitcpio
        }

        remove_autodetect_hook () {
            # to run arch in most any environment we need build init image with all we can add to it
            sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base systemd modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
        }

        kernel_install () {
            # installing kernel and firmware
            pacman -S --needed --noconfirm --disable-download-timeout linux linux-firmware
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
            echo '127.0.0.1 home' >> /etc/hosts
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
            pacman -S --needed --noconfirm --disable-download-timeout git
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
                                      --mflags \" --noconfirm\" --mflags \"--disable-download-timeout\" \
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
            systemctl mask systemd-networkd
        }

        grub_install () {
            # installing grub. extra config needed because we dont have efivars in container
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
            # my personal config
            if [ "$WITH_CONFIG" = "true" ]; then
                wget -O - "https://raw.githubusercontent.com/deathmond1987/homework/main/custom_config.sh" | bash
            fi
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
        success "Create postinstall script for Virtual Machine..."
        # for now we have large initramfs and strange-installed-grub.
        # in this block we generate initrd image with autodetect hook, reinstall grub, fixing sudo permissions,
        # resizing partition / to full disk and creating swap
        # after that remove this helper script

        # adding this script to autoboot after first load arch linux
        if [ "$WITH_CONFIG" = "true" ]; then
            sed -i '1s#^#sudo /home/kosh/postinstall.sh\n#' "$MOUNT_PATH"/home/kosh/.zshrc
        else 
            sed -i '1s#^#sudo /home/kosh/postinstall.sh\n#' "$MOUNT_PATH"/home/kosh/.bashrc
        fi 
        # script body
        cat <<'EOL' >> "$MOUNT_PATH"/home/kosh/postinstall.sh
            #!/usr/bin/env bash
            set -xe
            . /etc/environment
            if ! [ "$WSL_INSTALL" = "true" ]; then
                ######################################################################################################
                ######################################### HOST #######################################################
                ######################################################################################################
                # if this real host and we have internet - we will install vendor blobs for processor
                if timeout 6 curl --head --silent --output /dev/null https://hub.docker.com; then
                    if ! systemd-detect-virt -q; then
                        vendor=$(lscpu | awk '/Vendor ID/{print $3}'| head -1)
                        if [[ "$vendor" == "GenuineIntel" ]]; then
                            yay -S --noconfirm intel-ucode
                        elif [[ "$vendor" == "AuthenticAMD" ]]; then
                            yay -S --noconfirm amd-ucode
                        else
                            echo "cpu vendor: $vendor"
                        fi
                    fi
                    if [ "$WITH_CONFIG" = true ]; then
                            cd /opt/tor
                            docker-compose up -d
                            cd -
                    fi
                fi

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
                echo "done"

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
            fi 
            # removing helper script from autoload
            if [ "$WITH_CONFIG" = true ]; then
                sed -i '1d' /home/kosh/.zshrc
            else
                sed -i '1d' /home/kosh/.bashrc
            fi
            # removing helper script itself
            rm /home/kosh/postinstall.sh

            # changing sudo rules to disable executing sudo without password
            sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
            # allow wheel group using sudo with password
            sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers

            if ! [ "$WSL_INSTALL" = "true" ]; then
                # rebooting OS after reconfiguring
                sudo reboot    
            fi
EOL
        # marking helper script executable
        chmod 777 "$MOUNT_PATH"/home/kosh/postinstall.sh
}

export_wsl () {
    # unmount all mounts
    # we need this to stop grub in vm dropping in grub-shell due first run
    success "Taring rootfs and unmount partitions..."
    tar -cf ./archfs.tar -C /mnt/arch .
    warn "$(ls -l $PWD/vhd.vhdx)"
    success "ARCH root filesystem exported to $PWD/archfs.tar"
    warn "You need to export this file to WSL. Example:"
    warn "wsl --import Arch-linux D:\arch\ .\archfs.tar"
    warn "Where: wsl - wsl command in windows"
    warn "       --import Arch-linux - import wsl machine with name Arch-linux"
    warn "       D:\arch - dir where will be placed image with filsesystem"
    warn "       .\archfs.tar - path to generated tar archive with filesystem"
    error "You must enable fonts in your terminal !"
    info "See here: https://github.com/romkatv/powerlevel10k#fonts <---"
}

unmount_wsl () {
    pkill -en gpg-agent || true
    umount -l "$MOUNT_PATH" || true
    losetup -d "$DISK" || true
    echo "Done"
    trap '' EXIT
}

unmount_images () {
    pkill -en gpg-agent || true
    sync
    #fuser killer may kill wsl...
    umount -l "$MOUNT_PATH"/boot/efi || true
    umount -l "$MOUNT_PATH"/boot || true
    umount -l "$MOUNT_PATH" || true
    lvchange -an /dev/arch/root || true
    losetup -d "$DISK" || true
    echo "Done"
    trap '' EXIT
}

qemu_install () {
    if [ "$ID" = "fedora" ]; then
            dnf install -y qemu-kvm-core \
                           edk2-ovmf          
    elif [ "$ID" = "arch" ]; then
            pacman -S --needed --disable-download-timeout \
                edk2-ovmf
            if ! pacman -Qi qemu-desktop > /dev/null 2>&1 ; then
                pacman -S --needed --noconfirm --disable-download-timeout qemu-base
            fi 
    elif [ "$ID" = "debian" ]; then
            apt install -y qemu-utils \
                       qemu-system-x86 \
                       ovmf
    elif [ "$ID" = "alpine" ]; then
        apk add qemu-system-x86_64 \
                qemu-img \
                ovmf
    else
        exit 1
    fi
}

export_image_hyperv () {
    qemu-img resize -f raw ./vhd.img 15G
    qemu-img convert -p -f raw -O vhdx ./vhd.img ./vhd.vhdx
    success "VHDX image for HYPER-V created"
    info "Arch Linux does not have official support of UEFI Secure shell"
    info "You need to disable UEFI Secure in HYPER-V"
    warn "$(ls -l $PWD./vhd.vhdx)"
}

export_image_wmware () {
    qemu-img resize -f raw ./vhd.img 15G
    qemu-img convert -p -f raw -O vmdk ./vhd.img ./vhd.vmdk
    success "VMDK image for VMWARE created"
    info "VMWARE Workstation create VM without UEFI"
    info "You need enable UEFI for VM manually after create VM"
    warn "$(ls -l $PWD/vhd.vhdx)"
}

run_in_qemu () {
    if [ "$ID" = "fedora" ] || [ "$ID" = "debian" ] || [ "$ID" = "alpine" ] ; then
        OVMF_PATH=/usr/share/OVMF/OVMF_CODE.fd
    elif [ "$ID" = "arch" ]; then
        OVMF_PATH=/usr/share/edk2/x64/OVMF_CODE.fd
    else
        echo "Unknown OS"
    fi    
    qemu-system-x86_64 \
                             -enable-kvm \
                             -smp cores=4 \
                             -m 2G \
                             -drive if=pflash,format=raw,readonly=on,file="$OVMF_PATH" \
                             -device nvme,drive=drive0,serial=badbeef \
                             -drive if=none,id=drive0,file=./vhd.img &
                             success "Done"
                             exit 0
}

nspawn_install () {
   if [ "$ID" = "fedora" ]; then
       true               
   elif [ "$ID" = "arch" ]; then
       true
   elif [ "$ID" = "debian" ]; then
       apt install -y systemd-container
   elif [ "$ID" = "alpine" ]; then
       exit 1     
   else
       exit 1
   fi
}

nspawn_exec_wsl () {
    FILE_PATH=$PWD
    mkdir -p /tmp/nspawn-arch
    cd /tmp/nspawn-arch
    tar -xf "$FILE_PATH"/archfs.tar --numeric-owner
    systemd-nspawn -b -D /tmp/nspawn-arch <<-EOF
       kosh
       qwe
EOF
}

nspawn_exec_image () {
    systemd-nspawn -b -i ./vhd.img <<-EOF
        kosh
        qwe
EOF
}

main () {
    options_handler "$@"
    if [ "$WSL_INSTALL" = "true" ]; then
        prepare_dependecies
        create_image_wsl
        mount_image
        exit_trap_wsl
        format_image_wsl
        mkdir_root
        mount_root_wsl
        pacstrap_base
        chroot_arch
        postinstall_config
        export_wsl
        unmount_wsl
        if [ "$NSPAWN_CHECK" = "true" ]; then
            nspawn_install
            nspawn_exec_wsl
        fi
    else
        prepare_dependecies
        create_image
        mount_image
        exit_trap
        format_image
        mkdir_root
        mount_root
        pacstrap_base
        mount_boot
        disable_swap
        fstab_gen
        chroot_arch
        postinstall_config
        unmount_images
        if [ "$QEMU_CHECK" = "true" ]; then
            qemu_install
            run_in_qemu
        fi
        if [ "$VMWARE_EXPORT" = "true" ]; then
            qemu_install
            export_image_wmware
        fi
        if [ "$HYPERV_EXPORT" = "true" ]; then
            qemu_install
            export_image_hyperv
        fi
        if [ "$NSPAWN_CHECK" = "true" ]; then
            nspawn_install
            nspawn_exec_image
        fi
    fi
    unset WSL_INSTALL
    unset WITH_CONFIG
    unset NSPAWN_CHECK
    unset QEMU_CHECK
    unset VMWARE_EXPORT
    unset HYPERV_EXPORT
}

main "$@"
