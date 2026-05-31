# Input Reconciliation: Original Overview vs PRD

## Summary

The PRD covers all five sections of the original overview and expands them substantially. Core features (social login, feed, product registration, 1:1 chat, DB schema, constraints) are fully represented. However, the original overview carries several implicit qualitative expectations — particularly around the "neighbor trust" feel, the simplicity of the registration flow ("수분 안에"), and the exact DB schema field set — that are either softened, generalized, or silently extended without acknowledgment.

## Gaps Found

- **DB schema divergence not flagged**: The original schema draft defined exactly four tables with specific fields (Users: id, nickname, profile_image_url; Products: id, seller_id, title, price, description, image_urls[], status; Chat_Rooms: id, seller_id, buyer_id, product_id; Messages: id, room_id, sender_id, content, created_at). The PRD references these tables in FR descriptions and the glossary but never presents the schema explicitly, and adds fields (e.g., category, neighborhood/location on Products; unread count logic on Messages) without noting the deviation from the overview's draft. Downstream architecture work may conflict if the schema is assumed settled.

- **"수분 안에 등록" (minutes-level registration speed) as a qualitative constraint**: The overview's vision statement frames the entire registration flow as completable in a few minutes. The PRD captures the functional steps (FR-16 through FR-19) but drops this time-to-complete expectation entirely. No success metric or NFR reflects registration flow duration, so the implicit "low friction" intent is unverifiable.

- **Kakao login parity with Google is weakened**: The overview lists "카카오 또는 구글" as a single social login requirement with equal standing. The PRD lists both in FR-1 and §6.1, but §9 Open Question #1 flags Kakao as requiring custom setup and treats it as a risk — effectively demoting it without formally marking it as conditional or at-risk in the FR itself. FR-1 reads as if both are confirmed in scope, which is inconsistent with the open question.

- **"이웃" (neighbor/community) trust tone is absent**: The overview's stated goal is validating a neighbor-based trust trading platform. The PRD's vision paragraph mentions it briefly ("같은 동네에 사는 사람들"), but no FR, NFR, or success metric captures trust signals (e.g., seller profile completeness, nickname display prominence, or neighborhood verification feel). The qualitative intent that distinguishes this from a generic secondhand marketplace is not operationalized anywhere.

- **Single codebase (단일 코드베이스) constraint not stated as a requirement**: The overview explicitly calls out "iOS 및 Android 모바일 앱 (단일 코드베이스 적용)" as a platform constraint. The PRD mentions React Native (Expo) in the vision and §6.1 implies it, but there is no explicit NFR or constraint statement requiring a single shared codebase. This matters for architecture decisions and should be a stated constraint, not an implied one.

## Well-covered

- **Social login (FR-1, FR-2, FR-3, FR-4)**: Both Google and Kakao login, non-authenticated read-only access, forced redirect on write/chat attempts — all confirmed at §4.1.
- **Main feed with infinite scroll, 20-item pages, card metadata**: Confirmed at §4.3 FR-7 and FR-8; thumbnail, title, price, elapsed time, and like count all specified.
- **Product registration flow (camera/gallery → Storage upload → DB insert)**: Confirmed at §4.5 FR-16, FR-17, FR-19; Supabase Storage explicitly named.
- **1:1 real-time chat via Supabase Realtime**: Confirmed at §4.6 FR-20 through FR-24; subscription-based delivery and 2-second latency target stated.
- **No payment system (cash/bank transfer only)**: Confirmed at §5 explicit non-goals and §6.2 exclusion table.
- **Location auth replaced by dropdown**: Confirmed at §4.2 FR-5, FR-6 and §5 non-goals ("GPS 기반 실시간 위치 인증").
- **React Native / Expo + Supabase stack**: Confirmed in §1 vision and throughout FR assumptions.
- **Product status states (판매중/예약중/판매완료)**: Confirmed in glossary §3 and FR-7, FR-11, FR-14.
