#!/usr/bin/env bash
# FairHire — start backend + frontend with one command
# Usage: ./run.sh

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"

# ── Backend ───────────────────────────────────────────────────────────────────
echo "Starting backend on http://localhost:8000 ..."
cd "$ROOT/backend"
"$ROOT/backend/.venv/bin/uvicorn" main:app --reload --port 8000 &
BACKEND_PID=$!
cd "$ROOT"

# ── Frontend ──────────────────────────────────────────────────────────────────
echo "Starting Flutter web on Chrome ..."
cd "$ROOT/frontend"
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000 &
FLUTTER_PID=$!
cd "$ROOT"

echo ""
echo "Backend  → http://localhost:8000        (PID $BACKEND_PID)"
echo "API docs → http://localhost:8000/docs"
echo ""
echo "Press Ctrl+C to stop everything."

# Stop both on Ctrl+C
trap "kill $BACKEND_PID $FLUTTER_PID 2>/dev/null; exit" INT TERM
wait
