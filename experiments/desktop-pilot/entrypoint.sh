#!/bin/bash
set -euo pipefail
/usr/local/bin/entrypoint.sh &
main=$!
trap 'kill "$main" 2>/dev/null || true; wait "$main" || true; exit 0' TERM INT
for ((attempt=0; attempt<180; attempt++)); do
    if [ -f /run/ai-docker-ready ]; then break; fi
    kill -0 "$main" 2>/dev/null || { wait "$main"; exit 1; }
    sleep 5
done
[ -f /run/ai-docker-ready ] || { echo 'Pilot setup did not become ready.' >&2; kill "$main"; exit 1; }
/usr/local/bin/setup_desktop_pilot.sh
wait "$main"
