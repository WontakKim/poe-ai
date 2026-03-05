"""JSON file loader with mtime-based caching."""

import json
from pathlib import Path

_cache: dict[str, tuple[float, object]] = {}


def load_json(path: Path) -> object:
    """Load a JSON file, returning cached data if file hasn't changed."""
    key = str(path)
    if not path.exists():
        return None

    mtime = path.stat().st_mtime
    if key in _cache and _cache[key][0] == mtime:
        return _cache[key][1]

    with open(path) as f:
        data = json.load(f)
    _cache[key] = (mtime, data)
    return data


def list_json_files(directory: Path) -> list[str]:
    """List JSON filenames (without extension) in a directory, excluding source.json."""
    if not directory.is_dir():
        return []
    return sorted(
        p.stem for p in directory.glob("*.json") if p.name != "source.json"
    )
