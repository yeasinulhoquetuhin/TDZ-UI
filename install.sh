#!/bin/bash
# =====================================================
# TDZ-UI Installer
# Developer: Yeasinul Hoque Tuhin
# Website: https://tuhinbro.website
# Based on: 3X-UI by MHSanaei
# =====================================================

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    alpine)
        apk update && apk add wget curl tar tzdata
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/tdz-ui/tdz-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/tdz-ui/tdz-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/tdz-ui/tdz-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "Please set up the panel port: " config_port
                echo -e "${yellow}Your Panel Port is: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}Generated random port: ${config_port}${plain}"
            fi

            /usr/local/tdz-ui/tdz-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "Fresh installation detected, random credentials generated:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "${green}Port: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath missing, generating new one...${plain}"
            /usr/local/tdz-ui/tdz-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Generating secure ones...${plain}"
            /usr/local/tdz-ui/tdz-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "New login credentials:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}Credentials already set. Skipping...${plain}"
        fi
    fi

    /usr/local/tdz-ui/tdz-ui migrate
}

install_tdz_ui() {
    cd /usr/local/

    # Download resources from 3x-ui repo
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}Failed to fetch 3x-ui version from GitHub${plain}"
            exit 1
        fi
        echo -e "Got 3x-ui latest version: ${tag_version}, beginning TDZ-UI installation..."
        wget -N -O /usr/local/tdz-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading failed. Check GitHub connectivity.${plain}"
            exit 1
        fi
    else
        tag_version=$1
        echo -e "Installing TDZ-UI $1..."
        wget -N -O /usr/local/tdz-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download failed, version may not exist.${plain}"
            exit 1
        fi
    fi

    wget -O /usr/bin/tdz-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh

    # Stop old service
    if [[ -e /usr/local/tdz-ui/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service tdz-ui stop
        else
            systemctl stop tdz-ui
        fi
        rm /usr/local/tdz-ui/ -rf
    fi

    # Extract resources
    tar zxvf tdz-ui-linux-$(arch).tar.gz
    rm tdz-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh

    mv -f /usr/bin/tdz-ui-temp /usr/bin/tdz-ui
    chmod +x /usr/bin/tdz-ui
    config_after_install

    if [[ $release == "alpine" ]]; then
        wget -O /etc/init.d/tdz-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc
        chmod +x /etc/init.d/tdz-ui
        rc-update add tdz-ui
        rc-service tdz-ui start
    else
        cp -f x-ui.service /etc/systemd/system/tdz-ui.service
        sed -i 's/x-ui/tdz-ui/g' /etc/systemd/system/tdz-ui.service
        systemctl daemon-reload
        systemctl enable tdz-ui
        systemctl start tdz-ui
    fi

    echo -e "${green}TDZ-UI ${tag_version}${plain} installation finished, it is running now..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐"
    echo -e "│  ${blue}TDZ-UI Control Menu (subcommands):${plain}             │"
    echo -e "│                                                       │"
    echo -e "│  ${blue}tdz-ui${plain}              - Admin Management Script     │"
    echo -e "│  ${blue}tdz-ui start${plain}        - Start                        │"
    echo -e "│  ${blue}tdz-ui stop${plain}         - Stop                         │"
    echo -e "│  ${blue}tdz-ui restart${plain}      - Restart                      │"
    echo -e "│  ${blue}tdz-ui status${plain}       - Current Status               │"
    echo -e "│  ${blue}tdz-ui settings${plain}     - Current Settings             │"
    echo -e "│  ${blue}tdz-ui enable${plain}       - Enable Autostart             │"
    echo -e "│  ${blue}tdz-ui disable${plain}      - Disable Autostart            │"
    echo -e "│  ${blue}tdz-ui log${plain}          - Check logs                   │"
    echo -e "│  ${blue}tdz-ui update${plain}       - Update                       │"
    echo -e "│  ${blue}tdz-ui uninstall${plain}    - Uninstall                    │"
    echo -e "└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running TDZ-UI Installer...${plain}"
install_base
install_tdz_ui $1
