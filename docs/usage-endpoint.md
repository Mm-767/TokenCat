# OAuth Usage 엔드포인트 (M0 스파이크 ⑵ 실측 결과)

- 검증일: 2026-07-14 (실제 토큰으로 1회 호출, HTTP 200)
- 선례 대조: jens-duttke/usage-monitor-for-claude `api.py`, Claude-Code-Usage-Monitor issue #202
- ⚠️ 비문서화 API — 언제든 변경·차단될 수 있음. 파싱은 스키마-관용적으로, 실패 시 추정 모드 폴백 (§8).

## 요청

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/<버전>        ← 필수. 없으면 공격적 레이트리밋 버킷(429 지속)
Content-Type: application/json
```

- 폴링 간격 180초 준수 (§F3 갱신 전략).
- 토큰은 읽기 전용, Anthropic 외 어디에도 전송·로깅 금지 (§4 주석 규칙).

## 토큰 로드 설계 (키체인 프롬프트 최소화)

1. **액세스 토큰은 메모리 캐시** — 자격증명 읽기는 만료(expiresAt, 없으면 ~55분 가정)
   시에만. 매 폴링(180초)마다 키체인을 읽으면 프롬프트가 반복될 수 있어 금지.
2. **`~/.claude/.credentials.json` 파일이 있으면 키체인보다 먼저 사용.**
3. 키체인은 **`/usr/bin/security` 서브프로세스**로 읽는다:
   `security find-generic-password -s "Claude Code-credentials" -a $USER -w`
   — ACL의 "항상 허용"이 security 바이너리에 걸리므로 앱을 리빌드해도 승인 유지.
   Security.framework 직접 호출(SecItemCopyMatching)은 앱 서명 기준 ACL이라
   서명이 바뀔 때마다 프롬프트가 재발해 사용 금지.
4. 401 응답 시 캐시 무효화 → 재읽기 → 1회 재시도.
5. **unlock-keychain 자동화·암호 저장류 편법 금지.** 신뢰 등록/최초 접근 시
   macOS가 묻는 1회 프롬프트는 정상 동작이다.
6. 앱 서명도 고정 identity("TokenCat Dev", scripts/setup-signing.sh) — ad-hoc 금지.
   빌드마다 서명이 바뀌면 키체인 ACL·TCC(알림 등) 승인이 리셋되기 때문.

## 토큰 위치 (macOS 실측 — 기획안 §2와 다름)

1. **이 머신엔 `~/.claude/.credentials.json`이 없다.** macOS는 **키체인**에 저장:
   - 서비스명 `Claude Code-credentials` (generic password), 계정 = 사용자명
2. JSON 구조:
   ```json
   {
     "claudeAiOauth": {
       "accessToken": "...",
       "refreshToken": "...",
       "expiresAt": 1789...,              // epoch ms
       "refreshTokenExpiresAt": 1789...,
       "scopes": ["user:file_upload", "user:inference", "user:mcp_servers",
                   "user:profile", "user:sessions:claude_code"],
       "subscriptionType": "pro",
       "rateLimitTier": "..."
     },
     "mcpOAuth": { "...": "MCP 서버용 — 사용 안 함" }
   }
   ```
3. **토큰 갱신 전략 (v1)**: 기획안은 refreshToken 갱신 로직을 요구하지만,
   Claude Code 자체가 실행될 때마다 키체인의 토큰을 갱신해 준다
   (실측: expiresAt이 호출 시점 기준 약 7시간 뒤 — "약 60분 만료" 가정과 다름).
   → v1은 **401 응답 시 키체인 재읽기 → 그래도 실패면 추정 모드 폴백**으로 충분.
   자체 refresh 구현(oauth/token 엔드포인트)은 v1.1 검토. 선례(usage-monitor-for-claude)도
   refresh를 구현하지 않음.

## 응답 (HTTP 200 실측, 값은 호출 시점 기준)

```json
{
  "five_hour": { "utilization": 61.0, "resets_at": "2026-07-14T11:50:00.300459+00:00",
                 "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "seven_day": { "utilization": 42.0, "resets_at": "2026-07-19T11:00:00.300485+00:00",
                 "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "seven_day_opus": null, "seven_day_sonnet": null,
  "limits": [
    { "kind": "session",       "group": "session", "percent": 61, "severity": "normal",
      "resets_at": "2026-07-14T11:50:00Z", "scope": null, "is_active": true },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 42, "severity": "normal",
      "resets_at": "2026-07-19T11:00:00Z", "scope": null, "is_active": false },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 50, "severity": "normal",
      "resets_at": "2026-07-19T11:00:00Z",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
      "is_active": false }
  ],
  "extra_usage": { "is_enabled": false, "...": null },
  "spend": { "percent": 0, "enabled": false, "...": "크레딧 관련 — v1 미사용" },
  "member_dashboard_available": false
}
```
(그 외 `seven_day_oauth_apps`, `tangelo` 등 실험 필드 다수 — 전부 null, 무시)

## 파싱 규칙 (OAuthUsageProvider용)

- **세션 게이지** = `five_hour.utilization` (0~100), 리셋 = `five_hour.resets_at`
- **주간 게이지** = `seven_day.utilization`, 리셋 = `seven_day.resets_at`
- 모델별 주간(`limits[] kind=weekly_scoped`, display_name별 %)은 M2에서 모델 비중 표시에 활용 가능
- `severity`(normal/…)는 80/95% 경고와 별개로 참고만

## 기획안 §2·§F3과 다른 점 (보고)

1. **절대값 없음**: `limit_dollars`/`used_dollars`/`remaining_dollars` 전부 null.
   §F3 "usage 응답에 절대값 포함되면 보간 정확도 향상" → **미포함**.
   보간은 계획대로 플랜 프리셋 추정 한도로 환산해야 함.
2. **공식 세션 리셋 시각은 UTC 정시가 아님** (실측 11:50:00Z).
   ccusage식 "UTC 정시 내림 + 5시간" 블록과 공식 창이 어긋난다 →
   게이지·리셋 카운트다운은 공식 `resets_at`을 그대로 쓰고,
   JSONL 블록 계산은 고양이 속도·토큰 절대량 표시 전용으로 유지 (§2 하이브리드 원칙 그대로).
3. **토큰 저장소**: 이 머신은 credentials.json이 아니라 **키체인** (위 참조).
4. **토큰 수명**: "약 60분"이 아니라 실측 약 7시간 + Claude Code가 알아서 갱신
   → v1은 자체 refresh 불필요 (401 시 키체인 재읽기).
5. `subscriptionType: "pro"` 확인 — 추정 모드 폴백의 기본 플랜 프리셋도
   max5x가 아닌 **pro**(500K)로 잡는 게 이 계정에 맞음.
