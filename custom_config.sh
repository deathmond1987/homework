#!/usr/bin/env bash
set -xe 

. /etc/environment
if [ "$WSL_INSTALL" = "true" ]; then
    echo "Configuring wsl..."
    echo "[boot]
systemd=true
[user]
default=kosh
[automount]
enabled = true
options = \"metadata\"
mountFsTab = true" > "$MOUNT_PATH"/etc/wsl.conf
    #Under wsl thereis issue in memory cache. We will drop memory caches with systemd unit every 3 minute
    echo -e "[Unit]
Description=Periodically drop caches to save memory under WSL.
Documentation=https://github.com/arkane-systems/wsl-drop-caches
ConditionVirtualization=wsl
Requires=drop_cache.timer

[Service]
Type=oneshot
ExecStartPre=sync
ExecStart=echo 3 > /proc/sys/vm/drop_caches" > "$MOUNT_PATH"/etc/systemd/system/drop_cache.service

    echo -e "[Unit]
Description=Periodically drop caches to save memory under WSL.
Documentation=https://github.com/arkane-systems/wsl-drop-caches
ConditionVirtualization=wsl
PartOf=drop_cache.service

[Timer]
OnBootSec=3min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target" > "$MOUNT_PATH"/etc/systemd/system/drop_cache.timer

    systemctl enable drop_cache.timer
    systemctl disable systemd-networkd-wait-online

# not work in wsl with default user in wsl.conf
echo "MC_SKIN=gotar" >> /home/kosh/.zshrc
else
# changing grub config
    sed -i 's/GRUB_TIMEOUT_STYLE=menu/GRUB_TIMEOUT_STYLE=countdown/g' /etc/default/grub
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
sed -i 's/BUILDENV=(!distcc color check !sign)/BUILDENV=(!distcc color ccache check !sign)/g' /etc/makepkg.conf

# installing packages 
su - kosh -c "LANG=C yay -S \
                         --noprovides \
                         --answerdiff None \
                         --answerclean None \
                         --mflags \" --noconfirm\" \
                                                    docker \
                                                    docker-compose \
                                                    dive \
                                                    mc \
                                                    pigz \
                                                    docker-buildx \
                                                    polkit \
                                                    strace \
                                                    pacman-contrib \
                                                    pacman-cleanup-hook \
                                                    find-the-command \
                                                    hstr-git \
                                                    ccache \
                                                    qemu-base \
                                                    --noconfirm"
# админу локалхоста дозволено:)
usermod -aG docker kosh

# adding zsh
su - kosh -c "wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh | bash"
        
# changing default mc theme
echo "MC_SKIN=gotar" >> /etc/environment

# enabling hstr alias
echo "export HISTFILE=~/.zsh_history" >> /home/kosh/.zshrc
echo 'alias history="hstr"' >> /home/kosh/.zshrc
# workaround slow mc start. long time to create subshell for mc. we will load mc from bash
echo 'alias mc="SHELL=/bin/bash /usr/bin/mc; zsh"' >> /home/kosh/.zshrc
# habit
echo 'alias netstat="ss"' >> /home/kosh/.zshrc
        
# downloading tor fork for docker
mkdir -p /opt/tor
wget -O /opt/tor/docker-compose.yml https://raw.githubusercontent.com/deathmond1987/docker-tor/main/docker-compose.yml

# enabling units
systemctl enable docker.service
systemctl enable sshd.service

# changing sudo rules to disable executing sudo without password
sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
# allow wheel group using sudo with password
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
