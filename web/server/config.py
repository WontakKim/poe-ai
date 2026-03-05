"""Configuration constants and paths."""

from pathlib import Path

# Project root = web/../
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

# Data directories
DB_DIR = PROJECT_ROOT / "db"
DB_POB_DIR = DB_DIR / "pob"
DB_NINJA_DIR = DB_DIR / "ninja"

# PoB scripts
POB_SCRIPTS_DIR = PROJECT_ROOT / "vendor" / "pob" / "scripts"
RUN_POB_SIM = POB_SCRIPTS_DIR / "run-pob-sim.sh"
OPTIMIZE_ITEMS = POB_SCRIPTS_DIR / "optimize-items.sh"
OPTIMIZE_GEMS = POB_SCRIPTS_DIR / "optimize-gems.sh"
IMPORT_CHARACTER = POB_SCRIPTS_DIR / "import-character.sh"
DECODE_BUILD_CODE = POB_SCRIPTS_DIR / "decode-build-code.py"

# Server
HOST = "127.0.0.1"
PORT = 8421

# Frontend
FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

# Timeouts (seconds)
TIMEOUT_SIMULATE = 30
TIMEOUT_IMPORT = 60
TIMEOUT_DECODE = 5
TIMEOUT_OPTIMIZE = 120

# Validation — allow unicode (Korean etc.) but block shell metacharacters
ACCOUNT_PATTERN = r"^[^/\\;&|`$!<>\x00-\x1f]+$"
BUILD_CODE_PATTERN = r"^[A-Za-z0-9+/=_\-]+$"

# Valid equipment slots for item optimization
VALID_SLOTS = [
    "Body Armour",
    "Helmet",
    "Gloves",
    "Boots",
    "Weapon 1",
    "Weapon 2",
    "Ring 1",
    "Ring 2",
    "Amulet",
    "Belt",
]

# Data types available in ninja
NINJA_TYPES = [
    "currency",
    "unique-weapon",
    "unique-armour",
    "unique-accessory",
    "unique-flask",
    "unique-jewel",
    "skill-gem",
]

# Data categories in pob
POB_CATEGORIES = [
    "base-item",
    "unique-item",
    "skill-gem",
    "passive-tree",
]
