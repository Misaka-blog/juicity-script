#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# Detect the system and define the package management commands
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "Please run the script as root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "The operating system of your VPS is currently not supported!" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'x86_64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) red "Unsupported CPU architecture!" && exit 1 ;;
    esac
}

realip(){
    ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
}

instjuicity(){
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        realip
    fi

    if [[ ! ${SYSTEM} == "CentOS" ]]; then
        ${PACKAGE_UPDATE}
        ${PACKAGE_INSTALL} bind-utils
    fi
    ${PACKAGE_INSTALL} wget curl sudo unzip dnsutils
    
    last_version=$(curl -Ls "https://api.github.com/repos/juicity/juicity/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || last_version=v$(curl -Ls "https://data.jsdelivr.com/v1/package/resolve/gh/juicity/juicity" | grep '"version":' | sed -E 's/.*"([^"]+)".*/\1/')
    tmp_dir=$(mktemp -d)

    wget https://github.com/juicity/juicity/releases/download/$last_version/juicity-linux-$(archAffix).zip -O $tmp_dir/juicity.zip

    cd $tmp_dir
    unzip juicity.zip
    cp -f juicity-server /usr/bin/juicity-server
    cp -f juicity-server.service /etc/systemd/system/juicity-server.service

    if [[ -f "/usr/bin/juicity-server" && -f "/etc/systemd/system/juicity-server.service" ]]; then
        chmod +x /usr/bin/juicity-server /etc/systemd/system/juicity-server.service
        rm -f $tmp_dir/*
    else
        red "Juicity installation failed!"
        rm -f $tmp_dir/*
        exit 1
    fi

    green "Juicity certificate application methods:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Automatic application by the script ${YELLOW}(Default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Specify custom certificate path"
    echo ""
    read -rp "Please enter your choice [1-2]: " certInput
    if [[ $certInput == 2 ]]; then
        read -p "Enter the path of the crt file: " cert_path
        yellow "crt file path: $cert_path "
        read -p "Enter the path of the key file: " key_path
        yellow "key file path: $key_path "
        read -p "Enter the domain name of the certificate: " domain
        yellow "Certificate domain name: $domain"
    else
        cert_path="/root/cert.crt"
        key_path="/root/private.key"
        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            domain=$(cat /root/ca.log)
            green "Detected existing certificate for domain: $domain, applying"
        else
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
            fi
            
            read -p "Enter the domain name for the certificate application: " domain
            [[ -z $domain ]] && red "No domain name entered, unable to proceed!" && exit 1
            green "Entered domain name: $domain" && sleep 1
            domainIP=$(dig @8.8.8.8 +time=2 +short "$domain" 2>/dev/null | sed -n 1p)
            if echo $domainIP | grep -q "network unreachable\|timed out" || [[ -z $domainIP ]]; then
                domainIP=$(dig @2001:4860:4860::8888 +time=2 aaaa +short "$domain" 2>/dev/null | sed -n 1p)
            fi
            if echo $domainIP | grep -q "network unreachable\|timed out" || [[ -z $domainIP ]] ; then
                red "Failed to resolve IP, please check if the domain name is entered correctly" 
                yellow "Do you want to attempt forced matching?"
                green "1. Yes, use forced matching"
                green "2. No, exit the script"
                read -p "Please enter your choice [1-2]: " ipChoice
                if [[ $ipChoice == 1 ]]; then
                    yellow "Attempting forced matching to apply for the domain certificate"
                else
                    red "Exiting the script"
                    exit 1
                fi
            fi
            
            if [[ $domainIP == $ip ]]; then
                ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
                if [[ $SYSTEM == "CentOS" ]]; then
                    ${PACKAGE_INSTALL[int]} cronie
                    systemctl start crond
                    systemctl enable crond
                else
                    ${PACKAGE_INSTALL[int]} cron
                    systemctl start cron
                    systemctl enable cron
                fi
                curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
                source ~/.bashrc
                bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ -n $(echo $ip | grep ":") ]]; then
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6 --insecure
                else
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --insecure
                fi
                bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
                if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]]; then
                    echo $domain > /root/ca.log
                    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                    green "Certificate application successful! The certificate (cert.crt) and private key (private.key) files obtained by the script are saved in the /root directory"
                    yellow "Certificate crt file path: /root/cert.crt"
                    yellow "Private key file path: /root/private.key"
                fi
            else
                red "The IP resolved by the current domain name does not match the real IP used by the current VPS"
                green "Suggestions:"
                yellow "1. Make sure the CloudFlare orange cloud is turned off (only DNS), other domain name resolution or CDN website settings are similar"
                yellow "2. Check if the IP set in the DNS resolution is the real IP of the VPS"
                yellow "3. The script may not keep up with the times, it is recommended to take a screenshot and post it on GitHub Issues, GitLab Issues, forums or TG group for consultation"
            fi
        fi
    fi

    read -p "Set the Juicity port [1-65535] (press Enter to randomly assign a port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} port is already occupied by other programs, please change the port and try again!"
            read -p "Set the Juicity port [1-65535] (press Enter to randomly assign a port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "The port used for the Juicity node: $port"

    read -p "Set the Juicity UUID (press Enter to skip and use a random UUID): " uuid
    [[ -z $uuid ]] && uuid=$(cat /proc/sys/kernel/random/uuid)
    yellow "The username used for the Juicity node: $uuid"

    read -p "Set the Juicity password (press Enter to skip and use random characters): " passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "The password used for the Juicity node: $passwd"

    mkdir /etc/juicity
    cat << EOF > /etc/juicity/server.json
{
    "listen": ":$port",
    "users": {
        "$uuid": "$passwd"
    },
    "certificate": "$cert_path",
    "private_key": "$key_path",
    "congestion_control": "bbr",
    "log_level": "info"
}
EOF

    mkdir /root/juicity
    cat << EOF > /root/juicity/client.json
{
    "listen": ":7080",
    "server": "$ip:$port",
    "uuid": "$uuid",
    "password": "$passwd",
    "sni": "$domain",
    "allow_insecure": true,
    "congestion_control": "bbr",
    "log_level": "info"
}
EOF

    shared_link=$(juicity-server generate-sharelink -c /etc/juicity/server.json)
    echo "$shared_link" > /root/juicity/url.txt

    systemctl daemon-reload
    systemctl enable juicity-server
    systemctl start juicity-server
    if [[ -n $(systemctl status juicity-server 2>/dev/null | grep -w active) && -f '/etc/juicity/server.json' ]]; then
        green "Juicity service started successfully"
    else
        red "Juicity service failed to start. Please run 'systemctl status juicity-server' to check the service status and provide feedback. Exiting the script." && exit 1
    fi
    red "======================================================================================"
    green "Juicity proxy service installation completed"
    yellow "The content of the CLI client configuration file client.json is as follows and saved to /root/juicity/client.json"
    cat /root/juicity/client.json
    yellow "The Juicity node sharing link is as follows and saved to /root/juicity/url.txt"
    cat /root/juicity/url.txt
}

unstjuicity(){
    systemctl stop juicity-server
    systemctl disable juicity-server
    rm -f /etc/systemd/system/juicity-server.service /root/juicity.sh
    rm -rf /usr/bin/juicity-server /etc/juicity /root/juicity
    
    green "Juicity has been completely uninstalled!"
}

startjuicity(){
    systemctl start juicity-server
    systemctl enable juicity-server >/dev/null 2>&1
}

stopjuicity(){
    systemctl stop juicity-server
    systemctl disable juicity-server >/dev/null 2>&1
}

juicityswitch(){
    yellow "Please select the operation you need:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Start Juicity"
    echo -e " ${GREEN}2.${PLAIN} Stop Juicity"
    echo -e " ${GREEN}3.${PLAIN} Restart Juicity"
    echo ""
    read -rp "Please enter your choice [0-3]: " switchInput
    case $switchInput in
        1 ) startjuicity ;;
        2 ) stopjuicity ;;
        3 ) stopjuicity && startjuicity ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    oldport=$(cat /etc/juicity/server.json 2>/dev/null | sed -n 2p | awk '{print $2}' | tr -d ',' | awk -F ":" '{print $2}' | tr -d '"')
    
    read -p "Set the Juicity port [1-65535] (press Enter to randomly assign a port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} port is already occupied by other programs, please change the port and try again!"
            read -p "Set the Juicity port [1-65535] (press Enter to randomly assign a port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "2s#$oldport#$port#g" /etc/juicity/server.json
    sed -i "3s#$oldport#$port#g" /root/juicity/client.json
    sed -i "s#$oldport#$port#g" /root/juicity/url.txt

    stopjuicity && startjuicity

    green "Juicity port has been successfully modified to: $port"
    yellow "Please manually update the client configuration file to use the node"
    showconf
}

changeuuid(){
    olduuid=$(cat /etc/juicity/server.json 2>/dev/null | sed -n 4p | awk '{print $1}' | tr -d ':"')

    read -p "Set the Juicity UUID (press Enter to skip and use a random UUID): " uuid
    [[ -z $uuid ]] && uuid=$(cat /proc/sys/kernel/random/uuid)

    sed -i "4s#$olduuid#$uuid#g" /etc/juicity/server.json
    sed -i "4s#$olduuid#$uuid#g" /root/juicity/client.json
    sed -i "s#$olduuid#$uuid#g" /root/juicity/url.txt

    stopjuicity && startjuicity

    green "Juicity node UUID has been successfully modified to: $uuid"
    yellow "Please manually update the client configuration file to use the node"
    showconf
}

changepasswd(){
    oldpasswd=$(cat /etc/juicity/server.json 2>/dev/null | sed -n 4p | awk '{print $2}' | tr -d '"')

    read -p "Set the Juicity password (press Enter to skip and use random characters): " passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)

    sed -i "4s#$oldpasswd#$passwd#g" /etc/juicity/server.json
    sed -i "5s#$oldpasswd#$passwd#g" /root/juicity/client.json
    sed -i "s#$oldpasswd#$passwd#g" /root/juicity/url.txt

    stopjuicity && startjuicity

    green "Juicity node password has been successfully modified to: $passwd"
    yellow "Please manually update the client configuration file to use the node"
    showconf
}

changeconf(){
    green "Juicity configuration change options:"
    echo -e " ${GREEN}1.${PLAIN} Modify port"
    echo -e " ${GREEN}2.${PLAIN} Modify UUID"
    echo -e " ${GREEN}3.${PLAIN} Modify password"
    echo ""
    read -p "Please select an operation [1-2]: " confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changeuuid ;;
        3 ) changepasswd ;;
        * ) exit 1 ;;
    esac
}

updatejuicity(){
    if [[ -f "/usr/bin/juicity-server" && -f "/etc/systemd/system/juicity-server.service" ]]; then
        last_version=$(curl -Ls "https://api.github.com/repos/juicity/juicity/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || last_version=v$(curl -Ls "https://data.jsdelivr.com/v1/package/resolve/gh/juicity/juicity" | grep '"version":' | sed -E 's/.*"([^"]+)".*/\1/')
        tmp_dir=$(mktemp -d)

        wget https://github.com/juicity/juicity/releases/download/$last_version/juicity-linux-$(archAffix).zip -O $tmp_dir/juicity.zip

        cd $tmp_dir
        unzip juicity.zip
        cp -f juicity-server /usr/bin/juicity-server
        cp -f juicity-server.service /etc/systemd/system/juicity-server.service

        if [[ -f "/usr/bin/juicity-server" && -f "/etc/systemd/system/juicity-server.service" ]]; then
            chmod +x /usr/bin/juicity-server /etc/systemd/system/juicity-server.service
            rm -f $tmp_dir/*
        else
            red "Juicity update failed!"
            rm -f $tmp_dir/*
            exit 1
        fi

        systemctl daemon-reload
        systemctl restart juicity-server
        green "Juicity has been successfully updated to the latest version!"
    else
        red "Juicity is not installed on this server. Please install it first."
    fi
}

showconf(){
    yellow "The content of the CLI client configuration file client.json is as follows and saved to /root/juicity/client.json"
    cat /root/juicity/client.json
    yellow "The Juicity node sharing link is as follows and saved to /root/juicity/url.txt"
    cat /root/juicity/url.txt
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                ${RED}Juicity Installation Script${PLAIN}                #"
    echo -e "# ${GREEN}Author${PLAIN}: MisakaNo の Little Broken Site                    #"
    echo -e "# ${GREEN}Blog${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitHub Project${PLAIN}: https://github.com/Misaka-blog            #"
    echo -e "# ${GREEN}GitLab Project${PLAIN}: https://gitlab.com/Misaka-blog            #"
    echo -e "# ${GREEN}Telegram Channel${PLAIN}: https://t.me/misakanocchannel           #"
    echo -e "# ${GREEN}Telegram Group${PLAIN}: https://t.me/misakanoc                    #"
    echo -e "# ${GREEN}YouTube Channel${PLAIN}: https://www.youtube.com/@misaka-blog     #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install Juicity"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall Juicity${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Stop, Start, Restart Juicity"
    echo -e " ${GREEN}4.${PLAIN} Modify Juicity Configuration"
    echo -e " ${GREEN}5.${PLAIN} Update Juicity"
    echo -e " ${GREEN}6.${PLAIN} Show Juicity Configuration"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} Exit Script"
    echo ""
    read -rp "Please enter your choice [0-6]: " menuInput
    case $menuInput in
        1 ) instjuicity ;;
        2 ) unstjuicity ;;
        3 ) juicityswitch ;;
        4 ) changeconf ;;
        5 ) updatejuicity ;;
        6 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu
