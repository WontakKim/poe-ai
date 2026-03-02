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
    ingest-currency.sh             <- Exchange API + Legacy API merge → currency.json
    ingest-item.sh                 <- ItemOverview API → {type}.json (6 item types)

db/pob/                            <- PoB build data (version-keyed)
  base-item/                       <- 20 files + source.json, 1,063 items
  unique-item/                     <- 20 files + source.json, 1,265 items
  skill-gem/                       <- 6 files + source.json, 741 items
  passive-tree/                    <- 6 files + source.json, 3,206 items

db/ninja/                          <- poe.ninja market data (league-keyed)
  {league}/currency/               <- currency.json + source.json, ~115 items
  {league}/unique-weapon/          <- unique-weapon.json + source.json, ~637 items
  {league}/unique-armour/          <- unique-armour.json + source.json, ~851 items
  {league}/unique-accessory/       <- unique-accessory.json + source.json, ~309 items
  {league}/unique-flask/           <- unique-flask.json + source.json, ~38 items
  {league}/unique-jewel/           <- unique-jewel.json + source.json, ~125 items
  {league}/skill-gem/              <- skill-gem.json + source.json, ~5,942 items

.claude/
  agents/
    pob/sync/                      <- IAM Executor agents (haiku) — ref sync (4)
    pob/ingest/                    <- IAM Executor agents (haiku) — DB ingest (4)
    ninja/ingest/
      currency.md                  <- IAM Executor agent — currency ingest (Exchange + Legacy API)
      item.md                      <- IAM Executor agent — item ingest (6 types via ninjaType param)
  skills/
    sync-pob-ref/SKILL.md          <- /sync-pob-ref — ref sync only
    sync-pob-rag/SKILL.md          <- /sync-pob-rag — ref sync + DB ingest (4 types)
    sync-ninja-rag/SKILL.md        <- /sync-ninja-rag — ninja market data ingest (7 types)
    e2e-pob-ref/SKILL.md           <- /e2e-pob-ref — E2E test for ref sync
  settings.json                    <- Bash(**) permission allow
```

## Current State (5e11ede on main)

### PoB Pipeline — 완성
모든 PoB 데이터 타입의 ref sync + ingest 파이프라인 구현 및 커밋 완료.

### Ninja Pipeline — 완성
Currency + 6 item types 전체 파이프라인 구현 및 E2E 검증 완료.

| Component | Status | Notes |
|-----------|--------|-------|
| `resolve-league.sh` | committed | poedb scraping, 40 leagues |
| `ingest-currency.sh` | committed | Exchange + Legacy API merge |
| `ingest-item.sh` | committed | ItemOverview API, 6 types |
| `ninja-ingest-currency` agent | committed | currency ingest |
| `ninja-ingest-item` agent | committed | 6 item types via ninjaType param |
| `/sync-ninja-rag` skill | committed | 7 types, per-type cache, parallel ingest |

**E2E Results (`/sync-ninja-rag Keepers`, 7/7 pass):**

| Type | Items | Status |
|------|-------|--------|
| currency | 115 | OK |
| unique-weapon | 637 | OK |
| unique-armour | 851 | OK |
| unique-accessory | 309 | OK |
| unique-flask | 38 | OK |
| unique-jewel | 125 | OK |
| skill-gem | 5,942 | OK |

## What Worked

- ItemOverview API (`/api/data/ItemOverview?league={league}&type={ninjaType}`) — 이름 포함, legacy merge 불필요
- 1 script + 1 agent for 6 item types — DRY (ItemOverview 구조 동일)
- Currency는 별도 유지 — Exchange API + Legacy API merge라 근본적으로 다름
- Optional fields (`variant`, `links`, `gemLevel`, `gemQuality`, `corrupted`) — jq conditional include로 null 없이 compact
- CamelCase→kebab-case 변환: `sed 's/\([A-Z]\)/-\1/g' | sed 's/^-//' | tr '[:upper:]' '[:lower:]'`

## What Didn't Work

- `.claude/agents/` 에 새 에이전트 파일 추가해도 현재 세션에서 즉시 인식되지 않음 → 세션 재시작 필요
- jq에서 `!= null` 필터는 zsh에서 `!` 이슈 가능 → `has()` 또는 single-quote 사용

## Next Steps

1. **Korean i18n** — poedb crawling
2. **Build advisor skill** — PoB DB + ninja DB를 결합한 RAG advisor
