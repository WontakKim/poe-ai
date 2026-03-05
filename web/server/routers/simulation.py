"""Simulation API endpoints — PoB subprocess calls."""

import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, field_validator

from ..config import (
    RUN_POB_SIM, IMPORT_CHARACTER, DECODE_BUILD_CODE,
    TIMEOUT_SIMULATE, TIMEOUT_IMPORT, TIMEOUT_DECODE,
    ACCOUNT_PATTERN, BUILD_CODE_PATTERN, PROJECT_ROOT,
)
from ..services.subprocess_runner import run_script

router = APIRouter()


class SimulateRequest(BaseModel):
    build_code: str | None = None
    xml: str | None = None
    skill: str | None = None

    @field_validator("build_code")
    @classmethod
    def validate_build_code(cls, v):
        if v and not re.match(BUILD_CODE_PATTERN, v):
            raise ValueError("Invalid build code characters")
        return v

    @field_validator("skill")
    @classmethod
    def validate_skill(cls, v):
        if v and len(v) > 100:
            raise ValueError("skill must be 100 characters or fewer")
        return v


class CharacterRequest(BaseModel):
    account: str
    character: str

    @field_validator("account", "character")
    @classmethod
    def validate_name(cls, v):
        if not re.match(ACCOUNT_PATTERN, v):
            raise ValueError(f"Invalid name: {v}")
        return v


class DecodeRequest(BaseModel):
    build_code: str

    @field_validator("build_code")
    @classmethod
    def validate_build_code(cls, v):
        if not re.match(BUILD_CODE_PATTERN, v):
            raise ValueError("Invalid build code characters")
        return v


@router.post("/simulate")
async def simulate(req: SimulateRequest):
    if not RUN_POB_SIM.exists():
        raise HTTPException(503, "PoB simulation not available")

    if not req.build_code and not req.xml:
        raise HTTPException(400, "Provide build_code or xml")

    # If build_code provided, decode first
    xml_content = req.xml
    if req.build_code and not xml_content:
        decode_result = await run_script(
            ["python3", str(DECODE_BUILD_CODE)],
            stdin_data=req.build_code,
            timeout=TIMEOUT_DECODE,
            cwd=PROJECT_ROOT,
        )
        if "error" in decode_result:
            raise HTTPException(400, f"Decode failed: {decode_result['error']}")
        xml_content = decode_result.get("result", "")
        if not xml_content:
            raise HTTPException(400, "Decode returned empty XML")

    # Run simulation
    args = ["bash", str(RUN_POB_SIM), "xml"]
    if req.skill:
        args.extend(["--skill", req.skill])

    result = await run_script(
        args,
        stdin_data=xml_content,
        timeout=TIMEOUT_SIMULATE,
        cwd=PROJECT_ROOT,
    )

    if "error" in result:
        raise HTTPException(500, result["error"])
    return result.get("result", {})


@router.post("/simulate/character")
async def simulate_character(req: CharacterRequest):
    if not IMPORT_CHARACTER.exists():
        raise HTTPException(503, "Character import not available")

    result = await run_script(
        ["bash", str(IMPORT_CHARACTER), req.account, req.character],
        timeout=TIMEOUT_IMPORT,
        cwd=PROJECT_ROOT,
    )
    if "error" in result:
        raise HTTPException(500, result["error"])
    return result.get("result", {})


@router.post("/decode")
async def decode(req: DecodeRequest):
    if not DECODE_BUILD_CODE.exists():
        raise HTTPException(503, "Decoder not available")

    result = await run_script(
        ["python3", str(DECODE_BUILD_CODE)],
        stdin_data=req.build_code,
        timeout=TIMEOUT_DECODE,
        cwd=PROJECT_ROOT,
    )
    if "error" in result:
        raise HTTPException(400, result["error"])
    return {"xml": result.get("result", "")}
