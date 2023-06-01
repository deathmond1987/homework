FROM rockylinux:latest
RUN dnf update -y
RUN useradd test; su - test
COPY ../../zsh_home_install.sh ./
ENTRYPOINT [ "/bin/bash", "-c", "./zsh_home_install.sh" ]
