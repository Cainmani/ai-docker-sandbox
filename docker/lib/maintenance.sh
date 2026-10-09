#!/bin/bash
# Shared admission lock. FD 9 stays open for the entire managed session/mutation.
# 75 = busy, 69 = required locking/probing unavailable. Never remove lock files.
ai_maintenance_acquire() {
    local mode="${1:-exclusive}" state="${HOME}/.ai-docker"
    command -v flock >/dev/null 2>&1 || { echo 'LOCK=unavailable' >&2; return 69; }
    mkdir -p "$state" || return 69
    exec 9> "$state/update.lock" || return 69
    if [ "$mode" = shared ]; then
        flock -sn 9 || { echo 'LOCK=busy' >&2; return 75; }
    else
        flock -xn 9 || { echo 'LOCK=busy' >&2; return 75; }
        # Managed launches hold a shared lock. Also reject visible sessions opened
        # manually/over SSH. This is best effort: arbitrary external launches and
        # vendor self-updaters do not participate in our admission protocol.
        local proc executable arg target
        for proc in "${AI_MAINTENANCE_PROC_ROOT:-/proc}"/[0-9]*/cmdline; do
            [ -r "$proc" ] || continue
            executable='' arg=''
            { IFS= read -r -d '' executable; IFS= read -r -d '' arg; } < "$proc" || true
            target=$(readlink "${proc%/cmdline}/exe" 2>/dev/null || true)
            case "$target" in */.local/share/claude/versions/*)
                echo 'LOCK=active-session' >&2; flock -u 9; return 75 ;;
            esac
            case "${executable##*/}:${arg##*/}" in
                claude:*|codex:*|codex-*:*|gemini:*|opencode:*|vibe-kanban:*|9router:*|omniroute:*|node:claude|node:codex|node:codex.js|node:gemini|node:opencode|node:vibe-kanban|node:cli.js|node:9router|node:omniroute)
                    echo 'LOCK=active-session' >&2; flock -u 9; return 75 ;;
            esac
        done
    fi
}
