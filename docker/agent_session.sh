#!/bin/bash
set -uo pipefail
# Called only after bash startup; action/path are positional arguments, never code.
action="${1:-terminal}" folder="${2:-/workspace}"
case "$action" in terminal|claude|codex|claude-login|codex-login|codex-device|claude-resume|codex-resume) ;; *) echo 'Unknown agent action.' >&2; exit 2 ;; esac
if [ "$folder" != /workspace ] && [[ "$folder" != /workspace/* ]]; then
    echo 'Choose a folder inside the workspace.' >&2; exit 2
fi
resolved=$(realpath -e -- "$folder" 2>/dev/null) || resolved=''
if { [ "$resolved" != /workspace ] && [[ "$resolved" != /workspace/* ]]; } || ! cd -- "$folder"; then
    echo 'The selected folder is missing, inaccessible, or outside the workspace. No agent was started.' >&2
    exec bash -i
fi
if [ "$action" = terminal ]; then exec bash --norc -i; fi
source /usr/local/lib/maintenance.sh
ai_maintenance_acquire shared || { echo 'Tools are being maintained. Try again when maintenance finishes.'; exec 9>&-; exec bash -i; }
case "$action" in
    claude) claude ;;
    codex) codex ;;
    claude-login) claude auth login ;;
    codex-login) codex login ;;
    codex-device) codex login --device-auth ;;
    claude-resume) claude --resume ;;
    codex-resume) codex resume ;;
esac
result=$?
flock -u 9
exec 9>&-
echo "Agent finished (exit $result). Your terminal remains open."
# bashrc may contain cd /workspace; restore the selected folder after it runs.
exec bash -i -c 'cd -- "$1"; exec bash --norc -i' bash "$folder"
