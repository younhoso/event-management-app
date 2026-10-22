---
name: phase0-progress
description: "Phase 0(M0) 사용자 결정 사항 — 대상 DB는 새 Supabase 프로젝트, 문서를 코드에 맞춤 (2026-10-22)"
metadata:
  node_type: memory
  type: project
---

ROADMAP Phase 0 진행 중 사용자가 내린 결정. 진행 상태는 `docs/ROADMAP.md` 체크박스를 기준으로 한다.

**사용자 결정 (2026-10-22)**
- 대상 DB는 이 앱 전용 **새 Supabase 프로젝트**. [[mcp-supabase-shared-db]] 참고.
- 문서를 코드에 맞춘다: ROADMAP/PRD에 `expenses`/`settlements` 참여자 FK의 `DEFERRABLE INITIALLY DEFERRED`와 `carpool_rides.seats_total <= 20` 상한을 한 줄씩 추가한다.

**Why:** `schema.sql` 헤더가 `profiles`·`handle_new_user()`가 이미 있다고 전제하는데 확인한 DB에는 없었다. 그래서 `profiles`를 만드는 `supabase/000_profiles.sql`을 `schema.sql` 앞에 실행하는 방향으로 정했다.

**How to apply:** 이어서 작업하면 먼저 사용자에게 새 프로젝트를 만들었는지, `.env.local`을 바꿨는지, MCP를 새 프로젝트로 다시 연결했는지 묻는다. 안 됐으면 DB가 필요 없는 작업부터 진행한다. `.env*`는 읽거나 쓸 수 없으니 사용자가 직접 바꾸게 한다.
