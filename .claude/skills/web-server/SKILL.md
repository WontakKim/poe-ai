---
name: serve
description: Start or restart the poe-ai web server on port 8421. Kills any existing process on the port before launching.
allowed-tools:
  - Bash
---

# Web Server — Start/Restart

Start the poe-ai FastAPI server. Kills any existing process on port 8421 first.

## Invocation

```
/serve          — start server (foreground log tailing)
/serve stop     — stop the running server
```

## Workflow

### Start (default)

1. Kill any existing process on port 8421:
   ```bash
   kill $(lsof -t -i :8421) 2>/dev/null; sleep 1
   ```

2. Launch uvicorn in background from project root:
   ```bash
   cd /Users/wontak/Desktop/private/poe-ai
   web/.venv/bin/uvicorn web.server.main:app --host 127.0.0.1 --port 8421 &
   ```
   Use `run_in_background: true` and `dangerouslyDisableSandbox: true` for the server process.

3. Wait 2 seconds, then verify with health check:
   ```bash
   sleep 2 && curl -s http://127.0.0.1:8421/api/health
   ```

4. Report the URL: `http://127.0.0.1:8421`

### Stop

1. Kill the process on port 8421:
   ```bash
   kill $(lsof -t -i :8421) 2>/dev/null
   ```

2. Confirm the port is free.

## Setup (first time)

If `.venv` doesn't exist, create it:
```bash
cd /Users/wontak/Desktop/private/poe-ai/web
python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt
```

## Notes

- Server binds to `127.0.0.1:8421` (localhost only)
- Frontend served at `/`, API at `/api/*`
- Advisor page: `http://127.0.0.1:8421/#advisor`
- Requires `dangerouslyDisableSandbox: true` for network binding
