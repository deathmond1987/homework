#!/usr/bin/env bash
set -o noglob

reset=$(tput sgr0)

red=$(tput setaf 1)
green=$(tput setaf 2)
white=$(tput setaf 7)
tan=$(tput setaf 3)

info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}

set -e

alert_root () {
if [ "$EUID" -eq 0 ]; then
    read -rp "You want install oh-my-zsh to root user? yes(y)/no(n): " ANSWER
    case $ANSWER in
        yes|y) echo "Oh-my-zsh will be installed in $HOME"
            ;;
         no|n) echo "OK. Exiting"
            ;;
            *) echo "Unrecognised option"
               alert_root
            ;;
    esac
fi
}

install_git_zsh () {
    if command -v dnf > /dev/null ; then
        sudo dnf install git zsh ncurses -y
    elif command -v apt-get > /dev/null ; then
        sudo apt-get install git zsh -y
    elif command -v pacman > /dev/null ; then
        sudo pacman -S --noconfirm git zsh
    elif command -v zypper > /dev/null ; then
        sudo zypper install -y git zsh
    else
        echo "Package manager not found"
        exit 1
    fi
}

config_proxy_oh_my_zsh () {
    if [ -n "$HTTP_PROXY" ]; then
        #config git with proxy
        git config --global http.proxy http://"$HTTP_PROXY"
        git config --global http.proxyAuthMethod 'basic'
        git config --global http.sslVerify false
        #get oh-my-zsh
        sh -c "$(curl -fsSL -x "$HTTP_PROXY" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        #since we in proxy default install of gitstatusd not working. disable download
        echo "POWERLEVEL9K_DISABLE_GITSTATUS=true" >> ~/.zshrc
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
}

install_plugins () {
    #get zsh syntax highlightning plugin
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    #get zsh autosuggections plugin
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    #enabling plugins in .zshrc config file
    sed -i 's/plugins=(git)/plugins=(docker docker-compose systemd git zsh-autosuggestions zsh-syntax-highlighting sudo)/g' $HOME/.zshrc
}

install_powerlevel () {
    #get powerlevel10k theme for zsh
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    #enable powerlevel10k theme in zsh config
    sed -i 's:ZSH_THEME="robbyrussell":ZSH_THEME="powerlevel10k/powerlevel10k":g' $HOME/.zshrc
}

fix_zsh_docker () {
    #enabling stacking options for docker suggections. need to docker -it working with autosuggections
    echo -e "zstyle ':completion:*:*:docker:*' option-stacking yes\nzstyle ':completion:*:*:docker-*:*' option-stacking yes" >> $HOME/.zshrc
}

config_font() {
    #clear screen to delimint install information and important information
    clear
    #this need do manually, so asking for that
    info "Default shell now will change to zsh."
    error "IMPORTANT:"
    info "You must enable fonts in your terminal"
    info "See here: https://github.com/romkatv/powerlevel10k <---"
}

change_shell () {
    #changing default shell
    SUDO_USER=$(whoami)
    export SUDO_USER
    sudo -E usermod -s /usr/bin/zsh "$SUDO_USER"
}

linux_2023 () {
    #links to new programs
APPS=btop dust duf bat micro lsd gdu
for apps in "${APPS[@]}"; do
    if command -v dnf > /dev/null ; then
        sudo dnf install "$apps" -y && echo -e "$apps found and installed" || true
    elif command -v apt-get > /dev/null ; then
        sudo apt-get install "$apps" -y && echo -e "$apps found and installed" || true
    elif command -v pacman > /dev/null ; then
        sudo pacman -S --noconfirm "$apps" && echo -e "$apps found and installed" || true
    elif command -v zypper > /dev/null ; then
        sudo zypper install -y "$apps" && echo -e "$apps found and installed" || true
    else
        echo "Package manager not found"
        exit 1
    fi
    
    info "    
    You need manually install:
    https://github.com/sharkdp/bat/releases
    https://github.com/lsd-rs/lsd/releases
    https://github.com/bootandy/dust/releases
    https://github.com/muesli/duf/releases
    https://github.com/aristocratos/btop/releases
    https://github.com/dundee/gdu/releases
    "
    
    
    #create aliases to links new programs to defaults
    echo -e 'alias yay="sudo dnf update"
    alias htop="btop"
    alias du="dust"
    alias df="duf"
    alias cat="bat -pp -P"
    alias nano="micro"
    alias ls="lsd"
    alias ncdu="gdu"' >> $HOME/.zshrc
}

drop_proxy_config_git () {
    git config --global --unset http.proxy || true
    git config --global --unset http.proxyAuthMethod || true
    git config --global --unset http.sslVerify || true
}

main () {
    alert_root
    install_git_zsh
    drop_proxy_config_git
    config_proxy_oh_my_zsh
    install_plugins
    install_powerlevel
    fix_zsh_docker
    config_font
    change_shell
    linux_2023
    drop_proxy_config_git
}

main "$@"
