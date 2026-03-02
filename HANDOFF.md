# HANDOFF — poe-ai RAG Database System

## Goal

Path of Exile RAG advisor system. Build a static item database per league season so that when a new season drops, an agent can automatically generate the entire DB and provide accurate build advisory.

## Architecture Overview

Two data sources: **PoB** (build data — items, gems, passives) and **poe.ninja** (market prices).

```
vendor/pob/
  origin/                          <- git submodule (PathOfBuilding repo, v2.60.0)
  source.json                      <- ref sync marker (pobCommit tracking)
  scripts/                         <- 8 scripts (4 ref sync + 4 ingest)
  references/                      <- 4 reference files (base-item, unique-item, skill-gem, passive-tree)

vendor/ninja/
  leagues.json                     <- resolve-league.sh output (version→league, 40 entries)
  scripts/
    resolve-league.sh              <- poedb scraping → leagues.json
    ingest-currency.sh             <- poe.ninja API → currency.json + source.json

db/pob/                            <- PoB build data (version-keyed)
  base-item/                       <- 20 files + source.json, 1,063 items
  unique-item/                     <- 20 files + source.json, 1,265 items
  skill-gem/                       <- 6 files + source.json, 741 items
  passive-tree/                    <- 6 files + source.json, 3,206 items

db/ninja/                          <- poe.ninja market data (league-keyed)
  Keepers/currency/                <- currency.json + source.json, 115 items

.claude/
  agents/
    pob/sync/                      <- IAM Executor agents (haiku) — ref sync (4)
    pob/ingest/                    <- IAM Executor agents (haiku) — DB ingest (4)
    ninja/ingest/
      currency.md                  <- IAM Executor agent (haiku) — currency ingest
  skills/
    sync-pob-ref/SKILL.md          <- /sync-pob-ref — ref sync only
    sync-pob-rag/SKILL.md          <- /sync-pob-rag — ref sync + DB ingest (4 types)
    sync-ninja-rag/SKILL.md        <- /sync-ninja-rag — ninja market data ingest
    e2e-pob-ref/SKILL.md           <- /e2e-pob-ref — E2E test for ref sync
  settings.json                    <- Bash(**) permission allow
```

## Current State (fa24d24)

### PoB Pipeline — 완성
모든 PoB 데이터 타입의 ref sync + ingest 파이프라인 구현 및 커밋 완료.

### Ninja Pipeline — 신규 (이번 세션)
poe.ninja 시세 데이터 ingest 파이프라인 구현 완료.

| Component | Status | Notes |
|-----------|--------|-------|
| `resolve-league.sh` | tested | poedb scraping, 40 leagues |
| `ingest-currency.sh` | tested | 115 items, sparkline 포함 |
| `ninja-ingest-currency` agent | created | `.claude/agents/ninja/ingest/currency.md` |
| `/sync-ninja-rag` skill | created | auto-detect + manual override 분기 |
| E2E test | passed | general-purpose agent 대행 (아래 참고) |

**Known Issue:**
- `ninja-ingest-currency` 에이전트가 현재 세션에서 subagent_type으로 인식되지 않음
- E2E 테스트는 `general-purpose` (haiku)로 대행하여 성공
- 다음 세션에서 에이전트 등록 확인 필요

## What Worked

- poe.ninja exchange overview API (`/poe1/api/economy/exchange/current/overview`) — 직접 호출 가능
- Legacy API (`/api/data/CurrencyOverview`) — name lookup용 `currencyDetails[].tradeId` → `name` 매핑
- Legacy API는 `-L` (follow redirect) 필요 (301)
- `currencyDetails`에 `tradeId == null`인 항목 52개 존재 → jq에서 `select(.tradeId != null)` 필터 필수
- sparkline 데이터: 7일 전 대비 누적 변동률(%) 배열, basePrice 역산 가능
- poedb HTML 파싱: `<tr><td>3.27</td><td><a ...>Keepers</a>...</td><td>18</td><td>2025-11-01</td>...` — perl regex로 안정적 추출

## What Didn't Work

- jq에서 `map({(.tradeId): .name})`로 name lookup 빌드 시 null key 에러 → null 필터 추가로 해결
- `.claude/agents/` 에 새 에이전트 파일 추가해도 현재 세션에서 즉시 인식되지 않음 → 세션 재시작 필요

## Next Steps

### 즉시 실행 (다음 세션)

1. **`ninja-ingest-currency` 에이전트 등록 확인**
   - 세션 시작 후 `/sync-ninja-rag` 실행
   - `ninja-ingest-currency` subagent_type이 정상 인식되는지 확인
   - 캐시 있으므로 "Update" 선택하여 full E2E 테스트

2. **커밋** — E2E 확인 후 필요 시 수정사항 커밋

### 후속 작업

3. **Ninja 타입 확장** — 동일 패턴으로 추가:
   - `ingest-unique-item.sh` → Item Overview API (`/api/data/ItemOverview?type=UniqueWeapon` 등)
   - `ingest-skill-gem.sh` → Item Overview API (`?type=SkillGem`)
   - Details/History API로 시세 추세 분석

4. **Remove legacy** — `.claude/agents/index/sync-pob-struct.md`, `.claude/agents/ingest/` 삭제

5. **Korean i18n** — poedb crawling

6. **Build advisor skill** — PoB DB + ninja DB를 결합한 RAG advisor
