#!/bin/bash
# VPS 초기 설정 스크립트 (Ubuntu 22.04)
# 실행: sudo bash setup-vps.sh
set -e

APP_DIR="/opt/app"
APP_USER="appuser"

echo "=== 시스템 패키지 업데이트 ==="
apt-get update && apt-get upgrade -y

echo "=== 필수 패키지 설치 ==="
apt-get install -y curl git nginx certbot python3-certbot-nginx \
    build-essential libpq-dev postgresql postgresql-contrib

echo "=== Node.js 22 설치 ==="
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

echo "=== uv 설치 (Python 패키지 매니저) ==="
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

echo "=== PM2 설치 (Next.js 프로세스 관리) ==="
npm install -g pm2

echo "=== 앱 전용 유저 생성 ==="
id -u $APP_USER &>/dev/null || useradd -m -s /bin/bash $APP_USER

echo "=== 앱 디렉토리 생성 ==="
mkdir -p $APP_DIR
chown $APP_USER:$APP_USER $APP_DIR

echo "=== PostgreSQL DB 생성 ==="
# .env의 값을 여기서 직접 설정하거나 스크립트 파라미터로 받으세요
DB_NAME="${POSTGRES_DB:-marketplace}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASS="${POSTGRES_PASSWORD:-changeme123}"

sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true

echo "=== 방화벽 설정 ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "=== 완료 ==="
echo "다음 단계: deploy/deploy-app.sh 실행"
