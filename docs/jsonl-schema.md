# Claude Code JSONL 스키마 (M0 실물 검증 결과)

- 검증일: 2026-07-14
- 샘플: `~/.claude/projects/**/*.jsonl` 6개 파일, assistant 레코드 1,432건
- Claude Code 버전(레코드 `version` 필드): 2.1.205 / 2.1.207

## 파일 구조

- 경로: `~/.claude/projects/<프로젝트-경로-슬러그>/<sessionId>.jsonl`
- 한 줄 = JSON 객체 1개. 줄 단위 append-only.
- 레코드 `type` 종류(실측): `assistant`, `user`, `system`, `attachment`,
  `ai-title`, `custom-title`, `last-prompt`, `queue-operation`, `mode`,
  `permission-mode`, `file-history-snapshot`
- **토큰 집계에 필요한 것은 `type == "assistant"` 뿐이다.** 나머지는 스킵.

## assistant 레코드

최상위 키(실측 전부):
`cwd`, `entrypoint`, `gitBranch`, `isSidechain`, `message`, `parentUuid`,
`requestId`, `sessionId`, `timestamp`, `type`, `userType`, `uuid`, `version`

집계에 사용하는 필드:

| 필드 | 타입 | 비고 |
|---|---|---|
| `timestamp` | string | ISO-8601 UTC, 밀리초 포함, `Z` 접미사. 예: `2026-07-13T03:01:38.767Z` |
| `requestId` | string | `req_...`. 실측에서 누락 0건 |
| `message.id` | string | API 메시지 ID |
| `message.model` | string | 예: `claude-sonnet-5`, `claude-opus-4-8`, `claude-fable-5`, `<synthetic>` |
| `message.usage` | object | 아래 참조. 실측에서 누락 0건 (단, 방어적으로 누락 시 skip) |
| `entrypoint` | string | 실측값: `"cli"`(209건), `"claude-desktop"`(1419건) — 둘 다 인터랙티브. 프로그래매틱(Agent SDK 등) 레코드는 로컬에 없어 미관측 → 파서는 "sdk" 포함 여부로 관용 판별 |

### message.usage (실측 전체 형태)

```json
{
  "input_tokens": 12804,
  "cache_creation_input_tokens": 6154,
  "cache_read_input_tokens": 28286,
  "output_tokens": 260,
  "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
  "service_tier": "standard",
  "cache_creation": { "ephemeral_1h_input_tokens": 6154, "ephemeral_5m_input_tokens": 0 },
  "inference_geo": "not_available",
  "iterations": [ { "...": "요청 내 반복별 세부 usage" } ],
  "speed": "standard"
}
```

집계에는 4개 필드만 사용: `input_tokens`, `output_tokens`,
`cache_creation_input_tokens`, `cache_read_input_tokens`.
총 토큰 = 4개 합 (ccusage와 동일 규칙).

## ⚠️ 중복 제거 (필수)

**같은 응답이 여러 줄에 중복 기록된다.** 스트리밍 중 어시스턴트 메시지가
콘텐츠 블록 단위로 나뉘어 저장되며, 각 줄이 동일한 usage 객체를 통째로 갖는다.

- 실측: assistant 1,432건 → 고유 `(message.id, requestId)` **497건** (최대 6중복)
- 중복 레코드끼리 usage 값은 **항상 동일** (935쌍 비교, 차이 0건)
- **규칙: `message.id + requestId` 조합을 키로 최초 1회만 집계.**
  중복 제거 없이 합산하면 약 2.9배 과대집계된다.

## 스킵 규칙

1. `type != "assistant"` → skip
2. `message.usage` 없음 → skip (방어)
3. `message.model == "<synthetic>"` → skip (클라이언트 생성 메시지, usage 전부 0)
4. `(message.id, requestId)` 기존 등장 → skip (중복)

## 기획안 §2와 다른 점 (보고)

1. **[가장 중요] 중복 기록**: §2는 "requestId로 중복 제거"만 언급하지만,
   실물은 한 requestId가 최대 6줄로 중복 기록됨. 중복 제거는 선택이 아니라
   필수이며, 키는 `requestId` 단독보다 `message.id + requestId` 조합이 안전.
2. **`<synthetic>` 모델 존재**: §2에 없음. usage가 전부 0인 클라이언트 생성
   레코드. 집계에서 명시적으로 제외.
3. **usage에 추가 필드 다수**: `cache_creation.ephemeral_1h/5m`,
   `server_tool_use`, `iterations`, `speed`, `service_tier`, `inference_geo` 등.
   v1 집계에는 불필요 — 파서는 관용적으로 무시.
4. **assistant 외 레코드 타입이 §2 예상보다 많음** (11종). 파서는 type 먼저
   확인하고 즉시 스킵해야 성능 확보.
5. 나머지(필드명 `input_tokens` 등, `timestamp`, `message.model`,
   `requestId`)는 §2 기술과 일치.
