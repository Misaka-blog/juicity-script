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

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前暂不支持你的VPS的操作系统！" && exit 1

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
        * ) red "不支持的CPU架构!" && exit 1 ;;
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
    fi
    ${PACKAGE_INSTALL} wget curl sudo unzip
    
    last_version=$(curl -Ls "https://api.github.com/repos/juicity/juicity/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    tmp_dir=$(mktemp -d)

    wget https://github.com/juicity/juicity/releases/download/$last_version/juicity-linux-x86_64.zip -O $tmp_dir/juicity.zip

    cd $tmp_dir
    unzip juicity.zip
    cp -f juicity-server /usr/bin/juicity-server
    cp -f juicity-server.service /etc/systemd/system/juicity-server.service

    if [[ -f "/usr/bin/juicity-server" && -f "/etc/systemd/system/juicity-server.service" ]]; then
        chmod +x /usr/bin/juicity-server /etc/systemd/system/juicity-server.service
        rm -f $tmp_dir/*
    else
        red "Juicity 内核安装失败！"
        rm -f $tmp_dir/*
        exit 1
    fi

    green "Juicity 协议证书申请方式如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 脚本自动申请 ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 自定义证书路径"
    echo ""
    read -rp "请输入选项 [1-2]: " certInput
    if [[ $certInput == 2 ]]; then
        read -p "请输入公钥文件 crt 的路径：" cert_path
        yellow "公钥文件 crt 的路径：$cert_path "
        read -p "请输入密钥文件 key 的路径：" key_path
        yellow "密钥文件 key 的路径：$key_path "
        read -p "请输入证书的域名：" domain
        yellow "证书域名：$domain"
    else
        cert_path="/root/cert.crt"
        key_path="/root/private.key"
        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            domain=$(cat /root/ca.log)
            green "检测到原有域名：$domain 的证书，正在应用"
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
            
            read -p "请输入需要申请证书的域名：" domain
            [[ -z $domain ]] && red "未输入域名，无法执行操作！" && exit 1
            green "已输入的域名：$domain" && sleep 1
            domainIP=$(curl -sm8 ipget.net/?ip="${domain}")
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
                    green "证书申请成功! 脚本申请到的证书 (cert.crt) 和私钥 (private.key) 文件已保存到 /root 文件夹下"
                    yellow "证书crt文件路径如下: /root/cert.crt"
                    yellow "私钥key文件路径如下: /root/private.key"
                fi
            else
                red "当前域名解析的 IP 与当前 VPS 使用的真实 IP 不匹配"
                green "建议如下："
                yellow "1. 请确保CloudFlare小云朵为关闭状态(仅限DNS), 其他域名解析或CDN网站设置同理"
                yellow "2. 请检查DNS解析设置的IP是否为VPS的真实IP"
                yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
            fi
        fi
    fi

    read -p "设置 Juicity 端口 [1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Juicity 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    read -p "设置 Juicity UUID（回车跳过为随机 UUID）：" uuid
    [[ -z $uuid ]] && uuid=$(cat /proc/sys/kernel/random/uuid)

    read -p "设置 Juicity 密码（回车跳过为随机字符）：" passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)

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
        green "Juicity 服务启动成功"
    else
        red "Juicity 服务启动失败，请运行 systemctl status juicity-server 查看服务状态并反馈，脚本退出" && exit 1
    fi
    red "======================================================================================"
    green "Juicity 代理服务安装完成"
    yellow "CLI 客户端配置文件 client.json 内容如下，并保存到 /root/juicity/client.json"
    cat /root/juicity/client.json
    yellow "Juicity 节点分享链接如下，并保存到 /root/juicity/url.txt"
    cat /root/juicity/url.txt
}

unstjuicity(){
    systemctl stop juicity-server
    systemctl disable juicity-server
    rm -f /etc/systemd/system/juicity-server.service /root/juicity.sh
    rm -rf /usr/bin/juicity-server /etc/juicity /root/juicity
    
    green "Juicity 已彻底卸载完成！"
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
    yellow "请选择你需要的操作："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 启动 Juicity"
    echo -e " ${GREEN}2.${PLAIN} 关闭 Juicity"
    echo -e " ${GREEN}3.${PLAIN} 重启 Juicity"
    echo ""
    read -rp "请输入选项 [0-3]: " switchInput
    case $switchInput in
        1 ) startjuicity ;;
        2 ) stopjuicity ;;
        3 ) stopjuicity && startjuicity ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    oldport=$(cat /etc/juicity/server.json 2>/dev/null | sed -n 2p | awk '{print $2}' | tr -d ',' | awk -F ":" '{print $2}' | tr -d '"')
    
    read -p "设置 Juicity 端口[1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Juicity 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "2s#$oldport#$port#g" /etc/juicity/server.json
    sed -i "3s#$oldport#$port#g" /root/juicity/client.json
    sed -i "s#$oldport#$port#g" /root/juicity/url.txt

    stopjuicity && startjuicity

    green "Jucicity 端口已成功修改为：$port"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changeuuid(){
    olduuid=$(cat /etc/juicity/server.json 2>/dev/null | sed -n 4p | awk '{print $1}' | tr -d ':"')

    read -p "设置 Juicity UUID（回车跳过为随机 UUID）：" uuid
    [[ -z $uuid ]] && uuid=$(cat /proc/sys/kernel/random/uuid)

    sed -i "4s#$olduuid#$uuid#g" /etc/juicity/server.json
    sed -i "4s#$olduuid#$uuid#g" /root/juicity/client.json
    sed -i "s#$olduuid#$uuid#g" /root/juicity/url.txt

    stopjuicity && startjuicity

    green "Jucicity 节点 UUID 已成功修改为：$uuid"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changepasswd(){
    oldpasswd=$(cat /etc/juicity/server.json 2>/dev/null | sed -n 4p | awk '{print $2}' | tr -d '"')

    read -p "设置 Juicity 密码（回车跳过为随机字符）：" passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)

    sed -i "4s#$oldpasswd#$passwd#g" /etc/juicity/server.json
    sed -i "5s#$oldpasswd#$passwd#g" /root/juicity/client.json
    sed -i "s#$oldpasswd#$passwd#g" /root/juicity/url.txt

    stopjuicity && startjuicity

    green "Jucicity 节点密码已成功修改为：$passwd"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changeconf(){
    green "Juicity 配置变更选择如下:"
    echo -e " ${GREEN}1.${PLAIN} 修改端口"
    echo -e " ${GREEN}2.${PLAIN} 修改 UUID"
    echo -e " ${GREEN}3.${PLAIN} 修改密码"
    echo ""
    read -p " 请选择操作[1-2]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changeuuid ;;
        3 ) changepasswd ;;
        * ) exit 1 ;;
    esac
}

showconf(){
    yellow "CLI 客户端配置文件 client.json 内容如下，并保存到 /root/juicity/client.json"
    cat /root/juicity/client.json
    yellow "Juicity 节点分享链接如下，并保存到 /root/juicity/url.txt"
    cat /root/juicity/url.txt
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                    ${RED}Juicity 一键安装脚本${PLAIN}                   #"
    echo -e "# ${GREEN}作者${PLAIN}: MisakaNo の 小破站                                  #"
    echo -e "# ${GREEN}博客${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitHub 项目${PLAIN}: https://github.com/Misaka-blog               #"
    echo -e "# ${GREEN}GitLab 项目${PLAIN}: https://gitlab.com/Misaka-blog               #"
    echo -e "# ${GREEN}Telegram 频道${PLAIN}: https://t.me/misakanocchannel              #"
    echo -e "# ${GREEN}Telegram 群组${PLAIN}: https://t.me/misakanoc                     #"
    echo -e "# ${GREEN}YouTube 频道${PLAIN}: https://www.youtube.com/@misaka-blog        #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Juicity"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Juicity${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、开启、重启 Juicity"
    echo -e " ${GREEN}4.${PLAIN} 修改 Juicity 配置"
    echo -e " ${GREEN}5.${PLAIN} 显示 Juicity 配置文件"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-5]: " menuInput
    case $menuInput in
        1 ) instjuicity ;;
        2 ) unstjuicity ;;
        3 ) juicityswitch ;;
        4 ) changeconf ;;
        5 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu