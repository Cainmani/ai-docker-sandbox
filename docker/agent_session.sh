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
open_workspace_shell() {
    # Startup files may cd /workspace. Both terminal routes restore the folder
    # afterwards while retaining aliases, wrappers and the status line.
    export AI_DOCKER_SESSION_FOLDER="$folder"
    exec bash --rcfile <(printf '%s\n' 'source "$HOME/.bashrc"' 'cd -- "$AI_DOCKER_SESSION_FOLDER" || echo "Selected folder is no longer accessible."' 'unset AI_DOCKER_SESSION_FOLDER') -i
}
if [ "$action" = terminal ]; then open_workspace_shell; fi
source /usr/local/lib/maintenance.sh
ai_maintenance_acquire shared
lock_result=$?
if [ "$lock_result" -ne 0 ]; then
    if [ "$lock_result" -eq 69 ]; then
        echo 'Maintenance coordination is unavailable. Recreate the container using setup.'
    else
        echo 'Tools are being maintained. Try again when maintenance finishes.'
    fi
    exec 9>&-
    exec bash -i
fi
case "$action" in
    claude) claude 9>&- ;;
    codex) codex 9>&- ;;
    claude-login) claude auth login 9>&- ;;
    codex-login) codex login 9>&- ;;
    codex-device) codex login --device-auth 9>&- ;;
    claude-resume) claude --resume 9>&- ;;
    codex-resume) codex resume 9>&- ;;
esac
result=$?
flock -u 9
exec 9>&-
echo "Agent finished (exit $result). Your terminal remains open."
# Only the session shell owns admission; vendor descendants inherit no lock FD.
open_workspace_shell
