#!/usr/bin/env bash
set -eo noglob

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

termux_install () {
    #in termux virtualenv we can`t use sudo.
    #so, we`ll download script, removing all sudo enters and re-run new script
        if [ -n "$TERMUX_VERSION" ]; then
            if [ -n "$TERMUX_PATCH" ]; then
                true
            else
                wget -O ./script.sh https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh
                sed -i 's|sudo -E ||g' ./script.sh
                sed -i 's|sudo||g' ./script.sh
                chmod 755 ./script.sh
                export TERMUX_PATCH=true
                exec ./script.sh
            fi
        fi
}

alpine_install () {
. /etc/os-release
    if [ "$ID" = "alpine" ]; then
        if [ "$ALPINE_PATCH" = "true" ]; then
            true
        else
            #getting raw script
            wget -O ./script.sh https://raw.githubusercontent.com/deathmond1987/homework/main/zsh_home_install.sh
            #ash not known about bash arrays. patching to line
            sed -i 's|APPS=( "btop" "dust" "duf" "bat" "micro" "lsd" "gdu" "fd" )||g' ./script.sh
            sed -i "s|    for apps in.*do|    for apps in btop dust duf bat micro lsd gdu fd; do|g" ./script.sh
            chmod 755 ./script.sh
            #export variable to stop cycle
            export ALPINE_PATCH=true
            #exec from ash to supress bash shebang in script
            ash ./script.sh
            exit 0
        fi
    fi
}
alpine_install

alert_root () {
#aware user about installing zsh to root
if [ "$EUID" -eq 0 ]; then
    read -rp "You want install oh-my-zsh to root user? yes(y)/no(n): " ANSWER
    case $ANSWER in
        yes|y) warn "Oh-my-zsh will be installed in $HOME"
            ;;
         no|n) warn "OK. If you want install zsh for your user - re-run this script from your user without sudo"
            ;;
            *) error "Unrecognised option"
               alert_root
            ;;
    esac
fi
}

install_git_zsh () {
    #search package manager and config it to use proxy if HTTP_PROXY is not null. after this - installing needed packages
    if command -v dnf > /dev/null ; then
        success "dnf package manager found. installing zsh..."
        if [ -n "$HTTP_PROXY" ]; then
            echo "proxy=$HTTP_PROXY" | sudo tee -a /etc/dnf/dnf.conf
        fi
        sudo dnf install git zsh -y
        sudo dnf install epel-release -y || true
    elif command -v apt > /dev/null ; then
        success "apt package manager found. installing zsh..."
        if [ -n "$HTTP_PROXY" ]; then
            echo "Acquire::http::Proxy \"http://$HTTP_PROXY\";" | sudo tee -a /etc/apt/apt.conf.d/proxy
        fi
        sudo apt install git zsh -y
    elif command -v pacman > /dev/null ; then
        success "pacman package manager found. installing zsh..."
        http_proxy="$HTTP_PROXY"
        sudo pacman -S --noconfirm git zsh
    elif command -v zypper > /dev/null ; then
        success "zypper package manager found. installing zsh..."
        sudo zypper install -y git zsh
    elif command -v apk > /dev/null ; then
        success "apk package manager found. installing zsh..."
        if [ -n "$HTTP_PROXY" ]; then
            http_proxy=http://"$HTTP_PROXY"
            https_proxy=http://"$HTTP_PROXY"
        fi    
        sudo -E apk add git zsh
    else
        error "Package manager not known"
        exit 1
    fi
    success "Dependencies of oh-my-zsh installed"
}

config_proxy_oh_my_zsh () {
    #if HTTP_PROXY is not null we must config git to use proxy and then install oh-my-zsh
    if [ -n "$HTTP_PROXY" ]; then
        warn "HTTP_PROXY found. Configuring proxy for git"
        #config git with proxy
        git config --global http.proxy http://"$HTTP_PROXY"
        git config --global http.proxyAuthMethod 'basic'
        git config --global http.sslVerify false
        #get oh-my-zsh
        warn "Installing oh-my-zsh"
        sh -c "$(curl -fsSL -x "$HTTP_PROXY" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        #since we in proxy default install of gitstatusd not working. disable download
        echo "POWERLEVEL9K_DISABLE_GITSTATUS=true" >> ~/.zshrc
        success "Done"
    else
        warn "Installing oh-my-zsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        success "Done"
    fi
}

install_plugins () {
    warn "Installing and enabling plugins (autosuggestions, syntax-highlighting)"
    #get zsh syntax highlightning plugin
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    #get zsh autosuggections plugin
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    #enabling plugins in .zshrc config file
    sed -i 's/plugins=(git)/plugins=(docker docker-compose systemd git zsh-autosuggestions zsh-syntax-highlighting sudo)/g' $HOME/.zshrc
    success "Done"
}

install_powerlevel () {
    warn "Installing powerlevel10k theme for zsh"
    #get powerlevel10k theme for zsh
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    #enable powerlevel10k theme in zsh config
    sed -i 's:ZSH_THEME="robbyrussell":ZSH_THEME="powerlevel10k/powerlevel10k":g' "$HOME"/.zshrc
    success "Done"
}

fix_zsh_docker () {
    warn "fix docker exec -it autocomplete"
    info "by default zsh completions for docker not working after inputting arguments. so, docker exec -ti not shows container names. fixing"
    #enabling stacking options for docker suggections. need to docker -it working with autosuggections
    echo -e "zstyle ':completion:*:*:docker:*' option-stacking yes\nzstyle ':completion:*:*:docker-*:*' option-stacking yes" >> "$HOME"/.zshrc
    success "Done"
}

config_font() {
    #clear screen to delimint install information and important information
    clear
    #this need do manually, so asking for that
    info "Default shell now will change to zsh."
    error "IMPORTANT:"
    info "You must enable fonts in your terminal"
    info "See here: https://github.com/romkatv/powerlevel10k <---
    
    "
    sleep 5
}

change_shell () {
    #changing default shell
    warn "Changing default shell"
    if [ ! -z "$TERMUX_VERSION" ]; then
            chsh -s $(command -v zsh)
    else
        SUDO_USER=$(whoami)
        export SUDO_USER
        sudo -E usermod -s $(command -v zsh) "$SUDO_USER"
    fi
    success "Done"
}

linux_2023 () { 
#now we trying to install additional modern unix programs
APPS=( "btop" "dust" "duf" "bat" "micro" "lsd" "gdu" "fd" )
    warn "Installing modern apps"
    for apps in "${APPS[@]}"; do
        INSTALL=failed
        if command -v dnf > /dev/null ; then
            dnf install "$apps" -y >/dev/null 2>&1 && success "$apps found and installed" && INSTALL=true || true 
        elif command -v apt-get > /dev/null ; then
            apt-get install "$apps" -y >/dev/null 2>&1 && success "$apps found and installed" && INSTALL=true || true
        elif command -v pacman > /dev/null ; then
            echo y | LANG=C yay -S \
            --noprovides \
            --answerdiff None \
            --answerclean None \
            --mflags "--noconfirm" "$apps" >/dev/null 2>&1 && success "$apps found and installed" && INSTALL=true || true
        elif command -v zypper > /dev/null ; then
            zypper install -y "$apps" >/dev/null 2>&1 && success "$apps found and installed" && INSTALL=true || true 
        elif command -v apk > /dev/null ; then
            apk add "$apps" >/dev/null 2>&1 && success "$apps found and installed" && INSTALL=true || true
        else
            error "Package manager not known"
            exit 1
        fi
        #if program not found in default repo - than we can at least give link to program github homepages
        if [ "$INSTALL" = "failed" ]; then
            error "$apps not found in repo"
            if [ "$apps" = "btop" ]; then
                info "Install $apps manually from https://github.com/aristocratos/btop/releases"
            elif [ "$apps" = "dust" ]; then 
                info "Install $apps manually from https://github.com/bootandy/dust/releases"
            elif [ "$apps" = "duf" ]; then 
                info "Install $apps manually from https://github.com/muesli/duf/releases"
            elif [ "$apps" = "bat" ]; then 
                info "Install $apps manually from https://github.com/sharkdp/bat/releases"
            elif [ "$apps" = "micro" ]; then 
                info "Install $apps manually from https://github.com/zyedidia/micro/releases"
            elif [ "$apps" = "lsd" ]; then 
                info "Install $apps manually from https://github.com/lsd-rs/lsd/releases"
            elif [ "$apps" = "gdu" ]; then 
                info "Install $apps manually from https://github.com/dundee/gdu/releases"
            fi
        fi
    done

    #create aliases to links new programs to defaults
    echo -e 'alias htop="btop"
    alias du="dust"
    alias df="duf"
    alias cat="bat -pp -P"
    alias nano="micro"
    alias ls="lsd"
    alias ncdu="gdu"' >> "$HOME"/.zshrc
}

drop_proxy_config_git () {
    #cleanup git config if HTTP_PROXY was configured
    if [ -n "$HTTP_PROXY" ]; then
        warn "Removeing git proxy config"
        git config --global --unset http.proxy || true
        git config --global --unset http.proxyAuthMethod || true
        git config --global --unset http.sslVerify || true
        success "Done"
    fi
}

drop_proxy_pkg_manager_conf () {
if [ -n "$HTTP_PROXY" ]; then
    warn "Removing package manager proxy config"
    if command -v dnf > /dev/null ; then
        sudo sed -i "s/proxy=$HTTP_PROXY//g" tee -a /etc/dnf/dnf.conf
    elif command -v apt-get > /dev/null ; then
        sudo rm /etc/apt/apt.conf.d/proxy
    elif command -v pacman > /dev/null ; then
        true
    elif command -v zypper > /dev/null ; then
        true
    elif command -v apk > /dev/null ; then
        true
    else
        error "Package manager not known"
        exit 1
    fi
    success "Done"
fi
}

on_exit () {
    echo ""
    warn "In next login to shell you need to answer few questions to configure powerlevel10k theme."
    warn "But before that you must configure your terminal fonts."
    success "Installing complete!"
}

main () {
    termux_install
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
    drop_proxy_pkg_manager_conf
    on_exit
}

main "$@"
