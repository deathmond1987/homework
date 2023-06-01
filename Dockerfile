FROM fedora:latest
RUN dnf update -y && useradd test
COPY ./zsh_home_install.sh .
RUN chmod 755 ./zsh_home_install.sh
RUN test ALL = NOPASSWD: sudo dnf install git zsh -y
USER test
RUN bash -c ./zsh_home_install.sh
