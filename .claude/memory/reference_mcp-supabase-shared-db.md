---
name: mcp-supabase-shared-db
description: MCP supabase가 연결된 프로젝트(lrqqxzlxuilwfumitwmc)는 다른 앱과 공유하는 DB이며 profiles가 없어 이 앱 스키마를 실행하면 안 됨
metadata:
  node_type: memory
  type: reference
---

2026-10-22 읽기 전용 조회 결과, MCP `supabase`가 연결된 `https://lrqqxzlxuilwfumitwmc.supabase.co`는 이 앱의 DB가 아니다.
- `public.profiles` 없음. `schema.sql`의 `events.host_id references public.profiles`가 첫 테이블에서 실패한다.
- 다른 앱의 테이블이 섞여 있다.
- `auth.users`에 다른 앱용 트리거가 걸려 있어, 여기서 카카오 가입을 하면 다른 앱 테이블에 행이 생긴다.

**Why:** 공유 DB에 이 앱 스키마나 트리거를 얹으면 다른 앱의 가입 흐름과 데이터를 건드릴 수 있다. 사용자도 새 프로젝트 사용으로 결정했다. [[phase0-progress]]

**How to apply:** 이 MCP로 DDL·`apply_migration`·쓰기 SQL을 실행하지 않는다. MCP를 새 프로젝트로 다시 연결했다고 사용자가 확인하기 전에는 SELECT도 이 앱 스키마 검증용으로 쓰지 않는다. 앱이 실제로 가리키는 프로젝트는 `.env*`를 읽을 수 없어 확인하지 못했다.
