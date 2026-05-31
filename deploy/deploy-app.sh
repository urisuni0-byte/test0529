#!/bin/bash
# 앱 배포 스크립트 — 처음 배포 및 업데이트 모두 사용
# 실행: bash deploy/deploy-app.sh
set -e

APP_DIR="/opt/app"
REPO_URL="${REPO_URL:-}"  # 예: https://github.com/yourname/yourrepo.git

echo "=== 코드 배포 ==="
if [ -d "$APP_DIR/.git" ]; then
    cd $APP_DIR && git pull origin main
else
    if [ -z "$REPO_URL" ]; then
        echo "REPO_URL 환경변수를 설정하거나 코드를 $APP_DIR 에 직접 복사하세요"
        exit 1
    fi
    git clone $REPO_URL $APP_DIR
fi

cd $APP_DIR

echo "=== .env 확인 ==="
if [ ! -f .env ]; then
    cp .env.example .env
    echo "⚠️  .env 파일을 편집하세요: nano $APP_DIR/.env"
    exit 1
fi

# .env 로드
set -a; source .env; set +a

echo "=== 백엔드 의존성 설치 ==="
cd $APP_DIR/backend
uv sync --frozen --no-dev

echo "=== DB 마이그레이션 ==="
uv run alembic upgrade head

echo "=== 초기 데이터 생성 (어드민 계정) ==="
uv run python app/initial_data.py

echo "=== 어드민 빌드 ==="
cd $APP_DIR/admin
npm ci
API_URL="https://api.${DOMAIN}/api/v1" npm run build

echo "=== systemd 서비스 등록 ==="
cp $APP_DIR/deploy/backend.service /etc/systemd/system/marketplace-backend.service
cp $APP_DIR/deploy/admin.service /etc/systemd/system/marketplace-admin.service

# .env 경로를 서비스 파일에 반영
sed -i "s|APP_DIR_PLACEHOLDER|$APP_DIR|g" /etc/systemd/system/marketplace-backend.service
sed -i "s|APP_DIR_PLACEHOLDER|$APP_DIR|g" /etc/systemd/system/marketplace-admin.service

systemctl daemon-reload
systemctl enable marketplace-backend marketplace-admin
systemctl restart marketplace-backend marketplace-admin

echo "=== nginx 설정 ==="
envsubst '$DOMAIN' < $APP_DIR/deploy/nginx.conf > /etc/nginx/sites-available/marketplace
ln -sf /etc/nginx/sites-available/marketplace /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

echo "=== SSL 인증서 발급 ==="
certbot --nginx -d api.$DOMAIN -d admin.$DOMAIN --non-interactive --agree-tos \
    --email ${FIRST_SUPERUSER:-admin@example.com} --redirect || \
    echo "⚠️  certbot 실패 — DNS가 설정되었는지 확인하세요"

echo ""
echo "✅ 배포 완료"
echo "  API:   https://api.$DOMAIN/docs"
echo "  Admin: https://admin.$DOMAIN"
