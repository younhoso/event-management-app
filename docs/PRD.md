# 모임 이벤트 관리 웹 MVP — PRD

> 한 이벤트 = 한 링크. 공지·참석·카풀·정산을 카톡방 밖으로 꺼내 한곳에서 끝낸다.

- 대상 앱: `frontend/` (Next.js 14 App Router + Tailwind + shadcn/ui + Supabase)
- 범위: MVP (4대 기능). `admin/`은 MVP 범위 밖

---

## 1. 문제 정의 & 타깃

| 구분 | 내용 |
|---|---|
| 핵심 문제 | 공지·참석·카풀·정산이 카톡방에 흩어져 주최자 부담이 크고, 참여자는 정보를 찾기 어렵다 |
| 1차 타깃 | 교회 소그룹/셀 리더, 수영·헬스 동호회 총무, 친구 모임 주최자 (월 1~4회 모임) |
| 대체재 | 카카오톡 공지·투표, 구글폼, 엑셀, 토스 정산 |
| 차별점 | 한 링크에 4가지 기능 통합 / **참여자 가입 불필요** / 모바일 우선 |

### 페르소나
- **주최자 "총무 민수"(35)**: 매번 공지 쓰고, 인원 세고, N빵 계산하는 게 귀찮다.
- **참여자 "게스트 지현"(28)**: 앱 설치·가입이 싫다. 링크 눌러 3탭 안에 응답하고 싶다.

## 2. MVP 범위

### In (4대 기능)
1. 이벤트 생성 + 공지 + 공유 링크
2. 참석 응답(참석/불참/미정) + 동반 인원 + 명단
3. 카풀: 운전자가 차량 등록(좌석·출발지·시간), 탑승자가 신청, 운전자/주최자가 확정
4. 정산: 지출 항목 등록 → 참석자 기준 N빵(주최자 단일 결제) → 입금 확인 체크

### Out (Post-MVP)
카톡 알림톡 자동발송, 반복 모임, 모임(그룹) 단위 관리, 지도 경로, 토스/카카오페이 송금 연동, 회비 자동 납부, 관리자(admin) 대시보드, 다중 결제자 정산, 확정 동승자 간 전화번호 공개

## 3. 핵심 사용자 여정

**주최자**
카카오 로그인 → 이벤트 만들기(제목·일시·장소·정원·설명) → 공유 링크 복사 → 카톡방에 공유 → 대시보드에서 참석/카풀/정산 확인(본인도 참석하면 "나도 참석" 토글) → 모임 후 정산 요청

**참여자**
링크 클릭 → 이름 입력(최초 1회, `participant_token`을 httpOnly 쿠키로 저장) → 참석 응답 → (선택) 카풀 등록/신청 → 내 부담금·입금 계좌 확인

## 4. 화면 목록 (모바일 우선)

| 경로 | 대상 | 설명 |
|---|---|---|
| `/` | 공개 | 서비스 소개 + 이벤트 만들기 CTA |
| `/login` | 주최자 | 카카오(OAuth) 로그인 (**신규 생성**, 현재 코드에 없음) |
| `/dashboard` | 주최자 | 내 이벤트 목록 |
| `/events/new` | 주최자 | 이벤트 생성 폼 |
| `/events/[id]/manage` | 주최자 | 탭: 공지 / 참석자 / 카풀 / 정산 |
| `/e/[shareCode]` | 참여자 | 이벤트 상세 + RSVP + 공지 (공개 링크) |
| `/e/[shareCode]/carpool` | 참여자 | 카풀 목록·등록·신청 |
| `/e/[shareCode]/settle` | 참여자 | 내 부담금·계좌·입금 상태 |

## 5. 기능 요구사항

우선순위: **P0** 필수 / **P1** 권장

### 5.1 이벤트·공지
- P0: 이벤트 생성·수정·취소·응답 마감, 공유 링크(`share_code` 랜덤 8자), 공지 작성/고정
- 상태: `open`(응답 가능) / `closed`(주최자가 수동으로 응답 마감) / `canceled`(취소). `closed`·`canceled`에서는 RSVP·카풀 쓰기 차단, 정산은 가능
- P1: 공지 읽음 수, 링크 복사 버튼 + 카톡 공유

### 5.2 참석 응답(RSVP)
- P0: 참석/불참/미정, 동반 인원(`guests_count` 0~10), 응답 수정, 정원 초과 시 대기(`waitlisted`) 처리
- P0: 주최자는 기본 미참석. 관리 화면 "나도 참석" 토글을 켜면 주최자 RSVP(`yes`) 행이 생겨 정원·N빵에 포함
- 정원·N빵 인원 = `yes` 응답자 본인 + `guests_count` (동반 몫은 응답자에게 합산)
- P1: 응답 마감일, 미응답자 목록

### 5.3 카풀
- P0: 운전자 차량 등록(좌석수·출발지·출발시간), 탑승 신청/취소, 좌석 자동 차감, 운전자 확정
- 규칙: 신청은 본인만(1신청=1석), RSVP `yes`인 참여자만 신청·차량 등록 가능, 참석을 취소(`yes` 이탈)하면 해당 신청은 자동 거절. `closed`/`canceled`에서는 차량 등록·수정과 신청이 모두 차단(삭제는 허용)
- P1: 귀가 카풀

### 5.4 정산(N빵) — 주최자 단일 결제
- P0: 지출 항목(항목명·금액·결제자 메모) 등록, 참석자 균등 N빵, 입금 계좌 표시, 입금 완료 체크
- 모든 지출은 **주최자가 대표 결제**한 것으로 간주한다. 결제자 필드는 메모용이며 계산에 쓰지 않는다.
- 계산: `unit = floor(총액 / Σshares)`, 참여자 `amount_due = unit × shares`. 나머지 원은 주최자가 흡수
- 불변식: `Σ참여자 amount_due + 주최자 몫 + 나머지 = 총액`
- 가드: 정산 대상 인원 0 또는 총액 0이면 정산 확정 불가
- 확정 시점에 인원·금액을 고정(스냅샷). 이후 변경은 주최자가 "재계산"을 눌러야 반영
- 입금 완료 후 지출이 바뀌면 `amount_paid`를 보존하고 잔액(`amount_due - amount_paid`, 양수=추가 청구, 음수=환불)으로 표시
- 주최자 본인 몫(참석 시)은 입금 완료로 자동 처리
- P1: 사람별 가중치(불참/반액), 영수증 사진

### 5.5 비기능
- 모바일 우선 반응형, 참여자 응답 3탭 이내
- 링크 추측 불가(랜덤 코드)
- 개인정보 최소화(이름 필수, 전화번호 선택·**주최자만** 열람). 공개 명단은 이름·상태·동반 인원만 표시, 주최자 이메일(아이디) 비노출

## 6. 데이터 모델 (Supabase)

```
profiles(기존)    id, email, full_name, avatar_url, role
events            id, host_id→profiles, title, description, starts_at, location,
                  capacity, share_code(unique), status(open/closed/canceled)
participants      id, event_id, name, phone?, participant_token_hash(unique, sha256,
                  주최자 행은 null), is_host(bool), created_at
rsvps             id, event_id, participant_id, status(yes/no/maybe/waitlisted),
                  guests_count(0~10), waitlisted_at
announcements     id, event_id, content, pinned, created_at
carpool_rides     id, event_id, driver_participant_id, seats_total, depart_from, depart_at, memo
carpool_requests  id, ride_id, participant_id, status(pending/confirmed/rejected)
expenses          id, event_id, title, amount, paid_by_participant_id(메모용)
settlements       id, event_id, participant_id, shares, amount_due, amount_paid,
                  paid(bool), paid_at, reported_at, confirmed_at
event_bank        id, event_id(unique), bank_name, account_number, holder
```

- `participants.is_host`: 이벤트 생성 시 주최자 participants 행 자동 등록(카풀·정산 참여용). 정원·N빵 포함 여부는 "나도 참석" RSVP로 결정
- `rsvps.waitlisted_at`: 대기 순번(FIFO) 기준
- `settlements.shares`: 확정 시점 몫(본인 1 + 동반), `amount_paid`: 실제 입금액, `reported_at`: 참여자 "입금했어요", `confirmed_at`: 정산 확정 시각

### 인증/보안
- **주최자**: Supabase Auth(카카오). RLS로 `events.host_id = auth.uid()` 소유자만 관리.
- **참여자(비로그인)**: `anon`에 테이블 직접 접근을 주지 않는다. Next.js Server Action/Route Handler에서 `share_code` + `participant_token`을 검증한 뒤 서비스 롤로 접근한다.
- **토큰 저장**: 평문 토큰은 httpOnly 쿠키에만 둔다. DB에는 sha256 해시(`participant_token_hash`)만 저장하고, 검증 시 쿠키 값을 해시해 비교한다.
- **컬럼 단위 권한**: 주최자(`authenticated`)는 `participants.participant_token_hash`를 조회·수정할 수 없고, `participants`를 직접 생성할 수 없으며, 자동 등록된 주최자 행(`is_host`)은 삭제할 수 없다.
- **주최자의 참여자 동작**: 로그인한 주최자는 토큰 없이 Auth 세션(`auth.uid() = events.host_id`)으로 `is_host` 참여자 행을 행위자로 인정한다(쿠키·해시 발급 불필요).
- 스키마는 기존 방침대로 **Supabase 대시보드 SQL Editor**에서 실행한다.

## 7. 기술 접근 (기존 스타터 재사용)

- 인증 흐름 재사용: `frontend/src/middleware.ts` → `lib/supabase/middleware.ts#updateSession`. 보호 라우트 `/dashboard`, `/events/*`; 공개 라우트에 `/e/*` 추가 (현재 리다이렉트 로직 없음 → 확장 필요)
- `docs/TECH-STACK-PRIORITY.md` 원칙에 따라 **기능 구현 시점에** 의존성 추가 (`react-hook-form`+`zod`: 폼, `date-fns`: 일시, `sonner`: 토스트)
- 디자인은 `docs/design.shadcn.md` 토큰을 기본값으로 시작

## 8. 로드맵 · 지표 · 리스크

| 단계 | 기간 | 내용 |
|---|---|---|
| M0 | 0.5주 | PRD 확정, 디자인 토큰, Supabase 스키마 |
| M1 | 1주 | 주최자 로그인, 이벤트 CRUD, 공유 링크, 공지 |
| M2 | 1주 | 참여자 진입(이름+토큰), RSVP, 명단 |
| M3 | 1주 | 카풀 등록/신청/확정 |
| M4 | 1주 | 정산 N빵(주최자 단일 결제) + 입금 체크 |
| M5 | 1주 | 모바일 QA·보안 점검·배포 |
| 베타 | 병행 | 실제 교회 모임 2~3팀 (지표는 베타 종료 후 측정) |

> 1인 개발 기준 버퍼 포함 약 7~8주 추정. 상세는 `docs/ROADMAP.md`.

### 성공 지표
- 이벤트당 응답률 ≥ 80%
- 주최자 재생성률(이벤트 2회 이상) ≥ 40%
- 참여자 응답 완료까지 평균 30초 이내

### 리스크
1. 비로그인 참여자의 토큰 분실 → 이름 + 전화 뒷자리 재인증 (P1, 새 토큰 발급·기존 토큰 폐기)
2. 정산 금액 분쟁 → 확정 스냅샷 + 잔액 표시, 변경 이력(P1)
3. 개인정보(전화번호) → 선택 입력, 주최자만 열람

## 9. 확정된 가정

아래 5개 가정은 팀 확인을 거쳐 **확정**되었다.

1. 정원·N빵 인원은 `yes` 응답자 본인 + `guests_count`로 계산하고, 동반 몫은 응답자에게 합산한다.
2. 정원 초과 응답은 `rsvps.status = waitlisted`로 저장하고, `waitlisted_at` 순으로 자동 승격한다.
3. `participant_token`은 httpOnly 쿠키에 저장한다(DB에는 해시만).
4. 이벤트 생성 시 주최자를 `participants`(`is_host=true`)에 자동 등록한다.
5. 나머지 원은 주최자가 흡수하고, 정산 금액은 확정 시점에 고정한다.
