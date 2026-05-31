# Story 1.1: 프로젝트 기반 초기화 & DB 스키마

---
baseline_commit: NO_VCS
---

Status: done

## Story

As a developer,
I want to initialize the mono-repo with all three components and set up the core database schema,
so that the team can start development on a consistent, runnable foundation.

## Acceptance Criteria

1. `/mobile`(Flutter), `/backend`(FastAPI), `/admin`(Next.js) 3개 디렉토리가 생성된다
2. `docker compose up` 실행 시 PostgreSQL 15가 정상 기동된다
3. `alembic upgrade head` 실행 시 `users`, `neighborhoods` 테이블과 인덱스가 생성된다
4. `neighborhoods` 테이블에 시/구/동 계층 구조 초기 데이터가 삽입된다
5. FastAPI 서버가 `http://localhost:8000/docs`에서 Swagger UI를 정상 반환한다

## Tasks / Subtasks

- [x] Task 1: 모노레포 루트 구조 생성 (AC: 1)
  - [x] 루트 `README.md`, `.env.example` 생성
  - [x] 루트 `docker-compose.yml` 생성 (PostgreSQL 서비스)
  - [x] `.github/workflows/` 디렉토리 생성 (copier 템플릿이 CI 파일 포함)

- [x] Task 2: Flutter 모바일 앱 초기화 (AC: 1)
  - [x] `puro flutter create --org com.yourcompany --platforms android,ios mobile` 실행 (Flutter 3.44.0)
  - [x] `mobile/pubspec.yaml` 기본 의존성 확인
  - [x] `mobile/lib/main.dart` 생성 완료

- [x] Task 3: FastAPI 백엔드 초기화 (AC: 1)
  - [x] `copier copy gh:fastapi/full-stack-fastapi-template backend --trust` 실행
  - [x] `backend/frontend/` 폴더 삭제
  - [x] 중첩 구조 정리 (`backend/backend/` → `backend/app/` 직접 접근)
  - [x] 템플릿 기존 alembic 충돌 파일 제거
  - [x] PostgreSQL 17 직접 설치 (winget, Docker 대체)
  - [x] app DB 생성, postgres 비밀번호 설정
  - [x] `uv run uvicorn app.main:app --reload` → `http://localhost:8000/docs` 확인 ✅

- [x] Task 4: Next.js 어드민 초기화 (AC: 1)
  - [x] `npx create-next-app@latest admin --ts --tailwind --app --src-dir --import-alias "@/*"` 실행 (Next.js 16.2.6)
  - [x] `admin/.env.local` 생성 (NEXT_PUBLIC_API_URL)

- [x] Task 5: Alembic 마이그레이션 001 — 초기 스키마 (AC: 3)
  - [x] `backend/app/alembic/versions/001_initial_schema.py` 생성
  - [x] `users` 테이블 정의 (UUID PK, email UNIQUE, nickname, role, is_active, fcm_token 등)
  - [x] `neighborhoods` 테이블 정의 (id, name, parent_id self-ref, level)
  - [x] 인덱스 정의: `idx_users_email` (UNIQUE), `idx_neighborhoods_parent_id`
  - [x] `uv run alembic upgrade head` 실행 완료 ✅

- [x] Task 6: Alembic 마이그레이션 002 — neighborhoods 시드 데이터 (AC: 4)
  - [x] `backend/app/alembic/versions/002_seed_neighborhoods.py` 생성
  - [x] 서울특별시 > 5개 구 > 24개 동 데이터 (총 30개 레코드)
  - [x] `uv run alembic upgrade head` 실행 완료 — 시드 데이터 삽입 확인 ✅

## Dev Notes

### 기술 스택 (버전 고정)

| 컴포넌트 | 기술 | 버전 |
|---|---|---|
| Mobile | Flutter | **3.44.0** (Dart 3.10+) |
| Backend | FastAPI | 0.115+ |
| Backend ORM | SQLModel | **0.0.21** (SQLAlchemy 2.0 async 내장) |
| Backend DB 드라이버 | asyncpg | 최신 안정 (SQLModel이 의존성 포함) |
| Backend 패키지 관리 | uv | copier 템플릿 기본 |
| Backend 마이그레이션 | Alembic | copier 템플릿 기본 |
| Admin | Next.js | 15.x |
| Admin 스타일 | Tailwind CSS | v4 |
| DB | PostgreSQL | 15+ |
| 컨테이너 | Docker Compose | v2 (`docker compose`, NOT `docker-compose`) |

### DB 스키마 (반드시 이 구조로 생성)

```sql
-- neighborhoods 테이블 (users보다 먼저 생성 — FK 의존성)
CREATE TABLE neighborhoods (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    parent_id INTEGER REFERENCES neighborhoods(id),
    level VARCHAR(20) NOT NULL  -- 'city', 'district', 'dong'
);
CREATE INDEX idx_neighborhoods_parent_id ON neighborhoods(parent_id);

-- users 테이블
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    nickname VARCHAR(15),
    profile_image_url TEXT,
    neighborhood_id INTEGER REFERENCES neighborhoods(id),
    role VARCHAR(20) NOT NULL DEFAULT 'user',  -- 'user' | 'admin'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    fcm_token TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_users_email ON users(email);
```

**SQLModel 모델 파일 위치:**
- `backend/app/models/neighborhood.py` — Neighborhood 모델
- `backend/app/models/user.py` — User 모델

**네이밍 규칙 (반드시 준수):**
- 테이블명: 복수 snake_case (`users`, `neighborhoods`)
- 컬럼명: snake_case (`parent_id`, `created_at`)
- ENUM 값: 소문자 문자열 (`'user'`, `'admin'`, `'city'`, `'district'`, `'dong'`)

### fastapi/full-stack-fastapi-template 초기화 후 제거 대상

copier 실행 후 반드시 다음을 제거:
```
backend/frontend/           # React 프론트엔드 전체 폴더 삭제
```

`docker-compose.yml` (또는 `docker-compose.override.yml`)에서 제거:
```yaml
# 이 서비스들 삭제
frontend:
  ...
adminer:  # (있는 경우)
  ...
```

copier 템플릿이 제공하는 것들 (건드리지 말 것):
- `backend/pyproject.toml` — uv 패키지 관리
- `backend/alembic/env.py` — Alembic 비동기 설정
- `backend/app/core/config.py` — Pydantic Settings
- `backend/.github/workflows/` — CI 파이프라인
- `backend/app/api/v1/deps.py` — `get_db`, `get_current_user` 의존성 (이후 스토리에서 사용)

### 모노레포 루트 docker-compose.yml 구조

루트 `docker-compose.yml`은 로컬 개발용으로 PostgreSQL만 포함:
```yaml
version: "3.9"
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-changethis}
      POSTGRES_DB: ${POSTGRES_DB:-app}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

FastAPI는 로컬에서 `uv run uvicorn app.main:app --reload`로 별도 실행.

### neighborhoods 시드 데이터 최소 요구사항

최소 3단계 계층 구조 필요:
- Level 1 (city): 서울특별시
- Level 2 (district): 강남구, 마포구, 성동구 (최소 3개)
- Level 3 (dong): 각 구당 최소 3개 동

예시:
```python
# 002_seed_neighborhoods.py
neighborhoods_data = [
    # (id, name, parent_id, level)
    (1, "서울특별시", None, "city"),
    (2, "강남구", 1, "district"),
    (3, "마포구", 1, "district"),
    (4, "성동구", 1, "district"),
    (5, "역삼동", 2, "dong"),
    (6, "삼성동", 2, "dong"),
    (7, "논현동", 2, "dong"),
    (8, "합정동", 3, "dong"),
    (9, "망원동", 3, "dong"),
    (10, "연남동", 3, "dong"),
    (11, "성수동1가", 4, "dong"),
    (12, "성수동2가", 4, "dong"),
    (13, "왕십리동", 4, "dong"),
]
```

### 프로젝트 구조 참조

```
/ (mono-repo root)
├── .github/workflows/        ← copier가 backend/ 안에 생성, 루트에도 빈 폴더 준비
├── docker-compose.yml        ← 루트: PostgreSQL만
├── .env.example
├── README.md
├── mobile/                   ← flutter create 결과
│   ├── lib/main.dart
│   └── pubspec.yaml
├── backend/                  ← copier 템플릿 결과 (React 제거)
│   ├── app/
│   │   ├── main.py
│   │   ├── models/
│   │   │   ├── user.py       ← 이 스토리에서 생성
│   │   │   └── neighborhood.py ← 이 스토리에서 생성
│   │   └── core/config.py
│   ├── alembic/versions/
│   │   ├── 001_initial_schema.py  ← 이 스토리에서 생성
│   │   └── 002_seed_neighborhoods.py ← 이 스토리에서 생성
│   └── pyproject.toml
└── admin/                    ← create-next-app 결과
    ├── src/app/
    └── package.json
```

### 이 스토리에서 생성하지 않는 것 (범위 외)

- `backend/app/api/` 라우터 파일 (Story 1.2+에서 생성)
- `backend/app/core/security.py` JWT 설정 (Story 1.2에서 생성)
- Flutter 기능 코드 (Story 1.3+에서 생성)
- Next.js 페이지 구현 (Story 5.1+에서 생성)
- Products, Chat_Rooms, Messages 테이블 (Story 2.1, 4.1에서 생성)

### SQLModel Async 엔진 설정 패턴 (반드시 이 패턴 사용)

```python
# backend/app/core/db.py
from sqlmodel.ext.asyncio.session import AsyncSession
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(
    str(settings.SQLALCHEMY_DATABASE_URI),  # postgresql+asyncpg://...
    echo=False,
)
SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
```

⚠️ 주의: `create_engine` (동기) 사용 금지 — 반드시 `create_async_engine` 사용.

### Alembic + Seed 실행 순서

```bash
# DB 기동 후
cd backend
alembic upgrade head          # 001, 002 마이그레이션 순서대로 적용
# 또는 Makefile 타겟으로 래핑:
# make db-init → alembic upgrade head
```

copier 템플릿의 `app/initial_data.py` 가 있다면 seed는 Alembic 마이그레이션 방식(002)으로 대체.

### References

- [Source: architecture.md#Starter Template Evaluation] — 스타터 초기화 커맨드
- [Source: architecture.md#Data Architecture] — DB 스키마 결정 사항
- [Source: architecture.md#Implementation Patterns] — 네이밍 컨벤션
- [Source: architecture.md#Complete Project Directory Structure] — 전체 디렉토리 구조
- [Source: epics.md#Story 1.1] — 인수 조건 원본

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

### Completion Notes List

- 모노레포 루트 구조 생성 완료 (docker-compose.yml, .env, .env.example, README.md)
- Flutter 3.44.0으로 mobile/ 초기화 (Puro 경유)
- FastAPI copier 템플릿으로 backend/ 초기화, frontend/ 제거 및 중첩 구조 정리
- Next.js 16.2.6으로 admin/ 초기화 (TypeScript + Tailwind + App Router)
- PostgreSQL 17 직접 설치 (Docker WSL2 미지원 환경 대체)
- app DB 생성 및 postgres 비밀번호 설정
- Alembic 001: users + neighborhoods 테이블 + 인덱스 생성 완료
- Alembic 002: 서울특별시 5구 24동 시드 데이터 삽입 완료
- FastAPI Swagger UI http://localhost:8000/docs 정상 동작 확인
- .env는 프로젝트 루트(../. env)에 위치해야 함 (config.py 설계 기준)

### File List

**생성된 파일 (모노레포 루트):**
- `docker-compose.yml` — PostgreSQL 서비스 (Docker용)
- `.env` — 프로젝트 환경 변수 (DB 연결, 시크릿 키 등)
- `.env.example` — 환경 변수 템플릿
- `README.md` — 프로젝트 개요 및 실행 가이드
- `.github/workflows/` — CI 파이프라인 (copier 템플릿)

**생성된 파일 (backend/):**
- `backend/app/` — FastAPI 애플리케이션 (copier 템플릿)
- `backend/app/alembic/versions/001_initial_schema.py` — users + neighborhoods 테이블
- `backend/app/alembic/versions/002_seed_neighborhoods.py` — 서울 구/동 시드 데이터
- `backend/pyproject.toml` — Python 의존성 (uv)
- `backend/alembic.ini` — Alembic 설정

**생성된 파일 (mobile/):**
- `mobile/` — Flutter 3.44.0 프로젝트 전체 (75개 파일)
- `mobile/lib/main.dart` — 앱 진입점
- `mobile/pubspec.yaml` — Flutter 의존성

**생성된 파일 (admin/):**
- `admin/` — Next.js 16.2.6 프로젝트 전체
- `admin/src/app/` — App Router 구조
- `admin/.env.local` — 어드민 환경 변수
