        # enabling pacman from game
        sed -i '/^\[options.*/a ILoveCandy' /etc/pacman.conf
        #enabling parallel downloads in pacman
        sed -i '/ParallelDownloads = 5/s/^#//g' /etc/pacman.conf
        #enabling colors in pacman output
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
