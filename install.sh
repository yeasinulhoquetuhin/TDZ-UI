#!/bin/bash

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
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
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

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "This is a fresh installation, generating random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "${green}Port: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "Generated new random login credentials:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}Username, Password, and WebBasePath are properly set. Exiting...${plain}"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    # Download resources
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}Failed to fetch x-ui version, it may be due to GitHub API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got x-ui latest version: ${tag_version}, beginning the installation..."
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading x-ui failed, please be sure that your server can access GitHub ${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Beginning to install x-ui $1"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui $1 failed, please check if the version exists ${plain}"
            exit 1
        fi
    fi
    wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh

    # Stop x-ui service and remove old resources
    if [[ -e /usr/local/x-ui/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        rm /usr/local/x-ui/ -rf
    fi

    # Extract resources and set permissions
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)

    # Update x-ui cli and se set permission
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    config_after_install

    if [[ $release == "alpine" ]]; then
        wget -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi

    echo -e "${green}x-ui ${tag_version}${plain} installation finished, it is running now..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui $1    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo -e "${cyan}Architecture: ${green}$(arch)${plain}"

show_banner() {
    echo -e "${magenta}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║               ████████╗██████╗ ███████╗                  ║"
    echo "║               ╚══██╔══╝██╔══██╗██╔════╝                  ║"
    echo "║                  ██║   ██║  ██║█████╗                    ║"
    echo "║                  ██║   ██║  ██║██╔══╝                    ║"
    echo "║                  ██║   ██████╔╝███████╗                  ║"
    echo "║                  ╚═╝   ╚═════╝ ╚══════╝                  ║"
    echo "║                                                          ║"
    echo "║               ${cyan}Enterprise VPN Solution${magenta}               ║"
    echo "║                                                          ║"
    echo "║           Modified by: ${green}$MOD_AUTHOR${magenta}           ║"
    echo "║           Website: ${cyan}$MOD_WEBSITE${magenta}                ║"
    echo "║           Version: ${yellow}$MOD_VERSION${magenta}                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${plain}"
}

install_base() {
    echo -e "${cyan}Installing system dependencies...${plain}"
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
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
    echo -e "${green}✓ Dependencies installed successfully${plain}"
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    echo -e "${cyan}Configuring Tdz Tunnel settings...${plain}"
    local existing_hasDefaultCredential=$(/usr/local/tdz/tdz setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/tdz/tdz setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/tdz/tdz setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    
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

            /usr/local/tdz/tdz setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            
            echo -e "${green}"
            echo "╔══════════════════════════════════════════════════════════╗"
            echo "║                 Tdz Tunnel Login Information             ║"
            echo "╚══════════════════════════════════════════════════════════╝"
            echo -e "${plain}"
            echo -e "${cyan}Username: ${green}${config_username}${plain}"
            echo -e "${cyan}Password: ${green}${config_password}${plain}"
            echo -e "${cyan}Port: ${green}${config_port}${plain}"
            echo -e "${cyan}WebBasePath: ${green}${config_webBasePath}${plain}"
            echo -e "${cyan}Access URL: ${yellow}http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "${cyan}Admin Panel: ${yellow}http://${server_ip}:${config_port}/${config_webBasePath}/admin${plain}"
            echo -e "${green}✓ Configuration completed successfully${plain}"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            /usr/local/tdz/tdz setting -webBasePath "${config_webBasePath}"
            echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            /usr/local/tdz/tdz setting -username "${config_username}" -password "${config_password}"
            
            echo -e "${green}"
            echo "╔══════════════════════════════════════════════════════════╗"
            echo "║                New Login Credentials                     ║"
            echo "╚══════════════════════════════════════════════════════════╝"
            echo -e "${plain}"
            echo -e "${cyan}Username: ${green}${config_username}${plain}"
            echo -e "${cyan}Password: ${green}${config_password}${plain}"
            echo -e "${green}✓ Security credentials updated${plain}"
        else
            echo -e "${green}✓ Username, Password, and WebBasePath are properly set${plain}"
        fi
    fi

    /usr/local/tdz/tdz migrate
    echo -e "${green}✓ Database migration completed${plain}"
}

install_tdz() {
    cd /usr/local/
    echo -e "${cyan}Starting Tdz Tunnel installation...${plain}"

    # Download resources
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}Failed to fetch tdz version, it may be due to GitHub API restrictions${plain}"
            exit 1
        fi
        echo -e "${green}Latest version: ${yellow}${tag_version}${plain}, beginning installation..."
        wget -N -O /usr/local/tdz-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading tdz failed, please check your internet connection${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "${green}Installing tdz ${tag_version}${plain}"
        wget -N -O /usr/local/tdz-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download tdz ${tag_version} failed${plain}"
            exit 1
        fi
    fi

    # Download custom script
    wget -O /usr/bin/tdz-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh

    # Stop tdz service and remove old resources
    if [[ -e /usr/local/tdz/ ]]; then
        systemctl stop tdz
        rm /usr/local/tdz/ -rf
        echo -e "${yellow}Removed previous installation${plain}"
    fi

    # Extract resources and set permissions
    echo -e "${cyan}Extracting files...${plain}"
    tar zxvf tdz-linux-$(arch).tar.gz
    rm tdz-linux-$(arch).tar.gz -f
    
    # Rename directory from x-ui to tdz
    if [[ -d "x-ui" ]]; then
        mv x-ui tdz
    fi
    
    cd tdz
    chmod +x tdz
    chmod +x tdz.sh

    # Rename binary files
    if [[ -f "bin/xray-linux-$(arch)" ]]; then
        mv bin/xray-linux-$(arch) bin/tdz-core
        chmod +x bin/tdz-core
    fi

    # Update tdz cli and set permission
    mv -f /usr/bin/tdz-temp /usr/bin/tdz
    chmod +x /usr/bin/tdz

    # Apply custom branding to the binary
    echo -e "${cyan}Applying custom branding...${plain}"
    if [[ -f "tdz" ]]; then
        sed -i "s/x-ui/tdz/g" tdz
        sed -i "s/X-UI/Tdz Tunnel/g" tdz
        sed -i "s/MHSanaei/$MOD_AUTHOR/g" tdz
        sed -i "s|github.com/MHSanaei/3x-ui|$MOD_WEBSITE|g" tdz
    fi

    config_after_install

    # Update service file
    if [[ -f "x-ui.service" ]]; then
        sed -i "s/x-ui/tdz/g" x-ui.service
        sed -i "s/X-UI/Tdz Tunnel/g" x-ui.service
        sed -i "s/Description=.*/Description=Tdz Tunnel Enterprise VPN Service - Modified by $MOD_AUTHOR/g" x-ui.service
        cp -f x-ui.service /etc/systemd/system/tdz.service
    else
        # Create new service file if not exists
        cat > /etc/systemd/system/tdz.service << EOF
[Unit]
Description=Tdz Tunnel Enterprise VPN Service - Modified by $MOD_AUTHOR
Documentation=$MOD_WEBSITE
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/tdz
ExecStart=/usr/local/tdz/tdz
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable tdz
    systemctl start tdz

    echo -e "${green}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Tdz Tunnel Installation Complete            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${plain}"
    echo -e "${green}✓ ${yellow}Tdz Tunnel ${tag_version}${green} installed successfully${plain}"
    echo -e "${green}✓ Service is now running${plain}"
    echo -e ""

    echo -e "${cyan}┌───────────────────────────────────────────────────────┐"
    echo -e "│  ${magenta}Tdz Tunnel Control Menu:${cyan}                          │"
    echo -e "│                                                       │"
    echo -e "│  ${green}tdz${cyan}              - Admin Management Script          │"
    echo -e "│  ${green}tdz start${cyan}        - Start Service                    │"
    echo -e "│  ${green}tdz stop${cyan}         - Stop Service                     │"
    echo -e "│  ${green}tdz restart${cyan}      - Restart Service                  │"
    echo -e "│  ${green}tdz status${cyan}       - Show Service Status              │"
    echo -e "│  ${green}tdz settings${cyan}     - Show Current Settings            │"
    echo -e "│  ${green}tdz enable${cyan}       - Enable Autostart                 │"
    echo -e "│  ${green}tdz disable${cyan}      - Disable Autostart                │"
    echo -e "│  ${green}tdz log${cyan}          - View Logs                        │"
    echo -e "│  ${green}tdz update${cyan}       - Update Tdz Tunnel                │"
    echo -e "│  ${green}tdz install${cyan}      - Install                          │"
    echo -e "│  ${green}tdz uninstall${cyan}    - Uninstall                        │"
    echo -e "└───────────────────────────────────────────────────────┘${plain}"
    echo -e ""
    echo -e "${yellow}Modified by: ${green}$MOD_AUTHOR${plain}"
    echo -e "${yellow}Website: ${cyan}$MOD_WEBSITE${plain}"
    echo -e "${yellow}Version: ${magenta}$MOD_VERSION${plain}"
}

# Main execution
show_banner
echo -e "${green}Starting Tdz Tunnel installation...${plain}"
install_base
install_tdz $1
