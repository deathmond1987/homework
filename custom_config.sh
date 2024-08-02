#!/usr/bin/env bash
set -euo pipefail

. /etc/environment

USER_NAME=${USER_NAME:-kosh}
user_packages='docker docker-compose dive mc pigz docker-buildx polkit strace pacman-contrib pacman-cleanup-hook ccache qemu-base bc net-tools cpio etc-update'
yay_opts='--answerdiff None --answerclean None --noconfirm --needed'

if [ "$WSL_INSTALL" = "true" ]; then
    echo "Configuring wsl..."
    echo "[boot]
systemd=true
[user]
default=$USER_NAME
[automount]
enabled = true
options = \"metadata\"
mountFsTab = true
[interop]
appendWindowsPath = false
autoMemoryReclaim=gradual
networkingMode=mirrored
dnsTunneling=true" > /etc/wsl.conf
    rm -f /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
    rm -f /usr/lib/systemd/system/systemd-firstboot.service
    echo "" > /etc/fstab
    # fix cgroup2 not mounted for docker
    echo "cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime,nsdelegate 0 0" > /etc/fstab
    # fix mount x socket in wsl
    echo '[Unit]
Description=remount xsocket for wslg
After=network.target

[Service]
Type=simple
ExecStartPre=+/bin/bash -c "if [ -d /mnt/wslg/.X11-unix ]; then [ -d /tmp/.X11-unix ] && rm -rf /tmp/.X11-unix || true; fi"
ExecStart=/usr/sbin/ln -s /mnt/wslg/.X11-unix /tmp/
Restart=on-abort

[Install]
WantedBy=multi-user.target' >> /etc/systemd/system/wslg-tmp.service
    systemctl daemon-reload
    systemctl enable wslg-tmp.service
else
    # changing grub config
    # sed -i 's/GRUB_TIMEOUT_STYLE=menu/GRUB_TIMEOUT_STYLE=countdown/g' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/g' /etc/default/grub
fi 

# PACMAN CONF
# enabling pacman from game
sed -i '/^\[options.*/a ILoveCandy' /etc/pacman.conf
# enabling parallel downloads in pacman
sed -i '/ParallelDownloads = 5/s/^#//g' /etc/pacman.conf
# enabling colors in pacman output
sed -i '/Color/s/^#//g' /etc/pacman.conf

# MAKEPKG CONF
# Optimizing build config
sed -i 's/COMPRESSZST=(zstd -c -z -q -)/COMPRESSZST=(zstd -c -z -q --threads=0 -)/g' /etc/makepkg.conf
# disable build debug package 
sed -i 's/OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge debug lto)/OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)/g' /etc/makepkg.conf
# installing packages 
su - "$USER_NAME" -c "LANG=C yay -S $yay_opts $user_packages"
if [[ $user_packages == *docker* ]]; then
    # админу локалхоста дозволено:)
    echo "adding user to docker group"    
    usermod -aG docker $USER_NAME
fi
# enabling ccache
if [[ $user_packages == *ccache* ]]; then
    echo "adding ccache config for makepkg"
    sed -i 's/BUILDENV=(!distcc color check !sign)/BUILDENV=(!distcc color ccache check !debug !sign)/g' /etc/makepkg.conf
fi 

# adding zsh
su - "$USER_NAME" -c "wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh | bash"
if [[ $user_packages == *mc* ]]; then       
    # changing default mc theme
    echo "adding mc config"
    echo "MC_SKIN=gotar" >> /etc/environment
    echo "MC_SKIN=gotar" >> /home/"$USER_NAME"/.zshrc
fi
# enabling hstr alias
echo "export HISTFILE=~/.zsh_history" >> /home/"$USER_NAME"/.zshrc
# workaround slow mc start. long time to create subshell for mc. we will load mc from bash
echo 'alias mc="SHELL=/bin/bash /usr/bin/mc; zsh"' >> /home/"$USER_NAME"/.zshrc
# habit
#echo 'alias netstat="ss"' >> /home/kosh/.zshrc
       
# downloading tor fork for docker
cd /opt
git clone https://github.com/deathmond1987/tor_with_bridges.git
mv ./tor_with_bridges ./tor
cd -

cd /home/"$USER_NAME"/
mkdir -p ./.git
GH_USER=${GH_USER:=deathmond1987}
PROJECT_LIST=$(curl -s https://api.github.com/users/"$GH_USER"/repos\?page\=1\&per_page\=100 | grep -e 'clone_url' | cut -d \" -f 4 | sed '/WSA/d' | xargs -L1)
for project in ${PROJECT_LIST}; do
    project_name=$(echo "${project}" | cut -d'/' -f 5)
    echo "[ $project_name ] start..."
    if [ -d ./"${project_name//.git/}" ]; then
        cd ./"${project_name//.git/}"
        git pull
        cd - &>/dev/null
    else
        git clone "${project}"
    fi
    echo "[ $project_name ] done."
done

# enabling units
systemctl enable docker.service
systemctl enable sshd.service
