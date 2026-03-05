"""Async subprocess wrapper with timeout and temp file management."""

import asyncio
import json
import tempfile
from pathlib import Path


async def run_script(
    args: list[str],
    *,
    stdin_data: str | None = None,
    timeout: int = 30,
    cwd: Path | None = None,
) -> dict:
    """Run a script asynchronously, returning parsed JSON stdout or error."""
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdin=asyncio.subprocess.PIPE if stdin_data else None,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=str(cwd) if cwd else None,
    )

    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(stdin_data.encode() if stdin_data else None),
            timeout=timeout,
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return {"error": f"Script timed out after {timeout}s", "exit_code": -1}

    stdout_text = stdout.decode(errors="replace").strip()
    stderr_text = stderr.decode(errors="replace").strip()

    if proc.returncode != 0:
        return {
            "error": stderr_text or f"Script failed with exit code {proc.returncode}",
            "exit_code": proc.returncode,
        }

    # Try to parse stdout as JSON
    if stdout_text:
        try:
            return {"result": json.loads(stdout_text), "stderr": stderr_text}
        except json.JSONDecodeError:
            return {"result": stdout_text, "stderr": stderr_text}

    return {"result": None, "stderr": stderr_text}


class TempXMLFile:
    """Context manager for temporary XML files."""

    def __init__(self, content: str):
        self._content = content
        self._file = None

    async def __aenter__(self) -> Path:
        self._file = tempfile.NamedTemporaryFile(
            mode="w", suffix=".xml", delete=False
        )
        self._file.write(self._content)
        self._file.close()
        return Path(self._file.name)

    async def __aexit__(self, *exc):
        if self._file:
            Path(self._file.name).unlink(missing_ok=True)
