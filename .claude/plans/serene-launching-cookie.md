# 모임 이벤트 관리 웹 MVP 기획 (단계별)

## Context
교회 수영·헬스·팀모임·소그룹 등 친구 모임의 **주최자**는 공지 → 참석 파악 → 카풀 → 정산을 카톡방에서 수작업으로 처리한다.
정보가 채팅에 묻히고, 누가 오는지/누가 돈을 냈는지 매번 다시 세야 한다.
→ 한 이벤트 = 한 링크 안에서 **공지·참석·카풀·정산**을 끝내는 웹 MVP를 기획한다.

**확정된 결정 (사용자 답변)**
- 참여자 인증: **로그인 없음, 공유 링크 + 이름만** (주최자만 로그인)
- 이번 산출물: **기획 문서(PRD)만** — 구현은 다음 단계
- MVP 기능: 이벤트 생성+공지 / 참석 응답(RSVP) / 카풀 매칭 / 정산(N빵) 전부 포함

**산출물**: `docs/PRD.md` (아래 Step 1~8 내용을 정리해 작성) — 기존 스타터의 `frontend/`(포트 3000)를 대상으로 하고, `admin/`은 MVP 범위 밖.

---

## Step 1. 문제 정의 & 타깃
| 구분 | 내용 |
|---|---|
| 핵심 문제 | 공지·참석·카풀·정산이 카톡방에 흩어져 주최자 부담 큼, 참여자는 정보를 찾기 어려움 |
| 1차 타깃 | 교회 소그룹/셀 리더, 수영·헬스 동호회 총무, 친구 모임 주최자 (월 1~4회 모임) |
| 대체재 | 카카오톡 공지·투표, 구글폼, 엑셀, 토스 정산 |
| 차별점 | 한 링크에 4가지 기능 통합, **참여자 가입 불필요**, 모바일 우선 |

**페르소나**
- 주최자 "총무 민수"(35): 매번 공지 쓰고 인원 세고 N빵 계산이 귀찮음
- 참여자 "게스트 지현"(28): 앱 설치/가입 싫음, 링크 눌러 3탭 안에 응답하고 싶음

## Step 2. MVP 범위 (In / Out)
**In (4대 기능)**
1. 이벤트 생성 + 공지 + 공유 링크
2. 참석 응답(참석/불참/미정) + 동반 인원 + 명단
3. 카풀: 운전자가 차량 등록(좌석·출발지·시간), 탑승자가 신청, 주최자/운전자 확정
4. 정산: 지출 항목 등록 → 참석자 기준 N빵 → 입금 확인 체크

**Out (Post-MVP)**: 카톡 알림톡 자동발송, 반복 모임, 그룹(모임 단위) 관리, 지도 경로, 토스/카카오페이 송금 연동, 회비 자동 납부, 관리자(admin) 대시보드

## Step 3. 핵심 사용자 여정
**주최자**: 카카오 로그인 → 이벤트 만들기(제목·일시·장소·정원·설명) → 공유 링크 복사 → 카톡방 투척 → 대시보드에서 참석 현황/카풀/정산 확인 → 모임 후 정산 요청
**참여자**: 링크 클릭 → 이름 입력(1회, 브라우저에 `participant_token` 저장) → 참석 응답 → (선택) 카풀 신청/등록 → 정산 금액·입금 계좌 확인

## Step 4. 화면 목록 (모바일 우선)
| 경로 | 대상 | 설명 |
|---|---|---|
| `/` | 공개 | 소개 + 이벤트 만들기 CTA |
| `/login` | 주최자 | 카카오(OAuth) 로그인 (기존 로그인 페이지 재사용) |
| `/dashboard` | 주최자 | 내 이벤트 목록 |
| `/events/new` | 주최자 | 이벤트 생성 폼 |
| `/events/[id]/manage` | 주최자 | 탭: 공지 / 참석자 / 카풀 / 정산 |
| `/e/[shareCode]` | 참여자 | 이벤트 상세 + RSVP + 공지 (공개 링크) |
| `/e/[shareCode]/carpool` | 참여자 | 카풀 목록·등록·신청 |
| `/e/[shareCode]/settle` | 참여자 | 내 부담금·계좌·입금 상태 |

## Step 5. 기능 요구사항 (우선순위 P0 필수 / P1 권장)
- **이벤트·공지**: P0 생성·수정·취소, 공유 링크(`share_code` 랜덤 8자), 공지 작성/고정 · P1 공지 읽음 수, 링크 복사 버튼 + 카톡 공유
- **RSVP**: P0 참석/불참/미정, 동반 인원, 응답 수정, 정원 초과 시 대기 · P1 응답 마감일, 미응답자 목록
- **카풀**: P0 운전자 차량 등록(좌석수·출발지·출발시간), 탑승 신청/취소, 좌석 자동 차감, 운전자 확정 · P1 동승자 연락처 공개, 귀가 카풀
- **정산**: P0 지출 항목(항목명·금액·결제자) 등록, 참석자 균등 N빵, 입금 계좌 표시, 입금 완료 체크 · P1 사람별 가중치(불참/반액), 지출 영수증 사진

**비기능**: 모바일 우선 반응형, 응답 3탭 이내, 링크 추측 불가(랜덤 코드), 개인정보 최소화(이름·선택 연락처)

## Step 6. 데이터 모델 (Supabase)
```
profiles(기존)  id, email, full_name, avatar_url, role
events          id, host_id→profiles, title, description, starts_at, location,
                capacity, share_code(unique), status(open/closed/canceled)
participants    id, event_id, name, phone?, participant_token(unique), created_at
rsvps           id, event_id, participant_id, status(yes/no/maybe), guests_count
announcements   id, event_id, content, pinned, created_at
carpool_rides   id, event_id, driver_participant_id, seats_total, depart_from, depart_at, memo
carpool_requests id, ride_id, participant_id, status(pending/confirmed/rejected)
expenses        id, event_id, title, amount, paid_by_participant_id
settlements     id, event_id, participant_id, amount_due, paid(bool), paid_at
event_bank      event_id, bank_name, account_number, holder  (정산 계좌)
```
**인증/보안 핵심**: 참여자는 비로그인이므로 `anon`에 테이블 직접 접근을 주지 않는다 → Next.js **Server Action/Route Handler**에서 `share_code` + `participant_token` 검증 후 서비스 롤로 접근. 주최자 접근은 RLS(`events.host_id = auth.uid()`). 스키마는 기존 방침대로 **Supabase 대시보드 SQL Editor**에서 실행.

## Step 7. 기술 접근 (기존 스타터 재사용)
- 대상 앱: `frontend/` — Next.js 14 App Router + Tailwind + shadcn/ui + @supabase/ssr + Axios (README 기준)
- 기존 인증 흐름 재사용: `middleware.ts` → `lib/supabase/middleware.ts#updateSession`; 보호 라우트 `/dashboard`, 공개 라우트에 `/e/*` 추가
- `docs/TECH-STACK-PRIORITY.md` 원칙: **기능 구현 시점에** 의존성 추가 (`react-hook-form`+`zod` = 이벤트 폼, `date-fns` = 일시, `sonner` = 토스트)
- 디자인: `docs/DESIGN.shadcn.md` 토큰을 기본값으로 사용, 01번 분위기 단어만 정하면 됨

## Step 8. 로드맵 · 지표 · 리스크
| 단계 | 기간 | 내용 |
|---|---|---|
| M0 | 0.5주 | PRD 확정, 디자인 토큰, Supabase 스키마 |
| M1 | 1주 | 주최자 로그인, 이벤트 CRUD, 공유 링크, 공지 |
| M2 | 1주 | 참여자 진입(이름+토큰), RSVP, 명단 |
| M3 | 1주 | 카풀 등록/신청/확정 |
| M4 | 1주 | 정산 N빵 + 입금 체크 |
| M5 | 0.5주 | 모바일 QA, 베타(실제 교회 모임 2~3팀) |

**성공 지표**: 이벤트당 응답률 ≥ 80%, 주최자 재생성률(2회 이상 이벤트) ≥ 40%, 응답 완료까지 평균 30초 이내
**리스크**: ① 비로그인 참여자의 토큰 분실 → 이름+전화 뒷자리 재인증 P1 ② 정산 금액 분쟁 → 변경 이력 표시 ③ 개인정보(전화번호) → 선택 입력·주최자만 열람

---

## 작업 (승인 후 수행)
1. 위 Step 1~8을 `docs/PRD.md`로 작성 (이전에 삭제 상태인 파일을 새 내용으로 대체)
2. 코드/스키마 변경 없음 (기획 문서만)

## 검증
- `docs/PRD.md`가 Step 1~8을 모두 포함하는지, 기능 4종·인증 방식·Out 범위가 위 확정 사항과 일치하는지 확인
- 데이터 모델의 모든 기능 요구사항(P0)이 테이블/화면에 매핑되는지 교차 점검
