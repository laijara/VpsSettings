#!/bin/bash

# ==============================================================================
# АВТОНОМНЫЙ УСТАНОВЩИК: WireGuard + MTProxy + Защита
# Структура проекта:
# /setup.sh
# /src/wireguard/wireguard-install.sh
# /src/mtprotoproxy/...
#
# КОМАНДА ДЛЯ ЗАПУСКА НА НОВОМ СЕРВЕРЕ:
# git clone https://github.com/ВАШ_ЛОГИН/ВАШ_РЕПОЗИТОРИЙ.git /root/vpn_deploy && cd /root/vpn_deploy && bash setup.sh
# ==============================================================================

echo "=== 1. Подготовка системы ==="
export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y curl wget git python3 python3-cryptography iptables iproute2 iptables-persistent

SERVER_IP=$(curl -s4 ifconfig.me)

echo "=== 2. Установка WireGuard (VPN) из папки src ==="
# Обращаемся к скрипту по новому пути
chmod +x src/wireguard/wireguard-install.sh

export AUTO_INSTALL=y
export CLIENT_NAME="MyPC"
export PASS=1
./src/wireguard/wireguard-install.sh

echo "=== 3. Настройка интернета (маршрутизации) ==="
sysctl -w net.ipv4.ip_forward=1
INTF=$(ip route | grep default | awk '{print $5}' | head -n 1)
iptables -t nat -A POSTROUTING -o $INTF -j MASQUERADE
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT

echo "=== 4. Установка Python MTProxy из папки src ==="
systemctl stop mtproxy 2>/dev/null
rm -rf /opt/mtprotoproxy

# Копируем папку с прокси по новому пути
cp -r src/mtprotoproxy /opt/mtprotoproxy

TG_SECRET=$(xxd -l 16 -p /dev/urandom)

cat << EOF > /opt/mtprotoproxy/config.py
PORT = 8443
USERS = {
    "admin": "${TG_SECRET}"
}
EOF

cat << EOF > /etc/systemd/system/mtproxy.service
[Unit]
Description=Lightweight Python MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/mtprotoproxy
ExecStart=/usr/bin/python3 mtprotoproxy.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mtproxy --now

echo "=== 5. Настройка базового фаервола ==="
iptables -I INPUT -p udp --dport 51820 -j ACCEPT
iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
ufw allow 51820/udp 2>/dev/null
ufw allow 8443/tcp 2>/dev/null

echo "=== 6. Защита сервера (Смена порта SSH на 8922) ==="
iptables -I INPUT -p tcp --dport 8922 -j ACCEPT
ufw allow 8922/tcp 2>/dev/null
sed -i 's/^#*Port 22/Port 8922/' /etc/ssh/sshd_config
grep -q "^Port 8922" /etc/ssh/sshd_config || echo "Port 8922" >> /etc/ssh/sshd_config

systemctl disable --now ssh.socket 2>/dev/null
systemctl enable --now ssh.service 2>/dev/null
systemctl restart ssh 2>/dev/null
systemctl restart sshd 2>/dev/null
netfilter-persistent save 2>/dev/null

echo ""
echo "=================================================="
echo "✅ СЕРВЕР УСПЕШНО НАСТРОЕН И ЗАЩИЩЕН!"
echo "=================================================="
echo "🛡️ ВАЖНО: ПОРТ SSH ИЗМЕНЕН НА 8922"
echo "=================================================="
cat /root/MyPC.conf
echo "--------------------------------------------------"
echo ""
echo "✈️ ВАШ ПРОКСИ ДЛЯ TELEGRAM:"
TG_LINK="tg://proxy?server=${SERVER_IP}&port=8443&secret=ee${TG_SECRET}7777772e676f6f676c652e636f6d"
echo "$TG_LINK"
echo "=================================================="