"""Data API endpoints — read-only access to DB files."""

from fastapi import APIRouter, HTTPException

from ..config import DB_NINJA_DIR, DB_POB_DIR, NINJA_TYPES, POB_CATEGORIES
from ..services.data_loader import load_json, list_json_files
from ..services.league import detect_active_league

router = APIRouter()


def _require_league() -> str:
    league = detect_active_league()
    if not league:
        raise HTTPException(404, "No active league found")
    return league


def _safe_name(name: str) -> str:
    """Validate a path component to prevent traversal."""
    if not name or "/" in name or "\\" in name or ".." in name:
        raise HTTPException(400, f"Invalid name: {name}")
    return name


@router.get("/builds")
async def builds():
    league = _require_league()
    data = load_json(DB_NINJA_DIR / league / "builds" / "builds.json")
    if data is None:
        raise HTTPException(404, "Builds data not found")
    return data


@router.get("/prices/{price_type}")
async def prices(price_type: str):
    price_type = _safe_name(price_type)
    if price_type not in NINJA_TYPES:
        raise HTTPException(400, f"Unknown type: {price_type}. Valid: {NINJA_TYPES}")

    league = _require_league()
    type_dir = DB_NINJA_DIR / league / price_type

    if not type_dir.is_dir():
        raise HTTPException(404, f"No data for {price_type}")

    files = list_json_files(type_dir)
    if not files:
        raise HTTPException(404, f"No data files in {price_type}")

    items = []
    for f in files:
        chunk = load_json(type_dir / f"{f}.json")
        if isinstance(chunk, list):
            items.extend(chunk)
    return {"type": price_type, "league": league, "items": items}


@router.get("/prices")
async def prices_all_types():
    league = _require_league()
    result = {}
    for t in NINJA_TYPES:
        type_dir = DB_NINJA_DIR / league / t
        if type_dir.is_dir():
            files = list_json_files(type_dir)
            result[t] = {"files": files, "count": len(files)}
    return {"league": league, "types": result}


@router.get("/items/{category}/{file}")
async def items(category: str, file: str):
    category = _safe_name(category)
    file = _safe_name(file)

    if category not in POB_CATEGORIES:
        raise HTTPException(400, f"Unknown category: {category}. Valid: {POB_CATEGORIES}")

    data = load_json(DB_POB_DIR / category / f"{file}.json")
    if data is None:
        raise HTTPException(404, f"File not found: {category}/{file}.json")
    return {"category": category, "file": file, "items": data}


@router.get("/items/{category}")
async def items_list(category: str):
    category = _safe_name(category)
    if category not in POB_CATEGORIES:
        raise HTTPException(400, f"Unknown category: {category}. Valid: {POB_CATEGORIES}")

    files = list_json_files(DB_POB_DIR / category)
    return {"category": category, "files": files}
