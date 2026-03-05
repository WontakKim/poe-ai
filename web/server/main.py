"""FastAPI application for poe-ai web frontend."""

import shutil

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import FRONTEND_DIR, RUN_POB_SIM
from .services.league import detect_active_league
from .routers import data, simulation, optimization

app = FastAPI(title="poe-ai", docs_url="/api/docs", redoc_url=None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(data.router, prefix="/api")
app.include_router(simulation.router, prefix="/api")
app.include_router(optimization.router, prefix="/api")


@app.get("/api/health")
async def health():
    league = detect_active_league()
    pob_available = RUN_POB_SIM.exists() and shutil.which("luajit") is not None
    return {"status": "ok", "league": league, "pob_available": pob_available}


@app.get("/api/league")
async def league():
    name = detect_active_league()
    if name is None:
        return {"league": None, "error": "No league data found"}
    return {"league": name}


# Serve frontend as static files (must be last)
app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
