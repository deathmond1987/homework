#!/usr/bin/env bash
set -xe 

. /etc/environment

user_packages='docker docker-compose dive mc pigz docker-buildx polkit strace pacman-contrib pacman-cleanup-hook ccache qemu-base bc net-tools cpio'
yay_opts='--answerdiff None --answerclean None --noconfirm'

if [ "$WSL_INSTALL" = "true" ]; then
    echo "Configuring wsl..."
    echo "[boot]
systemd=true
[user]
default=kosh
[automount]
enabled = true
options = \"metadata\"
mountFsTab = true
[interop]
appendWindowsPath = false
autoMemoryReclaim=gradual
networkingMode=mirrored
dnsTunneling=true" > /etc/wsl.conf

    #########################################
    # deprecated. autoMemoryReclaim=gradual #
    #########################################
    #Under wsl thereis issue in memory cache. We will drop memory caches with systemd unit every 3 minute
#    echo -e "[Unit]
#Description=Periodically drop caches to save memory under WSL.
#Documentation=https://github.com/arkane-systems/wsl-drop-caches
#ConditionVirtualization=wsl
#Requires=drop_cache.timer
#
#[Service]
#Type=oneshot
#ExecStartPre=sync
#ExecStart=echo 3 > /proc/sys/vm/drop_caches" > /etc/systemd/system/drop_cache.service
#
#    echo -e "[Unit]
#Description=Periodically drop caches to save memory under WSL.
#Documentation=https://github.com/arkane-systems/wsl-drop-caches
#ConditionVirtualization=wsl
#PartOf=drop_cache.service
#
#[Timer]
#OnBootSec=3min
#OnUnitActiveSec=3min
#
#[Install]
#WantedBy=timers.target" > /etc/systemd/system/drop_cache.timer
#
#    systemctl enable drop_cache.timer
    rm -f /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
    rm -f /usr/lib/systemd/system/systemd-firstboot.service
    echo "" > /etc/fstab
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
# enabling ccache
if [[ $user_packages == *ccache* ]]; then
    echo "adding ccache config for makepkg"
    sed -i 's/BUILDENV=(!distcc color check !sign)/BUILDENV=(!distcc color ccache check !sign)/g' /etc/makepkg.conf
fi 
# installing packages 
su - kosh -c "LANG=C yay -S $yay_opts $user_packages"
if [[ $user_packages == *docker* ]]; then
    # админу локалхоста дозволено:)
    echo "adding user to docker group"    
    usermod -aG docker kosh
fi

# adding zsh
su - kosh -c "wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh | bash"
if [[ $user_packages == *mc* ]]; then       
    # changing default mc theme
    echo "adding mc config"
    echo "MC_SKIN=gotar" >> /etc/environment
    echo "MC_SKIN=gotar" >> /home/kosh/.zshrc
fi
# enabling hstr alias
echo "export HISTFILE=~/.zsh_history" >> /home/kosh/.zshrc
# workaround slow mc start. long time to create subshell for mc. we will load mc from bash
echo 'alias mc="SHELL=/bin/bash /usr/bin/mc; zsh"' >> /home/kosh/.zshrc
# habit
#echo 'alias netstat="ss"' >> /home/kosh/.zshrc

if [ "$WSL_INSTALL" = "true" ]; then
    # fix cgroup2 not mounted for docker
    echo "cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime,nsdelegate 0 0" > /etc/fstab
    systemctl enable sshd.service
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
fi
        
# downloading tor fork for docker
mkdir -p /opt/tor
wget -qO /opt/tor/docker-compose.yml https://raw.githubusercontent.com/deathmond1987/docker-tor/main/docker-compose.yml

# enabling units
systemctl enable docker.service
