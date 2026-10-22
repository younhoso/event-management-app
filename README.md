# service.supabase.v2

Next.js 14 + Tailwind CSS + shadcn/ui + Supabase 기반의 풀스택 모노레포 프로젝트.

---

## 프로젝트 구조

두 개의 독립적인 Next.js 앱으로 구성된 모노레포입니다.

```
service.supabase.v2/
├── frontend/    # 사용자 앱 (포트 3000)
└── admin/       # 관리자 앱 (포트 3001)
```

### frontend/

| 항목 | 내용 |
|------|------|
| 프레임워크 | Next.js 14 (App Router) |
| 스타일 | Tailwind CSS v3 + shadcn/ui (base-nova) |
| 상태 관리 | Recoil |
| HTTP 클라이언트 | Axios (자동 토큰 주입 인터셉터) |
| 인증 | @supabase/ssr |

### admin/

| 항목 | 내용 |
|------|------|
| 프레임워크 | Next.js 14 (App Router) |
| 데이터 패칭 | @tanstack/react-query |
| HTTP 클라이언트 | Axios |
| 인증 | @supabase/ssr |

---

## 환경변수 설정

`frontend/.env.local` 및 `admin/.env.local` 파일을 각각 생성합니다.

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

Supabase 프로젝트 대시보드 → **Project Settings → API** 에서 값을 확인할 수 있습니다.

---

## 설치 및 실행

### 1. 의존성 설치

```bash
# frontend
cd frontend
npm install

# admin
cd admin
npm install
```

### 2. 개발 서버 실행

```bash
# frontend (포트 3000)
cd frontend
npm run dev

# admin (포트 3001)
cd admin
npm run dev
```

### 3. 프로덕션 빌드

```bash
# frontend
cd frontend
npm run build

# admin
cd admin
npm run build
```

---

## Supabase 스키마 설정

Supabase 스키마는 **대시보드 SQL Editor에서 직접 실행**합니다 (로컬 CLI 마이그레이션 미사용).

### profiles 테이블

```sql
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 회원가입 시 자동 생성 트리거
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, avatar_url)
  VALUES (NEW.id, NEW.email, NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'avatar_url');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

---

## 인증 흐름

### frontend

```
브라우저 요청
  → middleware.ts              # 모든 요청 인터셉트
  → lib/supabase/middleware.ts # updateSession()으로 세션 갱신 + 리다이렉트 결정
  → 보호 라우트: /dashboard    # 비인증 시 /login으로 리다이렉트
  → 인증 라우트: /login, /register # 인증 상태면 /dashboard로 리다이렉트
```

### admin

- `/sign/in`, `/sign/up` — 공개
- `/auth/callback` — OAuth 콜백
- 그 외 모든 경로 — 보호 (비인증 시 `/sign/in` 리다이렉트)
