FROM fedora:latest
RUN dnf update -y && dnf install sudo && useradd test
COPY ./zsh_home_install.sh .
RUN chmod 755 ./zsh_home_install.sh
RUN echo -e "test ALL = NOPASSWD: /usr/bin/dnf install git zsh -y\ntest ALL = NOPASSWD: /usr/sbin/usermod -s /bin/bash test" > /etc/sudoers.d/test
USER test
RUN bash -c ./zsh_home_install.sh
