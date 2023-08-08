#!/usr/bin/env bash
set -xe 

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
                                                    --noconfirm"
# админу локалхоста дозволено:)
usermod -aG docker kosh

# adding zsh
su - kosh -c "wget -qO - https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh | bash"

# enabling pacman from game
sed -i '/^\[options.*/a ILoveCandy' /etc/pacman.conf
# enabling parallel downloads in pacman
sed -i '/ParallelDownloads = 5/s/^#//g' /etc/pacman.conf
# enabling colors in pacman output
sed -i '/Color/s/^#//g' /etc/pacman.conf
        
# changing default mc theme
echo "MC_SKIN=gotar" >> /etc/environment
        
# enabling hstr alias
echo "export HISTFILE=~/.zsh_history" >> /home/kosh/.zshrc
echo 'alias history="hstr"' >> /home/kosh/.zshrc

# changing grub config
sed -i 's/GRUB_TIMEOUT_STYLE=menu/GRUB_TIMEOUT_STYLE=countdown/g' /etc/default/grub
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/g' /etc/default/grub
        
# downloading tor fork for docker
mkdir -p /opt/tor
wget -O /opt/tor/docker-compose.yml https://raw.githubusercontent.com/deathmond1987/docker-tor/main/docker-compose.yml

# workaround slow mc start. long time to create subshell for mc. we will load mc from bash
echo 'alias mc="SHELL=/bin/bash /usr/bin/mc"' >> /home/kosh/.zshrc
