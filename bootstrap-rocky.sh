#!/usr/bin/env bash
set -e
set -o noglob

reset=$(tput sgr0)

#colors
red=$(tput setaf 1)
green=$(tput setaf 2)
white=$(tput setaf 7)
tan=$(tput setaf 3)

#set output functions
info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}

check_dnf () {
    if ! command -v dnf &> /dev/null ; then
        error "DNF not found. This script for DNF based distros only"
        exit 1
    else 
        success "DNF found. Continue..."
    fi
    }

questions () {
    #asking questions. store answers in variables
    echo -e "Proxy. Confugure default proxy (10.38.22.253:3128), no proxy or custom proxy with IP:PORT"
    read -rp " Answer (default/d, no/n, ip:port ): " ANSWER
    case $ANSWER in
        no|n)
            ;;
        default|d)
             PROXY="10.38.22.253:3128"
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
    #well, there is some shit
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
    #export proxy configs to env and dnf.conf
    export http_proxy="$PROXY"
    export https_proxy="$PROXY"
    export HTTP_PROXY="$PROXY"
    export HTTPS_PROXY="$PROXY"
    export NO_PROXY=localhost
    echo "proxy=http://$PROXY/" >> /etc/dnf/dnf.conf
}

add_system_proxy () {
    PROXY_FILE=/etc/profile.d/ksb_proxy.sh
    #creating ksb_proxy.sh file to store proxy configuration
    #it will be load when user log in
    echo -e "export http_proxy=$PROXY\nexport https_proxy=$PROXY\nexport HTTP_PROXY=$PROXY\nexport HTTPS_PROXY=$PROXY\nexport NO_PROXY=localhost" > "$PROXY_FILE"
    chmod 644 "$PROXY_FILE"
    success "Proxy settings added to /etc/profile.d/ksb_proxy.sh"
}

dnf_install_default () {
    #adding epel repo to system
    dnf update -y && dnf install epel-release -y 
    #installing minimal tools
    dnf install mc htop telnet nano wget curl traceroute strace ncdu net-tools bind-utils bash-completion -y 
#    systemctl enable --now systemd-timesyncd.service
    success "bash-completion mc telnet htop nano wget curl traceroute strace ncdu net-tools bind-utils installed"
}

install_vmtools () {
    #check that this is VM. if so - we will install guest tools
    VIRT=$(systemd-detect-virt)
    if [ "$VIRT" = "vmware" ]; then
        warn "$VIRT virt detected. Installing guest tools..."
        dnf install open-vm-tools -y 
        systemctl enable --now vmtoolsd
    elif [ "$VIRT" = "microsoft" ]; then
        warn "$VIRT virt detected. Installing guest tools..."
        dnf install hyperv-daemons -y 
        #We only enable services. If we start service now - it will be fail? i don`t know why. After restart service seemse working
        systemctl enable hypervkvpd hypervvssd
    elif [ "$VIRT" = "qemu" ]; then
        warn "$VIRT virt detected. Installing guest tools..."
        dnf install qemu-guest-agent -y
    elif [ "$VIRT" = "wsl" ]; then
        #Under wsl thereis issue in memory cache. We will drop memory caches with systemd unit every 3 minute
        echo -e "[Unit]
Description=Periodically drop caches to save memory under WSL.
Documentation=https://github.com/arkane-systems/wsl-drop-caches
ConditionVirtualization=wsl
Requires=drop_cache.timer

[Service]
Type=oneshot
ExecStartPre=sync
ExecStart=echo 3 > /proc/sys/vm/drop_caches" > /etc/systemd/system/drop_cache.service
        echo -e "[Unit]
Description=Periodically drop caches to save memory under WSL.
Documentation=https://github.com/arkane-systems/wsl-drop-caches
ConditionVirtualization=wsl
PartOf=drop_cache.service

[Timer]
OnBootSec=3min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target" > /etc/systemd/system/drop_cache.timer
        #We need true if systemd is not enabled in wsl by default to avoid script failing
        systemctl daemon-reload || true
        systemctl enable --now drop_cache.timer || true
        warn "Added drop_cache.timer to drop linux caches every 3 minutes to avoid eating windows memory"
    elif [ -z "$VIRT" ]; then
        warn "virt not detected. Nothing to do..."
    else 
        warn "Unrecognized virt: $VIRT"
        warn "You need install guest tools manually"
fi
}

dnf_install_docker () {
    #adding docker repo and install it
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
    dnf install docker-ce docker-ce-cli docker-compose-plugin -y 
    systemctl enable --now docker 
    #add default dir to store docker projects
    mkdir -p /opt/docker
    success "Docker installed"
}
docker_proxy_config () {
    #adding override dir to docker.service and store there proxy config
    mkdir -p /etc/systemd/system/docker.service.d
    #adding proxy config
    echo -e "[Service]\nEnvironment=\"HTTP_PROXY=$PROXY\"\nEnvironment=\"HTTPS_PROXY=$PROXY\"\nEnvironment=\"NO_PROXY=localhost\"" > /etc/systemd/system/docker.service.d/http-proxy.conf
    #rebuilding systemd dependency tree and reload docker to apply changes
    systemctl daemon-reload
    systemctl restart docker
    success "Proxy config added to docker"
}

install_runner () {
    #getting gitlab-runner install helper
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | bash 
    #installing gitlab-runner
    dnf install gitlab-runner -y 
    success "Gitlab-runner installed"
}

install_postgresql () {
    #adding postgresql repo
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm 
    #disabling default postgresql in dnf
    dnf -qy module disable postgresql
    #installing postgresql 
    dnf install -y postgresql"$POSTGRESQL_VERSION"-server 
    #initializing database
    /usr/pgsql-"$POSTGRESQL_VERSION"/bin/postgresql-"$POSTGRESQL_VERSION"-setup initdb 
    #starting postgresql service
    systemctl enable --now postgresql-"$POSTGRESQL_VERSION"
}

install_netdata () {
    #getting netdata installer and install
    echo -e "Installing netdata..."
    wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh && sh /tmp/netdata-kickstart.sh --disable-telemetry --non-interactive --stable-channel> /dev/null
    #adding rules to firewalld with netdata port
    firewall-cmd --permanent --add-port=19999/tcp
    firewall-cmd --reload
    success "Netdata installed"
}

add_temp () {
    mkdir -p /home/"$SUDO_USER"/temp
}

dnf_remove_proxy () {
    #removing proxy config from /etc/dnf/dnf.conf
    sed -i "/^proxy*/d" /etc/dnf/dnf.conf
    success "Proxy config removed from /etc/dnf/dnf.conf"
}

main () {
    check_dnf
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
    add_temp
    if [ "$REMOVE_DNF_PROXY" = "true" ]; then
        dnf_remove_proxy
    fi
}

main "$@"
