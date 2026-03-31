#!/bin/bash

REPO_URL="https://github.com/laijara/VpsSettings.git"
WORKDIR="/root/vpn-server"

echo "=== 1. Подготовка среды и загрузка зависимостей ==="
apt-get update && apt-get install git curl ufw -y

# Скрипт скачивает репозиторий со всеми .tar образами на жесткий диск
rm -rf $WORKDIR
git clone $REPO_URL $WORKDIR
cd $WORKDIR

echo "=== 2. Настраиваем Фаервол ==="
ufw allow 22/tcp
ufw allow 2053/tcp
ufw allow 2096/tcp
ufw allow 443/tcp
ufw allow 8443/tcp
ufw enable

echo "=== 3. Устанавливаем Docker ==="
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
apt-get install docker-compose-plugin -y

echo "=== 4. Загружаем локальные образы (Offline Mode) ==="
# Распаковываем образы, которые только что скачали через git clone
docker load -i images/3x-ui.tar
docker load -i images/mtproxy.tar

echo "=== 5. Генерируем архитектуру (docker-compose.yml) ==="
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    restart: always
    network_mode: host

  mtproxy:
    image: nineseconds/mtg:1
    container_name: mtproxy
    restart: always
    network_mode: host
    command: run -b 0.0.0.0:8443 ${MTG_SECRET}
EOF

echo "=== 6. Инициализация и Запуск ==="
# Генерируем секрет через наш загруженный локальный образ
export MTG_SECRET=$(docker run --rm nineseconds/mtg:1 generate-secret tls -c google.com)
echo "MTG_SECRET=${MTG_SECRET}" > .env

docker compose up -d

echo "========================================"
PUBLIC_IP=$(curl -s ifconfig.me)
echo "✅ ГОТОВО! Сервер развернут из твоих Git-образов."
echo "Панель 3x-ui: http://${PUBLIC_IP}:2053 (admin/admin)"
echo "Telegram: tg://proxy?server=${PUBLIC_IP}&port=8443&secret=${MTG_SECRET}"