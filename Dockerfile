FROM fedora:latest
RUN dnf update -y && dnf install sudo && useradd test
COPY ./zsh_home_install.sh .
RUN chmod 755 ./zsh_home_install.sh
RUN echo "test ALL = NOPASSWD: sudo dnf install git zsh -y" > /etc/sudoers.d/test
USER test
RUN bash -c ./zsh_home_install.sh
