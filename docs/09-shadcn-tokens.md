# 09. CSS 변수 토큰 — 코드로 내보내는 칸

02~07에서 정한 값을 **코드가 읽는 형태**로 옮기는 파일.
변수 이름은 shadcn/ui 규약을 그대로 따르므로, shadcn을 쓰든 안 쓰든 그대로 사용 가능하다.

> 값은 비어 있다. 02~07에서 정한 값을 그대로 옮겨 적는다. 여기서 새 값을 만들지 않는다.

## 변수 이름 읽는 법

| 이름 규칙 | 뜻 |
|---|---|
| `--이름` | 그 요소의 **배경**색 |
| `--이름-foreground` | 그 배경 **위에 얹는 글자**색 |

`--primary`와 `--primary-foreground`는 항상 짝. 배경을 바꾸면 그 위 글자색도 함께 확인해야 한다.

## 어느 변수에 무엇을 넣나

| 변수 | 02~07의 어느 값 |
|---|---|
| `--background` / `--foreground` | 바탕 / 글자 기본 |
| `--card`, `--popover` | 표면 |
| `--primary` | 포인트 색 |
| `--primary-foreground` | 포인트 색 위에서 4.5:1이 나오는 색 |
| `--secondary`, `--accent`, `--muted` | 포인트 색 옅은 것, 또는 표면보다 한 단계 들어간 무채색 |
| `--muted-foreground` | 글자 보조 |
| `--border`, `--input` | 테두리 |
| `--ring` | 포커스 링 — 포인트 색 또는 테두리보다 진한 무채색 |
| `--destructive` | 위험(삭제) 색 — 7개 색 밖의 예외 |
| `--radius` | 05번 기준값 |
| `--chart-*` | 차트 계열색. 대시보드가 없으면 통째로 삭제 |
| `--sidebar-*` | 사이드바 전용. 사이드바가 없으면 통째로 삭제 |

## 채우는 칸

```css
:root {
  --radius: ______;

  --background: ______;
  --foreground: ______;

  --card: ______;
  --card-foreground: ______;

  --popover: ______;
  --popover-foreground: ______;

  --primary: ______;
  --primary-foreground: ______;

  --secondary: ______;
  --secondary-foreground: ______;

  --muted: ______;
  --muted-foreground: ______;

  --accent: ______;
  --accent-foreground: ______;

  --destructive: ______;
  --destructive-foreground: ______;

  --border: ______;
  --input: ______;
  --ring: ______;

  /* 대시보드가 없으면 이 블록 삭제 */
  --chart-1: ______;
  --chart-2: ______;
  --chart-3: ______;
  --chart-4: ______;
  --chart-5: ______;

  /* 사이드바가 없으면 이 블록 삭제 */
  --sidebar: ______;
  --sidebar-foreground: ______;
  --sidebar-primary: ______;
  --sidebar-primary-foreground: ______;
  --sidebar-accent: ______;
  --sidebar-accent-foreground: ______;
  --sidebar-border: ______;
  --sidebar-ring: ______;
}

/* 한 테마만 쓰기로 했다면(01번) 이 블록은 통째로 삭제 */
.dark {
  --background: ______;
  --foreground: ______;

  --card: ______;
  --card-foreground: ______;

  --popover: ______;
  --popover-foreground: ______;

  --primary: ______;
  --primary-foreground: ______;

  --secondary: ______;
  --secondary-foreground: ______;

  --muted: ______;
  --muted-foreground: ______;

  --accent: ______;
  --accent-foreground: ______;

  --destructive: ______;
  --destructive-foreground: ______;

  --border: ______;
  --input: ______;
  --ring: ______;
}
```

## 모서리 파생값 (05번 방식 2를 골랐다면)

기준값 하나만 채우면 나머지는 자동으로 따라온다. **파생값을 개별로 덮어쓰지 않는다.**

```css
--radius:    ______;                      /* 기준값 — 여기만 바꾼다 */
--radius-sm: calc(var(--radius) - ____);  /* 배지, 체크박스 */
--radius-md: calc(var(--radius) - ____);  /* 버튼, 입력창 */
--radius-lg: var(--radius);               /* 카드, 다이얼로그 */
--radius-xl: calc(var(--radius) + ____);  /* 큰 컨테이너, 모달 */
```

## 색 표기 — HEX와 OKLCH 중 하나로 통일

**OKLCH를 권장하는 이유:** 밝기(L)를 고정한 채 색상 각도만 바꿔도 눈에 보이는 명도가 일정하게 유지된다.
포인트 색만 갈아끼워 같은 시스템을 여러 브랜드에 재사용할 때 특히 유리하다.

```css
/* oklch(밝기 채도 색상각도) */
--primary: oklch(____ ____ ____);

/* 밝기·채도는 그대로 두고 각도만 바꾸면 대비감이 유지된 채 색만 바뀜 */
```

- **HEX로 갈 경우:** 디자인 툴에서 바로 집어올 수 있지만, 포인트 색을 바꿀 때 명도를 매번 눈으로 맞춰야 한다
- 한 프로젝트 안에서 두 표기를 **섞지 않는다**

## 값을 채울 때 순서

1. `--background` / `--foreground` — 나머지 명도의 기준
2. `--card` — 바탕과의 명도 차를 02번 기준대로
3. `--border` — 바탕과 글자 보조 사이
4. `--primary` / `--primary-foreground` — 짝으로 함께
5. `--muted` / `--muted-foreground` — 옅은 배경과 보조 글자
6. `--destructive` — 위험 신호는 대부분 빨강 계열을 유지하는 편이 안전
7. 안 쓰는 블록(`--chart-*`, `--sidebar-*`, `.dark`) 삭제

## 다크를 함께 쓸 경우

- 라이트 값을 **그대로 반전시키지 않는다.** 반전하면 포인트 색이 탁해진다 — `--primary`는 명도를 올려 따로 정할 것
- 바탕은 **순수 검정을 피한다.** 글자와 대비가 과해 눈이 피로해짐
- 다크에서는 그림자가 거의 안 보이므로, 테두리(`--border`)를 반투명 흰색 계열로 두는 방식이 흔히 쓰인다

## 체크리스트
- [ ] 02~07에서 정한 값만 옮겼는가 (여기서 새 값을 만들지 않았는가)
- [ ] 모든 `--이름` / `--이름-foreground` 짝의 대비가 4.5:1 이상인가
- [ ] HEX와 OKLCH 중 하나로 통일했는가
- [ ] 안 쓰는 변수 블록을 삭제했는가
- [ ] 컴포넌트 코드에서 색을 변수로만 참조하는가 (값을 직접 박지 않았는가)
