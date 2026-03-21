#!/bin/bash

# ==============================================================================
# УНИВЕРСАЛЬНЫЙ УСТАНОВЩИК: WireGuard (VPN) + Python MTProxy + Защита сервера
# ==============================================================================
# КАК ЗАПУСТИТЬ НА НОВОМ СЕРВЕРЕ:
# 1. Откройте этот файл на GitHub и нажмите кнопку "Raw" (Сырой код).
# 2. Скопируйте ссылку из адресной строки.
# 3. Вставьте в консоль чистого сервера команду:
#
#    curl -sL https://raw.githubusercontent.com/ВАШ_ЛОГИН/ВАШ_РЕП/main/setup.sh | bash
#
# ВАЖНО ПОСЛЕ УСТАНОВКИ:
# Порт SSH изменится со стандартного 22 на 8922. 
# Новое подключение: ssh -p 8922 root@IP_СЕРВЕРА
# ==============================================================================

echo "=== 1. Подготовка системы ==="
export DEBIAN_FRONTEND=noninteractive

# Глушим интерактивные окна при сохранении правил фаервола
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

apt-get update -y
apt-get install -y curl wget git python3 python3-cryptography iptables iproute2 iptables-persistent

SERVER_IP=$(curl -s4 ifconfig.me)

echo "=== 2. Установка WireGuard (VPN) ==="
curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
chmod +x wireguard-install.sh

export AUTO_INSTALL=y
export CLIENT_NAME="MyPC"
export PASS=1
./wireguard-install.sh

echo "=== 3. Настройка интернета (маршрутизации) ==="
sysctl -w net.ipv4.ip_forward=1
INTF=$(ip route | grep default | awk '{print $5}' | head -n 1)

# Жесткие правила для хостингов со строгим NAT
iptables -t nat -A POSTROUTING -o $INTF -j MASQUERADE
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT

echo "=== 4. Установка Python MTProxy для Telegram ==="
systemctl stop mtproxy 2>/dev/null
rm -rf /opt/mtprotoproxy
git clone https://github.com/alexbers/mtprotoproxy.git /opt/mtprotoproxy

# Генерируем правильный 32-значный HEX-ключ
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
# Открываем порты для VPN и Telegram
iptables -I INPUT -p udp --dport 51820 -j ACCEPT
iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
ufw allow 51820/udp 2>/dev/null
ufw allow 8443/tcp 2>/dev/null

echo "=== 6. Защита сервера (Смена порта SSH на 8922) ==="
# Открываем новый порт для SSH
iptables -I INPUT -p tcp --dport 8922 -j ACCEPT
ufw allow 8922/tcp 2>/dev/null

# Меняем порт в конфигурации SSH
sed -i 's/^#*Port 22/Port 8922/' /etc/ssh/sshd_config
grep -q "^Port 8922" /etc/ssh/sshd_config || echo "Port 8922" >> /etc/ssh/sshd_config

# Перезапускаем SSH
systemctl restart sshd
systemctl restart ssh 2>/dev/null

# Сохраняем все правила фаервола навсегда
netfilter-persistent save 2>/dev/null

echo ""
echo "=================================================="
echo "✅ СЕРВЕР УСПЕШНО НАСТРОЕН И ЗАЩИЩЕН!"
echo "=================================================="
echo "🛡️ ВАЖНО: ПОРТ SSH ИЗМЕНЕН НА 8922"
echo "Теперь для входа на сервер используйте команду:"
echo "ssh -p 8922 root@${SERVER_IP}"
echo "=================================================="
echo "🌐 ВАШ КONFIG ДЛЯ WIREGUARD:"
echo "--------------------------------------------------"
cat /root/MyPC.conf
echo "--------------------------------------------------"
echo ""
echo "✈️ ВАШ ПРОКСИ ДЛЯ TELEGRAM:"
# Формируем готовую ссылку FakeTLS
TG_LINK="tg://proxy?server=${SERVER_IP}&port=8443&secret=ee${TG_SECRET}7777772e676f6f676c652e636f6d"
echo "$TG_LINK"
echo "=================================================="