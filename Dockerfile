FROM fedora:latest
RUN dnf install sudo && useradd test 
COPY ./zsh_home_install.sh .
RUN chmod 755 ./zsh_home_install.sh
RUN echo -e "test ALL = NOPASSWD: /usr/bin/dnf install git zsh -y\ntest ALL = NOPASSWD:SETENV: /usr/sbin/usermod -s /usr/bin/zsh test\ntest ALL = NOPASSWD: /usr/bin/dnf install epel-release -y" > /etc/sudoers.d/test
USER test
ENV TERM=xterm
RUN bash -c ./zsh_home_install.sh
