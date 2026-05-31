---
stepsCompleted: [1, 2, 3, 4]
status: complete
completedAt: '2026-05-29'
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-test0529-2026-05-29/prd.md
  - _bmad-output/planning-artifacts/architecture.md
---

# 중고거래 모바일 플랫폼 MVP - Epic Breakdown

## Overview

이 문서는 PRD와 아키텍처 문서를 기반으로 중고거래 모바일 플랫폼 MVP의 에픽과 스토리를 분해한다. 기술 스택: Flutter(모바일) + FastAPI + PostgreSQL(백엔드) + Next.js(어드민 패널).

## Requirements Inventory

### Functional Requirements

FR-1: 비인증 사용자는 구글 계정으로 로그인할 수 있다. 카카오는 OQ-1 해소 후 추가.
FR-2: 비인증 사용자는 피드/상세 조회만 가능하며, 채팅하기·글쓰기·관심 시도 시 로그인 화면으로 전환된다.
FR-3: 유효한 JWT가 있으면 앱 재실행 시 로그인 화면을 건너뛴다. 액세스 토큰 만료 시 리프레시 토큰으로 자동 갱신.
FR-4: 인증된 사용자는 설정 화면에서 로그아웃할 수 있다.
FR-5: 인증된 사용자는 드롭다운에서 동네를 선택하고 저장할 수 있다.
FR-6: 사용자는 언제든지 동네를 변경할 수 있으며 피드가 즉시 갱신된다.
FR-7: 피드 화면은 현재 동네의 판매중 상품을 최신 등록 순으로 표시한다. (썸네일·제목·가격·시간·관심수)
FR-8: 피드는 한 번에 20개씩 로드하며 스크롤 하단 도달 시 다음 20개를 자동 로드한다.
FR-9: 피드 화면을 아래로 당기면(Pull-to-refresh) 최신 데이터로 갱신된다.
FR-10: 사용자는 피드 카드를 탭하여 상품 상세 화면으로 진입할 수 있다.
FR-11: 상품 상세 화면은 이미지 슬라이드·제목·가격·설명·카테고리·등록 시간·관심 수·판매 상태·판매자 닉네임을 표시한다.
FR-12: 사용자는 하트 버튼을 탭하여 관심을 등록/해제할 수 있다. 비인증 시 로그인 유도.
FR-13: 구매자는 "채팅하기" 버튼을 탭하여 채팅방에 진입한다. 기존 채팅방이 있으면 중복 생성 없이 진입.
FR-14: 판매자는 본인 상품의 제목·가격·설명·판매 상태를 수정할 수 있다.
FR-15: 판매자는 본인 상품을 삭제할 수 있다. 삭제 확인 후 피드에서 즉시 제거.
FR-16: 판매자는 카메라/갤러리에서 사진을 선택할 수 있다. (최대 10장, OS 권한 요청)
FR-17: 등록 제출 시 이미지를 FastAPI 엔드포인트를 통해 Cloudflare R2에 업로드한다. (클라이언트 압축 1MB)
FR-18: 판매자는 카테고리(드롭다운)·제목·가격·설명을 입력한다. (제목 필수 40자, 가격 필수, 카테고리 필수)
FR-19: 판매자는 입력 완료 후 등록 버튼을 탭하여 상품을 DB에 저장한다.
FR-20: 구매자가 "채팅하기"를 탭하면 해당 상품의 채팅방이 생성된다. (중복 생성 방지)
FR-21: 인증된 사용자는 텍스트 메시지를 전송할 수 있다. (빈 메시지 불가, DB 저장)
FR-22: 채팅방 화면의 사용자는 상대방 메시지를 실시간으로 수신한다. (WebSocket, 2초 이내)
FR-23: 인증된 사용자는 본인이 참여 중인 채팅방 목록을 볼 수 있다. (최근 메시지순, 미읽음 수 표시)
FR-24: 채팅 화면 상단에 연결된 상품의 썸네일·제목·가격·판매 상태가 표시된다.
FR-25: 새 메시지가 수신되면 수신자에게 FCM 푸시 알림을 전송한다. (발신자 닉네임, 미리보기 50자, 딥링크)
FR-26: 앱 최초 실행 시 OS 푸시 알림 권한을 요청하고 FCM 토큰을 서버에 등록한다.
FR-27: 소셜 로그인 최초 완료 후 닉네임 입력 화면을 표시한다. (2~15자, 특수문자 제외)
FR-28: 인증된 사용자는 설정 화면에서 닉네임과 프로필 사진을 변경할 수 있다.
FR-29: 인증된 사용자는 설정 화면에서 로그아웃(FR-4)과 프로필 편집(FR-28)에 접근할 수 있다.
FR-30: 어드민 사용자는 이메일·비밀번호로 로그인하며 role=admin 계정만 접근 가능하다.
FR-31: 어드민은 전체 상품 목록을 조회하고 개별 상품을 삭제할 수 있다. (필터: 등록일·상태·판매자)
FR-32: 어드민은 가입된 사용자 목록을 조회하고 계정을 비활성화할 수 있다.
FR-33: 어드민 홈에 기본 운영 지표를 표시한다. (총 가입자, 상품 수, 오늘 신규, 활성 채팅방 수)

### NonFunctional Requirements

NFR-1: 채팅 메시지 실시간 수신 지연 < 2초 (WebSocket SLA)
NFR-2: 메인 피드 초기 로딩 시간 < 3초 (3G 환경 기준)
NFR-3: 앱 크래시 없는 세션 비율 ≥ 95%
NFR-4: JWT 액세스 토큰 만료 15분, 리프레시 토큰 만료 30일
NFR-5: 이미지 장당 최대 1MB (클라이언트 flutter_image_compress 압축)
NFR-6: iOS 14+ / Android 10+ Flutter 단일 코드베이스
NFR-7: FastAPI RLS 수준 권한 제어 — 사용자는 본인 데이터만 수정·삭제 가능 (Depends 미들웨어)
NFR-8: 이미지 업로드 실패율 < 5%
NFR-9: 채팅 메시지 손실율 = 0%
NFR-10: 상품 등록 흐름 완료 시간 < 3분 (사진 선택~등록 완료, 정상 네트워크)

### Additional Requirements

- **모노레포 초기화**: `/mobile`(Flutter), `/backend`(FastAPI copier), `/admin`(Next.js) 3개 컴포넌트 초기화 — 구현 첫 스토리
- **DB 스키마 + 인덱스**: Alembic `001_initial_schema.py` — users, neighborhoods, products, likes, chat_rooms, chat_room_members, messages 테이블 + idx_products_neighborhood_id, idx_messages_room_id 인덱스
- **Neighborhoods seed 데이터**: Alembic `002_seed_neighborhoods.py` — 시/구/동 초기 데이터 삽입 (피드 필터 착수 차단 사안)
- **Firebase 프로젝트 설정**: FCM을 위한 google-services.json / GoogleService-Info.plist 설정
- **Cloudflare R2 스토리지 설정**: 버킷 생성, API 키 발급, FastAPI `core/storage.py` 연동
- **Docker Compose 설정**: 로컬 개발용 docker-compose.yml (PostgreSQL + FastAPI + Next.js)
- **GitHub Actions CI**: 각 컴포넌트별 CI 파이프라인 (copier 템플릿 기본 포함)
- **ConnectionManager**: FastAPI WebSocket 연결 레지스트리 (`services/websocket.py`)
- **JWT 미들웨어**: FastAPI `api/v1/deps.py` — get_current_user, role 검증

### UX Design Requirements

UX 설계 문서 없음 — UX 요구사항은 PRD의 기능 요구사항에 포함되어 있음.

### FR Coverage Map

| FR | 에픽 | 설명 |
|---|---|---|
| FR-1~4 | Epic 1 | 소셜 로그인, 접근 제어, 세션 유지, 로그아웃 |
| FR-5~6 | Epic 1 | 동네 선택/변경 |
| FR-27~29 | Epic 1 | 닉네임 온보딩, 프로필 편집, 설정 화면 |
| FR-7~11 | Epic 2 | 피드 목록, 페이지네이션, 새로고침, 상세 조회 |
| FR-12, 14~19 | Epic 3 | 관심, 수정, 삭제, 이미지 선택/업로드, 정보 입력, 등록 |
| FR-13, 20~26 | Epic 4 | 채팅하기 버튼, 채팅방 생성, 메시지, WebSocket, 목록, 푸시 알림 |
| FR-30~33 | Epic 5 | 어드민 인증, 상품 관리, 사용자 관리, 대시보드 |

## Epic List

### Epic 1: 기반 구축 & 사용자 인증
사용자가 앱에 로그인하고, 동네를 설정하고, 프로필을 완성할 수 있다. 모노레포 초기화·DB 스키마·외부 서비스 설정을 첫 스토리로 포함한다.
**FRs covered:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-27, FR-28, FR-29
**Architecture:** 모노레포 초기화, DB 스키마+인덱스, Neighborhoods seed, Docker Compose, Firebase/R2 설정

### Epic 2: 상품 탐색 (피드 & 상세)
사용자가 동네 피드를 탐색하고 상품 상세 정보를 조회할 수 있다.
**FRs covered:** FR-7, FR-8, FR-9, FR-10, FR-11

### Epic 3: 상품 등록 & 관리
판매자가 상품을 등록하고, 수정하고, 삭제하며 구매자가 관심을 등록할 수 있다.
**FRs covered:** FR-12, FR-14, FR-15, FR-16, FR-17, FR-18, FR-19

### Epic 4: 1:1 채팅 & 푸시 알림
구매자와 판매자가 실시간으로 채팅하고, 앱이 백그라운드일 때 FCM 푸시 알림을 받을 수 있다.
**FRs covered:** FR-13, FR-20, FR-21, FR-22, FR-23, FR-24, FR-25, FR-26

### Epic 5: 어드민 패널
운영자가 로그인하여 상품·사용자를 관리하고 기본 운영 지표를 확인할 수 있다.
**FRs covered:** FR-30, FR-31, FR-32, FR-33

---

## Epic 1: 기반 구축 & 사용자 인증

사용자가 앱에 로그인하고, 동네를 설정하고, 프로필을 완성할 수 있다. 모노레포·DB 스키마·외부 서비스 설정을 첫 스토리로 포함한다.

### Story 1.1: 프로젝트 기반 초기화 & DB 스키마

As a developer,
I want to initialize the mono-repo with all three components and set up the core database schema,
So that the team can start development on a consistent, runnable foundation.

**Acceptance Criteria:**

**Given** 빈 프로젝트 디렉토리가 있을 때
**When** 개발자가 초기화 스크립트를 실행하면
**Then** `/mobile`(Flutter), `/backend`(FastAPI copier), `/admin`(Next.js) 3개 디렉토리가 생성된다
**And** `docker-compose.yml`로 `docker compose up`이 성공하고 PostgreSQL이 정상 기동된다

**Given** Docker Compose가 실행 중일 때
**When** `alembic upgrade head`를 실행하면
**Then** `users`, `neighborhoods` 테이블이 생성된다
**And** `idx_users_email` 인덱스가 생성된다

**Given** 마이그레이션이 완료되었을 때
**When** `alembic upgrade head` (seed 포함)를 실행하면
**Then** `neighborhoods` 테이블에 시/구/동 계층 구조의 초기 데이터가 삽입된다
**And** FastAPI 서버가 `http://localhost:8000/docs`에서 Swagger UI를 정상 반환한다

---

### Story 1.2: Google OAuth 로그인 API

As an unauthenticated user,
I want to sign in with my Google account via the FastAPI backend,
So that I receive a JWT token pair to access protected features.

**Acceptance Criteria:**

**Given** 사용자가 구글 OAuth 인증 코드를 제출할 때
**When** `POST /api/v1/auth/google` 엔드포인트를 호출하면
**Then** FastAPI가 Google에서 사용자 정보를 검증하고 `users` 테이블에 upsert한다
**And** `access_token`(15분)과 `refresh_token`(30일)을 JSON으로 반환한다

**Given** 유효한 리프레시 토큰이 있을 때
**When** `POST /api/v1/auth/refresh`를 호출하면
**Then** 새로운 액세스 토큰을 반환한다

**Given** 보호된 엔드포인트에 요청할 때
**When** 유효하지 않거나 만료된 액세스 토큰을 사용하면
**Then** HTTP 401과 `{"detail": "인증이 필요합니다.", "code": "UNAUTHORIZED"}`를 반환한다

**Given** role=admin이 아닌 사용자가 `/api/v1/admin/*` 엔드포인트에 요청할 때
**When** 요청이 도달하면
**Then** HTTP 403을 반환한다

---

### Story 1.3: Flutter 로그인 화면 & JWT 세션 관리

As an unauthenticated user,
I want to log in with Google from the Flutter app and stay logged in across restarts,
So that I don't have to authenticate every time I open the app.

**Acceptance Criteria:**

**Given** 앱을 처음 실행했을 때
**When** 저장된 유효한 JWT가 없으면
**Then** 로그인 화면이 표시되고 "구글로 로그인" 버튼이 활성화된다

**Given** 로그인 화면에서 구글 로그인 버튼을 탭할 때
**When** Google 인증이 성공하면
**Then** FastAPI에서 토큰을 받아 `flutter_secure_storage`에 저장한다
**And** 닉네임 미설정 사용자는 닉네임 온보딩 화면으로, 설정된 사용자는 피드 화면으로 이동한다

**Given** 앱 재실행 시 저장된 액세스 토큰이 만료되었을 때
**When** 리프레시 토큰이 유효하면
**Then** Dio 인터셉터가 자동으로 토큰을 갱신하고 원래 요청을 재시도한다
**And** 리프레시 토큰도 만료된 경우 로그인 화면으로 이동한다

**Given** 비인증 상태에서 글쓰기·관심·채팅하기를 시도할 때
**When** 해당 버튼을 탭하면
**Then** 로그인 유도 팝업이 표시된다

---

### Story 1.4: 동네 선택 API & Flutter UI

As an authenticated user,
I want to select my neighborhood from a dropdown and have my feed filtered accordingly,
So that I see listings from my local area.

**Acceptance Criteria:**

**Given** 인증된 사용자가 동네 설정 화면에 진입할 때
**When** `GET /api/v1/neighborhoods`를 호출하면
**Then** 시/구/동 계층 구조의 동네 목록이 반환된다

**Given** 사용자가 드롭다운에서 동네를 선택하고 저장할 때
**When** `PATCH /api/v1/users/me`로 `neighborhood_id`를 전송하면
**Then** DB에 저장되고 피드가 해당 동네 기준으로 즉시 필터링된다

**Given** 동네 미설정 사용자가 글쓰기를 시도할 때
**When** 글쓰기 탭을 탭하면
**Then** 동네 설정 화면으로 먼저 안내된다

**Given** 설정된 동네를 변경할 때
**When** 다른 동네를 선택하고 저장하면
**Then** 피드가 새 동네 기준으로 즉시 갱신된다

---

### Story 1.5: 닉네임 온보딩

As a new user who just logged in for the first time,
I want to set my nickname before entering the app,
So that other users can identify me in listings and chat.

**Acceptance Criteria:**

**Given** 소셜 로그인 후 닉네임이 없는 신규 사용자일 때
**When** 로그인이 완료되면
**Then** 닉네임 입력 화면이 표시된다

**Given** 닉네임 입력 화면에서
**When** 2자 미만이거나 15자 초과, 또는 특수문자를 입력하면
**Then** 완료 버튼이 비활성화되고 유효성 오류 메시지가 표시된다

**Given** 유효한 닉네임을 입력하고 완료를 탭할 때
**When** `PATCH /api/v1/users/me`로 `nickname`을 전송하면
**Then** DB에 저장되고 피드 화면으로 이동한다

**Given** 닉네임이 이미 설정된 사용자가 재로그인할 때
**When** 로그인이 완료되면
**Then** 닉네임 온보딩 화면을 건너뛰고 피드 화면으로 이동한다

---

### Story 1.6: 프로필 편집 & 설정 화면

As an authenticated user,
I want to edit my profile and access app settings,
So that I can update my nickname, profile photo, and manage my account.

**Acceptance Criteria:**

**Given** 인증된 사용자가 설정 화면에 진입할 때
**When** 설정 화면이 로드되면
**Then** 현재 닉네임과 프로필 사진, 로그아웃 버튼이 표시된다

**Given** 사용자가 닉네임을 변경하고 저장할 때
**When** `PATCH /api/v1/users/me`로 변경된 닉네임을 전송하면
**Then** DB에 저장되고 화면에 즉시 반영된다

**Given** 사용자가 프로필 사진을 변경할 때
**When** 갤러리에서 사진을 선택하면
**Then** flutter_image_compress로 1MB 이하로 압축 후 R2에 업로드된다
**And** `profile_image_url`이 DB에 저장되고 화면에 반영된다

**Given** 사용자가 로그아웃 버튼을 탭할 때
**When** 확인 후 로그아웃을 실행하면
**Then** secure_storage에서 JWT가 삭제되고 로그인 화면으로 이동한다

---

## Epic 2: 상품 탐색 (피드 & 상세)

사용자가 동네 피드를 탐색하고 상품 상세 정보를 조회할 수 있다.

### Story 2.1: 상품 DB 모델 & 피드/상세 API

As a developer,
I want to create the Products table and implement the product feed and detail API endpoints,
So that the Flutter app can fetch and display product listings.

**Acceptance Criteria:**

**Given** 아키텍처 마이그레이션을 실행할 때
**When** `alembic upgrade head`를 실행하면
**Then** `products` 테이블이 생성된다 (id, seller_id, title, price, description, category, image_urls[], status, neighborhood_id, created_at)
**And** `idx_products_neighborhood_id`, `idx_products_created_at` 인덱스가 생성된다

**Given** 동네 ID와 페이지 파라미터를 전달할 때
**When** `GET /api/v1/products?neighborhood_id={id}&page=1&limit=20`을 호출하면
**Then** 해당 동네의 `판매중` + `예약중` 상품을 최신 등록 순으로 반환한다
**And** 응답 형식은 `{"items": [...], "total": N, "page": 1, "limit": 20}`이다
**And** 각 아이템에 썸네일(첫 번째 image_url)·제목·가격·created_at·관심수·status가 포함된다

**Given** 상품 ID로 상세 조회할 때
**When** `GET /api/v1/products/{id}`를 호출하면
**Then** image_urls 전체·제목·가격·설명·카테고리·created_at·관심수·status·판매자 닉네임이 반환된다
**And** 존재하지 않는 상품 ID는 HTTP 404를 반환한다

**Given** 비인증 사용자가 피드/상세 API를 호출할 때
**When** Authorization 헤더 없이 요청하면
**Then** 정상적으로 200을 반환한다 (읽기 전용 공개 엔드포인트)

---

### Story 2.2: Flutter 메인 피드 화면

As a user (authenticated or not),
I want to browse product listings in my neighborhood with infinite scroll,
So that I can discover items available nearby.

**Acceptance Criteria:**

**Given** 앱 진입 시 동네가 설정된 상태일 때
**When** 피드 화면이 로드되면
**Then** 해당 동네의 상품 카드가 최신순으로 표시된다
**And** 각 카드에 썸네일·제목·가격·경과 시간·관심수가 표시된다
**And** `예약중` 상품 카드에는 "예약중" 배지가 표시된다

**Given** 피드를 스크롤하여 하단에 도달할 때
**When** 추가 상품이 있으면
**Then** 다음 20개가 자동으로 로드되어 목록에 추가된다
**And** 로드 중 하단에 로딩 인디케이터가 표시된다

**Given** 더 이상 로드할 상품이 없을 때
**When** 스크롤이 하단에 도달하면
**Then** 추가 로드 없이 목록 끝 안내가 표시된다

**Given** 피드를 아래로 당길 때 (Pull-to-refresh)
**When** 새로고침이 완료되면
**Then** 가장 최신 상품이 최상단에 노출된다

**Given** 상품 카드를 탭할 때
**When** 탭 이벤트가 발생하면
**Then** 해당 상품의 상세 화면으로 이동한다

**Given** 네트워크가 없을 때
**When** 피드 화면에 진입하면
**Then** 오프라인 안내 토스트가 표시된다

---

### Story 2.3: Flutter 상품 상세 화면

As a user,
I want to view detailed information about a product including all photos and seller info,
So that I can decide whether to contact the seller.

**Acceptance Criteria:**

**Given** 피드에서 상품 카드를 탭했을 때
**When** 상품 상세 화면이 로드되면
**Then** 이미지 슬라이드·제목·가격·설명·카테고리·등록 시간·관심수·판매 상태·판매자 닉네임이 표시된다

**Given** 상품 이미지가 2장 이상일 때
**When** 이미지 영역을 좌우로 스와이프하면
**Then** 다음/이전 이미지로 전환된다
**And** 현재 이미지 순서를 나타내는 인디케이터가 표시된다

**Given** 판매 상태가 `판매완료`인 상품일 때
**When** 상세 화면이 로드되면
**Then** "채팅하기" 버튼이 비활성화된다
**And** "판매완료" 배지가 표시된다

**Given** 비인증 사용자가 상세 화면을 볼 때
**When** 화면이 로드되면
**Then** 로그인 없이 모든 상품 정보가 정상 표시된다

---

## Epic 3: 상품 등록 & 관리

판매자가 상품을 등록하고, 수정하고, 삭제하며 구매자가 관심을 등록할 수 있다.

### Story 3.1: 상품 등록 API & R2 이미지 업로드

As a developer,
I want to implement the product registration API with Cloudflare R2 image upload,
So that sellers can create new product listings with photos.

**Acceptance Criteria:**

**Given** 인증된 판매자가 이미지 파일과 상품 정보를 전송할 때
**When** `POST /api/v1/products/images`로 이미지를 업로드하면
**Then** FastAPI가 파일을 R2 버킷에 저장하고 공개 URL을 반환한다
**And** 단일 파일 크기가 1MB를 초과하면 HTTP 400을 반환한다
**And** 10장 초과 업로드 시도 시 HTTP 400을 반환한다

**Given** 이미지 URL 목록과 상품 정보를 전송할 때
**When** `POST /api/v1/products`로 상품을 등록하면
**Then** products 테이블에 저장되고 생성된 상품 객체를 HTTP 201로 반환한다
**And** 필수 필드(title, price, category) 누락 시 HTTP 422를 반환한다

**Given** 비인증 사용자가 상품 등록을 시도할 때
**When** `POST /api/v1/products`를 호출하면
**Then** HTTP 401을 반환한다

---

### Story 3.2: Flutter 상품 등록 화면

As a seller,
I want to select photos and fill in product details to create a listing,
So that buyers in my neighborhood can discover my items.

**Acceptance Criteria:**

**Given** 인증된 판매자가 글쓰기 탭을 탭할 때
**When** 동네가 설정되어 있으면
**Then** 상품 등록 화면이 표시된다
**And** 동네 미설정 시 동네 설정 화면으로 먼저 안내된다

**Given** 사진 선택 버튼을 탭할 때
**When** OS 권한 요청 후 갤러리/카메라를 선택하면
**Then** 최대 10장까지 선택 가능하다
**And** 10장 초과 선택 시 경고 토스트를 표시하고 10장만 유지한다
**And** 선택된 사진은 미리보기로 표시된다

**Given** 사진을 선택하고 등록을 시도할 때
**When** 업로드 전
**Then** flutter_image_compress로 각 이미지를 1MB 이하로 압축한다
**And** 업로드 진행률이 UI에 표시된다
**And** 업로드 실패 시 실패한 이미지만 재시도 가능하다

**Given** 제목·카테고리·가격이 모두 입력되지 않았을 때
**When** 등록 버튼을 탭하면
**Then** 등록 버튼이 비활성화 상태를 유지한다

**Given** 모든 필수 정보가 입력되고 등록 버튼을 탭할 때
**When** API 요청이 성공하면
**Then** 피드 화면으로 이동하며 방금 등록한 상품이 최상단에 노출된다
**And** 네트워크 오류 시 오류 토스트를 표시하고 입력 내용을 보존한다

---

### Story 3.3: 관심 & 상품 수정/삭제 API

As a developer,
I want to implement likes, product edit, and delete API endpoints,
So that buyers can save items and sellers can manage their listings.

**Acceptance Criteria:**

**Given** 아키텍처 마이그레이션을 실행할 때
**When** `alembic upgrade head`를 실행하면
**Then** `likes` 테이블이 생성된다 (user_id, product_id, created_at, UNIQUE 제약)

**Given** 인증된 사용자가 관심을 등록할 때
**When** `POST /api/v1/products/{id}/likes`를 호출하면
**Then** likes 테이블에 저장되고 HTTP 201을 반환한다
**And** 동일 사용자의 중복 관심 등록 시 HTTP 409를 반환한다

**Given** 인증된 사용자가 관심을 해제할 때
**When** `DELETE /api/v1/products/{id}/likes`를 호출하면
**Then** likes 레코드가 삭제되고 HTTP 204를 반환한다

**Given** 판매자가 본인 상품을 수정할 때
**When** `PATCH /api/v1/products/{id}`로 변경할 필드를 전송하면
**Then** 해당 필드만 업데이트되고 수정된 상품을 반환한다
**And** 타인의 상품 수정 시도 시 HTTP 403을 반환한다

**Given** 판매자가 본인 상품을 삭제할 때
**When** `DELETE /api/v1/products/{id}`를 호출하면
**Then** 상품이 삭제되고 HTTP 204를 반환한다
**And** 타인의 상품 삭제 시도 시 HTTP 403을 반환한다

---

### Story 3.4: Flutter 상품 관리 UI (관심·수정·삭제)

As a user,
I want to like products I'm interested in and manage my own listings,
So that I can save items to review later and keep my listings up to date.

**Acceptance Criteria:**

**Given** 인증된 사용자가 상품 상세 화면에서 하트 버튼을 탭할 때
**When** 관심 등록 API 호출이 성공하면
**Then** 하트 아이콘이 채워지고 관심 수가 1 증가한다
**And** 이미 관심 등록된 상품에서 다시 탭하면 해제되고 수가 1 감소한다

**Given** 비인증 사용자가 하트 버튼을 탭할 때
**When** 탭 이벤트가 발생하면
**Then** 로그인 유도 팝업이 표시된다

**Given** 판매자가 본인 상품 상세 화면에 진입할 때
**When** 화면이 로드되면
**Then** 수정 버튼과 삭제 버튼이 표시된다
**And** 타인의 상품에서는 해당 버튼이 표시되지 않는다

**Given** 판매자가 수정 버튼을 탭할 때
**When** 수정 화면이 로드되면
**Then** 기존 제목·가격·설명·판매 상태가 입력 필드에 채워진다
**And** 저장 후 상세 화면이 수정된 내용으로 즉시 갱신된다

**Given** 판매자가 삭제 버튼을 탭할 때
**When** 확인 다이얼로그에서 삭제를 선택하면
**Then** 상품이 삭제되고 피드 화면으로 이동한다
**And** 피드에서 해당 상품 카드가 즉시 사라진다

---

## Epic 4: 1:1 채팅 & 푸시 알림

구매자와 판매자가 실시간으로 채팅하고, 앱이 백그라운드일 때 FCM 푸시 알림을 받을 수 있다.

### Story 4.1: 채팅 DB 모델 & REST API

As a developer,
I want to create the chat room and message database schema and REST API endpoints,
So that the Flutter app can create chat rooms and load message history.

**Acceptance Criteria:**

**Given** 아키텍처 마이그레이션을 실행할 때
**When** `alembic upgrade head`를 실행하면
**Then** `chat_rooms`, `chat_room_members`, `messages` 테이블이 생성된다
**And** `chat_room_members`에 `last_read_at TIMESTAMP` 컬럼이 포함된다
**And** `idx_messages_room_id`, `idx_messages_created_at` 인덱스가 생성된다

**Given** 인증된 구매자가 상품에 대한 채팅방을 생성할 때
**When** `POST /api/v1/chat-rooms`로 `product_id`를 전송하면
**Then** 채팅방과 두 멤버(판매자·구매자) 레코드가 생성되고 HTTP 201로 반환된다
**And** 동일 상품·동일 구매자의 채팅방이 이미 존재하면 기존 채팅방을 HTTP 200으로 반환한다 (중복 생성 방지)

**Given** 인증된 사용자가 채팅 목록을 조회할 때
**When** `GET /api/v1/chat-rooms`를 호출하면
**Then** 본인이 참여 중인 채팅방 목록을 최근 메시지 순으로 반환한다
**And** 각 채팅방에 상품 썸네일·제목·가격·마지막 메시지·미읽음 수가 포함된다

**Given** 채팅방의 메시지 내역을 조회할 때
**When** `GET /api/v1/chat-rooms/{id}/messages?page=1&limit=50`을 호출하면
**Then** 메시지 목록을 최신순으로 반환한다
**And** 참여하지 않은 채팅방 조회 시 HTTP 403을 반환한다

---

### Story 4.2: FastAPI WebSocket 서버 & ConnectionManager

As a developer,
I want to implement the WebSocket server with a ConnectionManager for real-time chat,
So that messages are delivered to connected clients within 2 seconds.

**Acceptance Criteria:**

**Given** 인증된 사용자가 WebSocket에 연결할 때
**When** `wss://.../ws/chat/{room_id}?token={jwt}`로 연결하면
**Then** ConnectionManager가 해당 채팅방의 연결 레지스트리에 등록한다
**And** `{"type": "connected", "room_id": N}` 메시지를 클라이언트에 전송한다
**And** 참여하지 않은 채팅방 접근 시 연결을 즉시 종료한다

**Given** 클라이언트가 `{"type": "message", "content": "..."}` 메시지를 전송할 때
**When** WebSocket 핸들러가 수신하면
**Then** messages 테이블에 저장한다
**And** 같은 채팅방에 연결된 모든 클라이언트에게 2초 이내에 브로드캐스트한다
**And** 브로드캐스트 형식은 `{"type": "message", "id": N, "room_id": N, "sender_id": "uuid", "sender_nickname": "...", "content": "...", "created_at": "ISO8601"}`이다

**Given** WebSocket 연결이 끊어질 때
**When** 클라이언트가 연결을 종료하거나 네트워크 오류가 발생하면
**Then** ConnectionManager가 해당 연결을 레지스트리에서 제거한다
**And** 다른 클라이언트의 연결에 영향을 주지 않는다

**Given** 빈 content를 가진 메시지를 전송할 때
**When** WebSocket 핸들러가 수신하면
**Then** 저장하지 않고 무시한다

---

### Story 4.3: Flutter 채팅방 화면

As a buyer or seller,
I want to enter a chat room and exchange real-time messages,
So that I can coordinate the transaction with the other party.

**Acceptance Criteria:**

**Given** 구매자가 상품 상세 화면에서 "채팅하기"를 탭할 때
**When** API로 채팅방을 생성(또는 기존 방 조회)하면
**Then** 해당 채팅방 화면으로 이동한다
**And** 채팅방이 이미 존재하면 중복 생성 없이 기존 방으로 진입한다

**Given** 채팅방 화면에 진입할 때
**When** 화면이 로드되면
**Then** 채팅 상단에 연결된 상품의 썸네일·제목·가격·판매 상태가 표시된다
**And** 기존 메시지 내역이 최신순으로 표시된다
**And** WebSocket 연결이 수립된다

**Given** 메시지를 입력하고 전송 버튼을 탭할 때
**When** WebSocket으로 메시지를 전송하면
**Then** 본인 화면에 즉시 표시된다 (낙관적 업데이트)
**And** 빈 메시지는 전송되지 않는다

**Given** 상대방이 메시지를 전송할 때
**When** WebSocket 브로드캐스트가 수신되면
**Then** 2초 이내에 메시지가 화면에 표시된다
**And** 스크롤이 자동으로 최하단으로 이동한다

**Given** WebSocket 연결이 끊어질 때
**When** 네트워크 오류가 감지되면
**Then** 자동 재연결을 3회 시도한다
**And** 재연결 실패 시 오프라인 안내 토스트를 표시한다

---

### Story 4.4: Flutter 채팅 목록 화면

As an authenticated user,
I want to see all my active chat rooms with unread message counts,
So that I can quickly find and respond to conversations.

**Acceptance Criteria:**

**Given** 인증된 사용자가 채팅 탭에 진입할 때
**When** 화면이 로드되면
**Then** 본인이 참여 중인 채팅방 목록이 최근 메시지 순으로 표시된다
**And** 각 채팅방 항목에 상품 썸네일·제목·마지막 메시지 미리보기·경과 시간·미읽음 수 배지가 표시된다

**Given** 미읽음 메시지가 있는 채팅방이 있을 때
**When** 목록이 로드되면
**Then** `last_read_at` 이후의 메시지 수가 배지로 표시된다

**Given** 채팅방 항목을 탭할 때
**When** 탭 이벤트가 발생하면
**Then** 해당 채팅방 화면으로 이동하고 `last_read_at`이 현재 시각으로 업데이트된다
**And** 채팅 목록으로 돌아오면 해당 채팅방의 미읽음 배지가 사라진다

**Given** 참여 중인 채팅방이 없을 때
**When** 채팅 탭에 진입하면
**Then** "아직 채팅 내역이 없습니다" 안내 메시지가 표시된다

---

### Story 4.5: FCM 푸시 알림

As a user with the app in the background,
I want to receive a push notification when a new chat message arrives,
So that I can respond promptly without keeping the app open.

**Acceptance Criteria:**

**Given** 앱을 최초 실행할 때
**When** OS 푸시 알림 권한 요청 팝업이 표시되고 사용자가 허용하면
**Then** FCM 토큰이 발급되어 `PATCH /api/v1/users/me`로 서버에 등록된다
**And** `users.fcm_token` 컬럼에 저장된다

**Given** FCM 토큰이 갱신될 때 (FCM 재발급)
**When** Flutter FCM SDK가 토큰 갱신을 감지하면
**Then** 새 토큰이 서버에 자동으로 업데이트된다

**Given** 채팅방에 새 메시지가 저장될 때
**When** FastAPI BackgroundTasks가 수신자의 fcm_token으로 FCM API를 호출하면
**Then** 수신자 디바이스에 푸시 알림이 전달된다
**And** 알림에 발신자 닉네임과 메시지 미리보기(최대 50자)가 포함된다

**Given** 푸시 알림을 탭할 때
**When** 앱이 백그라운드 또는 종료 상태일 때
**Then** 해당 채팅방 화면으로 딥링크 진입한다

**Given** 사용자가 채팅방 화면에 현재 접속 중일 때
**When** 같은 채팅방의 새 메시지가 수신되면
**Then** 푸시 알림을 표시하지 않는다 (WebSocket 실시간 수신으로 충분)

**Given** 알림 권한이 거부된 경우
**When** 새 메시지가 수신되면
**Then** 푸시 알림 없이 앱 내 채팅 목록의 미읽음 배지만으로 표시한다

---

## Epic 5: 어드민 패널

운영자가 로그인하여 상품·사용자를 관리하고 기본 운영 지표를 확인할 수 있다.

### Story 5.1: 어드민 인증 API & Next.js 로그인 화면

As an admin operator,
I want to log in with email and password and have all admin routes protected,
So that only authorized operators can access the admin panel.

**Acceptance Criteria:**

**Given** 어드민 계정(role=admin)으로 로그인을 시도할 때
**When** `POST /api/v1/admin/auth/login`으로 이메일·비밀번호를 전송하면
**Then** role=admin 클레임이 포함된 JWT를 반환한다

**Given** role=admin이 아닌 계정으로 로그인을 시도할 때
**When** 같은 엔드포인트를 호출하면
**Then** HTTP 403을 반환한다

**Given** Next.js 어드민 앱에서 로그인 화면에 접근할 때
**When** `/login` 경로에 진입하면
**Then** 이메일·비밀번호 입력 폼이 표시된다
**And** 로그인 성공 시 JWT가 `httpOnly` 쿠키에 저장되고 `/dashboard`로 리다이렉트된다
**And** 로그인 실패 시 오류 메시지가 표시된다

**Given** 비인증 사용자가 어드민 페이지에 접근할 때
**When** `/(admin)/*` 경로에 접근하면
**Then** Next.js `middleware.ts`가 `/login`으로 리다이렉트한다
**And** 유효한 admin JWT 쿠키가 있으면 정상 접근된다

---

### Story 5.2: 어드민 상품 관리

As an admin operator,
I want to view all products and delete inappropriate ones,
So that I can maintain the quality and safety of marketplace listings.

**Acceptance Criteria:**

**Given** 어드민이 상품 목록 API를 호출할 때
**When** `GET /api/v1/admin/products`를 호출하면
**Then** 전체 상품 목록이 반환된다 (등록일·상태·판매자 필터 지원)
**And** 응답에 상품 ID·제목·가격·상태·판매자 닉네임·등록일이 포함된다

**Given** 어드민이 특정 상품을 삭제할 때
**When** `DELETE /api/v1/admin/products/{id}`를 호출하면
**Then** 상품이 삭제되고 HTTP 204를 반환한다
**And** 일반 사용자 JWT로 같은 엔드포인트를 호출하면 HTTP 403을 반환한다

**Given** 어드민이 Next.js 상품 관리 페이지에 접근할 때
**When** `/products` 페이지가 로드되면
**Then** 상품 목록이 테이블로 표시된다 (제목·상태·판매자·등록일 컬럼)
**And** 등록일·상태·판매자로 필터링할 수 있다

**Given** 어드민이 상품 삭제 버튼을 클릭할 때
**When** 확인 다이얼로그에서 삭제를 선택하면
**Then** 삭제 API가 호출되고 목록에서 해당 상품이 즉시 제거된다

---

### Story 5.3: 어드민 사용자 관리

As an admin operator,
I want to view all users and deactivate accounts when necessary,
So that I can handle policy violations and maintain platform integrity.

**Acceptance Criteria:**

**Given** 아키텍처 마이그레이션을 실행할 때
**When** `alembic upgrade head`를 실행하면
**Then** `users` 테이블에 `is_active BOOLEAN DEFAULT TRUE` 컬럼이 추가된다

**Given** 어드민이 사용자 목록 API를 호출할 때
**When** `GET /api/v1/admin/users`를 호출하면
**Then** 전체 사용자 목록이 반환된다 (닉네임·이메일·가입일·is_active 포함)

**Given** 어드민이 특정 사용자를 비활성화할 때
**When** `PATCH /api/v1/admin/users/{id}/deactivate`를 호출하면
**Then** `is_active=false`로 업데이트되고 HTTP 200을 반환한다

**Given** 비활성화된 사용자가 로그인을 시도할 때
**When** 인증 엔드포인트를 호출하면
**Then** HTTP 403과 `{"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"}`를 반환한다

**Given** 어드민이 Next.js 사용자 관리 페이지에 접근할 때
**When** `/users` 페이지가 로드되면
**Then** 사용자 목록이 테이블로 표시된다 (닉네임·가입일·상태 컬럼)
**And** 비활성화 버튼 클릭 후 확인 시 API가 호출되고 상태가 즉시 반영된다

---

### Story 5.4: 어드민 대시보드

As an admin operator,
I want to see key operational metrics on the dashboard,
So that I can monitor the health and activity of the platform at a glance.

**Acceptance Criteria:**

**Given** 어드민이 대시보드 stats API를 호출할 때
**When** `GET /api/v1/admin/stats`를 호출하면
**Then** 다음 지표를 포함한 JSON을 반환한다: `total_users`, `total_products`, `new_users_today`, `new_products_today`, `active_chat_rooms`
**And** 각 수치는 PostgreSQL에서 실시간으로 집계된다

**Given** 어드민이 Next.js 대시보드 페이지에 접근할 때
**When** `/dashboard` 페이지가 로드되면
**Then** 5개 지표가 카드 형태로 표시된다
**And** 페이지 진입 시 최신 데이터를 로드한다

**Given** 어드민이 대시보드에서 사이드바 메뉴를 사용할 때
**When** "상품 관리" 또는 "사용자 관리"를 클릭하면
**Then** 해당 페이지로 이동한다
