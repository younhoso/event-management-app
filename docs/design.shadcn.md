<!-- shadcn/ui 공식 기본값(Neutral)으로 채운 완성본. 그대로 복사해서 --primary와 --radius만 프로젝트에 맞게 바꿔 쓰면 됨. -->

# [서비스 이름] — Style Reference
> [서비스가 뭘 하는지 한 줄]. 또렷한, 군더더기 없는, 유틸리티 중심.

**Theme:** light (다크모드 별도 지원, 09-shadcn-tokens.md의 `.dark` 참고)
**Platform:** desktop 1440×900 / mobile 390×844

## Colors
| 이름 | 값 | 쓰는 곳 |
|---|---|---|
| 바탕 | #FFFFFF (--background) | 화면 배경 |
| 표면 | #FFFFFF (--card, 배경과 동일) | 카드, 시트 |
| 글자 기본 | #0A0A0A (--foreground) | 제목, 본문 |
| 글자 보조 | #737373 (--muted-foreground) | 날짜, 부가 정보 |
| 테두리 | #E5E5E5 (--border) | 구분선, 카드 경계 |
| 포인트 색 | #171717 (--primary, 프로젝트 브랜드 컬러로 교체 가능) | 주 버튼 |
| 포인트 색 옅은 것 | #F5F5F5 (--secondary / --accent) | 선택된 칩, 보조 배경 |

바탕과 표면이 같은 흰색 — 카드는 배경색이 아닌 **테두리 1px**로 구분한다.

## Typography
- Font: Geist (fallback: Inter, system-ui, sans-serif)
- 화면 제목 24px / 굵기 600
- 섹션 제목 20px / 굵기 600
- 카드 제목 16px / 굵기 600
- 본문 14px / 굵기 400
- 부가 정보 12px / 굵기 400
- 굵기는 400과 600만 쓴다

## Spacing
- 간격은 4·8·12·16·24·32만 쓴다. 그 사이 값은 쓰지 않는다
- 화면 좌우 여백 24px
- 카드 안쪽 여백 24px
- 카드와 카드 사이 16px

## Radius
- 기준값(--radius) 10px → 이 값 하나만 바꾸면 아래 전체가 따라감
- 버튼 8px (--radius-md)
- 카드 10px (--radius-lg)
- 입력창 8px (--radius-md)
- 원형은 999

## Elevation
- 페이지에 고정된 요소(카드, 버튼, 입력창) — 그림자 없음. 테두리 1px로만 구분
- 페이지 위에 뜨는 요소(Popover, DropdownMenu, Select, Tooltip) — 옅은 그림자(shadow-sm) + 테두리
- 화면을 덮는 요소(Dialog, Sheet) — 진한 그림자(shadow-lg)

## Components
- 주 버튼(Button default) — --primary 배경 + 흰 글자, 높이 36px, 모서리 8px, 화면당 하나만
- 보조 버튼(Button outline) — 흰 배경 + 글자 기본 + 테두리 1px
- 고스트 버튼(Button ghost) — 배경 없음, hover 시에만 --accent 배경 (아이콘/툴바용)
- 카드(Card) — 흰 배경, 모서리 10px, 테두리 1px, 그림자 없음, 안쪽 여백 24px
- 입력창(Input) — 흰 배경, 모서리 8px, 테두리 1px, 높이 36px, 포커스 시 --ring 아웃라인
- 배지(Badge) — 기본 --secondary 배경, 모서리 999, 위험 상태는 --destructive
- 칩/토글 — 기본 흰 배경, 선택되면 --accent 배경

## Guidelines

### DO
- 포인트 색은 주 버튼과 선택된 상태에만 쓴다
- 화면마다 주 버튼(default variant)은 하나. 나머지는 outline/ghost/link
- 색은 반드시 CSS 변수로 참조한다 (`bg-primary`, `text-muted-foreground` 등, HEX 직접 입력 금지)
- 컴포넌트는 shadcn 기본 컴포넌트를 그대로 쓰고 색상 변수만 교체한다
- Dialog가 아닌 요소에는 그림자를 쓰지 않는다

### DON'T
- 그라데이션, 글로우, 임의의 진한 그림자 금지
- 정해둔 굵기(400/600) 이상으로 올리지 않기
- 간격에 4의 배수가 아닌 중간값 금지
- `--radius-sm/md/lg`를 개별적으로 직접 덮어쓰지 않기 (기준값 하나만 조정)
- destructive 색은 삭제·취소 등 되돌릴 수 없는 동작에만 사용
