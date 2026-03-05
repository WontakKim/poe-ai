"""Active league detection from ninja data."""

import json
import time
from pathlib import Path

from ..config import DB_NINJA_DIR

_league_cache: tuple[float, str | None] | None = None
_LEAGUE_CACHE_TTL = 60.0


def detect_active_league() -> str | None:
    """Find the most recent league by checking ninja subdirectories for any source.json."""
    global _league_cache
    now = time.monotonic()
    if _league_cache is not None and now - _league_cache[0] < _LEAGUE_CACHE_TTL:
        return _league_cache[1]

    best_league = None
    best_mtime = 0.0

    if not DB_NINJA_DIR.is_dir():
        _league_cache = (now, None)
        return None

    for league_dir in DB_NINJA_DIR.iterdir():
        if not league_dir.is_dir():
            continue
        for source in league_dir.rglob("source.json"):
            mtime = source.stat().st_mtime
            if mtime > best_mtime:
                best_mtime = mtime
                best_league = league_dir.name

    _league_cache = (now, best_league)
    return best_league


def get_league_info(league: str) -> dict | None:
    """Get source metadata for a league's builds."""
    source = DB_NINJA_DIR / league / "builds" / "source.json"
    if not source.exists():
        return None
    with open(source) as f:
        return json.load(f)
