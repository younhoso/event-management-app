---
name: project-schema-status
description: docs/schema.sql 실행 여부와 수정 방식(in-place vs alter 스크립트), 확정된 설계 결정 3가지
metadata:
  type: project
---

docs/schema.sql 은 2026-10-22 기준 아직 DB(Supabase SQL Editor)에 실행된 적 없음 → 수정은 in-place 로 한다.
첫 실행 이후에는 파일 헤더 규칙대로 docs/sql/ 에 alter 스크립트를 추가해야 한다.

확정 결정(사용자, 2026-10-22):
1. 정산 = 주최자 단일 결제. expenses.paid_by_participant_id 는 메모용.
2. participant_token 은 sha256 해시만 저장(participant_token_hash), 주최자 행만 null 허용.
3. 주최자는 기본 미참석, 관리 화면 토글로 RSVP 생성(DB 자동 yes 금지).

**Why:** PRD 5.4 / 6장과 ROADMAP 가정에 맞춘 사용자 확정 사항.
**How to apply:** 스키마 수정 요청 시 실행 여부를 먼저 확인하고, 위 결정과 충돌하는 제안은 하지 않는다. ROADMAP 59행의 "FK on delete cascade" 는 expenses/settlements 에 대해 NO ACTION 으로 의도적으로 벗어나 있다.
