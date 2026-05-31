---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
status: 'complete'
completedAt: '2026-05-29'
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-test0529-2026-05-29/prd.md
workflowType: 'architecture'
project_name: 'test0529'
user_name: 'User'
date: '2026-05-29'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
33개 FR, 9개 기능 그룹. 핵심 난이도는 WebSocket 기반 실시간 채팅과 FCM 푸시 알림의 비동기 파이프라인에 있다. 어드민 패널은 동일 백엔드를 사용하되 role=admin 클레임으로 접근 제어.

**Non-Functional Requirements:**
- 채팅 메시지 수신 지연 < 2초 (WebSocket SLA)
- 피드 초기 로딩 < 3초
- 크래시 없는 세션 ≥ 95%
- JWT 액세스 토큰 15분 / 리프레시 30일
- 이미지 장당 최대 1MB (클라이언트 압축)
- iOS 14+ / Android 10+ Flutter 단일 코드베이스

**Scale & Complexity:**
- Primary domain: Full-stack (Mobile API + Admin)
- Complexity level: Medium-High
- Estimated architectural components: 12+

### Technical Constraints & Dependencies

- FastAPI (Python 3.11+) + PostgreSQL 15+
- Flutter 단일 코드베이스 — 플랫폼별 네이티브 코드 금지
- FCM 필수 (Firebase 프로젝트 설정 선행 필요, OQ-3)
- 파일 스토리지 미결 (OQ-6) — 인터페이스 추상화 선행 설계
- 동네 목록 데이터 소스 미결 (OQ-4) — 착수 차단 사안

### Cross-Cutting Concerns Identified

1. **인증/인가**: JWT 미들웨어 + role 기반 접근 제어
2. **WebSocket 연결 관리**: 채팅방별 구독 레지스트리
3. **에러 처리 / 오프라인 대응**: Flutter + WebSocket 재연결
4. **파일 스토리지 추상화**: OQ-6 해소 전 인터페이스 우선 정의
5. **비동기 FCM 발송**: 메시지 저장과 알림 발송 분리

---

## Starter Template Evaluation

### Primary Technology Domain

Full-stack (Mobile + API + Admin) — 3개 독립 컴포넌트, 모노레포 구조

### 모노레포 구조

```
/ (project root)
├── mobile/     (Flutter)
├── backend/    (FastAPI + PostgreSQL)
└── admin/      (Next.js)
```

### Selected Starters

**mobile/ — Flutter v3.38+**

```bash
flutter create --org com.yourcompany --empty --platforms android,ios mobile
```

Architectural decisions made:
- Swift(iOS) / Kotlin(Android) 네이티브 레이어 (변경 불필요)
- `lib/` 하위 feature-first 구조 직접 구성 (`presentation/`, `domain/`, `data/`)
- Dart 3.10+

**backend/ — FastAPI v0.115+ (공식 full-stack 템플릿)**

```bash
copier copy https://github.com/fastapi/full-stack-fastapi-template backend --trust
# 이후 frontend/ 폴더 제거, docker-compose에서 frontend 서비스 제거
```

Architectural decisions made:
- Python 3.12+ / uv 패키지 관리
- SQLModel (SQLAlchemy 2.0 async) + asyncpg + PostgreSQL 15+
- Alembic 마이그레이션
- JWT 인증 (python-jose)
- Docker Compose (개발/프로덕션)
- GitHub Actions CI

**admin/ — Next.js v15.x**

```bash
npx create-next-app@latest admin --ts --tailwind --app --src-dir --import-alias "@/*"
```

Architectural decisions made:
- App Router + Server Components
- TypeScript
- Tailwind CSS v4
- ESLint

**Note:** 각 컴포넌트 초기화는 첫 번째 구현 스토리에 포함.

---

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (착수 차단):**
- 동네 목록 데이터 구조 → DB 테이블 (`neighborhoods`) 방식으로 결정
- 이미지 스토리지 → Cloudflare R2 (S3 호환 API)
- Flutter 상태 관리 → Riverpod 2.x

**Important Decisions (아키텍처 형태 결정):**
- 채팅 읽음 처리 → `last_read_at` 타임스탬프 방식
- WebSocket 연결 관리 → `ConnectionManager` 클래스 레지스트리
- FCM 발송 → FastAPI `BackgroundTasks` 비동기 처리
- 배포 환경 → Docker Compose 단일 서버 (VPS)

**Deferred (Post-MVP):**
- 카카오 로그인 (v1.1)
- Redis 캐싱 (사용자 증가 후)
- 수평 확장 / 로드 밸런서

### Data Architecture

| 결정 | 선택 | 근거 |
|---|---|---|
| ORM | SQLModel (SQLAlchemy 2.0 async) + asyncpg | Copier 템플릿 기본; async WebSocket 서버와 일관성 |
| 마이그레이션 | Alembic | Copier 템플릿 기본 |
| 동네 목록 | `neighborhoods` DB 테이블 (시/구/동 3단계) | 피드 필터 쿼리 단순화, 위치 기능 확장 대비; 초기 데이터는 Alembic seed |
| 채팅 읽음 처리 | `chat_room_members.last_read_at TIMESTAMP` | 구현 단순성 우선; 미읽음 수 = `COUNT(messages WHERE created_at > last_read_at)` |
| 이미지 스토리지 | Cloudflare R2 | 무료 10GB/월, 이그레스 무료, S3 호환 API → 추후 교체 용이 |
| 캐싱 | 없음 (MVP) | 사용자 규모 확인 후 Redis 도입 검토 |

### Authentication & Security

| 결정 | 선택 | 근거 |
|---|---|---|
| 인증 방식 | JWT (액세스 15분 / 리프레시 30일) | Copier 템플릿 기본 (python-jose) |
| OAuth 제공자 | Google OAuth 2.0 (MVP) | 카카오는 v1.1 추가 |
| Admin 역할 분리 | `users.role ENUM('user', 'admin')` | JWT role 클레임으로 미들웨어에서 검사 |
| API 인증 미들웨어 | FastAPI `Depends(get_current_user)` | 전체 보호 엔드포인트에 일관 적용 |

### API & Communication Patterns

| 결정 | 선택 | 근거 |
|---|---|---|
| REST 버전닝 | `/api/v1/` prefix | 하위 호환성 확보 |
| WebSocket 엔드포인트 | `/ws/chat/{room_id}` | 채팅방 단위 연결 격리 |
| WebSocket 연결 관리 | `ConnectionManager` 클래스 | 채팅방별 연결 레지스트리, 브로드캐스트 메서드 포함 |
| FCM 발송 타이밍 | FastAPI `BackgroundTasks` | 메시지 저장 후 논블로킹 발송, API 응답 지연 없음 |
| API 문서화 | FastAPI 자동 Swagger UI (`/docs`) | 별도 작업 없이 즉시 활용 |
| 에러 응답 형식 | `{"detail": "...", "code": "ERROR_CODE"}` | FastAPI 기본 + code 필드 추가 |

### Frontend Architecture

| 결정 | 선택 | 근거 |
|---|---|---|
| Flutter 상태 관리 | Riverpod 2.x (`flutter_riverpod` + `riverpod_annotation`) | 선언적, 테스트 용이, Flutter 공식 권장; 중간 규모에 적합 |
| Flutter 레이어 구조 | feature-first (`presentation/`, `domain/`, `data/`) | 기능 단위 응집도 유지 |
| Next.js 데이터 페칭 | Server Components + `fetch` | 어드민 CRUD에 충분; React Query 오버엔지니어링 |
| Next.js 인증 | JWT 쿠키 (`httpOnly`) + middleware route protection | 어드민 전용, 서버 사이드 검증 |

### Infrastructure & Deployment

| 결정 | 선택 | 근거 |
|---|---|---|
| 배포 환경 | Docker Compose 단일 서버 (VPS) | Copier 템플릿 포함; MVP 규모에 충분 |
| VPS 추천 | Oracle Free Tier / Hetzner CX22 | 비용 최소화 |
| 모바일 배포 | TestFlight (iOS) + Play Console 내부 트랙 (Android) | MVP 검증용 |
| 환경 변수 | `.env` + Pydantic Settings | Copier 템플릿 기본 |
| CI/CD | GitHub Actions | Copier 템플릿 기본 |
| 로깅 | `structlog` + stdout → Docker log driver | 단순, 추후 ELK 확장 가능 |

### Decision Impact Analysis

**구현 순서 의존성:**
1. `neighborhoods` 테이블 + seed 데이터 → 피드 API 착수 가능
2. JWT 인증 미들웨어 → 모든 보호 엔드포인트 착수 가능
3. `ConnectionManager` 구현 → 실시간 채팅 착수 가능
4. Cloudflare R2 설정 + 추상 인터페이스 → 이미지 업로드 착수 가능
5. FCM Firebase 프로젝트 설정 → 푸시 알림 착수 가능

**크로스 컴포넌트 의존성:**
- Flutter ↔ FastAPI: REST API 계약 (OpenAPI spec) 공유
- Flutter ↔ FCM: `google-services.json` / `GoogleService-Info.plist` 설정
- Next.js ↔ FastAPI: `/api/v1/admin/*` 전용 엔드포인트 + `role=admin` JWT
- FastAPI ↔ R2: `boto3` S3 호환 클라이언트 (`STORAGE_BACKEND` 추상화로 교체 가능)

---

## Architecture Validation Results

### Coherence Validation ✅

모든 기술 결정이 상호 호환됨. Flutter 3.38 + Riverpod 2.x, FastAPI + SQLModel async + asyncpg, Next.js 15 App Router + TypeScript + Tailwind, JWT + FastAPI Depends 패턴 — 충돌 없음. snake_case API JSON ↔ Flutter Dart 직접 매핑으로 변환 레이어 불필요.

### Requirements Coverage Validation ✅

**FR Coverage:** 33/33 FRs 완전 커버

| FR 그룹 | 위치 |
|---|---|
| FR-1~4 인증 | `routes/auth.py` + JWT 미들웨어 |
| FR-5~6 동네설정 | `routes/neighborhoods.py` + DB 테이블 |
| FR-7~10 피드 | `routes/products.py` + 페이지네이션 |
| FR-11~15 상품상세 | `routes/products.py` + `crud/product.py` |
| FR-16~19 상품등록 | `routes/products.py` + `services/storage.py` |
| FR-20~24 채팅 | `routes/chat.py` + `services/websocket.py` |
| FR-25~26 푸시알림 | `services/fcm.py` + BackgroundTasks |
| FR-27~29 프로필/설정 | `routes/users.py` |
| FR-30~33 어드민 | `routes/admin.py` + Next.js `(admin)/` |

**NFR Coverage:** 6/6 완전 커버 (채팅 <2초, 피드 <3초, 크래시 <5%, 이미지 <1MB, 단일 코드베이스, JWT 만료 정책)

### Gap Analysis Results

**Critical Gaps:** 없음

**Medium Gaps:**
- G-1: DB 인덱스 명세 → Alembic `001_initial_schema.py`에 `idx_products_neighborhood_id`, `idx_messages_room_id` 포함 필요
- G-2: `neighborhoods` seed 데이터 → Alembic `002_seed_neighborhoods.py` 첫 스토리에 포함

**Low Gaps:**
- G-3: `chat_room_members` 테이블이 `chat_room.py`에 포함되나 FR 매핑에서 명시 부족

### Architecture Completeness Checklist

**Requirements Analysis**
- [x] 프로젝트 컨텍스트 분석
- [x] 규모 및 복잡도 평가
- [x] 기술 제약사항 식별
- [x] 크로스커팅 관심사 매핑

**Architectural Decisions**
- [x] 핵심 결정사항 버전 포함 문서화
- [x] 기술 스택 완전 명세
- [x] 통합 패턴 정의
- [x] 성능 고려사항 반영

**Implementation Patterns**
- [x] 네이밍 컨벤션 수립
- [x] 구조 패턴 정의
- [x] 통신 패턴 명세
- [x] 프로세스 패턴 문서화

**Project Structure**
- [x] 완전한 디렉토리 구조 정의
- [x] 컴포넌트 경계 수립
- [x] 통합 포인트 매핑
- [x] 요구사항-구조 매핑 완료

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** High — Critical gap 없음, 33/33 FRs 커버, 16/16 체크리스트 완료

**Key Strengths:**
- 모노레포 구조로 세 컴포넌트 간 타입/계약 공유 용이
- copier FastAPI 템플릿으로 Docker, 마이그레이션, JWT, CI 즉시 사용 가능
- snake_case 단일 네이밍으로 Flutter ↔ FastAPI 변환 레이어 불필요
- R2 스토리지 추상화로 향후 교체 가능
- WebSocket ConnectionManager 패턴으로 실시간 채팅 확장성 확보

**Areas for Future Enhancement:**
- Redis 캐싱 (피드 쿼리, 세션) — 사용자 증가 후 도입
- 카카오 OAuth 추가 (v1.1)
- 수평 확장 / 로드 밸런서 (VPS → 클라우드)
- 키워드 검색 (Elasticsearch 또는 PostgreSQL FTS)

### Implementation Handoff

**AI Agent Guidelines:**
- 모든 아키텍처 결정을 문서 그대로 따를 것
- 구현 패턴을 세 컴포넌트 전체에 일관 적용할 것
- 프로젝트 구조와 경계를 준수할 것
- 아키텍처 질문 발생 시 이 문서를 참조할 것

**First Implementation Priority:**
1. `backend/` — copier 템플릿 초기화 + React frontend 제거
2. `mobile/` — `flutter create --empty --platforms android,ios mobile`
3. `admin/` — `npx create-next-app@latest admin --ts --tailwind --app --src-dir`
4. Alembic `001_initial_schema.py` — DB 스키마 + 인덱스 (G-1 해소)
5. Alembic `002_seed_neighborhoods.py` — 동네 목록 초기 데이터 (G-2 해소)

---

## Implementation Patterns & Consistency Rules

### Naming Patterns

**DB (PostgreSQL)**
- 테이블명: 복수 snake_case — `users`, `products`, `chat_rooms`, `messages`, `neighborhoods`
- 컬럼명: snake_case — `seller_id`, `created_at`, `image_urls`
- FK: `{table_단수}_id` — `seller_id`, `buyer_id`, `room_id`
- 인덱스: `idx_{table}_{column}` — `idx_products_neighborhood_id`
- ENUM 값: UPPER_SNAKE — `SALE`, `RESERVED`, `SOLD`

**FastAPI (Python)**
- 함수/변수: snake_case — `get_current_user`, `product_id`
- 클래스: PascalCase — `ProductCreate`, `UserResponse`
- 라우터 파일: snake_case — `products.py`, `chat_rooms.py`
- Pydantic 모델 suffix: `*Create`, `*Update`, `*Response`, `*InDB`

**Flutter (Dart)**
- 변수/함수: camelCase — `productId`, `getCurrentUser()`
- 클래스/위젯: PascalCase — `ProductCard`, `ChatScreen`
- 파일명: snake_case — `product_card.dart`, `chat_screen.dart`
- Provider: `{feature}Provider` — `productListProvider`, `authProvider`
- Notifier: `{feature}Notifier` — `ChatNotifier`

**Next.js (TypeScript)**
- 변수/함수: camelCase — `productId`, `getProducts()`
- 컴포넌트: PascalCase — `ProductTable`, `UserList`
- 파일: kebab-case — `product-table.tsx`, `user-list.tsx`
- Server Action: `action{Name}` — `actionDeleteProduct`

### REST API Endpoint Patterns

```
GET    /api/v1/products              # 목록
POST   /api/v1/products              # 생성
GET    /api/v1/products/{id}         # 단건 조회
PATCH  /api/v1/products/{id}         # 부분 수정 (PUT 사용 금지)
DELETE /api/v1/products/{id}         # 삭제
GET    /api/v1/products/{id}/likes   # 중첩 리소스
POST   /api/v1/chat-rooms/{id}/messages
GET    /api/v1/admin/users           # 어드민 전용
PATCH  /api/v1/admin/users/{id}/deactivate
```

- 경로: 복수 kebab-case (`chat-rooms`, not `chatRooms`)
- 쿼리 파라미터: snake_case (`neighborhood_id`, `page`, `limit`)

### API Response Formats

**목록:**
```json
{ "items": [...], "total": 100, "page": 1, "limit": 20 }
```

**단건:** 직접 객체 반환 (래퍼 없음)

**에러:**
```json
{ "detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND" }
```

**HTTP 상태 코드:** 200 조회/수정, 201 생성, 204 삭제, 400 유효성, 401 미인증, 403 권한, 404 없음, 422 Pydantic

**날짜/시간:** ISO 8601 UTC (`2026-05-29T10:30:00Z`), DB는 `TIMESTAMP WITH TIME ZONE`

**JSON 필드명:** snake_case 유지 (camelCase 변환 없음)

### WebSocket Message Format

```json
// 전송 (클라이언트 → 서버)
{ "type": "message", "content": "안녕하세요" }

// 수신 (서버 → 클라이언트)
{ "type": "message", "id": 42, "room_id": 7, "sender_id": "uuid",
  "sender_nickname": "지수", "content": "안녕하세요", "created_at": "2026-05-29T10:30:00Z" }

// 시스템
{ "type": "error", "code": "ROOM_NOT_FOUND", "detail": "..." }
{ "type": "connected", "room_id": 7 }
```

### Project Structure Patterns

**backend/app/**
```
api/v1/routes/   products.py, auth.py, chat.py, admin.py
api/v1/deps.py   get_current_user, get_db
core/            config.py, security.py, storage.py (R2 추상화)
models/          SQLModel DB 모델
schemas/         Pydantic 요청/응답 스키마
crud/            DB CRUD 함수
services/        fcm.py, websocket.py (ConnectionManager)
main.py
```

**mobile/lib/**
```
core/            network/, storage/, error/
features/        auth/, feed/, product/, chat/, profile/
  각 feature/    presentation/, domain/, data/
main.dart
```

**admin/src/**
```
app/(auth)/login/
app/(admin)/dashboard/, products/, users/
components/      공통 UI
lib/             api.ts, auth.ts
types/           공유 타입
```

### Error Handling Patterns

- **FastAPI:** `HTTPException(status_code, detail={"detail":"...", "code":"..."})`, 전역 핸들러로 500 로깅
- **Flutter:** Riverpod `AsyncValue` — `when(data:, error:, loading:)` 패턴 일관 적용, `DioException` → `AppError` 변환
- **Next.js:** `error.tsx` boundary, 인증 오류 → `redirect('/login')`

### Enforcement — All AI Agents MUST

1. DB 컬럼명 snake_case, API JSON 필드도 snake_case (변환 없음)
2. 날짜는 항상 ISO 8601 UTC 문자열
3. 에러 응답은 항상 `{"detail": "...", "code": "..."}` 형식
4. REST 엔드포인트는 항상 `/api/v1/` prefix
5. PATCH 사용, PUT 사용 금지
6. Flutter 파일명 snake_case, 클래스명 PascalCase
7. WebSocket 메시지는 항상 `type` 필드 포함

---

## Project Structure & Boundaries

### FR → 구조 매핑

| FR 그룹 | 백엔드 | 모바일 | 어드민 |
|---|---|---|---|
| Auth (FR-1~4) | `routes/auth.py` | `features/auth/` | `app/(auth)/login/` |
| 동네설정 (FR-5~6) | `routes/neighborhoods.py` | `features/feed/` | — |
| 피드 (FR-7~10) | `routes/products.py` | `features/feed/` | — |
| 상품상세 (FR-11~15) | `routes/products.py` | `features/product/` | `app/(admin)/products/` |
| 상품등록 (FR-16~19) | `routes/products.py` + `services/storage.py` | `features/product/` | — |
| 채팅 (FR-20~24) | `routes/chat.py` + `services/websocket.py` | `features/chat/` | — |
| 푸시알림 (FR-25~26) | `services/fcm.py` | `core/notifications/` | — |
| 프로필/설정 (FR-27~29) | `routes/users.py` | `features/profile/` | `app/(admin)/users/` |
| 어드민 (FR-30~33) | `routes/admin.py` | — | `app/(admin)/` 전체 |

### Complete Project Directory Structure

```
/ (mono-repo root)
├── .github/workflows/
│   ├── backend.yml
│   ├── mobile.yml
│   └── admin.yml
├── docker-compose.yml          ← 로컬 개발 전체 기동
├── docker-compose.prod.yml
├── .env.example
├── README.md
│
├── backend/                    ← FastAPI (copier 템플릿 기반, React 제거)
│   ├── app/
│   │   ├── main.py
│   │   ├── api/v1/
│   │   │   ├── deps.py              # get_current_user, get_db
│   │   │   └── routes/
│   │   │       ├── auth.py          # FR-1~4
│   │   │       ├── users.py         # FR-27~29
│   │   │       ├── neighborhoods.py # FR-5~6
│   │   │       ├── products.py      # FR-7~19
│   │   │       ├── likes.py         # FR-12
│   │   │       ├── chat.py          # FR-20~24
│   │   │       └── admin.py         # FR-30~33
│   │   ├── core/
│   │   │   ├── config.py            # Pydantic Settings
│   │   │   ├── security.py          # JWT 발급/검증
│   │   │   └── storage.py           # R2 스토리지 추상화 인터페이스
│   │   ├── models/
│   │   │   ├── user.py
│   │   │   ├── neighborhood.py
│   │   │   ├── product.py
│   │   │   ├── like.py
│   │   │   ├── chat_room.py         # Chat_Rooms + Members
│   │   │   └── message.py
│   │   ├── schemas/
│   │   │   ├── auth.py
│   │   │   ├── user.py
│   │   │   ├── product.py
│   │   │   ├── chat.py
│   │   │   └── admin.py
│   │   ├── crud/
│   │   │   ├── user.py
│   │   │   ├── product.py
│   │   │   ├── chat.py
│   │   │   └── neighborhood.py
│   │   └── services/
│   │       ├── websocket.py         # ConnectionManager
│   │       ├── fcm.py               # FCM 발송 (BackgroundTasks)
│   │       └── oauth.py             # Google OAuth 처리
│   ├── alembic/
│   │   ├── env.py
│   │   └── versions/
│   │       └── 001_initial_schema.py
│   ├── tests/api/ tests/services/
│   ├── .env  .env.example
│   ├── pyproject.toml
│   └── Dockerfile
│
├── mobile/                     ← Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── network/
│   │   │   │   ├── api_client.dart      # Dio 인스턴스
│   │   │   │   └── interceptors.dart    # JWT 자동 갱신
│   │   │   ├── storage/
│   │   │   │   └── secure_storage.dart  # JWT 저장
│   │   │   ├── error/
│   │   │   │   └── app_error.dart
│   │   │   └── notifications/
│   │   │       └── fcm_service.dart     # FCM 토큰 등록/갱신
│   │   └── features/
│   │       ├── auth/
│   │       │   ├── data/auth_repository.dart
│   │       │   ├── domain/auth_notifier.dart
│   │       │   └── presentation/
│   │       │       ├── login_screen.dart
│   │       │       └── onboarding_screen.dart   # FR-27
│   │       ├── feed/
│   │       │   ├── data/
│   │       │   │   ├── product_repository.dart
│   │       │   │   └── neighborhood_repository.dart
│   │       │   ├── domain/
│   │       │   │   ├── feed_notifier.dart
│   │       │   │   └── neighborhood_notifier.dart
│   │       │   └── presentation/
│   │       │       ├── feed_screen.dart
│   │       │       ├── product_card.dart
│   │       │       └── neighborhood_picker.dart  # FR-5~6
│   │       ├── product/
│   │       │   ├── data/product_repository.dart
│   │       │   ├── domain/product_notifier.dart
│   │       │   └── presentation/
│   │       │       ├── product_detail_screen.dart
│   │       │       └── product_register_screen.dart
│   │       ├── chat/
│   │       │   ├── data/
│   │       │   │   ├── chat_repository.dart
│   │       │   │   └── websocket_client.dart
│   │       │   ├── domain/chat_notifier.dart
│   │       │   └── presentation/
│   │       │       ├── chat_list_screen.dart
│   │       │       └── chat_room_screen.dart
│   │       └── profile/
│   │           └── presentation/
│   │               ├── profile_screen.dart
│   │               └── settings_screen.dart
│   ├── test/
│   ├── android/app/google-services.json
│   ├── ios/Runner/GoogleService-Info.plist
│   └── pubspec.yaml
│
└── admin/                      ← Next.js
    ├── src/
    │   ├── app/
    │   │   ├── layout.tsx
    │   │   ├── (auth)/login/page.tsx        # FR-30
    │   │   └── (admin)/
    │   │       ├── layout.tsx               # 인증 체크 + 사이드바
    │   │       ├── dashboard/page.tsx       # FR-33
    │   │       ├── products/
    │   │       │   ├── page.tsx             # FR-31
    │   │       │   └── [id]/page.tsx
    │   │       └── users/
    │   │           ├── page.tsx             # FR-32
    │   │           └── [id]/page.tsx
    │   ├── components/
    │   │   ├── ui/data-table.tsx
    │   │   ├── ui/stats-card.tsx
    │   │   └── layout/sidebar.tsx
    │   ├── lib/
    │   │   ├── api.ts                       # fetch 래퍼
    │   │   └── auth.ts                      # JWT 쿠키 유틸
    │   ├── types/index.ts
    │   └── middleware.ts                    # /admin/* route 보호
    ├── next.config.ts
    ├── tailwind.config.ts
    └── Dockerfile
```

### Architectural Boundaries

**API Boundaries:**
- Flutter → FastAPI: `https://api.domain.com/api/v1/` (REST) + `wss://api.domain.com/ws/chat/{room_id}` (WebSocket)
- Next.js → FastAPI: `https://api.domain.com/api/v1/admin/` (REST, Server Components)
- 인증 헤더: `Authorization: Bearer {access_token}` (Flutter) / `httpOnly 쿠키` (Next.js)

**Data Flow (채팅 메시지 전송):**
```
Flutter → POST /api/v1/chat-rooms/{id}/messages
        → FastAPI: DB 저장 (Messages)
        → BackgroundTask: FCM 발송 (수신자 오프라인 시)
        → WebSocket 브로드캐스트 → 수신자 Flutter (온라인 시)
```

**External Service Boundaries:**
- PostgreSQL: `asyncpg` 커넥션 풀 (`backend/`)
- Cloudflare R2: `boto3` S3 호환 (`core/storage.py` 추상화)
- FCM: Firebase Admin SDK (`services/fcm.py`)
- Google OAuth: `httpx` 비동기 (`services/oauth.py`)
