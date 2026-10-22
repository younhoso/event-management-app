# 프로젝트 규칙 (모임 이벤트 관리 웹 MVP)

> 세션 시작과 컨텍스트 압축 때 훅이 읽는다. PreCompact는 앞 50줄만 읽으므로 이 파일은 50줄 이내로 유지한다.
> 구조·명령어·아키텍처 설명은 `CLAUDE.md`, 요구사항 기준은 `docs/PRD.md`와 `docs/ROADMAP.md`.

## 작업 방식
- 응답·문서·주석·커밋 메시지는 한국어. 식별자와 기술 용어는 원문 유지.
- 구현 전에 `docs/PRD.md`, `docs/ROADMAP.md`를 먼저 읽는다. 문서와 코드가 다르면 임의로 맞추지 말고 알린다.
- MVP 대상은 `frontend/`뿐. `admin/`은 범위 밖.
- 의존성은 그 기능을 구현할 때 추가한다. 한쪽 앱의 버전(특히 보안 패치)을 올리면 다른 앱도 같이 올린다.
- 신규 기능은 Server Action 중심. Recoil/Axios를 늘리지 않는다.
- 테스트는 Phase마다 Playwright MCP 시나리오로 작성한다 (테스트 러너 없음).

## 보안 (어기면 안 되는 것)
- `anon` 역할에 신규 테이블 권한·정책을 주지 않는다.
- 참여자 접근은 서버에서 `share_code` + 쿠키 토큰의 sha256 해시(`participant_token_hash`)를 검증한 뒤 서비스 롤로 처리한다. 평문 토큰은 DB에 저장하지 않는다.
- 서비스 롤 키는 `server-only` 모듈에서만 쓰고 `NEXT_PUBLIC_` 접두사를 붙이지 않는다.
- 서비스 롤 조회는 `select('*')` 금지, 컬럼 명시 + `event_id` 필터. 공개 명단은 `name`/`status`/`guests_count`만.
- 주최자 브라우저 클라이언트도 `participants`에 `select('*')`를 쓰지 않는다.
- 참여자 액션의 행위자 ID는 토큰에서만 도출하고, 클라이언트가 보낸 ID는 `event_id` 일치를 재검증한다.
- `.env*`는 읽지도 수정하지도 않는다 (훅이 차단).

## DB
- 정원·대기열·카풀 좌석·이벤트 상태·정산 스냅샷은 `supabase/schema.sql`의 트리거가 강제한다. 앱에서 같은 규칙을 다시 만들지 말고 예외 코드를 `lib/errors.ts`에서 사용자 메시지로 매핑한다.
- 스키마는 Supabase 대시보드 SQL Editor에서 실행한다 (CLI 마이그레이션 미사용). 컬럼 변경은 `supabase/`에 번호 붙인 별도 파일로 추가한다.
- 새 테이블은 `enable row level security` + `revoke all ... from anon`을 함께 실행한다.
- 행을 직접 update하는 경로는 교착(`40P01`) 가능성이 있다. events를 먼저 잠그는 RPC로 모으고 1~2회 재시도한다.
- 정산 금액은 정수(원). 나머지 원은 주최자가 흡수. 인원 0 또는 총액 0이면 확정 불가.

## 커밋
- 커밋 전에 `code-reviewer`로 리뷰하고 APPROVED를 받는다.
- 형식: 한국어 + 이모지 컨벤셔널 커밋 (`.claude/skills/git-commit`).
- 관심사별로 나눠 커밋한다 (문서 / 스키마 / 설정 / 앱 코드).
