FROM fedora:latest
RUN dnf update -y && useradd test
USER test
COPY ./zsh_home_install.sh .
RUN chmod 755 ./zsh_home_install.sh
ENTRYPOINT [ "/bin/bash", "-c", "./zsh_home_install.sh" ]
