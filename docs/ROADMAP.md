# 모임 이벤트 관리 웹 MVP — ROADMAP

> 기준 문서: `docs/PRD.md` (M0~M5) · 대상 앱: `frontend/` · 작성일: 2026-10-22

## 개요

| 단계 | 기간 | 목표 | 선행 조건 |
|---|---|---|---|
| Phase 0 (M0) | 0.5주 | 스키마·RLS·디자인 토큰·서버 유틸 | - |
| Phase 1 (M1) | 1주 | 주최자 로그인, 이벤트 CRUD, 공유 링크, 공지 | P0 |
| Phase 2 (M2) | 1주 | 참여자 진입(이름+토큰), RSVP, 명단, 레이트리밋 | P1 |
| Phase 3 (M3) | 1주 | 카풀 등록/신청/확정 | P2 |
| Phase 4 (M4) | 1주 | 정산 N빵(주최자 단일 결제) + 입금 체크 | P2 (RSVP 확정 인원) |
| Phase 5 (M5) | 1주 | 모바일 QA·보안 점검·배포 | P1~P4 |
| 베타 운영 | 병행 | 실제 교회 모임 2~3팀 | Phase 5 배포 |

명목 5.5주. **1인 개발 기준 버퍼(리뷰·버그·카카오 설정 지연 등) 포함 약 7~8주 추정.** Phase 3과 4는 둘 다 Phase 2에만 의존하므로 인력이 2명 이상이면 병렬 진행 가능. 베타는 이후 개발(버그 수정·P1)과 병행한다.

KPI: 이벤트당 응답률 80% 이상 / 주최자 재생성률 40% 이상 / 참여자 응답 평균 30초 이내 (재생성률 등 지표는 **베타 종료 후** 측정)

## 공통 원칙

- **주최자**: Supabase Auth(카카오). RLS `events.host_id = auth.uid()` 소유자만 접근.
- **참여자(비로그인)**: `anon` 역할에는 신규 테이블 권한을 **전혀 주지 않는다**. 모든 참여자 동작은 Server Action / Route Handler에서 `share_code` → 이벤트 조회, 쿠키 토큰의 sha256 → `participant_token_hash` 조회 및 `participant.event_id` 일치 확인을 거친 뒤 서비스 롤 클라이언트로 처리한다.
- **참여자 액션 래퍼 `withParticipant`**: 행위자 ID는 **항상 토큰에서만** 도출한다. 클라이언트가 보낸 `participantId`/`rideId`/`settlementId`는 신뢰하지 않고 `event_id` 일치를 재검증한다.
- **참여자용 Route Handler**는 `/e/[code]/...` 아래에만 둔다(쿠키 path 범위와 일치).
- **서비스 롤 조회 규칙**: `select('*')` 금지, 컬럼을 명시하고 항상 `event_id` 필터를 건다. 공개 명단은 `name`/`status`/`guests_count`만 반환(주최자 이메일 아이디·전화번호·토큰 해시 비노출). 주최자 브라우저 클라이언트도 `participants`에 `select('*')`/`returning *`을 쓰지 않는다(컬럼 명시, 해시 컬럼은 권한 없음).
- **서비스 롤 키**: `SUPABASE_SERVICE_ROLE_KEY`는 `NEXT_PUBLIC_` 접두사 금지. `import 'server-only'`를 단 모듈에서만 사용.
- **새 테이블 체크리스트**: `enable row level security` + `revoke all ... from anon` 를 반드시 함께 실행.
- **에러 코드 매핑**: DB 함수/트리거의 예외는 아래 코드로 통일하고 `frontend/src/lib/errors.ts`에서 사용자 메시지로 매핑한다.

  | 코드 | 의미 |
  |---|---|
  | `event_not_open` | `closed`/`canceled` 이벤트에 RSVP·카풀 쓰기 |
  | `rsvp_capacity_exceeded` | 이미 참석(`yes`)인 사람이 동반 인원을 늘려 정원 초과(대기로 강등하지 않고 거부) |
  | `carpool_seats_full` | 잔여 좌석 없음 |
  | `carpool_self_request` | 본인 차량 신청 |
  | `carpool_already_confirmed` | 이미 다른 차량에 확정됨 |
  | `carpool_participant_event_mismatch` | 신청자·차량의 이벤트 불일치 |
  | `carpool_seats_below_confirmed` | 좌석 수를 확정 인원 미만으로 축소 |
  | `carpool_requires_rsvp_yes` | RSVP `yes`가 아닌 참여자의 신청 또는 차량 등록 |
  | `carpool_ride_not_found` | 존재하지 않는 차량에 신청 |
  | `share_code_generation_failed` | `share_code` 10회 재시도 후에도 충돌(서버에서 재시도) |

- **스키마**: Supabase 대시보드 SQL Editor에서 실행. 실행한 SQL은 `supabase/schema.sql`(및 이후 `supabase/` 아래 번호 붙인 변경 파일)로 보관.
- **의존성**: `docs/TECH-STACK-PRIORITY.md` 원칙대로 기능 구현 시점에 추가. 현재 `react-hook-form`, `zod`, `@hookform/resolvers`, `sonner`는 이미 설치되어 있음. `date-fns`는 Phase 1에서 추가. shadcn 컴포넌트는 필요할 때 CLI로 추가.
- **테스트**: API·비즈니스 로직이 있는 Phase마다 Playwright MCP 시나리오 테스트를 같이 작성한다.

## 현재 코드 현황 (2026-10-22 확인)

- `frontend/src/middleware.ts` → `lib/supabase/middleware.ts#updateSession`: 세션 갱신만 하고 **리다이렉트(라우트 보호) 로직이 없음**
- `/login` 페이지와 `/auth/callback` 라우트가 **없음** → 신규 생성
- 이미 있음: `(dashboard)/dashboard/page.tsx`, `DashboardHeader`, `AuthProvider`, `useUser`/`useAuth`, Recoil atoms, shadcn `button/input/card/dialog/form/sonner/avatar`
- 디자인 토큰 파일: `docs/design.shadcn.md`

---

## Phase 0 (M0) — 기반: 스키마·보안·토큰 (0.5주)

**P0**
- [ ] 테이블 생성 — `events, participants, rsvps, announcements, carpool_rides, carpool_requests, expenses, settlements, event_bank` / 완료 기준: PRD 6장 컬럼(`is_host`, `participant_token_hash`, `waitlisted_at`, `shares`, `amount_paid`, `reported_at`, `confirmed_at`, `event_bank.id` 포함), FK `on delete cascade`(단 `expenses`·`settlements`의 참여자 FK는 `NO ACTION`: 참여자 삭제로 재무 기록이 사라지지 않게 함. `RESTRICT` 아님), CHECK(status enum, `seats_total>0`, `amount>0`, `guests_count between 0 and 10`)
- [ ] 유니크·인덱스 — `events.share_code`, `participants.participant_token_hash`, `rsvps(event_id, participant_id)`, `carpool_requests(ride_id, participant_id)`, `settlements(event_id, participant_id)`, `event_bank.event_id` / 완료 기준: 중복 insert 시 에러 발생
- [ ] RLS 활성화 — 신규 테이블 전체 + `revoke from anon` / 완료 기준: `anon` 정책 0개, `authenticated`는 `events.host_id = auth.uid()`(하위 테이블은 `is_event_host(event_id)` 헬퍼, `carpool_requests`는 `is_ride_host(ride_id)`) 정책만 존재(총 35개)
- [ ] 컬럼 단위 권한 — `authenticated`의 `participants`는 select(해시 제외 7개 컬럼)·update(`name`,`phone`)·delete만 허용, insert 불가, `is_host` 행 삭제 불가 / 완료 기준: 주최자 세션으로 해시 컬럼 조회 또는 `select('*')` 시 권한 에러. `events`는 `share_code`·`id` 직접 지정/변경 불가(컬럼 단위 insert/update 권한)
- [ ] 주최자 자동 등록 — 이벤트 insert 시 `participants(is_host=true)` 생성(RSVP는 만들지 않음) / 완료 기준: 이벤트당 host 행 1개
- [ ] `share_code` 생성 — DB default 함수 또는 서버 유틸(8자, 혼동 문자 제외 base32 계열) / 완료 기준: 충돌 시 재시도, `crypto` 난수 사용
- [ ] 서비스 롤 클라이언트 — `frontend/src/lib/supabase/admin.ts` (`server-only`) / 완료 기준: 클라이언트 번들에 키가 포함되지 않음(빌드 결과 grep 확인)
- [ ] 참여자 검증 유틸 — `frontend/src/lib/participant/verify.ts` (`share_code` + 쿠키 토큰 sha256 → `{event, participant}`) / 완료 기준: 불일치·취소 이벤트일 때 일관된 에러 반환
- [ ] 타입 정의 — `frontend/src/types/db.types.ts` / 완료 기준: 신규 테이블 Row/Insert 타입 사용 가능

**P1**
- [ ] 디자인 토큰 적용 — `docs/design.shadcn.md` → `globals.css` 변수 / 완료 기준: 버튼·카드가 토큰 색/radius로 렌더링

**리스크/주의**
- 대시보드에서 직접 실행하므로 스키마 드리프트 위험이 있음. SQL 파일 보관과 실행 일자 기록으로 대응.
- `profiles`(기존) 트리거가 카카오 가입 시에도 동작하는지 확인 필요(카카오는 email 미제공 가능성 → `email` nullable 확인).

**DoD**
- SQL Editor 실행 완료, `anon` 키로 신규 테이블 select 시 0행 또는 권한 에러
- `admin.ts`, `verify.ts`가 빌드·린트 통과
- 인프라 단계이므로 Playwright 테스트는 없음

---

## Phase 1 (M1) — 주최자 인증 + 이벤트 + 공지 (1주)

**P0**
- [ ] 카카오 Provider 설정 — Supabase 대시보드 Auth > Providers, Redirect URL 등록 / 완료 기준: 로컬·배포 도메인 모두 콜백 성공
- [ ] 로그인 페이지(신규) — `frontend/src/app/login/page.tsx` (카카오 버튼, `signInWithOAuth`) / 완료 기준: 로그인 후 `next` 파라미터 또는 `/dashboard`로 이동
- [ ] OAuth 콜백 — `frontend/src/app/auth/callback/route.ts` (`exchangeCodeForSession`) / 완료 기준: 세션 쿠키 설정, 실패 시 `/login?error=` 이동
- [ ] 라우트 보호 — `lib/supabase/middleware.ts#updateSession` 확장 / 완료 기준: 비로그인으로 `/dashboard`, `/events/*` 접근 시 `/login?next=` 리다이렉트, `/`, `/login`, `/auth/*`, `/e/*`는 공개
- [ ] `/e/[code]` 정규화 — `frontend/src/middleware.ts`에서 소문자 등 비정규 코드를 대문자로 308 리다이렉트 / 완료 기준: 쿠키 path와 URL 대소문자 일치
- [ ] 이벤트 생성 — `/events/new` + Server Action (`events` insert, `share_code` 발급) / 완료 기준: zod 검증(제목·일시 필수, 정원 1 이상 또는 무제한), 생성 후 manage로 이동
- [ ] 이벤트 수정·마감·취소 — manage 상단 / 완료 기준: `closed`(수동 응답 마감)·`canceled`에서 RSVP·카풀 쓰기 차단(`event_not_open`), 정산은 가능, 참여자 페이지에 상태 표시
- [ ] 내 이벤트 목록 — `(dashboard)/dashboard/page.tsx` 교체 / 완료 기준: 본인 이벤트만 일시 내림차순, 상태 배지 표시
- [ ] manage 탭 골격 — `/events/[id]/manage` (공지/참석자/카풀/정산) / 완료 기준: 타인 이벤트 id 접근 시 404
- [ ] 공지 작성·고정 — `announcements` CRUD, `pinned` 토글 / 완료 기준: 고정 공지가 최상단, 나머지는 최신순
- [ ] 의존성 추가 — `date-fns` / 완료 기준: 일시가 KST 기준으로 표시

**P1**
- [ ] 링크 복사 버튼 — `navigator.clipboard` + `sonner` 토스트 / 완료 기준: 복사 성공 토스트
- [ ] 카톡 공유 — Web Share API(미지원 시 복사로 대체) / 완료 기준: 모바일 공유 시트 호출

**테스트 (Playwright MCP)**
- [ ] 로그인/라우트 보호 Playwright 테스트 -- 시나리오: 비인증 `/dashboard` 접근 → `/login?next=` 리다이렉트, `/e/xxx`는 리다이렉트 없음, 로그인 세션 주입 후 대시보드 표시
- [ ] 코드 정규화 Playwright 테스트 -- 시나리오: `/e/abcd1234` → `/e/ABCD1234` 리다이렉트
- [ ] 이벤트 CRUD Playwright 테스트 -- 시나리오: 생성 → 8자 share_code 링크 노출, 필수값 누락 시 폼 에러, 마감/취소 후 상태 배지 변경
- [ ] 소유권 Playwright 테스트 -- 시나리오: 다른 주최자 이벤트 manage 접근 시 404
- [ ] 공지 Playwright 테스트 -- 시나리오: 작성·수정·삭제, 고정 공지가 최상단 정렬

**리스크/주의**
- 카카오 OAuth는 E2E 자동화가 어려움 → 테스트용 이메일 계정 세션 쿠키 주입 또는 Supabase 테스트 유저 사용.
- 기존 Recoil/axios 구조는 Server Action 중심 설계와 중복될 수 있으므로 신규 기능은 Server Action을 우선 사용.

**DoD**
- 카카오 로그인 → 이벤트 생성 → 공유 링크 복사까지 모바일에서 1분 이내
- RLS로 타인 이벤트 조회·수정 불가 확인
- 해당 Phase의 모든 Playwright MCP 테스트가 통과됨

---

## Phase 2 (M2) — 참여자 진입 + RSVP + 명단 (1주)

**P0**
- [ ] 공개 이벤트 페이지 — `frontend/src/app/e/[shareCode]/page.tsx` (RSC, 서비스 롤 컬럼 명시 조회) / 완료 기준: 잘못된 코드는 404, 이벤트 정보·고정 공지 표시, 주최자 이메일 아이디 등 개인정보 미노출
- [ ] 참여자 등록 — Server Action `joinEvent(shareCode, name, phone?)` / 완료 기준: 토큰 32바이트 이상 난수, DB에는 sha256 해시만 저장, 평문은 httpOnly 쿠키(`pt_<shareCode>`, path `/e/<shareCode>`, `Secure`, `SameSite=Lax`, 1년)
- [ ] `withParticipant` 래퍼 — `frontend/src/lib/participant/withParticipant.ts` / 완료 기준: 모든 참여자 액션이 래퍼 경유, 행위자 ID는 토큰에서만 도출, 전달된 `participantId`/`rideId`/`settlementId`의 `event_id` 재검증. 예외: 로그인한 주최자(`auth.uid() = events.host_id`)는 토큰 없이 해당 이벤트의 `is_host` 참여자 행을 행위자로 인정(해시는 null 유지, 쿠키 발급 불필요)
- [ ] 레이트리밋 — IP + `share_code` 기준으로 `joinEvent`·404 응답·RSVP 제한 / 완료 기준: 임계 초과 시 429, 코드 추측(404 연속) 차단
- [ ] 재방문 인식 — 쿠키 토큰으로 participant 조회 / 완료 기준: 새로고침해도 이름 재입력 없음
- [ ] RSVP 쓰기 단일 경로 — RPC(또는 서버 액션 1곳)에서 `events` 행을 먼저 `for update`로 잠근 뒤 `rsvps` upsert / 완료 기준: 참석/불참/미정 + 동반 0~10, 3탭 이내, 데드락(`40P01`) 시 1~2회 재시도. 주최자의 직접 수정(참석자 상태 변경, 카풀 확정, 정원 변경)은 행을 먼저 잠그므로 events 선잠금 RPC를 거치거나 같은 재시도를 적용
- [ ] 정원·대기 처리 — 정원 = `yes` 본인 + `guests_count` / 완료 기준: 초과 시 `waitlisted`(`waitlisted_at` 기록), 취소 시 FIFO 자동 승격. 빈자리가 있어도 먼저 기다리는 대기자가 있으면 신규 `yes`는 대기(앞지르기 금지). 정원 증가·`closed`→`open` 재개 시에도 자동 승격. 1+동반이 정원보다 큰 신청은 DB가 대기로 저장해 대기열을 막을 수 있으므로 앱 폼에서 먼저 검증
- [ ] 주최자 "나도 참석" 토글 — manage 참석자 탭, 주최자 participants 행의 RSVP 생성/`no` 전환(동일 RSVP 경로 사용) / 완료 기준: 켜면 정원·N빵에 포함, 끄면 제외
- [ ] 주최자 참석자 탭 — 상태별 집계(참석·대기·미정·불참), 동반 포함 총 인원 / 완료 기준: 전화번호는 주최자에게만 표시
- [ ] 공개 명단 — `name`/`status`/`guests_count`만 반환 / 완료 기준: 전화번호·토큰·이메일 미포함

**P1**
- [ ] 응답 마감일 — `events.rsvp_deadline` 컬럼 추가 / 완료 기준: 마감 후 응답 버튼 비활성화
- [ ] 미응답자 목록 — 진입했으나 rsvp가 없는 participants / 완료 기준: 주최자 탭에 표시
- [ ] 토큰 분실 재인증 — 이름 + 전화 뒷자리 4자리 / 완료 기준: 참여자 단위 5회/1시간 잠금, 성공 시 새 토큰 발급·기존 토큰 해시 교체(폐기)

**테스트 (Playwright MCP)**
- [ ] 참여자 진입 Playwright 테스트 -- 시나리오: 이름 입력 → 쿠키(httpOnly·Secure·SameSite=Lax) 발급 → 새로고침 후 유지, 잘못된 shareCode → 404, 취소/마감 이벤트 → 응답 불가(`event_not_open`)
- [ ] RSVP Playwright 테스트 -- 시나리오: 참석 + 동반 2명 저장, 불참으로 수정, 동반 11명 입력 시 에러, 3탭 이내 완료
- [ ] 정원/대기 Playwright 테스트 -- 시나리오: 정원 초과 시 대기, 참석자 취소 시 대기 1순위 승격, 빈자리+대기자 존재 시 신규 yes는 대기, 동반 포함 계산, 동시 응답 시 초과 확정 없음
- [ ] 주최자 참석 토글 Playwright 테스트 -- 시나리오: 토글 ON → 집계 +1, OFF → 제외
- [ ] 접근 통제 Playwright 테스트 -- 시나리오: 다른 이벤트 토큰 거부, 타 이벤트 participantId 전달 시 거부, anon 키 REST 직접 조회 시 0행/권한 에러
- [ ] 레이트리밋 Playwright 테스트 -- 시나리오: 임계 초과 joinEvent·404 연속 요청 시 429
- [ ] 명단 노출 Playwright 테스트 -- 시나리오: 집계 수치 일치, 공개 페이지에 전화번호·이메일 미노출

**리스크/주의**
- 카톡 인앱 브라우저의 쿠키 유지 문제 → 인앱/외부 브라우저 간 토큰 비공유. P1 재인증으로 대응, 베타에서 실측.
- 동일인 중복 등록 가능 → MVP에서는 주최자가 명단에서 삭제할 수 있게 함.
- 레이트리밋 저장소(메모리/Upstash 등)는 서버리스 환경에서 인스턴스 간 공유 여부를 확인.

**DoD**
- 비로그인 참여자가 링크 → 이름 → 응답을 평균 30초 이내에 완료
- 정원·대기 로직이 동시 요청에서도 초과 확정 없이 동작
- 해당 Phase의 모든 Playwright MCP 테스트가 통과됨

---

## Phase 3 (M3) — 카풀 (1주)

**P0**
- [ ] 카풀 페이지 — `frontend/src/app/e/[shareCode]/carpool/page.tsx` / 완료 기준: 차량 카드(운전자·출발지·시간·잔여 좌석), 미등록 참여자는 진입 화면으로 유도
- [ ] 차량 등록·수정·삭제 — `withParticipant` 경유, `carpool_rides` / 완료 기준: 1인 1차량, 좌석 1 이상, 확정 인원 미만으로 축소 시 `carpool_seats_below_confirmed`, 운전자는 RSVP `yes`여야 함(`carpool_requires_rsvp_yes`), `closed`/`canceled`에서 등록·수정 차단(`event_not_open`, 삭제는 허용)
- [ ] 탑승 신청·취소 — 본인만(1신청=1석) / 완료 기준: RSVP `yes`만 가능(`carpool_requires_rsvp_yes`), 본인 차량 불가(`carpool_self_request`), 확정 차량 1대만(`carpool_already_confirmed`), 이벤트 불일치 거부(`carpool_participant_event_mismatch`)
- [ ] 좌석 자동 차감 — Postgres 함수로 `confirmed` 수 ≤ `seats_total` 보장 / 완료 기준: 동시 확정에도 초과 없음(`carpool_seats_full`), 잔여 0이면 신청 버튼 비활성화
- [ ] 확정·거절 — 운전자(토큰) 또는 주최자(RLS) / 완료 기준: `pending → confirmed/rejected` 반영
- [ ] 참석 취소 연동 — RSVP가 `yes`에서 벗어나면 해당 참여자의 신청을 자동 `rejected` / 완료 기준: 운전자 화면에 반영, 좌석 복구
- [ ] 에러 코드 매핑 — `lib/errors.ts`에 카풀 코드 메시지 / 완료 기준: 위 코드가 모두 사용자 메시지로 표시
- [ ] 주최자 카풀 탭 — manage / 완료 기준: 차량별 탑승자, 미배정 참석자 목록

**P1**
- [ ] 귀가 카풀 — `carpool_rides.direction(go/return)` / 완료 기준: 가는 편/오는 편 탭 분리

**테스트 (Playwright MCP)**
- [ ] 차량 등록 Playwright 테스트 -- 시나리오: 정상 등록, 좌석 0 에러, 1인 2차량 거부, 확정 인원 미만 축소 거부
- [ ] 탑승 신청 Playwright 테스트 -- 시나리오: 신청 → 확정 → 잔여 감소, 취소 시 복구, 본인 차량 거부, RSVP 미참석자 거부
- [ ] 좌석 초과 Playwright 테스트 -- 시나리오: 잔여 1석에서 2건 동시 확정 시 1건만 성공
- [ ] 참석 취소 연동 Playwright 테스트 -- 시나리오: 확정 탑승자가 불참으로 변경 → 신청 rejected, 좌석 복구
- [ ] 권한 Playwright 테스트 -- 시나리오: 운전자 아닌 참여자 확정 거부, 주최자 확정 가능, 마감 이벤트에서 신청 거부

**리스크/주의**
- 지도·경로 기능은 범위 밖. 출발지는 자유 텍스트.
- 전화번호는 주최자만 열람. 확정 동승자 간 공개는 Post-MVP.
- 알려진 미구현(DB 범위 밖, 구현 단계에서 처리): 등록된 운전자가 `yes`에서 이탈해도 차량은 자동 삭제되지 않음(주최자 화면에 경고 표시 필요). (`closed`→`open` 재개 시 대기자 승격은 DB 트리거가 자동 처리한다.)

**DoD**
- 운전자 등록부터 탑승 확정까지 참여자 화면만으로 완료 가능
- 좌석 초과가 DB 레벨에서 불가능
- 해당 Phase의 모든 Playwright MCP 테스트가 통과됨

---

## Phase 4 (M4) — 정산 N빵 + 입금 체크 (1주, 주최자 단일 결제 범위)

> 의존: Phase 2의 RSVP `yes` 확정 인원(대기자 제외, 주최자는 "나도 참석" 시 포함)이 정산 대상의 기준이다.

**정산 규칙**
- 모든 지출은 주최자 대표 결제로 간주. `paid_by_participant_id`는 메모용.
- `unit = floor(총액 / Σshares)` (shares = 본인 1 + 동반), 참여자 `amount_due = unit × shares`
- 나머지 원은 주최자가 흡수. 불변식: `Σ참여자 amount_due + 주최자 몫 + 나머지 = 총액`
- 0 가드: 정산 대상 인원 0 또는 총액 0이면 확정 불가
- 주최자 본인 몫은 입금 완료로 자동 처리
- 금액은 정수(원)만, 부동소수점 금지

**P0**
- [ ] 입금 계좌 등록 — manage 정산 탭, `event_bank` upsert / 완료 기준: 주최자만 수정, 참여자 정산 페이지에 표시
- [ ] 지출 항목 CRUD — `expenses` (항목명·금액·결제자 메모) / 완료 기준: 금액 정수(원), 1 이상(DB `amount > 0`)
- [ ] N빵 계산 — 서버 함수 `calculateSettlement(eventId)` / 완료 기준: 위 규칙대로 계산, 불변식 assert, 0 가드
- [ ] 정산 확정 — `settlements` 생성(`shares`·`amount_due`·`confirmed_at` 스냅샷) / 완료 기준: 이후 RSVP 변경은 "재계산" 클릭 시에만 반영
- [ ] 재계산 — 입금 완료 행은 `amount_paid` 보존 / 완료 기준: 잔액 = `amount_due - amount_paid` (양수=추가 청구, 음수=환불) 표시
- [ ] 참여자 정산 페이지 — `frontend/src/app/e/[shareCode]/settle/page.tsx` / 완료 기준: 내 부담금·잔액, 계좌(복사 버튼), 입금 상태
- [ ] 입금 완료 체크 — 참여자 "입금했어요"(`reported_at`) + 주최자 확인(`paid`, `paid_at`, `amount_paid`) / 완료 기준: 주최자 탭에 미입금자 목록

**P1**
- [ ] 정산 변경 이력 — `settlement_logs` 테이블 / 완료 기준: 금액·항목 변경 이력 표시
- [ ] 가중치(불참/반액) — 완료 기준: 가중치 반영 후에도 불변식 유지
- [ ] 영수증 사진 — Supabase Storage(private 버킷, 서명 URL) / 완료 기준: 주최자와 해당 이벤트 참여자만 열람

**테스트 (Playwright MCP)**
- [ ] 지출 등록 Playwright 테스트 -- 시나리오: 항목 추가·수정·삭제, 음수/빈 금액 에러
- [ ] N빵 계산 Playwright 테스트 -- 시나리오: 10,000원 ÷ 3명 → 3,333원×3 + 주최자 흡수 1원, 동반 합산, 대기자·불참자 제외, 주최자 참석 시 포함
- [ ] 0 가드 Playwright 테스트 -- 시나리오: 참석자 0명 또는 총액 0원에서 확정 버튼 거부
- [ ] 재계산 Playwright 테스트 -- 시나리오: 입금 완료 후 지출 추가 → `amount_paid` 보존, 양수 잔액(추가 청구) 표시, 지출 삭제 → 음수 잔액(환불) 표시
- [ ] 입금 체크 Playwright 테스트 -- 시나리오: 참여자 입금 표시 → 주최자 확인 → 미입금 목록 제외, 타 참여자 `settlementId` 전달 시 거부

**리스크/주의**
- 송금 연동(토스/카카오페이)은 범위 밖. 계좌 복사까지만 제공.
- 다중 결제자 정산은 Post-MVP.

**DoD**
- 모임 후 주최자가 지출 입력부터 정산 링크 공유까지 3분 이내
- 모든 분배 결과가 불변식을 만족
- 해당 Phase의 모든 Playwright MCP 테스트가 통과됨

---

## Phase 5 (M5) — 모바일 QA · 보안 점검 · 배포 (1주)

**P0**
- [ ] 모바일 QA — iOS Safari, Android Chrome, **카카오톡 인앱 브라우저** / 완료 기준: 주요 플로우에서 레이아웃 깨짐·쿠키 유실 없음(360px 폭 기준)
- [ ] 전체 회귀 E2E — Phase 1~4 Playwright 스위트 일괄 실행 / 완료 기준: 전부 통과
- [ ] 보안 점검 — anon 키 REST 직접 호출, 서비스 롤 키 번들 노출, 타 이벤트 토큰 재사용, 주최자 세션의 `participant_token_hash` 조회, **RSC payload에 token/phone 문자열 없음(grep)**, 신규 테이블 RLS·anon revoke 재확인 / 완료 기준: 전부 차단
- [ ] 배포 — Vercel 환경변수(`SUPABASE_SERVICE_ROLE_KEY` 포함), 카카오 Redirect URL 운영 도메인 등록 / 완료 기준: 운영 URL에서 로그인 → 정산 전체 플로우 성공

**P1**
- [ ] OG 메타 — `/e/[shareCode]` og:title/description / 완료 기준: 카톡 링크 미리보기 노출

**테스트 (Playwright MCP)**
- [ ] 모바일 뷰포트 Playwright 테스트 -- 시나리오: iPhone/Pixel 에뮬레이션으로 진입 → RSVP → 카풀 신청 → 정산 확인 전체 플로우
- [ ] 보안 회귀 Playwright 테스트 -- 시나리오: 토큰 쿠키 삭제 후 재진입 요구, 위조 토큰 거부, 페이지 응답에 토큰·전화번호 문자열 미포함

**DoD**
- 운영 배포 완료, 치명 버그 0건
- 해당 Phase의 모든 Playwright MCP 테스트가 통과됨

---

## 베타 운영 (개발과 병행)

- [ ] 실제 교회 모임 2~3팀 / 완료 기준: 팀별 이벤트 1회 이상 진행, 피드백 수집
- [ ] 카톡 인앱 브라우저 쿠키 유지 실측(첫 주 우선)
- [ ] 지표 수집(P1) — 응답률·응답 소요 시간·재생성률 / 완료 기준: **베타 종료 후** KPI 3종 산출
- 병행 작업: 베타 버그 수정, Phase 2~4 P1. 신규 요구는 백로그로 보내 범위 확대를 경계.

---

## 리스크 요약

| 리스크 | 영향 | 확률 | 대응 |
|---|---|---|---|
| 참여자 토큰 분실(인앱 브라우저·기기 변경) | 상 | 상 | httpOnly 쿠키 + 재인증(P1, 5회/1시간 잠금, 토큰 재발급) |
| 토큰·개인정보 유출 | 상 | 하 | 해시 저장, 컬럼 단위 권한, 컬럼 명시 조회, RSC payload grep |
| 서비스 롤 키 노출 | 상 | 하 | `server-only` 모듈, `NEXT_PUBLIC_` 금지, 빌드 결과 점검 |
| share_code 추측·남용 | 중 | 중 | 8자 난수 + IP·코드 기준 레이트리밋 |
| 정원·좌석 동시성 초과/데드락 | 중 | 중 | events 선잠금 단일 경로, 행 잠금, 40P01 재시도 |
| 정산 금액 분쟁 | 중 | 중 | 확정 스냅샷 + 잔액 표시, 나머지 주최자 흡수 고지, 변경 이력(P1) |
| 스키마 드리프트(대시보드 직접 실행) | 중 | 중 | `supabase/schema.sql` 보관, 실행 기록 |
| 카카오 OAuth E2E 자동화 어려움 | 하 | 상 | 테스트 계정 세션 주입 |
| 1인 개발 일정 지연 | 중 | 중 | 7~8주 추정, P1은 베타와 병행 |

## 확정 사항

1. 정원·N빵 인원은 `yes` 응답자 본인 + `guests_count`(0~10)로 계산하고, 동반 몫은 응답자에게 합산한다.
2. 정원 초과는 `rsvps.status = waitlisted` + `waitlisted_at` FIFO 승격.
3. `participant_token` 평문은 httpOnly 쿠키에만, DB에는 sha256 해시만. 주최자는 해시 컬럼 접근 불가.
4. 이벤트 생성 시 주최자를 `participants(is_host=true)`로 자동 등록. 기본 미참석, "나도 참석" 토글로 RSVP 생성.
5. 정산은 주최자 단일 결제. 나머지 원은 주최자 흡수, 금액은 확정 시점에 고정.
6. `/login`은 신규 생성. 전화번호 열람은 MVP에서 주최자만.

## 백로그 (Post-MVP)

카톡 알림톡, 반복 모임, 그룹 단위 관리, 지도 경로, 토스/카카오페이 송금 연동, 회비 자동 납부, admin 대시보드, 공지 읽음 수(별도 테이블), 정산 리마인드, 다중 결제자 정산, 확정 동승자 간 전화번호 공개

## 진행 추적

- 체크포인트: 각 Phase 종료일에 DoD 점검 → 다음 Phase 착수
- 보고: 이 문서의 체크박스를 갱신하고, Phase별 Playwright 결과(통과/실패 수)를 PR 설명에 기록
