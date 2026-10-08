#!/usr/bin/env bash
# Behavioral tests for `ai-docker cleanup`: conservative, confirmed removal of
# disposable data. Caches are pre-selected; anything that could hold work is
# opt-in; anything holding work is never offered.
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label (expected $expected, got $actual)"; fi
}
assert_contains() {
    local label=$1 haystack=$2 needle=$3
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then pass "$label"; else fail "$label (missing: $needle)"; fi
}
assert_exists() { if [ -e "$2" ]; then pass "$1"; else fail "$1"; fi; }
assert_gone() { if [ -e "$2" ]; then fail "$1"; else pass "$1"; fi; }

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null

age() { touch -d "-$2 days" "$1"; find "$1" -exec touch -h -d "-$2 days" {} + 2>/dev/null; }

setup_case() {
    CASE_DIR=$(mktemp -d "$TMP_DIR/case.XXXXXX")
    export HOME="$CASE_DIR/home"
    export AI_DOCKER_TMP_DIR="$CASE_DIR/tmp"
    export AI_DOCKER_LIB_DIR="$ROOT_DIR/docker/lib"
    export AI_DOCKER_MOUNTS_FILE="$CASE_DIR/mounts"; : > "$AI_DOCKER_MOUNTS_FILE"
    export AI_DOCKER_DISK_PATH="$CASE_DIR"
    export FAKE_LOG="$CASE_DIR/calls"; : > "$FAKE_LOG"
    mkdir -p "$HOME" "$AI_DOCKER_TMP_DIR" "$CASE_DIR/bin"
    uid=$(id -u)

    # npm / pip caches with fakes that record and clear them.
    mkdir -p "$HOME/.npm/_cacache" "$HOME/.npm/_npx/keep" "$HOME/.cache/pip/http"
    head -c 4096 /dev/zero > "$HOME/.npm/_cacache/blob"; head -c 4096 /dev/zero > "$HOME/.cache/pip/http/blob"
    cat > "$CASE_DIR/bin/npm" <<'SCRIPT'
#!/usr/bin/env bash
echo "npm $*" >> "$FAKE_LOG"
[ "$*" = "cache clean --force" ] && rm -rf "$HOME/.npm/_cacache"
exit 0
SCRIPT
    cat > "$CASE_DIR/bin/pip3" <<'SCRIPT'
#!/usr/bin/env bash
echo "pip3 $*" >> "$FAKE_LOG"
[ "$*" = "cache purge" ] && rm -rf "$HOME/.cache/pip"
exit 0
SCRIPT

    # Claude Code versions, native layout: each version is one executable FILE
    # (review regression: the old fixture used folders, which real installs
    # never have). 2.1.3 is current (claude points at it).
    mkdir -p "$HOME/.local/share/claude/versions"
    for v in 2.1.1 2.1.2 2.1.3; do
        head -c 2048 /dev/zero > "$HOME/.local/share/claude/versions/$v"; chmod +x "$HOME/.local/share/claude/versions/$v"
    done
    ln -s "$HOME/.local/share/claude/versions/2.1.3" "$CASE_DIR/bin/claude"

    # Playwright: older build is offered but not pre-selected.
    mkdir -p "$HOME/.cache/ms-playwright/chromium-1208" "$HOME/.cache/ms-playwright/chromium-1234"
    head -c 2048 /dev/zero > "$HOME/.cache/ms-playwright/chromium-1208/x"

    # Agent scratch sessions.
    sdir="$AI_DOCKER_TMP_DIR/claude-$uid/-workspace"
    mkdir -p "$sdir/old-session/scratchpad/.venv/lib" "$sdir/old-session/scratchpad/web/node_modules/pkg" \
        "$sdir/recent-session/scratchpad/.venv" "$sdir/old-with-work/scratchpad"
    head -c 2048 /dev/zero > "$sdir/old-session/scratchpad/.venv/lib/blob"
    head -c 2048 /dev/zero > "$sdir/old-session/scratchpad/web/node_modules/pkg/index.js"
    # Review regression: source files with no "document" extension are work too.
    echo 'print(1)' > "$sdir/old-session/scratchpad/analysis.py"
    : > "$sdir/recent-session/scratchpad/x"
    : > "$sdir/old-with-work/scratchpad/handoff.pdf"
    age "$sdir/old-session" 10; age "$sdir/old-with-work" 10

    # Temp virtualenv.
    mkdir -p "$AI_DOCKER_TMP_DIR/oldvenv/lib"; : > "$AI_DOCKER_TMP_DIR/oldvenv/pyvenv.cfg"; age "$AI_DOCKER_TMP_DIR/oldvenv" 10

    # Clones in ~/src: clean+pushed (offered) and dirty (never offered).
    git init -q --bare "$CASE_DIR/remote.git"
    git clone -q "$CASE_DIR/remote.git" "$HOME/src/clean-old" 2>/dev/null
    echo a > "$HOME/src/clean-old/f"; git -C "$HOME/src/clean-old" add f; git -C "$HOME/src/clean-old" commit -qm a
    git -C "$HOME/src/clean-old" push -q origin HEAD 2>/dev/null
    git clone -q "$CASE_DIR/remote.git" "$HOME/src/dirty" 2>/dev/null
    echo change > "$HOME/src/dirty/f"
    # Review regression: unpushed work on a non-checked-out branch.
    git clone -q "$CASE_DIR/remote.git" "$HOME/src/sidebranch" 2>/dev/null
    git -C "$HOME/src/sidebranch" checkout -qb experiment
    echo idea > "$HOME/src/sidebranch/g"; git -C "$HOME/src/sidebranch" add g; git -C "$HOME/src/sidebranch" commit -qm idea
    git -C "$HOME/src/sidebranch" checkout -q -
    age "$HOME/src/clean-old" 10; age "$HOME/src/dirty" 10; age "$HOME/src/sidebranch" 10

    chmod +x "$CASE_DIR/bin/"*
    export PATH="$CASE_DIR/bin:/usr/bin:/bin"
}

run_cleanup() {
    # run_cleanup <stdin answers> [args...]
    local answers=$1; shift
    set +e
    RUN_OUTPUT=$(printf '%b' "$answers" | bash "$ROOT_DIR/docker/ai_docker.sh" cleanup "$@" 2>&1)
    RUN_RC=$?
    set -u
}

# --- preview (default) deletes nothing -----------------------------------------
setup_case
run_cleanup ""
assert_eq "preview exits 0" 0 "$RUN_RC"
assert_contains "preview lists the npm cache" "$RUN_OUTPUT" "npm download cache"
assert_contains "caches are pre-selected" "$RUN_OUTPUT" "[x] npm download cache"
assert_contains "old Claude Code versions are pre-selected" "$RUN_OUTPUT" "[x] Claude Code versions"
assert_contains "Playwright builds are offered unticked" "$RUN_OUTPUT" "[ ] Playwright browser builds"
assert_contains "report-only section is shown" "$RUN_OUTPUT" "Report only - cleanup never deletes these"
assert_contains "scratch dependency folders are reported with paths" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session/scratchpad/.venv"
assert_contains "temp virtualenvs are reported with paths" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/oldvenv"
assert_contains "pushed clones are reported with paths" "$RUN_OUTPUT" "$HOME/src/clean-old"
assert_contains "sizes are estimates" "$RUN_OUTPUT" "estimated"
assert_contains "compaction caveat is stated" "$RUN_OUTPUT" "does not shrink the Windows disk file"
assert_contains "preview says how to apply" "$RUN_OUTPUT" "ai-docker cleanup --apply"
assert_exists "preview removes nothing" "$HOME/.npm/_cacache/blob"
if grep -q 'cache' "$FAKE_LOG"; then fail "preview runs no cache command"; else pass "preview runs no cache command"; fi

# --- apply with all defaults: only pre-selected groups ------------------------
setup_case
run_cleanup "\n\n\n\n" --apply
assert_eq "apply with defaults exits 0" 0 "$RUN_RC"
assert_contains "npm cache cleared through npm" "$(cat "$FAKE_LOG")" "npm cache clean --force"
assert_exists "npx cache used by MCP servers is kept" "$HOME/.npm/_npx/keep"
assert_contains "pip cache purged through pip" "$(cat "$FAKE_LOG")" "pip3 cache purge"
assert_gone "oldest Claude Code version removed" "$HOME/.local/share/claude/versions/2.1.1"
assert_exists "previous Claude Code version kept" "$HOME/.local/share/claude/versions/2.1.2"
assert_exists "current Claude Code version kept" "$HOME/.local/share/claude/versions/2.1.3"
assert_exists "unticked Playwright build kept" "$HOME/.cache/ms-playwright/chromium-1208"
assert_contains "freed space is reported as an estimate" "$RUN_OUTPUT" "Freed about"

# --- answering yes to everything: report-only groups still survive --------
setup_case
run_cleanup "y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n" --apply
assert_gone "opted-in Playwright build removed" "$HOME/.cache/ms-playwright/chromium-1208"
assert_exists "newest Playwright build kept" "$HOME/.cache/ms-playwright/chromium-1234"
assert_exists "scratch virtualenv survives --apply (report only)" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session/scratchpad/.venv/lib/blob"
assert_exists "scratch node_modules survives --apply (report only)" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session/scratchpad/web/node_modules/pkg/index.js"
assert_exists "temp virtualenv survives --apply (report only)" "$AI_DOCKER_TMP_DIR/oldvenv/pyvenv.cfg"
assert_exists "pushed clone survives --apply (report only)" "$HOME/src/clean-old/f"
assert_exists "source file in old scratch survives" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session/scratchpad/analysis.py"
assert_exists "dirty clone survives" "$HOME/src/dirty/f"
if printf '%s\n' "$RUN_OUTPUT" | grep -Eq 'Delete (Clean, pushed|Temporary virtualenvs|Rebuildable folders)'; then
    fail "report-only groups are never offered for deletion"
else
    pass "report-only groups are never offered for deletion"
fi

# --- active use is checked right before deleting ---------------------------------
# Review regression: an old Claude Code version that is still running (a long
# session started before an update) must not be deleted.
setup_case
cp /bin/sleep "$HOME/.local/share/claude/versions/2.1.1"
"$HOME/.local/share/claude/versions/2.1.1" 30 &
running=$!
sleep 0.3
run_cleanup "\ny\ny\n\n" --apply
kill "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true
assert_exists "running old Claude Code version is not deleted" "$HOME/.local/share/claude/versions/2.1.1"
assert_contains "in-use skip is reported" "$RUN_OUTPUT" "in use"

# Review regression: closed input must never count as a yes.
setup_case
set +e; RUN_OUTPUT=$(bash "$ROOT_DIR/docker/ai_docker.sh" cleanup --apply < /dev/null 2>&1); set -u
assert_exists "no input deletes nothing (even suggested groups)" "$HOME/.local/share/claude/versions/2.1.1"
if grep -q 'cache' "$FAKE_LOG"; then fail "no input runs no cache command"; else pass "no input runs no cache command"; fi
assert_contains "closed input is reported" "$RUN_OUTPUT" "Input ended"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
