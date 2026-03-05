"""Optimization API endpoints — item/gem optimization via PoB scripts."""

import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, field_validator

from ..config import (
    OPTIMIZE_ITEMS, OPTIMIZE_GEMS, DECODE_BUILD_CODE,
    TIMEOUT_OPTIMIZE, TIMEOUT_DECODE, BUILD_CODE_PATTERN, PROJECT_ROOT, VALID_SLOTS,
)
from ..services.league import detect_active_league
from ..services.subprocess_runner import run_script, TempXMLFile

router = APIRouter()


class OptimizeItemsRequest(BaseModel):
    build_code: str | None = None
    xml: str | None = None
    slot: str
    budget_divine: float | None = None
    skill: str | None = None

    @field_validator("build_code")
    @classmethod
    def validate_build_code(cls, v):
        if v and not re.match(BUILD_CODE_PATTERN, v):
            raise ValueError("Invalid build code characters")
        return v

    @field_validator("slot")
    @classmethod
    def validate_slot(cls, v):
        if v not in VALID_SLOTS:
            raise ValueError(f"Invalid slot. Valid: {VALID_SLOTS}")
        return v

    @field_validator("skill")
    @classmethod
    def validate_skill(cls, v):
        if v and len(v) > 100:
            raise ValueError("skill must be 100 characters or fewer")
        return v


class OptimizeGemsRequest(BaseModel):
    build_code: str | None = None
    xml: str | None = None
    skill: str

    @field_validator("build_code")
    @classmethod
    def validate_build_code(cls, v):
        if v and not re.match(BUILD_CODE_PATTERN, v):
            raise ValueError("Invalid build code characters")
        return v

    @field_validator("skill")
    @classmethod
    def validate_skill(cls, v):
        if len(v) > 100:
            raise ValueError("skill must be 100 characters or fewer")
        return v


async def _resolve_xml(build_code: str | None, xml: str | None) -> str:
    """Resolve XML content from build_code or direct xml."""
    if xml:
        return xml
    if not build_code:
        raise HTTPException(400, "Provide build_code or xml")

    result = await run_script(
        ["python3", str(DECODE_BUILD_CODE)],
        stdin_data=build_code,
        timeout=TIMEOUT_DECODE,
        cwd=PROJECT_ROOT,
    )
    if "error" in result:
        raise HTTPException(400, f"Decode failed: {result['error']}")
    content = result.get("result", "")
    if not content:
        raise HTTPException(400, "Decode returned empty XML")
    return content


@router.post("/optimize/items")
async def optimize_items(req: OptimizeItemsRequest):
    if not OPTIMIZE_ITEMS.exists():
        raise HTTPException(503, "Item optimizer not available")

    league = detect_active_league()
    if not league:
        raise HTTPException(404, "No active league")

    xml_content = await _resolve_xml(req.build_code, req.xml)

    async with TempXMLFile(xml_content) as xml_path:
        args = ["bash", str(OPTIMIZE_ITEMS), str(xml_path), req.slot, league]
        if req.budget_divine is not None:
            args.append(str(req.budget_divine))
        if req.skill:
            args.extend(["--skill", req.skill])

        result = await run_script(args, timeout=TIMEOUT_OPTIMIZE, cwd=PROJECT_ROOT)

    if "error" in result:
        raise HTTPException(500, result["error"])
    return result.get("result", {})


@router.post("/optimize/gems")
async def optimize_gems(req: OptimizeGemsRequest):
    if not OPTIMIZE_GEMS.exists():
        raise HTTPException(503, "Gem optimizer not available")

    league = detect_active_league()
    if not league:
        raise HTTPException(404, "No active league")

    xml_content = await _resolve_xml(req.build_code, req.xml)

    async with TempXMLFile(xml_content) as xml_path:
        args = ["bash", str(OPTIMIZE_GEMS), str(xml_path), req.skill, league]
        result = await run_script(args, timeout=TIMEOUT_OPTIMIZE, cwd=PROJECT_ROOT)

    if "error" in result:
        raise HTTPException(500, result["error"])
    return result.get("result", {})
