#!/usr/bin/env bash
# ai-docker: health of the AI Docker container at a glance.
#
#   ai-docker status           tools, updates, disk and container limits
#   ai-docker status --brief   one line for the login banner (no tool is run)
#   ai-docker doctor           network/auth diagnostics (configure-tools --diagnose)
#
# Reads the records other scripts keep (install marker, update status) rather
# than re-deriving them, works offline, and reports sizes and counts only -
# never file names or contents. Exit status: 0 healthy, 1 needs attention,
# 2 usage error.
set -uo pipefail

LIB_DIR="${AI_DOCKER_LIB_DIR:-/usr/local/lib}"
STATE_DIR="${HOME}/.ai-docker"
STATUS_FILE="${STATE_DIR}/update-status"
INSTALL_MARKER="${HOME}/.cli_tools_installed"
VERSION_FILE="${AI_DOCKER_VERSION_FILE:-/etc/ai-docker-version}"
CGROUP_DIR="${AI_DOCKER_CGROUP_DIR:-/sys/fs/cgroup}"
TMP_ROOT="${AI_DOCKER_TMP_DIR:-/tmp}"
DISK_PATH="${AI_DOCKER_DISK_PATH:-/}"
DISK_WARN_GB="${AI_DOCKER_DISK_WARN_GB:-80}"
# Warn when no update check has succeeded for this long (weekly cadence + slack).
STALE_DAYS="${AI_DOCKER_STALE_DAYS:-10}"
TOOLS="claude gh codex gemini opencode"

# shellcheck source=lib/entrypoint_helpers.sh
. "$LIB_DIR/entrypoint_helpers.sh"

status_value() {
    sed -n "s/^$1=//p" "$STATUS_FILE" 2>/dev/null | head -n1
}

# update_lock_held: an updater currently holds the update lock.
update_lock_held() {
    command -v flock >/dev/null 2>&1 || return 1
    [ -e "$STATE_DIR/update.lock" ] || return 1
    ! flock -n "$STATE_DIR/update.lock" true 2>/dev/null
}

# days_since <iso-timestamp>: whole days elapsed, or nothing if unparseable.
days_since() {
    local since
    [ -n "$1" ] || return 1
    since=$(date -d "$1" +%s 2>/dev/null) || return 1
    echo $(( ($(date +%s) - since) / 86400 ))
}

age_phrase() {
    case "$1" in
        0) echo "today" ;;
        1) echo "1 day ago" ;;
        *) echo "$1 days ago" ;;
    esac
}

image_version() {
    if [ -r "$VERSION_FILE" ]; then
        tr -cd '0-9.A-Za-z+-' < "$VERSION_FILE"
    else
        echo "unknown"
    fi
}

disk_used_gb() {
    df -B1 --output=used "$DISK_PATH" 2>/dev/null | tail -n1 | awk '{ printf "%d", $1 / 1073741824 }'
}

# collect_issues: fills ISSUES (short phrases) and HINTS (what to do).
collect_issues() {
    ISSUES=()
    HINTS=()
    local state failed result attempt_days check_days used

    state=$(install_status_state "$INSTALL_MARKER")
    case "$state" in
        partial)
            failed=$(install_status_get "$INSTALL_MARKER" FAILED_TOOLS)
            ISSUES+=("tools failed to install: ${failed:-unknown}")
            HINTS+=("Repair failed tools: install_cli_tools.sh --repair (also retried on every start)")
            ;;
        missing)
            ISSUES+=("tool installation has not completed")
            HINTS+=("Restart the container, or run: install_cli_tools.sh")
            ;;
    esac

    if [ -f "$STATUS_FILE" ]; then
        result=$(status_value RESULT)
        attempt_days=$(days_since "$(status_value LAST_ATTEMPT)" || true)
        check_days=$(days_since "$(status_value LAST_CHECK_OK)" || true)
        case "$result" in
            running)
                if update_lock_held; then
                    : # in progress; shown in the summary, not a problem
                else
                    ISSUES+=("last update was interrupted $(age_phrase "${attempt_days:-0}")")
                    HINTS+=("Run it again: update-container-tools --force")
                fi
                ;;
            failed)
                ISSUES+=("last update failed ($(status_value FAILED_STAGES)) $(age_phrase "${attempt_days:-0}")")
                HINTS+=("Retry and review the errors: update-container-tools --force")
                ;;
            check_failed)
                ISSUES+=("last update check failed $(age_phrase "${attempt_days:-0}")")
                HINTS+=("Check network access with: ai-docker doctor")
                ;;
        esac
        if [ -z "$check_days" ]; then
            [ "$result" = check_failed ] || ISSUES+=("no successful update check recorded")
        elif [ "$check_days" -ge "$STALE_DAYS" ]; then
            ISSUES+=("no successful update check for $check_days days")
            HINTS+=("Run updates now: update-container-tools --force")
        fi
    fi

    used=$(disk_used_gb)
    if [ -n "$used" ] && [ "$used" -ge "$DISK_WARN_GB" ]; then
        ISSUES+=("Docker disk $used GB used")
        HINTS+=("See the disk breakdown in: ai-docker status")
    fi
}

update_summary() {
    local check_days
    [ -f "$STATUS_FILE" ] || { echo "update check pending"; return; }
    if [ "$(status_value RESULT)" = running ] && update_lock_held; then
        echo "update running"
        return
    fi
    check_days=$(days_since "$(status_value LAST_CHECK_OK)" || true)
    if [ -n "$check_days" ]; then
        echo "updates checked $(age_phrase "$check_days")"
    else
        echo "no successful update check yet"
    fi
}

cmd_brief() {
    collect_issues
    if [ "${#ISSUES[@]}" -eq 0 ]; then
        echo "AI Docker $(image_version) - tools OK - $(update_summary) - Docker disk $(disk_used_gb) GB used"
        return 0
    fi
    local joined
    joined=$(printf '%s; ' "${ISSUES[@]}")
    echo "AI Docker $(image_version): ATTENTION - ${joined%; } - run: ai-docker status"
    return 1
}

memory_limit() {
    local raw
    raw=$(cat "$CGROUP_DIR/memory.max" 2>/dev/null || echo max)
    if [ "$raw" = max ] || ! [ "$raw" -gt 0 ] 2>/dev/null; then
        echo "memory limit none"
    else
        awk -v b="$raw" 'BEGIN { printf "memory limit %.1f GB", b / 1073741824 }'
    fi
}

cpu_limit() {
    local quota period
    read -r quota period < "$CGROUP_DIR/cpu.max" 2>/dev/null || { echo "CPU limit none"; return; }
    if [ "$quota" = max ] || [ -z "${period:-}" ]; then
        echo "CPU limit none"
    else
        awk -v q="$quota" -v p="$period" 'BEGIN { c = q / p; if (c == int(c)) printf "%d CPUs", c; else printf "%.1f CPUs", c }'
    fi
}

# size_of <du-args...>: total size estimate, bounded so status never hangs on a
# huge tree. Prints e.g. "3.2 GB", "3.2 GB (partial)" when some folders were
# unreadable, or "over time limit".
size_of() {
    local out rc kb arg parent suffix="" count=0
    local -a args=()
    for arg in "$@"; do
        if [[ "$arg" == --* ]]; then
            args+=("$arg")
            continue
        fi
        parent=$(dirname -- "$arg")
        # Only call a path absent when its parent can actually be inspected.
        if [ ! -e "$arg" ] && [ ! -L "$arg" ] && [ -d "$parent" ] && [ -r "$parent" ] && [ -x "$parent" ]; then
            continue
        fi
        args+=("$arg")
        count=$((count + 1))
    done
    if [ "$count" -eq 0 ]; then
        echo "not present"
        return
    fi
    out=$(timeout 20 du -sck "${args[@]}" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 124 ]; then
        echo "over time limit"
        return
    fi
    # du exits 1 when it could not read part of the tree; the total still counts the rest.
    [ "$rc" -eq 0 ] || suffix=" (partial) - some paths could not be read"
    kb=$(printf '%s\n' "$out" | tail -n1 | cut -f1)
    awk -v k="${kb:-0}" -v s="$suffix" 'BEGIN { if (k >= 1048576) printf "%.1f GB%s", k / 1048576, s; else printf "%d MB%s", k / 1024, s }'
}

cmd_status() {
    local state tool version disk_size disk_used
    collect_issues

    echo "AI Docker status"
    echo ""
    echo "Container   image $(image_version) - $(memory_limit) - $(cpu_limit)"
    echo "            (change limits with Resources in the Windows launcher; no image rebuild needed)"
    echo ""

    state=$(install_status_state "$INSTALL_MARKER")
    echo "Tools       install status: $state"
    for tool in $TOOLS; do
        if command -v "$tool" >/dev/null 2>&1 \
            && version=$(timeout 15 "$tool" --version 2>/dev/null | head -n1) && [ -n "$version" ]; then
            printf '            %-9s %s\n' "$tool" "$version"
        elif [ "$(install_status_get "$INSTALL_MARKER" "TOOL_$tool" 2>/dev/null)" = ok ]; then
            # The installer recorded it as working; it no longer runs.
            printf '            %-9s %s\n' "$tool" "NOT WORKING"
            ISSUES+=("$tool is installed but not working")
            HINTS+=("Repair it: install_cli_tools.sh --repair")
        else
            printf '            %-9s %s\n' "$tool" "not installed"
        fi
    done
    echo ""

    if [ -f "$STATUS_FILE" ]; then
        echo "Updates     last result: $(status_value RESULT)"
        echo "            last attempt: $(status_value LAST_ATTEMPT)"
        echo "            last successful check: $(status_value LAST_CHECK_OK)"
        echo "            last successful update: $(status_value LAST_UPDATE_OK)"
        echo "            failed stages: $(status_value FAILED_STAGES)"
    else
        echo "Updates     no update has run yet (one starts in the background after container start)"
    fi
    echo ""

    disk_used=$(disk_used_gb)
    disk_size=$(df -B1 --output=size "$DISK_PATH" 2>/dev/null | tail -n1 | awk '{ printf "%d", $1 / 1073741824 }')
    echo "Disk        Docker disk: ${disk_used} GB used of ${disk_size} GB"
    echo "            (estimates; freeing space inside Linux does not shrink the Windows disk file until it is compacted)"
    printf '            %-22s %s\n' "Claude scratch dirs" "$(size_of "$TMP_ROOT/claude-$(id -u)")"
    printf '            %-22s %s\n' "other temp files" "$(size_of --exclude="claude-$(id -u)" "$TMP_ROOT")"
    printf '            %-22s %s\n' "package caches" "$(size_of "$HOME/.npm" "$HOME/.cache")"
    printf '            %-22s %s\n' 'container home ~/src' "$(size_of "$HOME/src")"
    echo "            (home ~/src is inside the container; your AI_Work folder is /workspace)"
    echo ""

    if [ "${#ISSUES[@]}" -eq 0 ]; then
        echo "Everything looks healthy."
    else
        echo "Needs attention:"
        printf '  - %s\n' "${ISSUES[@]}"
        if [ "${#HINTS[@]}" -gt 0 ]; then
            echo ""
            echo "What to do:"
            printf '  - %s\n' "${HINTS[@]}"
        fi
    fi
    echo ""
    echo "Network, DNS and login checks: ai-docker doctor"
    [ "${#ISSUES[@]}" -eq 0 ]
}

# --- rescue-scan ----------------------------------------------------------------
#
# A rebuild, recreate or uninstall deletes the container's writable layer: /tmp
# and everything in $HOME except the named-volume mounts. rescue-scan lists work
# there that would be lost (git repos with uncommitted, stashed or unpushed work
# or no remote; any other file outside dependency folders) and --copy
# moves it into the workspace, verified by checksum. Exit: 0 nothing found,
# 3 work found (or, with --copy, 0 once safely copied), 1 copy failed,
# 4 scan incomplete (some location unreadable).

MOUNTS_FILE="${AI_DOCKER_MOUNTS_FILE:-/proc/mounts}"
RESCUE_ROOT="${AI_DOCKER_RESCUE_ROOT:-/workspace/_rescued}"
# Folders whose contents are reinstalled, never hand-made work.
RESCUE_SKIP_DIRS="node_modules site-packages __pycache__ .cache .npm .npm-global .local .cargo .rustup .gradle"
# Inside a virtualenv (found by its pyvenv.cfg) only these parts are rebuildable;
# anything else placed in it is work.
RESCUE_VENV_PARTS="bin lib lib64 include share Lib Scripts"
RESCUE_VENV_FILES="pyvenv.cfg .gitignore CACHEDIR.TAG"
# Hidden folders at the top of a scan root that hold application state (tool
# config, credentials, caches, sockets) rather than work. Any other hidden
# folder is scanned like a visible one.
RESCUE_APP_STATE_DIRS=".ai-docker .ai-docker-cli .cache .config .local .npm .npm-global .claude .codex .gemini .opencode
    .copilot .router-data .tool-auth .vibe-kanban .mcp-auth .ssh .gnupg .pki .docker .kube .aws .azure
    .gcloud .android .gradle .m2 .cargo .rustup .nvm .bun .deno .dotnet .nuget .vscode-server
    .cursor-server .ipython .jupyter .conda .dbus .X11-unix .ICE-unix .XIM-unix .font-unix .Test-unix"
RESCUE_APP_STATE_FILES=".bashrc .bash_profile .bash_login .bash_logout .profile .zshrc .zprofile .zshenv
    .gitconfig .cli_tools_installed .last_update_check .npm-pinned-tools .claude.json
    .bash_history .python_history .node_repl_history .lesshst .wget-hsts .viminfo .lock-*"
declare -A RESCUE_LINK_ORIGINAL=() RESCUE_LINK_REPAIRED=() RESCUE_LINK_ACTIVE=()

# Mount targets inside the scan roots (named volumes) survive a rebuild.
rescue_mounts() {
    awk '{ print $2 }' "$MOUNTS_FILE" 2>/dev/null | sed 's/\\040/ /g'
}

# rescue_find <root>: candidate git repos, virtualenvs, files and symlinks,
# NUL-separated, prefixed "repo:", "venv:", "doc:<size>:" or "link:".
# Never descends into skip dirs, mounts or app-state folders.
rescue_find() {
    local root="$1" name
    local -a prune=()
    [ -d "$root" ] || return 0
    for name in $RESCUE_SKIP_DIRS; do prune+=(-name "$name" -o); done
    for name in $RESCUE_APP_STATE_DIRS; do prune+=(-path "$root/$name" -o); done
    while IFS= read -r name; do
        [ -n "$name" ] && [ "$name" != "/" ] && prune+=(-path "$name" -o)
    done < <(rescue_mounts)
    # Provably rebuildable or not user work: Claude Code's bundled skills and
    # pytest temp are recreated; ai-docker-rescue is this scanner's own copy.
    prune+=(-path "$root/claude-*/bundled-skills" -o -path "$root/pytest-of-*" -o -path "$root/ai-docker-rescue")

    # Any regular file a person or agent left is work unless it is provably
    # rebuildable - file types are no guide (scripts, notebooks, images...).
    # Known shell rc, install markers and tool config are app state, as is
    # this scan's own error file (TMPDIR may be the
    # scanned /tmp). Each file carries its size so callers need no stat.
    # pyvenv.cfg marks a virtualenv, whatever the folder is called. Symlinks
    # are reported for the caller to judge by their target.
    # Errors (unreadable folders) go to RESCUE_ERRFILE: a scan that could not
    # see everything must never report "nothing found".
    local -a mine=(! -path "${RESCUE_ERRFILE:-}")
    for name in $RESCUE_APP_STATE_FILES; do mine+=(! -path "$root/$name"); done
    find "$root" -mindepth 1 \( -type d \( "${prune[@]}" \) -prune \) \
        -o \( -name .git -printf 'repo:%h\0' -prune \) \
        -o \( -name pyvenv.cfg -printf 'venv:%h\0' \) \
        -o \( -type f "${mine[@]}" -printf 'doc:%s:%p\0' \) \
        -o \( -type l "${mine[@]}" -printf 'link:%p\0' \) 2>>"${RESCUE_ERRFILE:-/dev/null}"
}

# rescue_repo_files <repo>: every file and symlink in the working tree that
# could be work (relative paths, NUL-separated) - skipping .git, dependency and
# cache folders, the rebuildable parts of virtualenvs, and nested repositories
# (judged on their own). Fails if any folder could not be read.
rescue_repo_files() {
    local repo="$1" name
    local -a prune=()
    for name in $RESCUE_SKIP_DIRS; do prune+=(-name "$name" -o); done
    unset 'prune[${#prune[@]}-1]'
    ( cd "$repo" && find . -mindepth 1 \( -name .git -printf 'n\t%h\0' -prune \) \
        -o \( \( "${prune[@]}" \) -prune \) -o \( -name pyvenv.cfg -printf 'v\t%h\0' \) \
        -o \( ! -type d -printf 'f\t%P\0' \) 2>/dev/null ) \
    | awk -v RS='\0' -v ORS='\0' -v parts="$RESCUE_VENV_PARTS" -v vfiles="$RESCUE_VENV_FILES" '
        function dir(d) { sub(/^\.\/?/, "", d); return d == "" ? "" : d "/" }
        BEGIN { np = split(parts, P, " "); nv = split(vfiles, VF, " ") }
        /^n\t/ { d = dir(substr($0, 3)); if (d != "") N[++nn] = d; next }
        /^v\t/ { V[++nvenv] = dir(substr($0, 3)); next }
        { F[++nf] = substr($0, 3) }
        END {
            for (i = 1; i <= nf; i++) {
                f = F[i]; drop = 0
                for (j = 1; j <= nn && !drop; j++) if (index(f, N[j]) == 1) drop = 1
                for (j = 1; j <= nvenv && !drop; j++) {
                    if (index(f, V[j]) != 1) continue
                    rest = substr(f, length(V[j]) + 1)
                    for (k = 1; k <= np; k++) if (index(rest, P[k] "/") == 1) drop = 1
                    for (k = 1; k <= nv; k++) if (rest == VF[k]) drop = 1
                }
                if (!drop) print f
            }
        }'
}

# rescue_repo_reasons <repo>: comma-separated reasons the repo holds work only
# here; empty if it is clean, stash-free and fully pushed. Fails (status 1) if
# git could not inspect it - an unreadable repo is never "clean".
rescue_repo_reasons() {
    local repo="$1" reasons=() n out
    local -a tips=(--branches --tags)
    n=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l) || return 1
    [ "$n" -gt 0 ] && reasons+=("$n uncommitted change(s)")
    n=$(git -C "$repo" stash list 2>/dev/null | wc -l) || return 1
    [ "$n" -gt 0 ] && reasons+=("$n stash(es)")
    out=$(git -C "$repo" remote 2>/dev/null) || return 1
    if [ -z "$out" ]; then
        reasons+=("no remote")
    else
        # Every local branch and tag, not just the checked-out one; HEAD too
        # when it exists (a detached HEAD belongs to no branch).
        git -C "$repo" rev-parse -q --verify HEAD >/dev/null 2>&1 && tips=(HEAD "${tips[@]}")
        n=$(git -C "$repo" rev-list --count "${tips[@]}" --not --remotes 2>/dev/null) || return 1
        [ "$n" -gt 0 ] && reasons+=("$n unpushed commit(s)")
    fi
    # Files hidden by .gitignore (exports, data, build output) are not in the
    # remote either. check-ignore exits 1 when nothing is ignored.
    n=$(rescue_repo_files "$repo" | { git -C "$repo" check-ignore -z --stdin 2>/dev/null; [ $? -le 1 ]; } \
        | tr -cd '\0' | wc -c) || return 1
    [ "$n" -gt 0 ] && reasons+=("$n ignored file(s)")
    # Edits git has been told not to report (assume-unchanged, skip-worktree).
    out=$(git -C "$repo" ls-files -v 2>/dev/null) || return 1
    n=$(printf '%s\n' "$out" | grep -c '^[a-zS]' || true)
    [ "$n" -gt 0 ] && reasons+=("$n file(s) hidden from git status")
    local IFS=','
    echo "${reasons[*]}"
}

# rescue_collect: fills the RESCUE_* results for $HOME and /tmp.
rescue_collect() {
    rescue_collect_roots "$HOME" "$TMP_ROOT"
}

# rescue_collect_roots <root...>: fills
#   RESCUE_PATHS, RESCUE_LINES  findings (repos, folders, loose files) and their report lines
#   RESCUE_REPOS                repositories holding work
#   RESCUE_GROUPS               folders and loose files holding work
#   RESCUE_FILES                exactly the files and symlinks to copy from those groups
#   RESCUE_UNREADABLE           locations that could not be checked
rescue_collect_roots() {
    RESCUE_PATHS=()
    RESCUE_LINES=()
    RESCUE_UNREADABLE=()
    RESCUE_REPOS=()
    RESCUE_GROUPS=()
    RESCUE_FILES=()
    RESCUE_LINK_ORIGINAL=(); RESCUE_LINK_REPAIRED=(); RESCUE_LINK_ACTIVE=()
    if ! RESCUE_ERRFILE=$(mktemp 2>/dev/null); then
        RESCUE_UNREADABLE+=("temporary scan error file (could not be created)")
        return
    fi
    local root entry path reasons repo inside group rel venv part target
    local -a repos=() docs=() groups=() venvs=() extras=()
    local -A doc_root=() doc_size=() group_count=() group_bytes=()
    # find only learns a folder is a repo (or virtualenv) when it reaches its
    # .git (or pyvenv.cfg), so gather everything first, then judge files inside
    # a repo by the repo and drop files inside a virtualenv.
    for root in "$@"; do
        while IFS= read -r -d '' entry; do
            case "$entry" in
                repo:*) repos+=("${entry#repo:}") ;;
                venv:*) venvs+=("${entry#venv:}") ;;
                doc:*)
                    entry=${entry#doc:}
                    path=${entry#*:}
                    docs+=("$path"); doc_root[$path]=$root; doc_size[$path]=${entry%%:*}
                    ;;
                link:*)
                    path=${entry#link:}
                    docs+=("$path"); doc_root[$path]=$root
                    ;;
            esac
        done < <(rescue_find "$root")
    done
    mapfile -t RESCUE_UNREADABLE < <(sed -n -E "s/^find: ['‘](.*)['’]: Permission denied$/\1/p" "$RESCUE_ERRFILE" | sort -u)
    if [ "${#RESCUE_UNREADABLE[@]}" -eq 0 ] && [ -s "$RESCUE_ERRFILE" ]; then
        # Any other find error also makes the scan untrustworthy.
        mapfile -t RESCUE_UNREADABLE < <(sed 's/^find: //' "$RESCUE_ERRFILE" | sort -u)
    fi
    rm -f "$RESCUE_ERRFILE"

    for repo in "${repos[@]}"; do
        if ! reasons=$(rescue_repo_reasons "$repo"); then
            RESCUE_UNREADABLE+=("$repo (git could not inspect it)")
            continue
        fi
        [ -n "$reasons" ] || continue
        RESCUE_PATHS+=("$repo")
        RESCUE_REPOS+=("$repo")
        RESCUE_LINES+=("git repo  $repo  (${reasons//,/, })")
    done
    for path in "${docs[@]}"; do
        inside=0
        for repo in "${repos[@]}"; do
            case "$path" in "$repo"/*) inside=1; break ;; esac
        done
        for venv in "${venvs[@]}"; do
            for part in $RESCUE_VENV_PARTS; do
                case "$path" in "$venv/$part"/*) inside=1; break 2 ;; esac
            done
            for part in $RESCUE_VENV_FILES; do
                [ "$path" = "$venv/$part" ] && { inside=1; break 2; }
            done
        done
        [ "$inside" -eq 0 ] || continue
        # Group by top-level folder under the scan root, so one batch of
        # files is one line; loose files stand alone.
        rel=${path#"${doc_root[$path]}"/}
        case "$rel" in
            */*) group="${doc_root[$path]}/${rel%%/*}" ;;
            *) group=$path ;;
        esac
        if [ -L "$path" ]; then
            # A symlink explicitly references work even if its target is in
            # a normally skipped tool folder. Any other link is copied along
            # with work in the same folder.
            if target=$(readlink -f -- "$path") && [ -e "$target" ] \
                && in_discard_zone "$target"; then
                doc_size[$path]=$(du -sb -- "$target" 2>/dev/null | cut -f1)
            else
                extras+=("$path")
                continue
            fi
        fi
        RESCUE_FILES+=("$path")
        if [ -z "${group_count[$group]:-}" ]; then
            groups+=("$group")
            group_count[$group]=0
            group_bytes[$group]=0
        fi
        group_count[$group]=$(( ${group_count[$group]} + 1 ))
        group_bytes[$group]=$(( ${group_bytes[$group]} + ${doc_size[$path]:-0} ))
    done
    for path in "${extras[@]}"; do
        rel=${path#"${doc_root[$path]}"/}
        case "$rel" in */*) group="${doc_root[$path]}/${rel%%/*}" ;; *) continue ;; esac
        [ -n "${group_count[$group]:-}" ] && RESCUE_FILES+=("$path")
    done
    RESCUE_GROUPS=("${groups[@]}")
    local -A loose_count=() loose_bytes=()
    for group in "${groups[@]}"; do
        RESCUE_PATHS+=("$group")
        if [ -d "$group" ]; then
            RESCUE_LINES+=("folder    $group  ($(plural "${group_count[$group]}" file), $(human_bytes "${group_bytes[$group]}"))")
        else
            # Loose files directly in a scan root: one summary line per root.
            root=${group%/*}
            loose_count[$root]=$(( ${loose_count[$root]:-0} + 1 ))
            loose_bytes[$root]=$(( ${loose_bytes[$root]:-0} + ${group_bytes[$group]} ))
        fi
    done
    for root in "${!loose_count[@]}"; do
        RESCUE_LINES+=("files     $root/  ($(plural "${loose_count[$root]}" "loose file"), $(human_bytes "${loose_bytes[$root]}"))")
    done
}

# plural <n> <noun>: "1 document", "3 documents".
plural() {
    if [ "$1" -eq 1 ]; then echo "1 $2"; else echo "$1 ${2}s"; fi
}

human_bytes() {
    awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.1f GB", b / 1073741824; else if (b >= 1048576) printf "%.1f MB", b / 1048576; else printf "%d KB", (b + 1023) / 1024 }'
}

# rescue_destination: next free <yyyymmdd>_container_rescue_vX_XX folder.
rescue_destination() {
    local day minor=0 dest
    day=$(date +%Y%m%d)
    while :; do
        dest=$(printf '%s/%s_container_rescue_v1_%02d' "$RESCUE_ROOT" "$day" "$minor")
        [ -e "$dest" ] || { echo "$dest"; return; }
        minor=$((minor + 1))
    done
}

# rescue_check_sums <dest>: check the checksum list <dest>/.verify.$$ against
# the copy, then remove the list. An empty list (only symlinks) checks nothing.
rescue_check_sums() {
    local dest="$1" rc=0
    if [ -s "$dest/.verify.$$" ]; then
        ( cd "$dest" && sha256sum --quiet -c "$dest/.verify.$$" ) >/dev/null 2>&1 || rc=1
    fi
    rm -f "$dest/.verify.$$"
    return "$rc"
}

# rescue_copy <dest>: copy each finding to <dest><absolute path> and verify
# every copied file by checksum. The plan never overlaps: folders contribute
# exactly the files the scan found (never a repository, a named volume or
# dependency data inside them), and a repository nested in another travels
# with the outer copy. Repositories are converted and checked only once
# every copy is in place.
rescue_copy() {
    local dest="$1" path name mount repo outer item
    local -a excludes=() prune=() items=()
    mkdir -p "$dest" || return 1
    if [ "${#RESCUE_FILES[@]}" -gt 0 ]; then
        printf '%s\0' "${RESCUE_FILES[@]#/}" | tar -C / --null --no-recursion -T - -cf - 2>/dev/null \
            | tar -C "$dest" -xf - 2>/dev/null || return 1
        for path in "${RESCUE_FILES[@]}"; do
            [ -L "$path" ] || printf '%s\0' "${path#/}"
        done | ( cd / && xargs -0 -r sha256sum ) > "$dest/.verify.$$" 2>/dev/null || return 1
        rescue_check_sums "$dest" || return 1
    fi
    for repo in "${RESCUE_REPOS[@]}"; do
        for outer in "${RESCUE_REPOS[@]}"; do
            case "$repo" in "$outer"/*) continue 2 ;; esac
        done
        items+=("$repo")
        # One exclusion list drives both the copy and its verification: named
        # volumes inside the repository (anchored), dependency folders (by name).
        excludes=(--anchored); prune=()
        while IFS= read -r mount; do
            case "$mount" in "$repo"/*) excludes+=(--exclude="${mount#/}"); prune+=(-path "${mount#/}" -o) ;; esac
        done < <(rescue_mounts)
        excludes+=(--no-anchored)
        for name in $RESCUE_SKIP_DIRS; do
            excludes+=(--exclude="$name")
            prune+=(-name "$name" -o)
        done
        unset 'prune[${#prune[@]}-1]'
        tar -C / "${excludes[@]}" -cf - "${repo#/}" 2>/dev/null | tar -C "$dest" -xf - 2>/dev/null || return 1
        ( cd / && find "${repo#/}" \( -type d \( "${prune[@]}" \) -prune \) -o -type f -print0 \
            | xargs -0 -r sha256sum ) > "$dest/.verify.$$" 2>/dev/null || return 1
        rescue_check_sums "$dest" || return 1
        rescue_register_repos "$repo" "$dest$repo"
    done
    for item in "${RESCUE_GROUPS[@]}" "${items[@]}"; do
        rescue_fix_links "$item" "$dest" || return 1
    done
    for repo in "${RESCUE_REPOS[@]}"; do
        rescue_make_standalone "$repo" "$dest$repo" || return 1
        rescue_normalize_repo "$dest$repo" || return 1
    done
    for repo in "${RESCUE_REPOS[@]}"; do
        rescue_verify_repo "$repo" "$dest$repo" || return 1
    done
}

# in_discard_zone <path>: storage a rebuild deletes - /tmp or the home folder
# outside the named-volume mounts.
in_discard_zone() {
    local mount
    case "$1" in
        "$TMP_ROOT"/*|"$HOME"/*) ;;
        *) return 1 ;;
    esac
    while IFS= read -r mount; do
        [ -n "$mount" ] && [ "$mount" != "/" ] || continue
        case "$1/" in "$mount"/*) return 1 ;; esac
    done < <(rescue_mounts)
    return 0
}

# rescue_copy_verified <source> <copy> [logical-source]: copy a referent and
# check its content. Directory copies preserve child links and exclude named
# volumes; following links recursively with cp -L would copy those volumes.
rescue_copy_verified() {
    local src="$1" copy="$2" logical="${3:-$1}" mount list sums rc=0
    if [ -d "$src" ]; then
        local -a prune=(-false)
        while IFS= read -r mount; do
            case "$mount" in "$src"/*) prune+=(-o -path "./${mount#"$src"/}") ;; esac
        done < <(rescue_mounts)
        list=$(mktemp) || return 1
        sums=$(mktemp) || { rm -f "$list"; return 1; }
        if ! ( cd "$src" && find . -mindepth 1 \( -type d \( "${prune[@]}" \) -prune \) -o -print0 ) > "$list" 2>/dev/null; then
            rm -f "$list" "$sums"; return 1
        fi
        mkdir -p -- "$copy" \
            && tar -C "$src" --null --no-recursion -T "$list" -cf - 2>/dev/null \
                | tar -C "$copy" --skip-old-files -xf - 2>/dev/null || rc=1
        if [ "$rc" -eq 0 ]; then
            ( cd "$src" && find . -mindepth 1 \( -type d \( "${prune[@]}" \) -prune \) \
                -o -type f -print0 | xargs -0 -r sha256sum ) > "$sums" 2>/dev/null || rc=1
            if [ -s "$sums" ]; then
                ( cd "$copy" && sha256sum --quiet -c "$sums" ) >/dev/null 2>&1 || rc=1
            fi
        fi
        rescue_register_repos "$logical" "$copy"
        rm -f "$list" "$sums"
        return "$rc"
    else
        if [ ! -e "$copy" ]; then
            mkdir -p -- "$(dirname -- "$copy")" && cp -a -- "$src" "$copy" || return 1
        fi
        cmp -s -- "$src" "$copy"
    fi
}

# Nested repos and initialized submodules travel with an outer repository,
# even when they were clean during discovery. Convert and verify them too.
rescue_register_repos() {
    local src="$1" copy="$2" path repo known existing
    while IFS= read -r -d '' path; do
        repo="$src${path#"$copy"}"
        known=0
        for existing in "${RESCUE_REPOS[@]}"; do [ "$existing" != "$repo" ] || known=1; done
        [ "$known" -eq 1 ] || RESCUE_REPOS+=("$repo")
    done < <(find "$copy" -mindepth 1 -name .git -printf '%h\0' -prune 2>/dev/null)
}

# Keep the original tracked link value in the index/history and in the rescue
# handoff. Relocating its working copy is an intentional unstaged change.
rescue_relocate_link() {
    local src="$1" link="$2" raw="$3" target="$4" dest="$5" tracked="$6"
    [ "$raw" != "$target" ] || return 0
    ln -sfn -- "$target" "$link" || return 1
    if [ "$tracked" -eq 1 ]; then
        RESCUE_LINK_ORIGINAL[$src]=$raw
        RESCUE_LINK_REPAIRED[$src]=$target
        mkdir -p "$dest/.ai-docker-rescue-metadata" || return 1
        printf 'source=%q\noriginal_target=%q\nrescued_target=%q\n\n' "$src" "$raw" "$target" \
            >> "$dest/.ai-docker-rescue-metadata/link-relocations.txt" || return 1
    fi
}

# rescue_fix_links <source item> <dest root>: make every symlink copied with
# the item work after the rebuild, judged by its final destination.
# - The target survives (named volume, workspace): a relative link now sits
#   elsewhere, so it is made absolute - then it must resolve.
# - The rebuild deletes the target and the copy does not carry it (outside
#   the item, or an absolute path): the link is replaced by a verified copy of
#   the target. If git tracks the link, keep it as a link to the rescued target
#   and retain its original value in the index and relocation handoff.
# - Relative links within the item travel with it if the copied target exists.
rescue_fix_links() {
    local item="$1" dest="$2" link src raw target inside tracked repaired
    while IFS= read -r -d '' link; do
        src=${link#"$dest"}
        raw=$(readlink -- "$src") || return 1
        target=$(readlink -f -- "$src") || return 1
        [ -e "$target" ] || continue
        inside=0
        case "$target/" in "$item"/*) inside=1 ;; esac
        tracked=0
        git -C "$(dirname -- "$src")" ls-files --error-unmatch -- ":(literal)$(basename -- "$src")" >/dev/null 2>&1 && tracked=1
        if ! in_discard_zone "$target"; then
            case "$raw" in /*) ;; *) rescue_relocate_link "$src" "$link" "$raw" "$target" "$dest" "$tracked" || return 1 ;; esac
        elif [ "$inside" -eq 0 ] || [ "${raw#/}" != "$raw" ] || [ ! -e "$link" ]; then
            if [ "$tracked" -eq 1 ]; then
                rescue_copy_verified "$target" "$dest$target" || return 1
                repaired=$(realpath --relative-to="$(dirname -- "$link")" -- "$dest$target") || return 1
                rescue_relocate_link "$src" "$link" "$raw" "$repaired" "$dest" "$tracked" || return 1
                if [ -d "$target" ] && [ -z "${RESCUE_LINK_ACTIVE[$target]:-}" ]; then
                    RESCUE_LINK_ACTIVE[$target]=1
                    rescue_fix_links "$target" "$dest" || return 1
                    unset 'RESCUE_LINK_ACTIVE[$target]'
                fi
            else
                if [ -d "$target" ]; then
                    [ -z "${RESCUE_LINK_ACTIVE[$target]:-}" ] || return 1
                    RESCUE_LINK_ACTIVE[$target]=1
                fi
                rm -f -- "$link" && rescue_copy_verified "$target" "$link" "$src" || return 1
                if [ -d "$target" ]; then
                    rescue_fix_links "$src" "$dest" || return 1
                    unset 'RESCUE_LINK_ACTIVE[$target]'
                fi
            fi
        fi
        [ -e "$link" ] || return 1
    done < <(find "$dest$item" -type l -print0 2>/dev/null)
}

# rescue_make_standalone <source repo> <copy>: a worktree's .git is a file that
# points at the original repository, which a rebuild may delete. Rebuild the
# copy as an independent repository from a bundle of every ref.
rescue_make_standalone() {
    local src="$1" copy="$2" bundle head remote
    [ -f "$copy/.git" ] || return 0
    bundle=$(mktemp) || return 1
    git -C "$src" bundle create "$bundle" --all >/dev/null 2>&1 || { rm -f "$bundle"; return 1; }
    rm -f "$copy/.git"
    git -C "$copy" init -q >/dev/null 2>&1 \
        && git -C "$copy" fetch -q --update-head-ok "$bundle" 'refs/*:refs/*' >/dev/null 2>&1 \
        || { rm -f "$bundle"; return 1; }
    rm -f "$bundle"
    for remote in $(git -C "$src" remote 2>/dev/null); do
        git -C "$copy" remote add "$remote" "$(git -C "$src" remote get-url "$remote")" 2>/dev/null || true
    done
    if head=$(git -C "$src" symbolic-ref -q HEAD); then
        git -C "$copy" symbolic-ref HEAD "$head"
    else
        git -C "$copy" update-ref --no-deref HEAD "$(git -C "$src" rev-parse HEAD)"
    fi
    # Keep the original index, so staged changes stay staged; rebuild it from
    # HEAD only if it cannot be read.
    local index
    index=$(cd "$src" && realpath -- "$(git rev-parse --git-path index)" 2>/dev/null)
    if [ -f "$index" ] && cp -- "$index" "$copy/.git/index"; then
        # Staged content lives as objects in the original repository, which
        # the bundle (committed history only) does not carry: copy any object
        # the index needs that the copy lacks.
        git -C "$copy" ls-files -s 2>/dev/null | awk '$1 != "160000" { print $2 }' | sort -u \
            | git -C "$copy" cat-file --batch-check 2>/dev/null | awk '$2 == "missing" { print $1 }' \
            | while IFS= read -r sha; do
                git -C "$src" cat-file blob "$sha" | git -C "$copy" hash-object -w --stdin >/dev/null || exit 1
            done || return 1
        git -C "$copy" update-index -q --refresh >/dev/null 2>&1 || true
    else
        git -C "$copy" reset -q >/dev/null 2>&1
    fi
}

# rescue_verify_repo <source repo> <copy>: the copy must work on its own and
# match the original's HEAD and tracked changes - checksums alone cannot tell.
# (Untracked files are covered by the checksum step; dependency folders are
# deliberately not copied, so they are left out of this comparison.)
rescue_normalize_repo() {
    local copy="$1" rc
    # Never let copied config send Git back to the original working tree.
    git --git-dir="$copy/.git" config --local --unset-all core.worktree >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ] || return 1
    if [ -f "$copy/.git/config.worktree" ]; then
        git --git-dir="$copy/.git" config --file "$copy/.git/config.worktree" --unset-all core.worktree >/dev/null 2>&1
        rc=$?
        [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ] || return 1
    fi
    return 0
}

rescue_verify_repo() {
    local src="$1" copy="$2" key before after rc=0
    # A clone made with --shared (or --reference) borrows objects from another
    # repository through objects/info/alternates; copy them in and drop the link.
    if [ -s "$copy/.git/objects/info/alternates" ]; then
        git -C "$copy" repack -a -d -q >/dev/null 2>&1 || return 1
        rm -f -- "$copy/.git/objects/info/alternates"
    fi
    git -C "$copy" fsck --connectivity-only --no-progress >/dev/null 2>&1 || return 1
    [ "$(git -C "$copy" rev-parse HEAD 2>/dev/null)" = "$(git -C "$src" rev-parse HEAD 2>/dev/null)" ] || return 1
    # Compare the original tracked changes before the deliberate link
    # relocations. Always restore the working links before returning.
    rc=0
    for key in "${!RESCUE_LINK_ORIGINAL[@]}"; do
        case "$key" in "$src"/*)
            ln -sfn -- "${RESCUE_LINK_ORIGINAL[$key]}" "${copy}${key#"$src"}" || rc=1 ;;
        esac
    done
    before=$(git -C "$src" status --porcelain --untracked-files=no 2>/dev/null | sort) || rc=1
    after=$(git -C "$copy" status --porcelain --untracked-files=no 2>/dev/null | sort) || rc=1
    [ "$before" = "$after" ] || rc=1
    for key in "${!RESCUE_LINK_ORIGINAL[@]}"; do
        case "$key" in "$src"/*)
            ln -sfn -- "${RESCUE_LINK_REPAIRED[$key]}" "${copy}${key#"$src"}" || rc=1
            [ -e "${copy}${key#"$src"}" ] || rc=1 ;;
        esac
    done
    return "$rc"
}

cmd_rescue_scan() {
    rescue_collect
    if [ "${#RESCUE_UNREADABLE[@]}" -gt 0 ]; then
        # Incomplete: something could not be checked, so nothing can be
        # declared safe and no rescue can be certified.
        echo "The scan is INCOMPLETE - these locations could not be read:"
        printf '  could not be read: %s\n' "${RESCUE_UNREADABLE[@]}"
        if [ "${#RESCUE_PATHS[@]}" -gt 0 ]; then
            echo ""
            echo "Work found in the readable locations:"
            printf '  %s\n' "${RESCUE_LINES[@]}"
        fi
        echo ""
        if [ "${1:-}" = "--copy" ]; then
            echo "ERROR: cannot certify a rescue while locations are unreadable. Do not rebuild or uninstall until this is resolved." >&2
            return 1
        fi
        echo "Fix the permissions (or copy those folders out by hand) before rebuilding."
        return 4
    fi
    if [ "${#RESCUE_PATHS[@]}" -eq 0 ]; then
        echo "Nothing found outside the folders a rebuild keeps."
        return 0
    fi
    echo "Found work outside the folders a rebuild keeps (${#RESCUE_LINES[@]} location(s)):"
    echo "A rebuild, recreate or uninstall of the container deletes these:"
    printf '  %s\n' "${RESCUE_LINES[@]}"
    if [ "${1:-}" != "--copy" ]; then
        echo ""
        echo "Copy them into the workspace first with: ai-docker rescue-scan --copy"
        return 3
    fi
    local dest
    dest=$(rescue_destination)
    if rescue_copy "$dest"; then
        echo ""
        echo "Copied and verified in: $dest"
        if [ "${#RESCUE_LINK_ORIGINAL[@]}" -gt 0 ]; then
            echo "Tracked links were relocated to keep working. Their original targets are saved in .ai-docker-rescue-metadata/link-relocations.txt; Git retains the original staged content."
        fi
        return 0
    fi
    echo ""
    echo "ERROR: the copy to $dest failed or did not verify. Do not rebuild or uninstall until this is resolved." >&2
    return 1
}

# --- cleanup --------------------------------------------------------------------
#
# Conservative removal of disposable data. Only tool-managed data with reliable
# recreation can be deleted: download caches and old Claude Code versions are
# suggested, older Playwright builds are opt-in. Clones, temporary virtualenvs
# and dependency folders in agent scratch are REPORT ONLY in this release -
# shown with paths and sizes, never deleted by cleanup - because no check can
# prove they hold nothing unique. Every deletion is re-checked for active use.

CLEANUP_AGE_DAYS="${AI_DOCKER_CLEANUP_AGE_DAYS:-3}"

# recently_used <dir>: any file in it modified within CLEANUP_AGE_DAYS.
# Directory timestamps are ignored (deleting a sub-folder bumps them; a new
# file is still caught), and so are .git internals (git status rewrites the index).
recently_used() {
    [ -n "$(find "$1" -name .git -prune -o ! -type d -newermt "-$CLEANUP_AGE_DAYS days" -print -quit 2>/dev/null)" ]
}

# in_use_by_process <path>: a running process uses it - its executable is
# <path> or inside it, or its working directory is inside it.
in_use_by_process() {
    local proc link
    for proc in /proc/[0-9]*; do
        for link in exe cwd; do
            link=$(readlink "$proc/$link" 2>/dev/null) || continue
            link=${link% (deleted)}
            case "$link/" in "$1"/*) return 0 ;; esac
        done
    done
    return 1
}

kb_of() { du -sk "$@" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }
# kb_of_list <newline-separated paths>: total size, safe for spaces in names.
kb_of_list() {
    printf '%s\n' "$1" | sed '/^$/d' | tr '\n' '\0' | du -sck --files0-from=- 2>/dev/null | tail -n1 | cut -f1
}
kb_phrase() { human_bytes $(( $1 * 1024 )); }

# rebuildable_dirs_in <dir>: outermost dependency/cache folders and virtualenvs
# (a pyvenv.cfg marks one, whatever its name) below <dir>, one per line.
rebuildable_dirs_in() {
    local name
    local -a names=(-name .venv -o -name venv -o)
    for name in $RESCUE_SKIP_DIRS; do names+=(-name "$name" -o); done
    unset 'names[${#names[@]}-1]'
    {
        find "$1" -mindepth 1 -type d \( "${names[@]}" \) -prune -print 2>/dev/null
        find "$1" -mindepth 2 -name pyvenv.cfg -printf '%h\n' 2>/dev/null
    } | sort -u | awk 'NR == 1 || index($0, prev "/") != 1 { print; prev = $0 }'
}

CLAUDE_VERSIONS_DIR="$HOME/.local/share/claude/versions"

# claude_versions_kept: two lines - the Claude Code version the launcher runs
# now, and the newest other one (the fallback). Asked again right before each
# deletion: an update can switch versions while cleanup waits for an answer.
claude_versions_kept() {
    local current prev
    current=$(readlink -f "$(command -v claude 2>/dev/null)" 2>/dev/null || true)
    current=${current#"$CLAUDE_VERSIONS_DIR"/}; current=${current%%/*}
    # The native installer keeps each version as one executable file
    # (older layouts used a folder); accept both.
    prev=$(find "$CLAUDE_VERSIONS_DIR" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -printf '%f\n' 2>/dev/null \
        | grep -vxF -- "$current" | sort -V | tail -n1)
    printf '%s\n%s\n' "$current" "$prev"
}

# Groups: parallel arrays. KIND is "cmd" (run CMD), "paths" (delete ITEMS after
# confirmation) or "report" (list ITEMS with sizes; never deleted).
cleanup_add_group() {
    G_LABEL+=("$1"); G_DEFAULT+=("$2"); G_KIND+=("$3"); G_CMD+=("$4"); G_ITEMS+=("$5"); G_KB+=("$6")
}

cleanup_collect() {
    G_LABEL=(); G_DEFAULT=(); G_KIND=(); G_CMD=(); G_ITEMS=(); G_KB=()
    local items dir name current prev builds keep path reasons

    [ -d "$HOME/.npm/_cacache" ] && \
        cleanup_add_group "npm download cache" y cmd "npm cache clean --force" "" "$(kb_of "$HOME/.npm/_cacache")"
    [ -d "$HOME/.cache/pip" ] && \
        cleanup_add_group "pip download cache" y cmd "pip3 cache purge" "" "$(kb_of "$HOME/.cache/pip")"

    # Claude Code: keep the running version and the newest other one.
    dir="$CLAUDE_VERSIONS_DIR"
    if [ -d "$dir" ]; then
        { read -r current; read -r prev; } < <(claude_versions_kept)
        items=$(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -printf '%f\n' | grep -vxF -e "$current" -e "${prev:-/}" | sed "s|^|$dir/|")
        [ -n "$items" ] && [ -n "$current" ] && \
            cleanup_add_group "Claude Code versions ($(printf '%s\n' "$items" | wc -l) old; current and fallback kept)" y paths "" "$items" "$(kb_of_list "$items")"
    fi

    # Playwright: keep the newest build of each browser; a project may pin an
    # older one, so older builds are opt-in.
    dir="$HOME/.cache/ms-playwright"
    if [ -d "$dir" ]; then
        items=""
        for name in $(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sed 's/-[0-9]*$//' | sort -u); do
            builds=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -name "$name-[0-9]*" -printf '%f\n' | sort -V)
            keep=$(printf '%s\n' "$builds" | tail -n1)
            items+=$(printf '%s\n' "$builds" | grep -vxF -- "$keep" | sed "s|^|$dir/|")$'\n'
        done
        items=$(printf '%s' "$items" | sed '/^$/d')
        [ -n "$items" ] && cleanup_add_group "Playwright browser builds ($(printf '%s\n' "$items" | wc -l) older)" n paths "" "$items" "$(kb_of_list "$items")"
    fi

    # Rebuildable folders (virtualenvs, node_modules, caches) inside agent
    # scratch folders unused for CLEANUP_AGE_DAYS. The scratch folders
    # themselves, and every other file in them, are never deleted: age alone
    # does not make hand-made work rebuildable.
    items=""
    while IFS= read -r session; do
        [ -n "$session" ] || continue
        recently_used "$session" && continue
        in_use_by_process "$session" && continue
        items+=$(rebuildable_dirs_in "$session")$'\n'
    done < <(find "$TMP_ROOT/claude-$(id -u)" -mindepth 2 -maxdepth 2 -type d ! -name bundled-skills 2>/dev/null)
    items=$(printf '%s' "$items" | sed '/^$/d')
    [ -n "$items" ] && cleanup_add_group "Dependency folders in agent scratch ($(printf '%s\n' "$items" | wc -l), unused ${CLEANUP_AGE_DAYS}+ days)" n report "" "$items" "$(kb_of_list "$items")"

    # Temporary virtualenvs (a pyvenv.cfg marks one), wherever they sit in /tmp.
    items=""
    while IFS= read -r path; do
        path=${path%/pyvenv.cfg}
        recently_used "$path" && continue
        in_use_by_process "$path" && continue
        items+="$path"$'\n'
    done < <(find "$TMP_ROOT" -mindepth 2 -maxdepth 5 -path "$TMP_ROOT/claude-*" -prune -o -name pyvenv.cfg -print 2>/dev/null)
    items=$(printf '%s' "$items" | sed '/^$/d')
    [ -n "$items" ] && cleanup_add_group "Temporary virtualenvs ($(printf '%s\n' "$items" | wc -l))" n report "" "$items" "$(kb_of_list "$items")"

    # Clones in ~/src that are clean, stash-free and fully pushed.
    items=""
    while IFS= read -r path; do
        path=${path%/.git}
        # A repo git cannot inspect is never reported as having nothing unpushed.
        reasons=$(rescue_repo_reasons "$path") || continue
        [ -n "$reasons" ] && continue
        recently_used "$path" && continue
        in_use_by_process "$path" && continue
        items+="$path"$'\n'
    done < <(find "$HOME/src" -mindepth 2 -maxdepth 2 -name .git 2>/dev/null)
    items=$(printf '%s' "$items" | sed '/^$/d')
    [ -n "$items" ] && cleanup_add_group "Clones in ~/src with nothing unpushed ($(printf '%s\n' "$items" | wc -l))" n report "" "$items" "$(kb_of_list "$items")"
}

cleanup_preview() {
    local i mark path shown deletable=0 reported=0
    echo "Cleanup - estimated sizes"
    echo ""
    for i in "${!G_LABEL[@]}"; do
        [ "${G_KIND[$i]}" != report ] || continue
        deletable=1
        if [ "${G_DEFAULT[$i]}" = y ]; then mark="[x]"; else mark="[ ]"; fi
        printf '  %s %-58s %s\n' "$mark" "${G_LABEL[$i]}" "$(kb_phrase "${G_KB[$i]}")"
    done
    [ "$deletable" -eq 1 ] || echo "  Nothing that cleanup can delete was found."

    for i in "${!G_LABEL[@]}"; do
        [ "${G_KIND[$i]}" = report ] || continue
        if [ "$reported" -eq 0 ]; then
            echo ""
            echo "Report only - cleanup never deletes these (check them and remove by hand if you are sure):"
            reported=1
        fi
        printf '  %-62s %s\n' "${G_LABEL[$i]}" "$(kb_phrase "${G_KB[$i]}")"
        shown=0
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            shown=$((shown + 1))
            if [ "$shown" -gt 15 ]; then
                echo "      ... and $(( $(printf '%s\n' "${G_ITEMS[$i]}" | sed '/^$/d' | wc -l) - 15 )) more"
                break
            fi
            printf '      %-56s %s\n' "$path" "$(kb_phrase "$(kb_of "$path")")"
        done <<< "${G_ITEMS[$i]}"
    done
    echo ""
    echo "[x] = suggested. Freeing space inside Linux does not shrink the Windows disk file until it is compacted."
}

# Re-check a path right before deleting it; prints why it was skipped.
cleanup_still_safe() {
    local path="$1"
    [ -e "$path" ] || return 1
    case "$path" in
        "$CLAUDE_VERSIONS_DIR"/*)
            if claude_versions_kept | grep -qxF -- "${path#"$CLAUDE_VERSIONS_DIR"/}"; then
                echo "  Skipped $path: it is now the current or fallback Claude Code version"
                return 1
            fi
            ;;
    esac
    if in_use_by_process "$path"; then
        echo "  Skipped $path: in use by a running process"
        return 1
    fi
}

cmd_cleanup() {
    cleanup_collect
    cleanup_preview
    if [ "${1:-}" != "--apply" ]; then
        echo ""
        echo "Nothing was deleted. To choose what to delete, run: ai-docker cleanup --apply"
        return 0
    fi

    local i answer prompt freed_kb=0 path
    echo ""
    for i in "${!G_LABEL[@]}"; do
        [ "${G_KIND[$i]}" != report ] || continue
        if [ "${G_DEFAULT[$i]}" = y ]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
        printf 'Delete %s (%s)? %s ' "${G_LABEL[$i]}" "$(kb_phrase "${G_KB[$i]}")" "$prompt"
        answer=""
        if ! read -r answer; then
            # Closed or interrupted input is never a "yes".
            echo ""
            echo "Input ended - stopping; nothing more will be deleted."
            break
        fi
        echo ""
        answer=${answer:-${G_DEFAULT[$i]}}
        case "$answer" in [Yy]*) ;; *) continue ;; esac

        if [ "${G_KIND[$i]}" = cmd ]; then
            if ${G_CMD[$i]} >/dev/null 2>&1; then
                freed_kb=$((freed_kb + G_KB[i]))
            else
                echo "  Could not clear ${G_LABEL[$i]}"
            fi
            continue
        fi
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            cleanup_still_safe "$path" || continue
            local kb
            kb=$(kb_of "$path")
            rm -rf -- "$path" && freed_kb=$((freed_kb + kb))
        done <<< "${G_ITEMS[$i]}"
    done
    echo "Freed about $(kb_phrase "$freed_kb") inside the container (estimated)."
    echo "To return the space to Windows, the Docker disk file must be compacted (see docs/CLI_TOOLS_GUIDE.md)."
}

usage() {
    cat <<'EOF'
Usage: ai-docker <command>

Commands:
  status               Tools, updates, disk use and container limits
  status --brief       One-line summary (shown when a shell starts)
  doctor               Network, DNS, TLS and login diagnostics
  rescue-scan          List work a rebuild/uninstall would delete
  rescue-scan --copy   Copy that work into the workspace (verified)
  cleanup              Preview disposable data that can be removed
  cleanup --apply      Choose, group by group, what to delete
  help                 Show this help
EOF
}

case "${1:-help}" in
    status)
        if [ "${2:-}" = "--brief" ]; then cmd_brief; else cmd_status; fi
        ;;
    doctor)
        exec /usr/local/bin/configure_tools.sh --diagnose
        ;;
    rescue-scan)
        cmd_rescue_scan "${2:-}"
        ;;
    cleanup)
        cmd_cleanup "${2:-}"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
