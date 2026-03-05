#!/usr/bin/env bash
# Start poe-ai web server with auto venv setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"

# Create venv if missing
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"

# Install/upgrade deps if requirements changed
MARKER="$VENV_DIR/.requirements.stamp"
if [[ ! -f "$MARKER" ]] || ! diff -q "$REQUIREMENTS" "$MARKER" >/dev/null 2>&1; then
    echo "Installing dependencies..."
    pip install -q -r "$REQUIREMENTS"
    cp "$REQUIREMENTS" "$MARKER"
fi

echo "Starting poe-ai on http://127.0.0.1:8421"
exec uvicorn web.server.main:app --host 127.0.0.1 --port 8421 --app-dir "$SCRIPT_DIR/.."
