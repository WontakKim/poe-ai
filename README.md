# poe-ai

Path of Exile RAG advisor system. Builds a static item/price DB per league season for accurate build recommendations powered by PoB simulation.

## Prerequisites

- macOS (Apple Silicon) or Linux
- [LuaJIT](https://luajit.org/) 2.1+
- [luarocks](https://luarocks.org/)
- Python 3.8+
- jq
- curl

## Setup

### 1. Clone with submodules

```bash
git clone --recurse-submodules <repo-url>
cd poe-ai
```

### 2. Install luautf8 (PoB runtime dependency)

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
  luarocks --lua-dir=/opt/homebrew/opt/luajit --lua-version=5.1 \
  --tree=vendor/pob/lua_modules install luautf8
```

> **Note:** The `PATH` override avoids ccache/fmt conflicts on macOS. On Linux, adjust `--lua-dir` to your LuaJIT installation path.

### 3. Verify

```bash
bash vendor/pob/scripts/run-pob-sim.sh xml <<< '<PathOfBuilding><Build/></PathOfBuilding>'
# Expected: JSON with Life=60, CombinedDPS=0.06 (blank Scion)
```

## Skills

| Skill | Description |
|-------|-------------|
| `/build-advisor` | Build recommendations with optional PoB DPS-backed analysis |
| `/pob-sim` | PoB build simulation, character import, item comparison |
| `/sync-pob-ref` | Sync PoB reference files from submodule |
| `/sync-pob-rag` | Sync PoB references + ingest equipment DB |
| `/sync-ninja-rag` | Sync poe.ninja market data into DB |
| `/e2e-pob-ref` | E2E test for PoB reference sync pipeline |

## Project Structure

```
db/
  pob/                 # Build data (base items, uniques, gems, passives)
  ninja/{league}/      # Market data per league (prices, builds)
  static/              # Static consumable data

vendor/
  pob/
    origin/            # PathOfBuilding git submodule
    scripts/           # Simulation, import, optimization scripts
    lua_modules/       # luautf8 (gitignored, install manually)
    references/        # Generated reference docs
  ninja/
    scripts/           # Market data ingest scripts
    references/        # Generated market reference docs

.claude/
  agents/              # IAM Executor agents (haiku)
  skills/              # Orchestrator skills
```
