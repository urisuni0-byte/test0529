# 배포 가이드

두 가지 방법 중 선택:
- **A. Docker 없이** (권장 — 간단, `deploy/` 폴더 스크립트 사용)
- **B. Docker Compose** (아래 섹션)

---

## 방법 A: Docker 없이 배포 (systemd + nginx)

### 로컬 테스트 (바로 실행)

```bash
# 터미널 1 — 백엔드 (http://localhost:8000/docs)
cd backend && uv run fastapi run app/main.py --reload --port 8000

# 터미널 2 — 어드민 (http://localhost:3000)
cd admin && npm run dev
```

### VPS 배포

```bash
# 1. VPS에서 초기 설정 (최초 1회)
sudo bash deploy/setup-vps.sh

# 2. .env 편집
cp .env.example .env && nano .env

# 3. 배포 (업데이트 시에도 동일)
sudo bash deploy/deploy-app.sh
```

서비스 관리:
```bash
systemctl status marketplace-backend marketplace-admin
systemctl restart marketplace-backend
journalctl -u marketplace-backend -f    # 로그
```

---

## 방법 B: Docker Compose

아키텍처: Docker Compose 단일 VPS (Oracle Free Tier / Hetzner CX22)

## 사전 요구사항

- Ubuntu 22.04 VPS
- 도메인 2개: `api.yourdomain.com`, `admin.yourdomain.com`
- Cloudflare R2 버킷 (이미지 스토리지)
- Google Cloud OAuth 2.0 클라이언트 ID
- Firebase 프로젝트 (FCM 푸시 알림)

---

## 1. VPS 초기 설정

```bash
# Docker + Docker Compose 설치
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# 방화벽 설정
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (Caddy → HTTPS 리다이렉트)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 443/udp   # HTTP/3
sudo ufw enable
```

---

## 2. 코드 배포

```bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git /opt/app
cd /opt/app
```

---

## 3. 환경변수 설정

```bash
cp .env.example .env
nano .env
```

`.env`에서 반드시 변경해야 할 항목:

| 변수 | 설명 |
|---|---|
| `DOMAIN` | 실제 도메인 (e.g. `example.com`) |
| `SECRET_KEY` | `python3 -c "import secrets; print(secrets.token_urlsafe(32))"` |
| `POSTGRES_PASSWORD` | 강력한 DB 비밀번호 |
| `FIRST_SUPERUSER` | 어드민 로그인 이메일 |
| `FIRST_SUPERUSER_PASSWORD` | 어드민 로그인 비밀번호 |
| `GOOGLE_CLIENT_ID` | Google Cloud Console OAuth 2.0 클라이언트 ID |
| `R2_ACCOUNT_ID` | Cloudflare 계정 ID |
| `R2_ACCESS_KEY_ID` | R2 API 토큰 접근 키 |
| `R2_SECRET_ACCESS_KEY` | R2 API 토큰 비밀 키 |
| `R2_PUBLIC_URL` | R2 버킷 공개 URL |
| `BACKEND_CORS_ORIGINS` | `"https://admin.yourdomain.com"` |

---

## 4. DNS 설정

도메인 DNS에 A 레코드 2개 추가 (VPS IP):

```
api.yourdomain.com    A    <VPS_IP>
admin.yourdomain.com  A    <VPS_IP>
```

---

## 5. Caddyfile 도메인 수정

`Caddyfile`은 환경변수 `$DOMAIN`을 자동으로 읽으므로 `.env`의 `DOMAIN`만 바꾸면 됩니다.

---

## 6. Firebase 서비스 계정 키 설정

```bash
# Firebase Console → 프로젝트 설정 → 서비스 계정 → JSON 키 다운로드
mkdir -p /opt/app/secrets
cp /path/to/firebase-key.json /opt/app/secrets/firebase_key.json
chmod 600 /opt/app/secrets/firebase_key.json
```

`docker-compose.prod.yml`의 backend 서비스에 볼륨 마운트:
```yaml
volumes:
  - ./secrets/firebase_key.json:/run/secrets/firebase_key.json:ro
```

---

## 7. 빌드 & 실행

```bash
# 처음 배포
docker compose -f docker-compose.prod.yml up -d --build

# 로그 확인
docker compose -f docker-compose.prod.yml logs -f backend
docker compose -f docker-compose.prod.yml logs -f caddy

# 상태 확인
docker compose -f docker-compose.prod.yml ps
```

Caddy가 자동으로 Let's Encrypt 인증서를 발급합니다 (1~2분 소요).

---

## 8. 배포 확인

```bash
# 백엔드 API Docs
curl https://api.yourdomain.com/docs

# 어드민 패널
curl https://admin.yourdomain.com

# DB 마이그레이션 상태
docker compose -f docker-compose.prod.yml exec backend alembic current
```

---

## 9. 업데이트 배포 (롤링)

```bash
cd /opt/app
git pull origin main

# 변경된 서비스만 재빌드
docker compose -f docker-compose.prod.yml up -d --build backend
# 또는 전체
docker compose -f docker-compose.prod.yml up -d --build
```

---

## 10. 모바일 앱 릴리즈 빌드

### Android (Play Console 내부 트랙)

```bash
cd mobile

# 릴리즈 서명 키 생성 (최초 1회)
keytool -genkey -v -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# android/key.properties 파일 생성
cat > android/key.properties << EOF
storePassword=<PASSWORD>
keyPassword=<PASSWORD>
keyAlias=upload
storeFile=../app/upload-keystore.jks
EOF

# 릴리즈 빌드 (API URL을 프로덕션으로 교체 후)
flutter build appbundle --release

# 빌드 결과물
# build/app/outputs/bundle/release/app-release.aab
```

### iOS (TestFlight)

```bash
# Xcode에서 서명 설정 후
flutter build ipa --release

# Xcode Organizer 또는 Transporter로 TestFlight 업로드
# build/ios/ipa/*.ipa
```

### Flutter 프로덕션 API URL 설정

`mobile/lib/core/network/api_client.dart`에서 API 베이스 URL을 변경:
```dart
// 개발
const baseUrl = 'http://localhost:8000/api/v1';
// 프로덕션
const baseUrl = 'https://api.yourdomain.com/api/v1';
```

또는 `--dart-define`으로 빌드 시 주입:
```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
```

---

## 운영

### 로그 조회
```bash
docker compose -f docker-compose.prod.yml logs -f [service]
# services: backend, admin, db, caddy
```

### DB 백업
```bash
docker compose -f docker-compose.prod.yml exec db \
  pg_dump -U $POSTGRES_USER $POSTGRES_DB > backup_$(date +%Y%m%d).sql
```

### DB 복원
```bash
cat backup_20260601.sql | docker compose -f docker-compose.prod.yml exec -T db \
  psql -U $POSTGRES_USER $POSTGRES_DB
```

### 컨테이너 재시작
```bash
docker compose -f docker-compose.prod.yml restart backend
```
