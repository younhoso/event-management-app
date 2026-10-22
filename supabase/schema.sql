-- =============================================================================
-- 모임 이벤트 관리 웹 MVP — Supabase 스키마 (Phase 0 / M0)
-- 근거 문서: docs/PRD.md "5.4 정산", "6. 데이터 모델", docs/ROADMAP.md "Phase 0", "확정 사항"
-- =============================================================================
--
-- [실행 방법]
--   Supabase 대시보드 > SQL Editor 에 이 파일 전체를 붙여넣고 한 번에 실행한다.
--
-- [실행 순서] (파일 안에서 아래 순서대로 정의되어 있음)
--   0. 확장(pgcrypto) 확인
--   1. 공통 함수 (updated_at 갱신, share_code 생성)
--   2. 테이블 생성 (events → participants → rsvps → announcements
--                   → carpool_rides → carpool_requests → expenses → settlements → event_bank)
--   3. 인덱스
--   4. RLS 헬퍼 함수 (SECURITY DEFINER, search_path 고정)
--   5. 비즈니스 트리거 (주최자 자동 등록, 이벤트 상태 가드, 정원/대기, 카풀 좌석·RSVP 연동,
--                       정산 상태 동기화, updated_at)
--   6. 권한(GRANT/REVOKE, participants 컬럼 단위 권한) + RLS 활성화 + 정책
--   7. 검증 쿼리 (파일 맨 아래 주석)
--
-- [멱등성] 여러 번 실행해도 안전하도록 작성했다.
--   - create extension / table / index ... if not exists
--   - create or replace function
--   - drop trigger if exists → create trigger
--   - drop policy if exists → create policy
--   - revoke all → grant (권한은 매번 처음부터 다시 부여)
--   주의: create table if not exists 는 "이미 있는 테이블의 컬럼 변경"을 하지 않는다.
--         컬럼을 바꿔야 하면 별도의 alter table 스크립트를 supabase/ 에 번호를 붙인 파일(예: 002_xxx.sql)로 추가한다.
--
-- [전제] 아래 객체는 이미 존재하므로 여기서 재생성하지 않는다.
--   - public.profiles (id uuid → auth.users, email, full_name, avatar_url, role user/admin)
--   - public.handle_new_user() 및 auth.users 트리거
--
-- [보안 주의] SUPABASE_SERVICE_ROLE_KEY 는 `import 'server-only'` 를 단 서버 모듈에서만 사용하고,
--             절대 NEXT_PUBLIC_ 접두사를 붙이거나 클라이언트 번들에 포함시키지 않는다.
--
-- [접근 모델]
--   - anon: 신규 테이블에 대한 정책 0개 + 테이블 권한 REVOKE. 참여자(비로그인) 동작은
--           Server Action / Route Handler 가 share_code 로 이벤트를 찾고, httpOnly 쿠키의 평문 토큰을
--           sha256 해시해 participants.participant_token_hash 와 비교(+ event_id 일치 확인)한 뒤
--           서비스 롤로 처리한다. 평문 토큰은 DB 에 저장하지 않는다.
--   - authenticated(주최자): events.host_id = auth.uid() 인 이벤트와 그 하위 행만 CRUD.
--           단 participants 는 컬럼 단위 권한으로 제한한다 (insert 불가, participant_token_hash 조회·수정 불가).
--   - service_role: RLS 우회(BYPASSRLS). 서버 전용. 참여자 생성·토큰 해시 기록은 서비스 롤만 한다.
--
-- [향후 추가 테이블 필수 체크] 새 테이블을 만들면 반드시 enable row level security + revoke all ... from anon.
--
-- [정산 모델 — 주최자 단일 결제] (PRD 5.4)
--   모든 지출은 주최자가 대표 결제한 것으로 간주한다(expenses.paid_by_participant_id 는 메모용, 계산에 미사용).
--   unit = floor(총액 / Σshares), 참여자 amount_due = unit × shares.
--   합계 불변식: Σamount_due(주최자 외 참여자) + 주최자 몫 + 나머지 = 총액. 나머지(원 단위 끝전)는 주최자가 흡수한다.
--   정산 대상 인원 0 또는 총액 0 이면 정산 확정 불가 — 이 불변식과 가드는 DB 가 아니라 앱(서버)에서 검사한다.
--   잔액 = amount_due - amount_paid (양수 = 추가 청구, 음수 = 환불).
--
-- [PRD 대비 추가 컬럼] (PRD 6장 기준. PRD 에 이미 명시된 컬럼도 DB 표현 방식을 함께 적는다)
--   - participants.participant_token_hash : sha256 hex(64자) 해시만 저장, 평문 미저장. 주최자 행만 null 허용 (5-1 참고)
--   - participants.is_host          : 이벤트 생성 시 자동 등록된 주최자 참여자 행 표시 (가정 3)
--   - rsvps.waitlisted_at           : 대기 순번(FIFO) 기준 시각 (Phase 2 대기자 자동 승격)
--   - settlements.shares            : 확정 시점 몫 수(본인 1 + 동반 인원) 스냅샷 (가정 1)
--   - settlements.amount_paid       : 실제 입금액. paid 전환 시 amount_due 로 채워지고, 재계산으로 금액이 바뀌어도 보존
--   - settlements.reported_at       : 참여자 "입금했어요" 표시 시각 (주최자 확인 = paid/paid_at)
--   - settlements.confirmed_at      : 정산 확정(스냅샷) 시각
--   - (PRD 미기재) 모든 신규 테이블 created_at / updated_at
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. 확장
-- -----------------------------------------------------------------------------
-- Supabase 는 pgcrypto 를 extensions 스키마에 설치한다. gen_random_bytes() 사용을 위해 필요.
-- (gen_random_uuid() 는 PostgreSQL 13+ 코어 함수라 확장 없이 사용 가능)
create extension if not exists pgcrypto with schema extensions;


-- -----------------------------------------------------------------------------
-- 1. 공통 함수
-- -----------------------------------------------------------------------------

-- updated_at 자동 갱신 트리거 함수
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- share_code 생성 함수: 8자, 혼동 문자(0/O, 1/I/L 중 I·O·0·1) 제외 32자 알파벳
--   - 암호학적 난수(pgcrypto gen_random_bytes) 사용, 256 % 32 = 0 이므로 모듈로 편향 없음
--   - 기존 코드와 충돌하면 최대 10회 재시도
--   - 동시 insert 로 인한 극히 드문 충돌은 unique 제약이 막으므로 서버에서 재시도한다
--   - SECURITY DEFINER: RLS 와 무관하게 전체 events 를 대상으로 충돌을 검사하기 위함
create or replace function public.generate_share_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32자
  v_bytes   bytea;
  v_code    text;
  v_attempt integer := 0;
  i         integer;
begin
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code  := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;

    if not exists (select 1 from public.events e where e.share_code = v_code) then
      return v_code;
    end if;

    v_attempt := v_attempt + 1;
    if v_attempt >= 10 then
      raise exception 'share_code_generation_failed';
    end if;
  end loop;
end;
$$;


-- -----------------------------------------------------------------------------
-- 2. 테이블
-- -----------------------------------------------------------------------------

-- 2-1. 이벤트
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  host_id     uuid not null references public.profiles (id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 100),
  description text check (description is null or char_length(description) <= 5000),
  starts_at   timestamptz not null,
  location    text check (location is null or char_length(location) <= 200),
  capacity    integer check (capacity is null or capacity > 0),          -- null = 무제한
  share_code  text not null unique default public.generate_share_code()
              check (share_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  -- open 이 아니면 rsvps / carpool_requests 쓰기를 트리거(5-2, 5-4)가 막는다. 정산·지출은 막지 않는다.
  status      text not null default 'open'
              check (status in ('open', 'closed', 'canceled')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2-2. 참여자 (비로그인, 토큰 기반)
--   평문 participant_token 은 httpOnly 쿠키에만 존재하고 DB 에는 저장하지 않는다.
--   서버가 sha256(평문 토큰) 을 hex 소문자 64자로 계산해 participant_token_hash 에 넣는다 (default 없음).
--   주최자 행(is_host)만 해시 null 허용: 5-1 handle_new_event 주석 참고.
--   unique 는 null 을 서로 다른 값으로 취급하므로(NULLS DISTINCT 기본값) 주최자 행 여러 개의 null 이 충돌하지 않는다.
create table if not exists public.participants (
  id                     uuid primary key default gen_random_uuid(),
  event_id               uuid not null references public.events (id) on delete cascade,
  name                   text not null check (char_length(btrim(name)) between 1 and 50),
  phone                  text check (phone is null or phone ~ '^[0-9+ -]{7,20}$'),  -- 선택, 주최자만 열람
  participant_token_hash text unique
                         check (participant_token_hash is null
                                or participant_token_hash ~ '^[0-9a-f]{64}$'),
  is_host                boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- 일반 참여자는 반드시 토큰 해시를 가진다 (null 은 주최자 행에서만 허용)
  constraint participants_token_hash_required
    check (is_host or participant_token_hash is not null),
  -- 하위 테이블에서 (participant_id, event_id) 복합 FK 로 "같은 이벤트 소속"을 강제하기 위한 키
  constraint participants_id_event_id_key unique (id, event_id)
);

-- 2-3. 참석 응답
create table if not exists public.rsvps (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.events (id) on delete cascade,
  participant_id uuid not null,
  status         text not null check (status in ('yes', 'no', 'maybe', 'waitlisted')),
  guests_count   integer not null default 0 check (guests_count between 0 and 10),
  waitlisted_at  timestamptz,                                    -- 대기 순번 기준 (트리거가 관리)
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint rsvps_event_participant_key unique (event_id, participant_id),
  constraint rsvps_participant_fkey foreign key (participant_id, event_id)
    references public.participants (id, event_id) on delete cascade
);

-- 2-4. 공지
create table if not exists public.announcements (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  content    text not null check (char_length(btrim(content)) between 1 and 5000),
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2-5. 카풀 차량 (1인 1차량)
create table if not exists public.carpool_rides (
  id                    uuid primary key default gen_random_uuid(),
  event_id              uuid not null references public.events (id) on delete cascade,
  driver_participant_id uuid not null,
  seats_total           integer not null check (seats_total > 0 and seats_total <= 20),
  depart_from           text not null check (char_length(btrim(depart_from)) between 1 and 200),
  depart_at             timestamptz not null,
  memo                  text check (memo is null or char_length(memo) <= 1000),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint carpool_rides_event_driver_key unique (event_id, driver_participant_id),
  constraint carpool_rides_driver_fkey foreign key (driver_participant_id, event_id)
    references public.participants (id, event_id) on delete cascade
);

-- 2-6. 카풀 탑승 신청
--   신청 1건 = 1석 (신청자 본인만). RSVP 동반 인원은 카풀 좌석에 포함되지 않는다.
--   같은 이벤트 소속 / 본인 차량 신청 금지 / RSVP yes 필수 / 좌석 초과 방지 / 이벤트 open 여부는
--   트리거(5-4)에서 검사한다.
create table if not exists public.carpool_requests (
  id             uuid primary key default gen_random_uuid(),
  ride_id        uuid not null references public.carpool_rides (id) on delete cascade,
  participant_id uuid not null references public.participants (id) on delete cascade,
  status         text not null default 'pending'
                 check (status in ('pending', 'confirmed', 'rejected')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint carpool_requests_ride_participant_key unique (ride_id, participant_id)
);

-- 2-7. 지출 (금액은 정수 원 단위)
--   주최자 단일 결제 모델: paid_by_participant_id 는 "누가 냈는지" 메모용이며 정산 계산에 쓰지 않는다.
--   paid_by FK 는 on delete 를 지정하지 않는다(기본 NO ACTION). 지출에 기록된 참여자를 삭제하면
--   에러가 나므로 지출이 조용히 사라지지 않는다. 참여자를 지우려면 앱에서 먼저 지출을 정리한다.
--   RESTRICT 가 아니라 NO ACTION + DEFERRABLE INITIALLY DEFERRED 인 이유: events 삭제 시
--   events → participants cascade 는 내부(SPI) 문장으로 따로 실행되고 NO ACTION 검사는 그 문장 끝에서 이뤄지므로,
--   expenses 가 아직 남아 있으면 이벤트·주최자 계정 삭제가 실패할 수 있다. 검사를 커밋 시점으로 미루면
--   events → expenses cascade 가 끝난 뒤에 검사한다. (참여자를 직접 삭제하면 오류가 COMMIT 시점에 표면화된다)
create table if not exists public.expenses (
  id                     uuid primary key default gen_random_uuid(),
  event_id               uuid not null references public.events (id) on delete cascade,
  title                  text not null check (char_length(btrim(title)) between 1 and 100),
  amount                 bigint not null check (amount > 0),
  paid_by_participant_id uuid not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint expenses_paid_by_fkey foreign key (paid_by_participant_id, event_id)
    references public.participants (id, event_id)  -- on delete NO ACTION (기본값, 의도적)
    deferrable initially deferred                  -- 검사를 커밋 시점으로: events cascade 삭제와 충돌 방지
);

-- 2-8. 정산 (확정 시점 금액 스냅샷)
--   amount_due 는 계산 컬럼이 아니라 "확정 시점에 저장된 값"이다.
--   RSVP·지출이 바뀌어도 자동으로 바뀌지 않으며, 주최자가 명시적으로 재계산할 때만 갱신한다.
--   amount_paid 는 실제 입금액. 잔액 = amount_due - amount_paid (양수 = 추가 청구, 음수 = 환불).
--   participant FK 는 expenses 와 같은 이유로 NO ACTION — 참여자 삭제 시 정산 기록이 조용히 사라지지 않는다.
--   이벤트 종료(closed/canceled) 후에도 정산 쓰기는 허용한다 (상태 가드 없음).
create table if not exists public.settlements (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.events (id) on delete cascade,
  participant_id uuid not null,
  shares         integer not null default 1 check (shares >= 1),  -- 본인 1 + 동반 인원 (스냅샷)
  amount_due     bigint not null check (amount_due >= 0),
  amount_paid    bigint not null default 0 check (amount_paid >= 0),
  reported_at    timestamptz,                                      -- 참여자 "입금했어요"
  paid           boolean not null default false,                   -- 주최자 최종 확인
  paid_at        timestamptz,
  confirmed_at   timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint settlements_event_participant_key unique (event_id, participant_id),
  constraint settlements_participant_fkey foreign key (participant_id, event_id)
    references public.participants (id, event_id)   -- on delete NO ACTION (기본값, 의도적)
    deferrable initially deferred,                  -- 검사를 커밋 시점으로 (expenses 와 같은 이유)
  -- 아래 두 CHECK 는 settlements_guard(5-5)가 BEFORE 단계에서 항상 만족시키므로 트리거와 충돌하지 않는다.
  constraint settlements_paid_at_consistency
    check ((paid and paid_at is not null) or (not paid and paid_at is null)),
  constraint settlements_paid_amount_consistency
    check (not paid or amount_paid = amount_due)
);

-- 2-9. 입금 계좌 (이벤트당 1개, upsert on conflict (event_id))
create table if not exists public.event_bank (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null unique references public.events (id) on delete cascade,
  bank_name      text not null check (char_length(btrim(bank_name)) between 1 and 50),
  account_number text not null check (account_number ~ '^[0-9 -]{4,40}$'),
  holder         text not null check (char_length(btrim(holder)) between 1 and 50),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);


-- -----------------------------------------------------------------------------
-- 3. 인덱스
--   - unique 제약(share_code, participant_token_hash, (event_id, participant_id) 등)은
--     자동으로 인덱스가 생성되므로 별도 생성하지 않는다.
--     (토큰 검증은 participant_token_hash unique 인덱스로 조회한다)
--   - FK 컬럼 중 선두 컬럼 인덱스가 없는 것만 추가 (cascade/NO ACTION 검사·조인 성능)
-- -----------------------------------------------------------------------------
create index if not exists events_host_id_starts_at_idx
  on public.events (host_id, starts_at desc);

create index if not exists participants_event_id_idx
  on public.participants (event_id);
-- 이벤트당 주최자 참여자 행은 최대 1개
create unique index if not exists participants_event_host_uidx
  on public.participants (event_id) where is_host;

create index if not exists rsvps_participant_id_idx
  on public.rsvps (participant_id);
create index if not exists rsvps_event_status_idx
  on public.rsvps (event_id, status, waitlisted_at);

create index if not exists announcements_event_order_idx
  on public.announcements (event_id, pinned desc, created_at desc);

create index if not exists carpool_rides_driver_idx
  on public.carpool_rides (driver_participant_id);

create index if not exists carpool_requests_participant_id_idx
  on public.carpool_requests (participant_id);
create index if not exists carpool_requests_ride_status_idx
  on public.carpool_requests (ride_id, status);

create index if not exists expenses_event_id_idx
  on public.expenses (event_id);
create index if not exists expenses_paid_by_idx
  on public.expenses (paid_by_participant_id);

create index if not exists settlements_participant_id_idx
  on public.settlements (participant_id);


-- -----------------------------------------------------------------------------
-- 4. RLS 헬퍼 함수
--   정책 안에서 events 를 직접 서브쿼리하면 RLS 가 중첩 평가되어 비용이 커지고
--   재귀 위험이 있으므로 SECURITY DEFINER 함수로 소유 여부만 boolean 으로 반환한다.
--   search_path 는 빈 값으로 고정하고 모든 객체를 스키마로 한정한다.
-- -----------------------------------------------------------------------------

-- 현재 로그인 사용자가 해당 이벤트의 주최자인지
create or replace function public.is_event_host(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.events e
    where e.id = p_event_id
      and e.host_id = (select auth.uid())
  );
$$;

-- 현재 로그인 사용자가 해당 카풀 차량이 속한 이벤트의 주최자인지 (carpool_requests 용)
create or replace function public.is_ride_host(p_ride_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.carpool_rides r
    join public.events e on e.id = r.event_id
    where r.id = p_ride_id
      and e.host_id = (select auth.uid())
  );
$$;

-- 정원 계산용 인원 수: status = 'yes' 응답자 본인 1명 + guests_count (가정 1)
--   SECURITY INVOKER 이므로 authenticated 는 RLS 에 의해 본인 이벤트만 집계된다.
create or replace function public.event_headcount(p_event_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(1 + r.guests_count), 0)::integer
  from public.rsvps r
  where r.event_id = p_event_id
    and r.status = 'yes';
$$;


-- -----------------------------------------------------------------------------
-- 5. 비즈니스 트리거
--   트리거 함수는 SECURITY DEFINER 로 실행하여 호출자(주최자/서비스 롤)와 무관하게
--   이벤트 전체 데이터를 기준으로 일관되게 검사한다.
--
--   [잠금 순서] 트리거는 events 행만 FOR UPDATE 한다. carpool_rides / participants 는 잠그지 않는다
--     (events 잠금이 같은 이벤트의 모든 RSVP·카풀 경로를 직렬화하므로 중복이며 교착 위험만 늘린다).
--     주의: BEFORE UPDATE/DELETE 트리거는 대상 행이 이미 잠긴 뒤 실행되므로, rsvps / carpool_requests /
--     carpool_rides 행을 직접 update 하는 경로(주최자 직접 수정 등)는 '행 → events' 순서가 되어
--     promote_waitlist·rsvps_after_change(events → 행)와 교착(40P01)할 수 있다.
--     서버는 쓰기를 'events 먼저 잠그는' RPC 로 모으고, 40P01 은 1~2회 재시도한다.
--
--   [이벤트 상태 가드] events.status <> 'open' 이면
--     - rsvps insert / 값 변경, carpool_requests insert / status·ride_id 변경,
--       carpool_rides insert / 내용 변경 → 'event_not_open' 예외 (carpool_rides 삭제는 정리 목적이므로 허용)
--     - promote_waitlist, 정원 변경 트리거, RSVP 이탈 시 카풀 자동 거절 → 예외 없이 조용히 건너뜀
--       (연쇄 트리거가 예외를 던져 원래 작업 전체를 롤백시키는 것을 막기 위함)
--     - settlements / expenses 는 이벤트 종료 후에도 써야 하므로 가드하지 않는다.
--
--   [트리거 연쇄와 재귀 안전성]
--     rsvps 변경 ─(AFTER rsvps_after_change)─┬→ promote_waitlist → rsvps update(waitlisted→yes)
--                                            │    → rsvps_after_change 재진입하지만 old.status <> 'yes' 이므로 아무것도 안 함
--                                            └→ carpool_requests update(→ rejected)
--                                                 → carpool_requests_after_confirm 은 new.status = 'confirmed' 일 때만 동작하므로 종료
--     carpool_requests confirmed ─(AFTER)→ 같은 참여자의 다른 pending → rejected (위와 같은 이유로 종료)
--     carpool_requests 쪽 트리거는 rsvps 를 쓰지 않으므로 rsvps ↔ carpool 사이 순환이 없다.
-- -----------------------------------------------------------------------------

-- 5-1. 이벤트 생성 시 주최자를 participants 에 자동 등록 (가정 3)
--   - 이름: profiles.full_name, 없으면 '주최자'. 이메일 로컬파트는 공개 명단에 노출될 수 있어 쓰지 않는다
--     (PRD 5.5 "주최자 이메일(아이디) 비노출").
--   - 주최자는 기본 미참석: RSVP 행은 만들지 않는다. 관리 화면의 "나도 참석" 토글이 rsvps 행을 생성한다.
--   - participant_token_hash 는 null 로 둔다. (난수 sha256 을 넣는 방식 대신 null 허용을 택한 이유)
--       1) 원본(평문)이 존재하지 않는 가짜 해시를 만들 필요가 없고, "토큰 미발급" 상태가 명시적으로 드러난다.
--       2) 해시 조회(where participant_token_hash = $1)는 null 과 절대 일치하지 않으므로 주최자 행이
--          토큰으로 선택될 가능성이 구조적으로 0 이다.
--       3) CHECK (is_host or participant_token_hash is not null) 로 일반 참여자는 해시 누락이 불가능하다.
--       4) 주최자가 참여자 화면용 쿠키가 필요해지면 서버(서비스 롤)가 쿠키 발급 시 해시를 채운다.
create or replace function public.handle_new_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  select left(coalesce(nullif(btrim(p.full_name), ''), '주최자'), 50)
    into v_name
  from public.profiles p
  where p.id = new.host_id;

  insert into public.participants (event_id, name, is_host)
  values (new.id, coalesce(v_name, '주최자'), true)
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_event_created on public.events;
create trigger on_event_created
  after insert on public.events
  for each row execute function public.handle_new_event();


-- 5-2. RSVP 이벤트 상태 가드 + 정원 강제
--   - insert 또는 값 변경(status / guests_count / 키) 시 events 행을 FOR UPDATE 로 잠가 동시 응답을 직렬화하고
--     events.status <> 'open' 이면 'event_not_open' 예외
--   - 정원 = sum(1 + guests_count) where status = 'yes'. 같은 participant 의 기존 행은 합계에서 제외
--   - 정원 초과 시
--       · 이전 상태가 yes 가 아닌 경우(신규 yes) → 자동으로 'waitlisted' 로 전환
--       · 이전 상태가 yes 이고 계속 yes 이면서 동반 인원이 늘어난 경우 → 'rsvp_capacity_exceeded' 예외
--         (본인을 대기로 강등하지 않는다)
--       · 이전 상태가 yes 이고 동반 인원이 늘지 않은 경우(정원 축소로 이미 초과 상태 등) → 그대로 허용
--   - "이전 상태"는 UPDATE 면 old, INSERT 면 같은 (event_id, participant_id) 의 기존 행을 본다.
--     upsert(insert ... on conflict do update) 는 BEFORE INSERT 트리거가 먼저 실행되고 그 결과가 EXCLUDED 로
--     넘어가므로, INSERT 단계에서 기존 yes 행을 고려하지 않으면 강등된 값이 그대로 update 될 수 있다.
--   - FIFO 앞지르기 금지: 자리가 있어도 더 먼저 기다리는 대기자(waitlisted_at 이 더 빠른 행)가 있으면
--     새로 yes 로 들어오는 사람은 'waitlisted' 로 보낸다. promote_waitlist 가 맨 앞 대기자를 승격할 때는
--     더 앞선 대기자가 없으므로 이 분기를 통과한다.
--   - 알려진 한계: 1 + guests_count 가 정원보다 큰 신청이 맨 앞 대기자가 되면 승격이 멈춘다 → 앱 폼에서 먼저 검증한다.
create or replace function public.rsvps_enforce_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capacity       integer;
  v_event_status   text;
  v_used           integer;
  v_changed        boolean;
  v_prev_status    text;
  v_prev_guests    integer;
  v_was_waitlisted boolean := false;
  v_prev_wl_at     timestamptz;
begin
  if tg_op = 'INSERT' then
    v_changed := true;
  else
    v_changed := new.status         is distinct from old.status
              or new.guests_count   is distinct from old.guests_count
              or new.event_id       is distinct from old.event_id
              or new.participant_id is distinct from old.participant_id;
    v_was_waitlisted := (old.status = 'waitlisted');
  end if;

  if v_changed then
    select e.capacity, e.status into v_capacity, v_event_status
    from public.events e
    where e.id = new.event_id
    for update;

    -- 이벤트가 없으면 FK 가 에러를 내도록 그대로 진행
    if found and v_event_status <> 'open' then
      raise exception 'event_not_open' using errcode = '23514';
    end if;

    if tg_op = 'UPDATE' then
      v_prev_status := old.status;
      v_prev_guests := old.guests_count;
      v_prev_wl_at  := old.waitlisted_at;
    else
      select r.status, r.guests_count, r.waitlisted_at
        into v_prev_status, v_prev_guests, v_prev_wl_at
      from public.rsvps r
      where r.event_id = new.event_id
        and r.participant_id = new.participant_id;
    end if;

    if new.status = 'yes' and v_capacity is not null then
      select coalesce(sum(1 + r.guests_count), 0) into v_used
      from public.rsvps r
      where r.event_id = new.event_id
        and r.status = 'yes'
        and r.participant_id <> new.participant_id;

      if v_used + 1 + new.guests_count > v_capacity then
        if v_prev_status = 'yes' then
          if new.guests_count > v_prev_guests then
            raise exception 'rsvp_capacity_exceeded' using errcode = '23514';
          end if;
          -- 동반 인원이 늘지 않은 yes 유지는 허용
        else
          new.status := 'waitlisted';
        end if;
      end if;

      -- FIFO 유지: 자리가 있어도 먼저 기다리는 대기자가 있으면 새로 yes 로 들어오는 사람은 줄 뒤로 보낸다
      --   (대기자 본인의 재요청은 자기 waitlisted_at 보다 앞선 대기자가 있을 때만 제자리 유지)
      --   promote_waitlist 가 맨 앞 대기자를 승격할 때는 더 앞선 대기자가 없으므로 통과한다.
      if new.status = 'yes'
         and v_prev_status is distinct from 'yes'
         and exists (
           select 1
           from public.rsvps w
           where w.event_id = new.event_id
             and w.status = 'waitlisted'
             and w.participant_id <> new.participant_id
             and (v_prev_wl_at is null or w.waitlisted_at < v_prev_wl_at)
         ) then
        new.status := 'waitlisted';
      end if;
    end if;
  end if;

  -- 대기 순번 시각 관리: 새로 대기에 들어갈 때만 now() 기록, 계속 대기 중이면 기존 값 유지
  -- (클라이언트가 waitlisted_at 을 임의로 바꿔 순번을 앞당기는 것을 방지)
  if new.status = 'waitlisted' then
    if v_was_waitlisted then
      new.waitlisted_at := coalesce(old.waitlisted_at, clock_timestamp());
    else
      -- now() 는 트랜잭션 시작 시각이라 events 잠금 획득 순서와 어긋날 수 있다. 잠금 후 시각을 쓴다.
      new.waitlisted_at := clock_timestamp();
    end if;
  else
    new.waitlisted_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists rsvps_enforce_capacity on public.rsvps;
create trigger rsvps_enforce_capacity
  before insert or update on public.rsvps
  for each row execute function public.rsvps_enforce_capacity();


-- 5-3. 대기자 자동 승격 (FIFO: waitlisted_at 오름차순, 맨 앞이 안 들어가면 중단)
--   이벤트가 없거나(cascade 삭제 중) open 이 아니면 아무것도 하지 않고 return 한다 (예외 금지).
create or replace function public.promote_waitlist(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capacity     integer;
  v_event_status text;
  v_used         integer;
  r              record;
begin
  select e.capacity, e.status into v_capacity, v_event_status
  from public.events e
  where e.id = p_event_id
  for update;

  if not found or v_event_status <> 'open' then
    return;
  end if;

  for r in
    select w.id, w.guests_count
    from public.rsvps w
    where w.event_id = p_event_id
      and w.status = 'waitlisted'
    order by w.waitlisted_at nulls last, w.created_at, w.id
  loop
    if v_capacity is not null then
      select coalesce(sum(1 + x.guests_count), 0) into v_used
      from public.rsvps x
      where x.event_id = p_event_id
        and x.status = 'yes';

      exit when v_used + 1 + r.guests_count > v_capacity;
    end if;

    -- BEFORE 트리거(5-2)가 다시 정원·상태를 검사한다
    update public.rsvps set status = 'yes' where id = r.id and status = 'waitlisted';
  end loop;
end;
$$;

-- RSVP 변경 후처리
--   (1) 참석 인원이 줄어드는 변경(yes → 다른 상태, 동반 감소, yes 행 삭제) 또는 대기자 이탈·동반 감소·삭제 후 대기자 승격 시도
--   (2) yes 가 아니게 바뀌거나 행이 삭제되면 그 참여자의 같은 이벤트 pending/confirmed 카풀 신청을 rejected 로 변경
--       - 이벤트가 없거나(cascade 삭제 중) open 이 아니면 건너뛴다 (카풀 가드의 event_not_open 예외로 롤백 방지)
--       - 참여자 자체가 삭제되는 중이면 건너뛴다 (카풀 신청은 participants FK cascade 로 함께 삭제됨)
create or replace function public.rsvps_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id       uuid;
  v_participant_id uuid;
  v_left_yes       boolean;
  v_event_status   text;
begin
  if tg_op = 'DELETE' then
    v_event_id       := old.event_id;
    v_participant_id := old.participant_id;
    v_left_yes       := true;  -- 삭제는 항상 카풀 정리 대상
    if old.status in ('yes', 'waitlisted') then
      perform public.promote_waitlist(old.event_id);
    end if;
  else
    v_event_id       := new.event_id;
    v_participant_id := new.participant_id;
    v_left_yes       := (old.status = 'yes' and new.status <> 'yes');
    -- 대기열 맨 앞 대기자가 빠지거나 동반 인원을 줄이면 뒤 대기자가 들어갈 수 있게 되므로 대기자 이탈·축소도 승격 대상.
    -- waitlisted → yes 는 제외한다 (promote_waitlist 안의 승격 update 가 다시 승격을 부르지 않게)
    if (old.status = 'yes'
          and (new.status <> 'yes' or new.guests_count < old.guests_count))
       or (old.status = 'waitlisted'
          and (new.status in ('no', 'maybe')
               or (new.status = 'waitlisted' and new.guests_count < old.guests_count))) then
      perform public.promote_waitlist(new.event_id);
    end if;
  end if;

  if v_left_yes then
    select e.status into v_event_status
    from public.events e
    where e.id = v_event_id
    for update;

    if found
       and v_event_status = 'open'
       and exists (select 1 from public.participants p where p.id = v_participant_id) then
      update public.carpool_requests c
         set status = 'rejected'
       where c.participant_id = v_participant_id
         and c.status in ('pending', 'confirmed')
         and exists (
           select 1
           from public.carpool_rides r
           where r.id = c.ride_id
             and r.event_id = v_event_id
         );
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists rsvps_after_change on public.rsvps;
create trigger rsvps_after_change
  after update or delete on public.rsvps
  for each row execute function public.rsvps_after_change();

-- 정원이 늘어나거나 무제한으로 바뀌면 승격 시도
--   (정원을 줄여도 기존 'yes' 를 강제로 대기로 내리지는 않는다 — 주최자 판단)
--   이벤트가 open 이 아니면 아무것도 하지 않는다 (예외 금지).
create or replace function public.events_after_capacity_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'open' then
    return new;
  end if;

  -- 정원 증가·무제한 전환, 또는 closed/canceled → open 재개 시 승격 시도
  if new.capacity is null
     or (old.capacity is not null and new.capacity > old.capacity)
     or old.status <> 'open' then
    perform public.promote_waitlist(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists events_after_capacity_change on public.events;
create trigger events_after_capacity_change
  after update of capacity, status on public.events
  for each row
  when (old.capacity is distinct from new.capacity
        or old.status is distinct from new.status)
  execute function public.events_after_capacity_change();


-- 5-4. 카풀 신청 검증 + 좌석 초과 방지 (confirmed 수 <= seats_total)
--   - 신청 1건 = 1석 (본인만). 동반 인원은 좌석 계산에 포함하지 않는다.
--   - events 행을 FOR UPDATE 로 잠가 상태 가드 및 RSVP 변경(5-2)과 직렬화
--   - insert 또는 status·ride_id 변경 시 이벤트가 open 이 아니면 'event_not_open'
--   - carpool_rides / participants 행은 잠그지 않는다: events 잠금이 같은 이벤트의 동시 확정
--     ("좌석 초과", "이벤트 내 확정 차량 1대" 검사)을 이미 직렬화하고, 추가 행 잠금은 교착 위험만 늘린다
--   - insert 시 및 confirmed 전환 시 신청자는 같은 이벤트에서 rsvps.status = 'yes' 여야 한다
create or replace function public.carpool_requests_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ride_event_id     uuid;
  v_driver_id         uuid;
  v_seats_total       integer;
  v_event_status      text;
  v_part_event_id     uuid;
  v_confirmed         integer;
  v_changed           boolean;
  v_becomes_confirmed boolean;
begin
  if tg_op = 'INSERT' then
    v_changed           := true;
    v_becomes_confirmed := (new.status = 'confirmed');
  else
    v_changed           := new.status         is distinct from old.status
                        or new.ride_id        is distinct from old.ride_id
                        or new.participant_id is distinct from old.participant_id;
    v_becomes_confirmed := new.status = 'confirmed'
                       and (old.status <> 'confirmed'
                            or old.ride_id <> new.ride_id
                            or old.participant_id <> new.participant_id);
  end if;

  -- 차량의 이벤트를 먼저 확인 (잠금 순서 events → carpool_rides 를 지키기 위해 여기서는 잠그지 않음)
  select r.event_id into v_ride_event_id
  from public.carpool_rides r
  where r.id = new.ride_id;

  if not found then
    raise exception 'carpool_ride_not_found' using errcode = '23503';
  end if;

  select e.status into v_event_status
  from public.events e
  where e.id = v_ride_event_id
  for update;

  if v_changed and v_event_status is distinct from 'open' then
    raise exception 'event_not_open' using errcode = '23514';
  end if;

  select r.driver_participant_id, r.seats_total
    into v_driver_id, v_seats_total
  from public.carpool_rides r
  where r.id = new.ride_id;

  select p.event_id into v_part_event_id
  from public.participants p
  where p.id = new.participant_id;

  if v_part_event_id is distinct from v_ride_event_id then
    raise exception 'carpool_participant_event_mismatch' using errcode = '23514';
  end if;

  if new.participant_id = v_driver_id then
    raise exception 'carpool_self_request' using errcode = '23514';
  end if;

  -- 신청자는 같은 이벤트에서 참석(yes) 상태여야 한다 (insert 시, confirmed 전환 시)
  if tg_op = 'INSERT' or v_becomes_confirmed then
    if not exists (
      select 1
      from public.rsvps rv
      where rv.event_id = v_ride_event_id
        and rv.participant_id = new.participant_id
        and rv.status = 'yes'
    ) then
      raise exception 'carpool_requires_rsvp_yes' using errcode = '23514';
    end if;
  end if;

  if v_becomes_confirmed then
    select count(*) into v_confirmed
    from public.carpool_requests c
    where c.ride_id = new.ride_id
      and c.status = 'confirmed'
      and c.id <> new.id;

    if v_confirmed >= v_seats_total then
      raise exception 'carpool_seats_full' using errcode = '23514';
    end if;

    -- 한 이벤트에서 확정된 차량은 1대만
    if exists (
      select 1
      from public.carpool_requests c
      join public.carpool_rides r on r.id = c.ride_id
      where c.participant_id = new.participant_id
        and c.status = 'confirmed'
        and c.id <> new.id
        and r.event_id = v_ride_event_id
    ) then
      raise exception 'carpool_already_confirmed' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists carpool_requests_guard on public.carpool_requests;
create trigger carpool_requests_guard
  before insert or update on public.carpool_requests
  for each row execute function public.carpool_requests_guard();

-- 신청이 confirmed 되면 같은 이벤트에서 그 참여자의 다른 pending 신청을 rejected 로 정리
--   rejected 로 바뀌는 행에 대해 이 트리거가 다시 호출되지만 new.status <> 'confirmed' 이므로 즉시 종료한다.
create or replace function public.carpool_requests_after_confirm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  if new.status <> 'confirmed' then
    return null;
  end if;

  if tg_op = 'UPDATE' and old.status = 'confirmed' and old.ride_id = new.ride_id then
    return null;  -- 이미 확정 상태였던 행
  end if;

  select r.event_id into v_event_id
  from public.carpool_rides r
  where r.id = new.ride_id;

  update public.carpool_requests c
     set status = 'rejected'
   where c.participant_id = new.participant_id
     and c.status = 'pending'
     and c.id <> new.id
     and exists (
       select 1
       from public.carpool_rides r
       where r.id = c.ride_id
         and r.event_id = v_event_id
     );

  return null;
end;
$$;

drop trigger if exists carpool_requests_after_confirm on public.carpool_requests;
create trigger carpool_requests_after_confirm
  after insert or update of status, ride_id on public.carpool_requests
  for each row execute function public.carpool_requests_after_confirm();

-- 좌석 수를 이미 확정된 인원보다 적게 줄이는 것 방지
create or replace function public.carpool_rides_seats_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_confirmed integer;
begin
  select count(*) into v_confirmed
  from public.carpool_requests c
  where c.ride_id = new.id
    and c.status = 'confirmed';

  if new.seats_total < v_confirmed then
    raise exception 'carpool_seats_below_confirmed' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists carpool_rides_seats_guard on public.carpool_rides;
create trigger carpool_rides_seats_guard
  before update of seats_total on public.carpool_rides
  for each row
  when (new.seats_total < old.seats_total)
  execute function public.carpool_rides_seats_guard();

-- 차량 등록·수정 가드
--   - 이벤트가 open 이 아니면 insert / 내용 변경을 'event_not_open' 으로 막는다 (삭제는 허용)
--   - insert 시, 그리고 운전자를 바꿀 때 운전자는 같은 이벤트에서 rsvps.status = 'yes' 여야 한다
--     ('carpool_requires_rsvp_yes' — 신청 가드(carpool_requests_guard)와 같은 코드를 쓴다)
--   - events 만 잠그고 다른 행은 잠그지 않는다 (UPDATE 는 ride 행이 이미 잠긴 뒤라 '행 → events' 순서일 수 있음, 위 [잠금 순서] 참고)
--   - 이미 등록된 운전자가 이후 yes 에서 이탈해도 차량은 자동 삭제하지 않는다 (주최자 판단, ROADMAP 백로그)
create or replace function public.carpool_rides_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_status text;
begin
  -- 내용이 바뀌지 않는 update (updated_at 갱신 등)는 검사하지 않는다
  if tg_op = 'UPDATE'
     and new.seats_total           is not distinct from old.seats_total
     and new.depart_from           is not distinct from old.depart_from
     and new.depart_at             is not distinct from old.depart_at
     and new.memo                  is not distinct from old.memo
     and new.driver_participant_id is not distinct from old.driver_participant_id
     and new.event_id              is not distinct from old.event_id then
    return new;
  end if;

  select e.status into v_event_status
  from public.events e
  where e.id = new.event_id
  for update;

  -- 이벤트가 없으면 FK 가 에러를 내도록 그대로 진행
  if found and v_event_status <> 'open' then
    raise exception 'event_not_open' using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     or new.driver_participant_id is distinct from old.driver_participant_id then
    if not exists (
      select 1
      from public.rsvps rv
      where rv.event_id = new.event_id
        and rv.participant_id = new.driver_participant_id
        and rv.status = 'yes'
    ) then
      raise exception 'carpool_requires_rsvp_yes' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists carpool_rides_guard on public.carpool_rides;
create trigger carpool_rides_guard
  before insert or update on public.carpool_rides
  for each row execute function public.carpool_rides_guard();


-- 5-5. 정산 상태 동기화 (주최자 단일 결제)
--   - paid 가 true 로 바뀌면 amount_paid := amount_due, paid_at := now()
--   - paid 가 계속 true 면 paid_at 은 기존 값 유지, amount_paid 는 amount_due 와 동일하게 유지
--   - paid 가 false 면 paid_at := null (amount_paid 는 주최자가 기록한 값 유지)
--   - 입금 완료(paid) 행에서 재계산으로 amount_due 가 바뀌면 paid 를 자동으로 false 로 되돌리고
--     amount_paid 는 이전 값을 보존한다 → 잔액(amount_due - amount_paid) 으로 추가 청구/환불 표시
--     (같은 update 에서 amount_paid 를 덮어쓰려 해도 보존 값이 우선한다)
--   - 이벤트 종료 후에도 쓰기 가능 (상태 가드 없음)
create or replace function public.settlements_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_was_paid boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_was_paid := old.paid;

    if old.paid and new.amount_due <> old.amount_due then
      new.paid        := false;
      new.amount_paid := old.amount_paid;
    end if;
  end if;

  if new.paid then
    if v_was_paid then
      new.paid_at := coalesce(old.paid_at, now());
    else
      new.paid_at := now();
    end if;
    new.amount_paid := new.amount_due;
  else
    new.paid_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists settlements_guard on public.settlements;
create trigger settlements_guard
  before insert or update on public.settlements
  for each row execute function public.settlements_guard();


-- 5-6. updated_at 트리거 (모든 신규 테이블)
do $$
declare
  t text;
begin
  foreach t in array array[
    'events', 'participants', 'rsvps', 'announcements',
    'carpool_rides', 'carpool_requests', 'expenses', 'settlements', 'event_bank'
  ] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I '
      'for each row execute function public.set_updated_at()', t
    );
  end loop;
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. 권한 + RLS
-- -----------------------------------------------------------------------------

-- 6-1. 함수 실행 권한
--   Supabase 는 기본적으로 public 스키마 함수에 anon/authenticated 실행 권한을 주므로 명시적으로 정리한다.
--   (트리거 함수의 실행 권한은 트리거 생성 시점에만 검사되므로 회수해도 트리거는 동작한다)
revoke all on function public.generate_share_code()               from public, anon;
grant execute on function public.generate_share_code()            to authenticated, service_role;

revoke all on function public.is_event_host(uuid)                 from public, anon;
grant execute on function public.is_event_host(uuid)              to authenticated, service_role;

revoke all on function public.is_ride_host(uuid)                  from public, anon;
grant execute on function public.is_ride_host(uuid)               to authenticated, service_role;

revoke all on function public.event_headcount(uuid)               from public, anon;
grant execute on function public.event_headcount(uuid)            to authenticated, service_role;

revoke all on function public.promote_waitlist(uuid)              from public, anon, authenticated;
grant execute on function public.promote_waitlist(uuid)           to service_role;

revoke all on function public.set_updated_at()                    from public, anon, authenticated;
revoke all on function public.handle_new_event()                  from public, anon, authenticated;
revoke all on function public.rsvps_enforce_capacity()            from public, anon, authenticated;
revoke all on function public.rsvps_after_change()                from public, anon, authenticated;
revoke all on function public.events_after_capacity_change()      from public, anon, authenticated;
revoke all on function public.carpool_requests_guard()            from public, anon, authenticated;
revoke all on function public.carpool_requests_after_confirm()    from public, anon, authenticated;
revoke all on function public.carpool_rides_seats_guard()         from public, anon, authenticated;
revoke all on function public.carpool_rides_guard()               from public, anon, authenticated;
revoke all on function public.settlements_guard()                 from public, anon, authenticated;


-- 6-2. 테이블 권한
--   - anon 은 전면 차단 (정책 0개 + 권한 회수의 이중 방어)
--   - authenticated 도 먼저 전부 회수한 뒤 필요한 권한만 다시 준다.
--     Supabase 기본 권한(default privileges)은 TRUNCATE / REFERENCES / TRIGGER 까지 부여하는데,
--     TRUNCATE 는 RLS 를 적용받지 않으므로 반드시 회수해야 한다.
--     테이블 단위 revoke 는 컬럼 단위 권한도 함께 회수하므로 재실행 시에도 결과가 같다.
revoke all on table
  public.events, public.participants, public.rsvps, public.announcements,
  public.carpool_rides, public.carpool_requests, public.expenses,
  public.settlements, public.event_bank
from anon, authenticated;

-- events: 컬럼 단위 권한. share_code / id / created_at 은 직접 지정·변경할 수 없다
--   (share_code 는 DB default 로만 발급. 재발급이 필요하면 별도 RPC 로 만든다)
grant select, delete on table public.events to authenticated;
grant insert (host_id, title, description, starts_at, location, capacity, status)
  on table public.events to authenticated;
grant update (title, description, starts_at, location, capacity, status)
  on table public.events to authenticated;

-- participants·events 를 제외한 7개 테이블: 행 범위는 RLS 정책으로 제한
grant select, insert, update, delete on table
  public.rsvps, public.announcements,
  public.carpool_rides, public.carpool_requests, public.expenses,
  public.settlements, public.event_bank
to authenticated;

-- participants: 컬럼 단위 권한
--   - select: participant_token_hash 를 제외한 컬럼만. 클라이언트는 select('*') / returning * 을 쓰면
--             권한 에러가 나므로 반드시 컬럼을 명시한다.
--   - update: name, phone 만. (is_host, event_id, participant_token_hash 변경 불가)
--   - delete: 허용 (단 주최자 행(is_host)은 정책이 막고, 지출·정산에 연결된 참여자는 NO ACTION FK 로 삭제 실패)
--   - insert: 주지 않는다. 참여자 생성(토큰 해시 기록 포함)은 서비스 롤만 한다.
grant select (id, event_id, name, phone, is_host, created_at, updated_at)
  on table public.participants to authenticated;
grant update (name, phone)
  on table public.participants to authenticated;
grant delete
  on table public.participants to authenticated;

grant all on table
  public.events, public.participants, public.rsvps, public.announcements,
  public.carpool_rides, public.carpool_requests, public.expenses,
  public.settlements, public.event_bank
to service_role;


-- 6-3. RLS 활성화 (모든 신규 테이블)
alter table public.events           enable row level security;
alter table public.participants     enable row level security;
alter table public.rsvps            enable row level security;
alter table public.announcements    enable row level security;
alter table public.carpool_rides    enable row level security;
alter table public.carpool_requests enable row level security;
alter table public.expenses         enable row level security;
alter table public.settlements      enable row level security;
alter table public.event_bank       enable row level security;


-- 6-4. events 정책 (authenticated 주최자 본인 소유만) — 4개
drop policy if exists events_host_select on public.events;
create policy events_host_select on public.events
  for select to authenticated
  using (host_id = (select auth.uid()));

drop policy if exists events_host_insert on public.events;
create policy events_host_insert on public.events
  for insert to authenticated
  with check (host_id = (select auth.uid()));

drop policy if exists events_host_update on public.events;
create policy events_host_update on public.events
  for update to authenticated
  using (host_id = (select auth.uid()))
  with check (host_id = (select auth.uid()));

drop policy if exists events_host_delete on public.events;
create policy events_host_delete on public.events
  for delete to authenticated
  using (host_id = (select auth.uid()));


-- 6-5. participants 정책 (select / update / delete) — 3개
--   insert 권한 자체가 없으므로 insert 정책도 두지 않는다. 이전 버전의 participants_host_insert 는 제거한다.
drop policy if exists participants_host_insert on public.participants;

drop policy if exists participants_host_select on public.participants;
create policy participants_host_select on public.participants
  for select to authenticated
  using (public.is_event_host(event_id));

drop policy if exists participants_host_update on public.participants;
create policy participants_host_update on public.participants
  for update to authenticated
  using (public.is_event_host(event_id))
  with check (public.is_event_host(event_id));

drop policy if exists participants_host_delete on public.participants;
create policy participants_host_delete on public.participants
  for delete to authenticated
  -- 주최자 자동 등록 행(is_host)은 삭제 불가: 지우면 다시 생성되지 않아 카풀·정산 참여 경로가 사라진다
  using (public.is_event_host(event_id) and not is_host);


-- 6-6. event_id 를 가진 나머지 하위 테이블 정책 (is_event_host 헬퍼 사용) — 6개 테이블 × 4 = 24개
--   update 의 with check 로 다른 사람 이벤트로 행을 옮기는 것도 차단한다.
do $$
declare
  t text;
begin
  foreach t in array array[
    'rsvps', 'announcements', 'carpool_rides',
    'expenses', 'settlements', 'event_bank'
  ] loop
    execute format('drop policy if exists %I on public.%I', t || '_host_select', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.is_event_host(event_id))',
      t || '_host_select', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_host_insert', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (public.is_event_host(event_id))',
      t || '_host_insert', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_host_update', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.is_event_host(event_id)) '
      'with check (public.is_event_host(event_id))',
      t || '_host_update', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_host_delete', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (public.is_event_host(event_id))',
      t || '_host_delete', t
    );
  end loop;
end;
$$;


-- 6-7. carpool_requests 정책 (event_id 가 없으므로 ride_id 경유 is_ride_host 사용) — 4개
drop policy if exists carpool_requests_host_select on public.carpool_requests;
create policy carpool_requests_host_select on public.carpool_requests
  for select to authenticated
  using (public.is_ride_host(ride_id));

drop policy if exists carpool_requests_host_insert on public.carpool_requests;
create policy carpool_requests_host_insert on public.carpool_requests
  for insert to authenticated
  with check (public.is_ride_host(ride_id));

drop policy if exists carpool_requests_host_update on public.carpool_requests;
create policy carpool_requests_host_update on public.carpool_requests
  for update to authenticated
  using (public.is_ride_host(ride_id))
  with check (public.is_ride_host(ride_id));

drop policy if exists carpool_requests_host_delete on public.carpool_requests;
create policy carpool_requests_host_delete on public.carpool_requests
  for delete to authenticated
  using (public.is_ride_host(ride_id));


-- =============================================================================
-- 7. 검증 쿼리 (실행 후 아래 주석을 풀어 하나씩 확인)
-- =============================================================================
--
-- (1) RLS 활성화 여부 — 9행 모두 rls_enabled = true 여야 한다
-- select c.relname as table_name, c.relrowsecurity as rls_enabled
-- from pg_class c
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public'
--   and c.relname in ('events','participants','rsvps','announcements','carpool_rides',
--                     'carpool_requests','expenses','settlements','event_bank')
-- order by c.relname;
--
-- (2) anon(및 public 롤) 대상 정책 0개 확인 — 결과 0 이어야 한다
-- select count(*) as anon_policy_count
-- from pg_policies
-- where schemaname = 'public'
--   and tablename in ('events','participants','rsvps','announcements','carpool_rides',
--                     'carpool_requests','expenses','settlements','event_bank')
--   and (roles @> array['anon']::name[] or roles @> array['public']::name[]);
--
-- (3) 정책 목록 — authenticated 정책 총 35개
--     events 4 + participants 3(select/update/delete, insert 없음)
--     + rsvps·announcements·carpool_rides·expenses·settlements·event_bank 6 × 4 = 24
--     + carpool_requests 4
--     participants_host_insert 는 결과에 없어야 한다.
-- select tablename, policyname, cmd, roles
-- from pg_policies
-- where schemaname = 'public'
--   and tablename in ('events','participants','rsvps','announcements','carpool_rides',
--                     'carpool_requests','expenses','settlements','event_bank')
-- order by tablename, cmd;
--
-- (4) anon 테이블 권한 회수 확인 — 모두 false 여야 한다
-- select t as table_name, has_table_privilege('anon', 'public.' || t, 'select') as anon_can_select
-- from unnest(array['events','participants','rsvps','announcements','carpool_rides',
--                   'carpool_requests','expenses','settlements','event_bank']) as t;
--
-- (5) authenticated 의 participants 권한 — 기대값을 주석으로 표시
-- select
--   has_table_privilege ('authenticated', 'public.participants', 'insert')                           as can_insert,     -- false
--   has_table_privilege ('authenticated', 'public.participants', 'delete')                           as can_delete,     -- true
--   has_column_privilege('authenticated', 'public.participants', 'participant_token_hash', 'select') as hash_select,    -- false
--   has_column_privilege('authenticated', 'public.participants', 'participant_token_hash', 'update') as hash_update,    -- false
--   has_column_privilege('authenticated', 'public.participants', 'name',    'select')                as name_select,    -- true
--   has_column_privilege('authenticated', 'public.participants', 'name',    'update')                as name_update,    -- true
--   has_column_privilege('authenticated', 'public.participants', 'is_host', 'update')                as is_host_update; -- false
--
-- (6) authenticated 의 TRUNCATE 권한 회수 확인 — 모두 false 여야 한다
-- select t as table_name, has_table_privilege('authenticated', 'public.' || t, 'truncate') as auth_can_truncate
-- from unnest(array['events','participants','rsvps','announcements','carpool_rides',
--                   'carpool_requests','expenses','settlements','event_bank']) as t;
--
-- (7) 참여자 FK 의 on delete 동작 — expenses/settlements 는 'a'(NO ACTION), rsvps/carpool 은 'c'(CASCADE)
-- select conrelid::regclass as table_name, conname, confdeltype
-- from pg_constraint
-- where contype = 'f'
--   and confrelid = 'public.participants'::regclass
-- order by conname;
--
-- (8) share_code 생성 함수 동작 — 8자, 혼동 문자 없음
-- select public.generate_share_code();
-- =============================================================================
