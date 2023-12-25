#!/usr/bin/env bash
set -euo

# color set
color_set () {
        colors_256 () {
           bold=$(tput bold)
           underline=$(tput sgr 0 1)
           reset=$(tput sgr0)

           red=$(tput setaf 196)
           green=$(tput setaf 40)
           white=$(tput setaf 255)
           tan=$(tput setaf 214)
           blue=$(tput setaf 27)

           debug() { printf "${white}DEBUG %s${reset}\n" "$@"
           }
           info() { printf "${white}➜ %s${reset}\n" "$@"
           }
           success() { printf "${green}✔ %s${reset}\n" "$@"
           }
           error() { printf "${red}✖ %s${reset}\n" "$@"
           }
           warn() { printf "${tan}➜ %s${reset}\n" "$@"
           }
           note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@"
           }
        }

        colors_8 () {
        bold='\033[1;34m'
           underline='\033[4;34m'
           reset='\033[0m'

           red='\033[0;31m'
           green='\033[0;32m'
           white='\033[0;37m'
           tan='\033[0;33m'
           blue='\033[0;34m'

           debug() { printf "${white}[DEBUG] %s${reset}\n" "$@"
           }
           info() { printf "${white}[INFO] %s${reset}\n" "$@"
           }
           success() { printf "${green}[ OK ] %s${reset}\n" "$@"
           }
           error() { printf "${red}[ERR ] %s${reset}\n" "$@"
           }
           warn() { printf "${tan}[WARN] %s${reset}\n" "$@"
           }
           note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@"
           }
        }

        if command -v tput >/dev/null 2>&1 && [ "$(tput colors)" -gt "8" ] ; then
           colors_256
        else
           colors_8
        fi
}

langpack () {
        ru_langpack () {
           loading="Загрузка"
           starting="Старт"
           shutdown="Выключение"
        }

        en_langpack () {
           loading="loading message"
           starting="starting message"
           shutdown="shutdown message"
        }

        lang="$LANG"
        if [ "$lang" = "ru_RU.UTF-8" ]; then
           ru_langpack
        else
           en_langpack
        fi
}

color_set
langpack

debug "$loading"
info "$starting"
success "$shutdown"
error "Test"
warn "Test"
note "Test"
