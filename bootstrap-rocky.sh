#!/usr/bin/env bash
hi () {
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

    echo "              _
             | |
             | |===( )   //////
             |_|   |||  | o o|
                    ||| ( c  )                  ____
                     ||| \= /                  ||   \_
                      ||||||                   ||     |
                      ||||||                ...||__/|-
                      ||||||             __|________|__
                        |||             |______________|
                        |||             || ||      || ||
                        |||             || ||      || ||
------------------------|||-------------||-||------||-||-------
                        |__>            || ||      || ||"
}

check_root () {
    if [ "$EUID" -ne 0 ]; then 
        echo "Please run this script as root"
        exit 1
    fi
}

check_dnf () {
    if ! command -v dnf &> /dev/null ; then
        error "DNF not found. This script for DNF based distros only"
        exit 1
    else 
        success "DNF found. Continue..."
    fi
}

questions_proxy () {
    echo -e "Proxy. Confugure default proxy (10.38.22.253:3128), no proxy or custom proxy with IP:PORT"
    read -rp "  Answer (default/d, no/n, ip:port ): " ANSWER
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
}

questions_permanent_proxy () {
    if [ -n "$PROXY" ]; then
        read -rp "Add permanent proxy config to system variables? (yes/y, no/n): " ANSWER
        case $ANSWER in
            yes|y) ADD_SYSTEM_PROXY=true
                ;;
             no|n) ADD_SYSTEM_PROXY=false
                ;;
              *) error "incorrect option"
                 questions_permanent_proxy
                ;;
        esac
        unset ANSWER
    fi
}

questions_docker () {
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
                         questions_docker
                         ;;
                 esac
                 unset ANSWER
             fi
            ;;
        no|n) DOCKER_INSTALL=false
            ;;
           *) error "Incorrect option"
              questions_docker
            ;;
    esac
    unset ANSWER
}

questions_gitlab_runner () {
    read -rp "Install gitlab-runner? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) RUNNER_INSTALL=true
            ;;
         no|n) RUNNER_INSTALL=false
            ;;
          *) error "incorrect option"
             questions_gitlab_runner
             ;;
    esac
    unset ANSWER
}

questions_postgres () {
    read -rp "Install postgresql? (yes/y, no/n): " ANSWER
    #well, there is some shit
    case $ANSWER in
        yes|y) POSTGRESQL_INSTALL=true
             read -rp "Postgresql version? (11 12 13 14 15): " POSTGRESQL_VERSION
            ;;
         no|n) POSTGRESQL_INSTALL=false
            ;;
         11|12|13|14|15) true
            ;;
          *) error "incorrect option"
             questions_postgres
            ;;
    esac
    unset ANSWER
}

questions_netdata () {
    read -rp "Install netdata? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) NETDATA_INSTALL=true
            ;;
          no|n) NETDATA_INSTALL=false
            ;;
          *) error "incorrect option"
             questions_netdata
            ;;
    esac
    unset ANSWER
}

questions_remove_dnf_config () {
    read -rp "Remove proxy config from /etc/dnf/dnf.conf? (yes/y, no/n): " ANSWER
    case $ANSWER in
        yes|y) REMOVE_DNF_PROXY=true
            ;;
         no|n) REMOVE_DNF_PROXY=false
            ;;
          *) error "incorrect option"
             questions_remove_dnf_config
            ;;
    esac
    unset ANSWER
}

questions () {
    #asking questions. store answers in variables
    questions_proxy
    questions_permanent_proxy
    questions_docker
    questions_gitlab_runner
    questions_postgres
    questions_netdata
    questions_remove_dnf_config
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
    echo -e "export http_proxy=$PROXY
    export https_proxy=$PROXY
    export HTTP_PROXY=$PROXY
    export HTTPS_PROXY=$PROXY
    export NO_PROXY=localhost" > "$PROXY_FILE"
    chmod 644 "$PROXY_FILE"
    success "Proxy settings added to /etc/profile.d/ksb_proxy.sh"
}

dnf_install_default () {
    #adding epel repo to system
    dnf install epel-release -y 
    #installing minimal tools
    dnf install mc htop telnet nano wget curl traceroute strace ncdu net-tools bind-utils bash-completion -y 
#    systemctl enable --now systemd-timesyncd.service
    success "Default system tools installed"
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
        warn "Added drop_cache.timer and drop_cache.service in /etc/systemd to drop linux caches every 3 minutes to avoid eating windows memory"
    elif [ -z "$VIRT" ]; then
        warn "virt not detected. Nothing to do..."
    else 
        warn "Unrecognized virt: $VIRT"
        warn "You need install guest tools manually"
fi
}


dnf_install_docker () {
    SERVICE=docker
    STATUS="$(systemctl is-active $SERVICE.service || true)"
    if [ "$STATUS" = "active" ]; then
        warn "It seems like $SERVICE already installed and running... Nothing to do..."
    else
        #adding docker repo and install it
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
        dnf install docker-ce docker-ce-cli docker-compose-plugin -y 
        systemctl enable --now docker 
        #add default dir to store docker projects
        mkdir -p /opt/docker
        success "Docker installed"
    fi
}
docker_proxy_config () {
    #adding override dir to docker.service and store there proxy config
    mkdir -p /etc/systemd/system/docker.service.d
    #adding proxy config
    echo -e "[Service]
    Environment=\"HTTP_PROXY=$PROXY\"
    Environment=\"HTTPS_PROXY=$PROXY\"
    Environment=\"NO_PROXY=localhost\"" > /etc/systemd/system/docker.service.d/http-proxy.conf
    #rebuilding systemd dependency tree and reload docker to apply changes
    systemctl daemon-reload
    systemctl restart docker
    success "Proxy config added to docker"
}

install_runner () {
    SERVICE=gitlab-runner
    STATUS="$(systemctl is-active $SERVICE.service || true)"
    if [ "$STATUS" = "active" ]; then
        warn "It seems like $SERVICE already installed and running... Nothing to do..."
    else
        #getting gitlab-runner install helper
        curl -L \
            "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | bash 
        #installing gitlab-runner
        dnf install gitlab-runner -y 
        success "Gitlab-runner installed"
    fi
}

install_postgresql () {
    SERVICE=postgresql-"$POSTGRESQL_VERSION"
    STATUS="$(systemctl is-active $SERVICE.service || true)"
    if [ "$STATUS" = "active" ]; then
        warn "It seems like $SERVICE already installed and running... Nothing to do..."
    else
        #adding postgresql repo
        dnf install -y \
            https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm 
        #disabling default postgresql in dnf
        dnf -qy module disable postgresql
        #installing postgresql 
        dnf install -y postgresql"$POSTGRESQL_VERSION"-server 
        #initializing database
        /usr/pgsql-"$POSTGRESQL_VERSION"/bin/postgresql-"$POSTGRESQL_VERSION"-setup initdb 
        #starting postgresql service
        systemctl enable --now postgresql-"$POSTGRESQL_VERSION"
    fi
}

install_netdata () {
    SERVICE=netdata
    STATUS="$(systemctl is-active $SERVICE.service || true)"
    if [ "$STATUS" = "active" ]; then
        warn "It seems like $SERVICE already installed and running... Nothing to do..."
    else
        #getting netdata installer and install
        echo -e "Installing netdata..."
        wget -O /tmp/netdata-kickstart.sh \
                https://my-netdata.io/kickstart.sh \
                && \
                sh /tmp/netdata-kickstart.sh \
                    --disable-telemetry \
                    --non-interactive \
                    --stable-channel> /dev/null
        #adding rules to firewalld with netdata port
        systemctl enable --now netdata
        firewall-cmd --permanent --add-port=19999/tcp
        firewall-cmd --reload
        success "Netdata installed"
    fi
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
    hi
    check_root
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
