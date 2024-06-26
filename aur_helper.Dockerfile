FROM archlinux:latest

# define options
ENV USER=build \
    SCRIPT=/usr/bin/run
# install base packages
RUN <<EOF
    pacman-key --init
    pacman-key --populate
    pacman -Syu --noconfirm --needed base base-devel git
    rm -rf /var/cache/pacman/pkg/*
EOF

# disable passwd, set locale, add user for work
RUN <<EOF
    sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
    locale-gen
    echo -e 'LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8' > /etc/locale.conf
    useradd -m -G wheel -s /bin/bash "$USER"
EOF

# install yay from aur
USER $USER
WORKDIR /home/"$USER"
RUN <<EOF
    git clone https://aur.archlinux.org/yay-bin
    cd yay-bin
    yes | makepkg -si
    cd ..
    rm -rf yay-bin
    yay -Y --gendb
    yes | yay -Syu --devel
    yay -Y --devel --save
    yay --editmenu --diffmenu=false --save
EOF

# set options
USER root
ENV PKGDEST=/out
RUN <<EOF
    sed -i '/ParallelDownloads = 5/s/^#//g' /etc/pacman.conf
    sed -i '/Color/s/^#//g' /etc/pacman.conf
    sed -i "s:^#PKGDEST=/home/packages:PKGDEST=$PKGDEST:g" /etc/makepkg.conf
    sed -i 's:#MAKEFLAGS="-j2":MAKEFLAGS="-j$(nproc)":g' /etc/makepkg.conf
EOF
RUN mkdir -p "$PKGDEST" && chown "$USER":"$USER" "$PKGDEST"

# gen help file
COPY <<EOF /man

error: nothing to build!

   Usage:
       docker run -v ./out:"$PKGDEST" container_name conky
       docker run -v ./out:"$PKGDEST" container_name zsh conky -d -s

   Options:
       -d - download all package deps to $PKGDEST dir
       -s - disable package signature check

   package will store in "$PKGDEST" dir

EOF

# gen entrypoint script
COPY <<'EOF' $SCRIPT
#!/usr/bin/env bash
set -eo pipefail

#colors
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

# if param not found - then show help and exit
if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cat /man
    exit 1
fi


# shoutout to Limp Bizkit
info "arch is rolling distributive. Upgrading..."
su - "$USER" -c "yay -Syua --noconfirm"
success "upgrade complete"

# filter param from package list
# if params found - do changes
for arg in "$@"; do
    if [[ "$arg" == "--with-deps" ]] || [[ "$arg" == "-d" ]]; then
        # change package cache dir
        sed -i "/CacheDir/c CacheDir = $PKGDEST" /etc/pacman.conf
        warn "With deps flag enabled. Pacman cache will stored in $PKGDEST inside container"
    elif [[ "$arg" == "--ignore-sign" ]] || [[ "$arg" == "-s" ]]; then
        # change signature level
        sed -i "/SigLevel    = Required DatabaseOptional/c SigLevel = Never" /etc/pacman.conf
        warn "pacman will ignore package signatures"
    else
        # add package names to array
        packages+=($arg)
    fi
done
# aray to string
pack="${packages[@]}"
echo ""
warn "Searching for packages: $pack"
# we need to change output dir owher to work user
# makepkg work from user
mkdir -p $PKGDEST
chown "$USER":"$USER" -R "$PKGDEST"
# exec yay
su - "$USER" -c "yay -Syu --noconfirm $pack"
success "Done. Exit from container"
echo ""
EOF
RUN chmod 777 "$SCRIPT"

ENTRYPOINT [ "/usr/bin/run" ]
