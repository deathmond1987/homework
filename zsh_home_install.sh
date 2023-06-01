#!/usr/bin/env bash
set -xe

dnf install git zsh -y
    if [ -z "$PROXY" ]; then
        #get oh-my-zsh
        sh -c "$(curl -fsSL -x http://$PROXY https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        #config git with proxy
        git config --global http.proxy http://"$PROXY"
        git config --global http.proxyAuthMethod 'basic' 
        git config --global http.sslVerify false
    fi
#get oh-my zsh without proxy
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
#get zsh syntax highlightning plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
#get zsh autosuggections plugin
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
#enabling plugins in .zshrc config file
sed -i 's/plugins=(git)/plugins=(docker docker-compose systemd git zsh-autosuggestions zsh-syntax-highlighting sudo)/g' $HOME/.zshrc
#enabling stacking options for docker suggections. need to docker -it working with autosuggections
echo -e "zstyle ':completion:*:*:docker:*' option-stacking yes\nzstyle ':completion:*:*:docker-*:*' option-stacking yes" >> .zshrc
#get powerlevel10k theme for zsh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
#enable powerlevel10k theme in zsh config
sed -i 's:ZSH_THEME="robbyrussell":ZSH_THEME="powerlevel10k/powerlevel10k":g' $HOME/.zshrc
#this need do manually, so asking for that
echo -e "You must enable fonts in your terminal\nSee here: https://github.com/romkatv/powerlevel10k"
#changing default shell
chsh -s /bin/zsh
#links to new programs
echo "You need manually install:
https://github.com/sharkdp/bat/releases
https://github.com/lsd-rs/lsd/releases
https://github.com/bootandy/dust/releases
https://github.com/muesli/duf/releases
https://github.com/aristocratos/btop/releases
https://github.com/dundee/gdu"
  
#create aliases to links new programs to defaults
echo -e 'alias yay="sudo dnf update"
alias htop="btop"
alias du="dust"
alias df="duf"
alias cat="bat -pp -P"
alias nano="micro"
alias ls="lsd"
alias ncdu="gdu"' >> .zshrc    
