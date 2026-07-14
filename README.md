# 🐱 TokenCat

macOS 메뉴바에서 픽셀 고양이가 뛰어다니고, Claude(Claude Code) 토큰 소모 속도가
빨라질수록 고양이도 빨라집니다. 클릭하면 5시간 세션·주간 사용량 팝오버가 열립니다.

- 😴 잠자기 → 🚶 산책 → 🏃 달리기 → 💨 질주 → 🌈 무지개 모드 (burn rate 기준 5단계)
- 사용률 80% 이상이면 🥵 지친 고양이, 95% 이상이면 ⚠️ 빨간 경고로 바뀝니다
- 80% / 95% 도달 시 macOS 알림 (창별 각 1회)

## 설치

```bash
scripts/build-app.sh        # dist/TokenCat.app + dist/TokenCat.dmg 생성 (ad-hoc 서명)
open dist/TokenCat.app
```

요구사항: macOS 13+, Xcode(빌드 시). `xcode-select`가 CommandLineTools를 가리키면
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`가 자동 적용됩니다.

개발 실행: `swift run TokenCat` (알림·자동 시작은 번들 앱에서만 동작),
단위 테스트: `swift test`, 집계 디버그: `.build/debug/TokenCat --report`

### 배포 서명 / notarize

ad-hoc 서명 앱은 로컬에서만 실행됩니다. 다른 사람에게 배포하려면:

```bash
xcrun notarytool store-credentials tokencat --apple-id <id> --team-id <team> --password <app-pw>  # 1회
CODESIGN_IDENTITY="Developer ID Application: 이름 (TEAMID)" NOTARY_PROFILE=tokencat scripts/build-app.sh
```

## 데이터 소스 (하이브리드)

| 데이터 | 소스 |
|---|---|
| 세션/주간 게이지 % | **공식 OAuth usage 엔드포인트** — Claude Code가 로컬(macOS 키체인)에 저장한 토큰으로 조회. 웹/데스크톱 사용량까지 합산된 계정 단위 값이라 `/usage`와 일치. 180초 폴링 + 팝오버 열 때 재조회, 그 사이엔 로컬 소모분으로 보간("보간 중" 표기) |
| 고양이 속도·오늘 토큰·스파크라인 | `~/.claude/projects/**/*.jsonl` 로컬 파싱 (3초 폴링, 증분) |
| 폴백 (추정 모드) | 공식 조회 실패·off 시 플랜 프리셋 대비 JSONL 집계로 추정 — 모든 추정값에 "(추정)" 라벨 |

자세한 실측 스키마: [docs/jsonl-schema.md](docs/jsonl-schema.md), [docs/usage-endpoint.md](docs/usage-endpoint.md)

## 한계 (정직하게)

- 공식 % 조회는 **비문서화 API**입니다. 변경·차단될 수 있으며, 그 경우 자동으로
  추정 모드로 폴백합니다 (앱은 죽지 않습니다).
- 추정 모드의 플랜 한도는 커뮤니티 추정치입니다. 설정의 캘리브레이션(`/usage`
  실측 % 입력)으로 보정하세요.
- 2026-06-15부터 프로그래매틱 사용(Agent SDK, `claude -p`)은 별도 크레딧 풀입니다.
  JSONL 집계는 합산하되, entrypoint에 "sdk"가 포함된 레코드가 있으면 오늘 섹션에
  "프로그래매틱 N tokens 포함" 캡션으로 분리 표시합니다 (관용 판별 — 실측 데이터에
  SDK 레코드가 없어 마커는 추정).
- OAuth 토큰은 읽기 전용으로 사용하며 Anthropic 외 어디에도 전송·저장·로깅하지 않습니다.

## 스프라이트

기본 에셋은 자체 제작 픽셀 아트(팝타르트 고양이 + 무지개 트레일, 냥캣 오마주)로,
`scripts/generate-assets.py`(PIL)로 재생성·수정할 수 있습니다.
직접 그린 PNG로 바꾸려면 `Sources/TokenCat/Assets/`의 `cat_run_0~7.png`,
`cat_rainbow_0~7.png`, `cat_sleep_0~1.png`, `cat_tired_0~1.png`,
`cat_alert_0~1.png` (36×22pt @1x / 72×44px @2x)를 교체하고 다시 빌드하면 됩니다.
PNG를 지우면 코드 생성 단색 고양이로 폴백되며, 색상 테마 3종(자동/주황/하늘,
팝오버 🐾 버튼)은 이 폴백 스프라이트에만 적용됩니다.
자세한 규격: [Sources/TokenCat/Assets/README.md](Sources/TokenCat/Assets/README.md)

냥캣 오마주 에셋은 전부 자체 제작이어야 하며 원작 이미지를 사용하지 마세요.

## 설정

메뉴바 고양이 클릭 → ⚙️: 공식 연동 on/off · 플랜(Pro/Max 5x/Max 20x/Custom) ·
한도 캘리브레이션 · 주간 리셋 요일/시각 · 민감도(낮음/보통/높음) · 한도/새 세션 알림 ·
로그인 시 자동 시작.
