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

    # Claude Code versions: 2.1.3 is current (claude points at it).
    for v in 2.1.1 2.1.2 2.1.3; do
        mkdir -p "$HOME/.local/share/claude/versions/$v"; head -c 2048 /dev/zero > "$HOME/.local/share/claude/versions/$v/bin"
    done
    ln -s "$HOME/.local/share/claude/versions/2.1.3/bin" "$CASE_DIR/bin/claude"

    # Playwright: older build is offered but not pre-selected.
    mkdir -p "$HOME/.cache/ms-playwright/chromium-1208" "$HOME/.cache/ms-playwright/chromium-1234"
    head -c 2048 /dev/zero > "$HOME/.cache/ms-playwright/chromium-1208/x"

    # Agent scratch sessions.
    sdir="$AI_DOCKER_TMP_DIR/claude-$uid/-workspace"
    mkdir -p "$sdir/old-session/scratchpad" "$sdir/recent-session/scratchpad" "$sdir/old-with-work/scratchpad"
    head -c 2048 /dev/zero > "$sdir/old-session/scratchpad/venv.tar"
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
    age "$HOME/src/clean-old" 10; age "$HOME/src/dirty" 10

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
assert_contains "scratch dirs are offered unticked" "$RUN_OUTPUT" "[ ] Agent scratch folders"
assert_contains "temp virtualenvs are offered unticked" "$RUN_OUTPUT" "[ ] Temporary virtualenvs"
assert_contains "pushed clones are offered unticked" "$RUN_OUTPUT" "[ ] Clean, pushed clones in ~/src"
assert_contains "sizes are estimates" "$RUN_OUTPUT" "estimated"
assert_contains "compaction caveat is stated" "$RUN_OUTPUT" "does not shrink the Windows disk file"
assert_contains "kept items holding work are explained" "$RUN_OUTPUT" "Kept (contains work)"
assert_contains "preview says how to apply" "$RUN_OUTPUT" "ai-docker cleanup --apply"
assert_exists "preview removes nothing" "$HOME/.npm/_cacache/blob"
if grep -q 'cache' "$FAKE_LOG"; then fail "preview runs no cache command"; else pass "preview runs no cache command"; fi

# --- apply with all defaults: only pre-selected groups ------------------------
setup_case
run_cleanup "\n\n\n\n\n\n\n\n" --apply
assert_eq "apply with defaults exits 0" 0 "$RUN_RC"
assert_contains "npm cache cleared through npm" "$(cat "$FAKE_LOG")" "npm cache clean --force"
assert_exists "npx cache used by MCP servers is kept" "$HOME/.npm/_npx/keep"
assert_contains "pip cache purged through pip" "$(cat "$FAKE_LOG")" "pip3 cache purge"
assert_gone "oldest Claude Code version removed" "$HOME/.local/share/claude/versions/2.1.1"
assert_exists "previous Claude Code version kept" "$HOME/.local/share/claude/versions/2.1.2"
assert_exists "current Claude Code version kept" "$HOME/.local/share/claude/versions/2.1.3"
assert_exists "unticked Playwright build kept" "$HOME/.cache/ms-playwright/chromium-1208"
assert_exists "unticked scratch kept" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session"
assert_exists "unticked venv kept" "$AI_DOCKER_TMP_DIR/oldvenv"
assert_exists "unticked clone kept" "$HOME/src/clean-old"
assert_contains "freed space is reported as an estimate" "$RUN_OUTPUT" "Freed about"

# --- opting in to every group ----------------------------------------------------
setup_case
run_cleanup "y\ny\ny\ny\ny\ny\ny\ny\n" --apply
assert_gone "opted-in Playwright build removed" "$HOME/.cache/ms-playwright/chromium-1208"
assert_exists "newest Playwright build kept" "$HOME/.cache/ms-playwright/chromium-1234"
assert_gone "opted-in old scratch removed" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session"
assert_exists "recently used scratch never offered" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/recent-session"
assert_exists "scratch holding a document never offered" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-with-work/scratchpad/handoff.pdf"
assert_gone "opted-in temp venv removed" "$AI_DOCKER_TMP_DIR/oldvenv"
assert_gone "opted-in pushed clone removed" "$HOME/src/clean-old"
assert_exists "dirty clone never offered" "$HOME/src/dirty/f"

# --- re-check right before deleting ------------------------------------------------
# Something written into an offered item after the preview makes it "in use".
setup_case
fifo="$CASE_DIR/answers"; mkfifo "$fifo"
out="$CASE_DIR/out"
bash "$ROOT_DIR/docker/ai_docker.sh" cleanup --apply < "$fifo" > "$out" 2>&1 &
cpid=$!
exec 7<> "$fifo"
for _ in $(seq 1 50); do grep -q 'Delete Agent scratch folders' "$out" 2>/dev/null && break; sleep 0.2; done
# Answer the groups before scratch with defaults, then touch the scratch item, then opt in.
printf '\n\n\n\n' >&7
sleep 0.5
: > "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session/scratchpad/new-output.md"
printf 'y\n\n\n\n' >&7
exec 7>&-
wait "$cpid"
assert_exists "item changed after the preview is skipped" "$AI_DOCKER_TMP_DIR/claude-$uid/-workspace/old-session/scratchpad/new-output.md"
assert_contains "skip is reported" "$(cat "$out")" "changed since the preview"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
