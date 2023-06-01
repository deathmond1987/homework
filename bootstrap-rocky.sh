#!/usr/bin/env bash
set -e
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

questions (){
    echo -e "Proxy. Confugure default proxy (10.38.20.253:3128), no proxy or custom proxy with IP:PORT"
    read -rp " Answer (default/d, no/n, ip:port ): " ANSWER
    case $ANSWER in
        no|n)
            ;;
        default|d)
             PROXY="10.38.20.253:3128"
            ;;
        *)
             PROXY=$ANSWER
            ;;
    esac
    unset ANSWER

    if [ -n "$PROXY" ]; then
        read -rp "Add permanent proxy config to system variables? (yes/y, no/n): " ANSWER
        case $ANSWER in
            yes|y) ADD_SYSTEM_PROXY=true
                ;;
             no|n) ADD_SYSTEM_PROXY=false
                ;;
              *) error "incorrect option"
                 exit 1
                ;;
        esac
        unset ANSWER
    fi

    read -rp "Install docker? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) DOCKER_INSTALL=true
             if [ -n "$PROXY" ]; then
                 read -rp "add current proxy config to docker? (yes/y, no/n): " ANSWER
                 case $ANSWER in
                     yes|y) DOCKER_PROXY_CONFIG=true
                         ;;
                      no|n) DOCKER_PROXY_CONFIG=false
                         ;;
                       *) error "incorrect option"
                         exit 1
                         ;;
                 esac
                 unset ANSWER
             fi
            ;;
        *)
            ;;
    esac
    unset ANSWER

    read -rp "Install gitlab-runner? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) RUNNER_INSTALL=true
            ;;
         no|n) RUNNER_INSTALL=false
            ;;
          *) error "incorrect option"
             exit 1
             ;;
    esac
    unset ANSWER

    read -rp "Install postgresql? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) POSTGRESQL_INSTALL=true
             read -rp "Postgresql version? (11 12 13 14 15): " POSTGRESQL_VERSION
            ;;
         no|n) POSTGRESQL_INSTALL=false
            ;;
          *) error "incorrect option"
             exit 1
            ;;
    esac
    unset ANSWER

    read -rp "Install netdata? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) NETDATA_INSTALL=true
            ;;
          no|n) NETDATA_INSTALL=false
            ;;
          *) error "incorrect option"
             exit 1
            ;;
    esac
    unset ANSWER

    read -rp "Remove proxy config from /etc/dnf/dnf.conf? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) REMOVE_DNF_PROXY=true
            ;;
         no|n) REMOVE_DNF_PROXY=false
            ;;
          *) error "incorrect option"
             exit 1
            ;;
    esac
    unset ANSWER

}

export_proxy () {
    export http_proxy="$PROXY"
    export https_proxy="$PROXY"
    export HTTP_PROXY="$PROXY"
    export HTTPS_PROXY="$PROXY"
    export NO_PROXY=localhost
    echo "proxy=http://$PROXY/" >> /etc/dnf/dnf.conf
}

add_system_proxy () {
    PROXY_FILE=/etc/profile.d/ksb_proxy.sh
    echo -e "export http_proxy=$PROXY\nexport https_proxy=$PROXY\nexport HTTP_PROXY=$PROXY\nexport HTTPS_PROXY=$PROXY\nexport NO_PROXY=localhost" > "$PROXY_FILE"
    chmod 644 "$PROXY_FILE"
    success "Proxy settings added to /etc/profile.d/ksb_proxy.sh"
}

dnf_install_default () {
    dnf update -y && dnf install epel-release -y 
    dnf install mc htop telnet nano wget curl traceroute strace ncdu net-tools bind-utils bash-completion -y 
#    systemctl enable --now systemd-timesyncd.service
    success "bash-completion mc telnet htop nano wget curl traceroute strace ncdu net-tools bind-utils installed"
}

install_vmtools () {
VIRT=$(systemd-detect-virt)
if [ "$VIRT" = "vmware" ]; then
    warn "vmware virt detected. Installing guest tools..."
    dnf install open-vm-tools -y 
    systemctl enable --now vmtoolsd
elif [ "$VIRT" = "microsoft" ]; then
    warn "microsoft virt detected. Installing guest tools..."
    dnf install hyperv-daemons -y 
    #systemctl start hypervkvpd hypervvssd
else true
fi
}

dnf_install_docker () {
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
    dnf install docker-ce docker-ce-cli docker-compose-plugin -y 
    systemctl enable --now docker 
    #systemctl status docker
    mkdir -p /opt/docker
    success "Docker installed"
}
docker_proxy_config () {
    mkdir -p /etc/systemd/system/docker.service.d
    echo -e "[Service]\nEnvironment=\"HTTP_PROXY=$PROXY\"\nEnvironment=\"HTTPS_PROXY=$PROXY\"\nEnvironment=\"NO_PROXY=localhost\"" > /etc/systemd/system/docker.service.d/http-proxy.conf
    systemctl daemon-reload
    systemctl restart docker
    success "Proxy config added to docker"
}

install_runner () {
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | bash 
    dnf install gitlab-runner -y 
    success "Gitlab-runner installed"
}

install_postgresql () {
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm 
    dnf -qy module disable postgresql
    dnf install -y postgresql"$POSTGRESQL_VERSION"-server 
    /usr/pgsql-"$POSTGRESQL_VERSION"/bin/postgresql-"$POSTGRESQL_VERSION"-setup initdb 
    systemctl enable --now postgresql-"$POSTGRESQL_VERSION"
}

install_netdata () {
    echo -e "Installing netdata..."
    wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh && sh /tmp/netdata-kickstart.sh --disable-telemetry --non-interactive --stable-channel> /dev/null
    firewall-cmd --permanent --add-port=19999/tcp
    firewall-cmd --reload
    success "Netdata installed"
}

dnf_remove_proxy () {
    sed -i "/^proxy*/d" /etc/dnf/dnf.conf
    success "Proxy config removed from /etc/dnf/dnf.conf"
}

adding_user () {
    useradd "$USER_NAME" || true
    echo -e "$USER_NAME:$PASSWORD" chpasswd
    usermod -aG wheel "$USER_NAME"
    success "User $USER_NAME added"
}

main () {
    questions
    if [ -n "$PROXY" ]; then
        export_proxy
        if [ "$ADD_SYSTEM_PROXY" = "true" ]; then
            add_system_proxy
        fi
    fi

    dnf_install_default
    install_vmtools

    if [ "$DOCKER_INSTALL" = "true" ]; then
        dnf_install_docker
        if [ "$DOCKER_PROXY_CONFIG" = "true" ]; then
            docker_proxy_config
        fi
    fi
    if [ "$RUNNER_INSTALL" = "true" ]; then
        install_runner
    fi
    if [ "$POSTGRESQL_INSTALL" = "true" ]; then
        install_postgresql
    fi
    if [ "$NETDATA_INSTALL" = "true" ]; then
        install_netdata
    fi
    if [ "$REMOVE_DNF_PROXY" = "true" ]; then
        dnf_remove_proxy
    fi

}

main "$@"
