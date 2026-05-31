# 중고거래 모바일 플랫폼 MVP

Flutter + FastAPI + PostgreSQL + Next.js(어드민) 기반 중고거래 앱.

## 구조

```
/
├── mobile/     # Flutter (iOS/Android)
├── backend/    # FastAPI + PostgreSQL
└── admin/      # Next.js 어드민 패널
```

## 빠른 시작

### 1. 환경 변수 설정
```bash
cp .env.example .env
# .env 파일을 열어 필요한 값 입력
```

### 2. DB 기동
```bash
docker compose up -d
```

### 3. 백엔드 실행
```bash
cd backend
uv sync
alembic upgrade head
uv run uvicorn app.main:app --reload
# → http://localhost:8000/docs
```

### 4. 어드민 실행
```bash
cd admin
npm install
npm run dev
# → http://localhost:3000
```

### 5. Flutter 앱 실행
```bash
cd mobile
flutter pub get
flutter run
```

## 기술 스택

| 컴포넌트 | 기술 |
|---|---|
| 모바일 | Flutter 3.44.0 |
| 백엔드 | FastAPI 0.115+ + PostgreSQL 15 |
| ORM | SQLModel 0.0.21 (SQLAlchemy 2.0 async) |
| 어드민 | Next.js 15 |
| 푸시알림 | FCM (Firebase Cloud Messaging) |
| 이미지 스토리지 | Cloudflare R2 |
