#!/usr/bin/env bash
# Behavioral tests for `ai-docker rescue-scan`: finds work a rebuild would
# delete (outside the named volumes and the workspace bind mount).
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
trap 'chmod -R u+w "$TMP_DIR" 2>/dev/null; rm -rf "$TMP_DIR"' EXIT

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
assert_not_contains() {
    local label=$1 haystack=$2 needle=$3
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then fail "$label (unexpected: $needle)"; else pass "$label"; fi
}

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null

setup_case() {
    CASE_DIR=$(mktemp -d "$TMP_DIR/case.XXXXXX")
    export HOME="$CASE_DIR/home"
    export AI_DOCKER_TMP_DIR="$CASE_DIR/tmp"
    export AI_DOCKER_LIB_DIR="$ROOT_DIR/docker/lib"
    export AI_DOCKER_MOUNTS_FILE="$CASE_DIR/mounts"
    export AI_DOCKER_RESCUE_ROOT="$CASE_DIR/workspace/_rescued"
    mkdir -p "$HOME" "$AI_DOCKER_TMP_DIR" "$CASE_DIR/workspace"
    # A named volume mounted inside home survives a rebuild.
    mkdir -p "$HOME/.claude"
    printf 'none %s ext4 rw 0 0\n' "$HOME/.claude" > "$AI_DOCKER_MOUNTS_FILE"
    git init -q --bare "$CASE_DIR/remote.git"
    seed="$CASE_DIR/seed"
    git clone -q "$CASE_DIR/remote.git" "$seed" 2>/dev/null
    echo base > "$seed/README"
    git -C "$seed" add README && git -C "$seed" commit -qm base && git -C "$seed" push -q origin HEAD 2>/dev/null
}

clone_to() { git clone -q "$CASE_DIR/remote.git" "$1" 2>/dev/null; }

run_scan() {
    set +e
    RUN_OUTPUT=$(bash "$ROOT_DIR/docker/ai_docker.sh" rescue-scan "$@" 2>&1)
    RUN_RC=$?
    set -u
}

# Nothing at risk -> exit 0.
setup_case
clone_to "$HOME/src/clean"
run_scan
assert_eq "nothing at risk exits 0" 0 "$RUN_RC"
assert_contains "nothing at risk is said plainly" "$RUN_OUTPUT" "Nothing found outside the folders a rebuild keeps"

# Work at risk -> listed, exit 3.
setup_case
clone_to "$HOME/src/clean"
clone_to "$HOME/src/dirty"; echo change >> "$HOME/src/dirty/README"
clone_to "$HOME/src/unpushed"; echo more >> "$HOME/src/unpushed/README"
git -C "$HOME/src/unpushed" commit -qam local
git init -q "$AI_DOCKER_TMP_DIR/noremote"; echo x > "$AI_DOCKER_TMP_DIR/noremote/f"
git -C "$AI_DOCKER_TMP_DIR/noremote" add f && git -C "$AI_DOCKER_TMP_DIR/noremote" commit -qm one
clone_to "$HOME/src/stashed"; echo s >> "$HOME/src/stashed/README"; git -C "$HOME/src/stashed" stash -q
mkdir -p "$AI_DOCKER_TMP_DIR/handoff"; head -c 3000 /dev/urandom > "$AI_DOCKER_TMP_DIR/handoff/model.step"
head -c 1000 /dev/urandom > "$AI_DOCKER_TMP_DIR/report.pdf"
mkdir -p "$HOME/app/.venv/lib" "$HOME/app/node_modules/pkg"
: > "$HOME/app/.venv/lib/bundled.pdf"; : > "$HOME/app/node_modules/pkg/doc.pdf"
: > "$HOME/.claude/notes.pdf"
run_scan
assert_eq "work at risk exits 3" 3 "$RUN_RC"
assert_contains "dirty repo is listed" "$RUN_OUTPUT" "src/dirty"
assert_contains "dirty repo reason" "$RUN_OUTPUT" "uncommitted"
assert_contains "unpushed repo is listed" "$RUN_OUTPUT" "src/unpushed"
assert_contains "unpushed reason" "$RUN_OUTPUT" "unpushed"
assert_contains "repo without remote is listed" "$RUN_OUTPUT" "no remote"
assert_contains "stash is listed" "$RUN_OUTPUT" "stash"
assert_contains "folder holding a CAD file is listed" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/handoff"
assert_contains "loose PDF is counted" "$RUN_OUTPUT" "1 loose file"
assert_not_contains "clean pushed repo is not listed" "$RUN_OUTPUT" "src/clean"
assert_not_contains "documents in virtualenvs are ignored" "$RUN_OUTPUT" "bundled.pdf"
assert_not_contains "documents in node_modules are ignored" "$RUN_OUTPUT" "doc.pdf"
assert_not_contains "named volumes are not scanned" "$RUN_OUTPUT" "notes.pdf"
assert_contains "wording does not claim files exist nowhere else" "$RUN_OUTPUT" "outside the folders a rebuild keeps"
assert_not_contains "documents inside repos are covered by the repo entry" "$RUN_OUTPUT" "src/dirty/README"

# --copy rescues everything into a versioned workspace folder and verifies it.
run_scan --copy
assert_eq "verified copy exits 0" 0 "$RUN_RC"
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
assert_contains "rescue folder follows the naming policy" "$(basename "${dest:-none}")" "_container_rescue_v1_00"
assert_eq "rescued CAD file is byte-identical" \
    "$(sha256sum < "$AI_DOCKER_TMP_DIR/handoff/model.step")" "$(sha256sum < "$dest$AI_DOCKER_TMP_DIR/handoff/model.step" 2>/dev/null)"
assert_eq "rescued dirty repo keeps its uncommitted change" \
    "$(cat "$HOME/src/dirty/README")" "$(cat "$dest$HOME/src/dirty/README" 2>/dev/null)"
[ -d "$dest$HOME/src/unpushed/.git" ] && pass "rescued repo keeps its history" || fail "rescued repo keeps its history"
assert_contains "copy reports where it went" "$RUN_OUTPUT" "$dest"
run_scan --copy
assert_eq "second rescue succeeds" 0 "$RUN_RC"
[ -d "$AI_DOCKER_RESCUE_ROOT/$(date +%Y%m%d)_container_rescue_v1_01" ] \
    && pass "second rescue gets the next version, never overwriting" || fail "second rescue gets the next version, never overwriting"

# Findings are grouped by top-level folder, and app state is not "work".
setup_case
mkdir -p "$AI_DOCKER_TMP_DIR/batch/sub" "$HOME/.pki/nssdb" "$AI_DOCKER_TMP_DIR/claude-$(id -u)/bundled-skills/x"
: > "$AI_DOCKER_TMP_DIR/batch/a.pdf"; : > "$AI_DOCKER_TMP_DIR/batch/sub/b.docx"
: > "$HOME/.pki/nssdb/pkcs11.txt"; : > "$AI_DOCKER_TMP_DIR/claude-$(id -u)/bundled-skills/x/SKILL.md"
run_scan
assert_contains "documents are grouped by top-level folder" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/batch  (2 files"
assert_not_contains "grouped files are not listed one by one" "$RUN_OUTPUT" "a.pdf"
assert_not_contains "hidden app-state folders are skipped" "$RUN_OUTPUT" "pkcs11.txt"
assert_not_contains "Claude Code bundled skills are skipped" "$RUN_OUTPUT" "SKILL.md"

# Loose files at the top of a scan root fold into one line; pytest temp is skipped.
setup_case
: > "$AI_DOCKER_TMP_DIR/note1.md"; : > "$AI_DOCKER_TMP_DIR/note2.md"; : > "$AI_DOCKER_TMP_DIR/map.kmz"
mkdir -p "$AI_DOCKER_TMP_DIR/single" "$AI_DOCKER_TMP_DIR/pytest-of-$(id -un)/test0"
: > "$AI_DOCKER_TMP_DIR/single/only.pdf"; : > "$AI_DOCKER_TMP_DIR/pytest-of-$(id -un)/test0/out.pdf"
run_scan
assert_contains "loose files are summarised in one line" "$RUN_OUTPUT" "3 loose files"
assert_not_contains "loose files are not listed one by one" "$RUN_OUTPUT" "note1.md"
assert_contains "a single document is singular" "$RUN_OUTPUT" "(1 file,"
assert_not_contains "pytest temp folders are skipped" "$RUN_OUTPUT" "pytest-of"
run_scan --copy
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
[ -e "$dest$AI_DOCKER_TMP_DIR/note2.md" ] && pass "summarised loose files are still copied" || fail "summarised loose files are still copied"

# Review regression: work that a HEAD-only, ignore-blind check missed.
setup_case
clone_to "$HOME/src/ignoredpdf"
printf 'out/\nnode_modules/\n' > "$HOME/src/ignoredpdf/.gitignore"
git -C "$HOME/src/ignoredpdf" add .gitignore && git -C "$HOME/src/ignoredpdf" commit -qm ignore && git -C "$HOME/src/ignoredpdf" push -q origin HEAD 2>/dev/null
mkdir -p "$HOME/src/ignoredpdf/out"; head -c 600 /dev/urandom > "$HOME/src/ignoredpdf/out/deliverable.pdf"
mkdir -p "$HOME/src/ignoredpdf/node_modules/x"; : > "$HOME/src/ignoredpdf/node_modules/x/readme.pdf"
run_scan
assert_eq "ignored deliverable in a pushed repo is found" 3 "$RUN_RC"
assert_contains "ignored deliverable reason" "$RUN_OUTPUT" "ignored file"

setup_case
clone_to "$HOME/src/sidebranch"
git -C "$HOME/src/sidebranch" checkout -qb experiment
echo idea >> "$HOME/src/sidebranch/README"; git -C "$HOME/src/sidebranch" commit -qam idea
git -C "$HOME/src/sidebranch" checkout -q -
run_scan
assert_eq "unpushed commit on another branch is found" 3 "$RUN_RC"
assert_contains "other-branch commits are counted" "$RUN_OUTPUT" "src/sidebranch"

# Review regression: a rescued worktree must work without the original repo.
setup_case
git clone -q "$CASE_DIR/remote.git" "$CASE_DIR/elsewhere/main" 2>/dev/null
git -C "$CASE_DIR/elsewhere/main" worktree add -q -b wtbranch "$HOME/src/wt" 2>/dev/null
echo wip >> "$HOME/src/wt/README"; git -C "$HOME/src/wt" commit -qam "worktree-only commit"
echo uncommitted >> "$HOME/src/wt/README"
src_head=$(git -C "$HOME/src/wt" rev-parse HEAD)
run_scan --copy
assert_eq "worktree rescue succeeds" 0 "$RUN_RC"
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
rm -rf "$CASE_DIR/elsewhere"
assert_eq "rescued worktree keeps its HEAD without the original repo" "$src_head" "$(git -C "$dest$HOME/src/wt" rev-parse HEAD 2>/dev/null)"
assert_contains "rescued worktree keeps its unpushed commit" "$(git -C "$dest$HOME/src/wt" log --format=%s 2>/dev/null)" "worktree-only commit"
assert_eq "rescued worktree is on its branch" "wtbranch" "$(git -C "$dest$HOME/src/wt" symbolic-ref --short HEAD 2>/dev/null)"
assert_contains "rescued worktree keeps its uncommitted change" "$(git -C "$dest$HOME/src/wt" status --porcelain 2>/dev/null)" "README"
[ -d "$dest$HOME/src/wt/.git" ] && pass "rescued worktree is a standalone repository" || fail "rescued worktree is a standalone repository"

# Any file a person or agent made is work - not just known document types.
setup_case
echo 'print(1)' > "$AI_DOCKER_TMP_DIR/analysis.py"
mkdir -p "$AI_DOCKER_TMP_DIR/notes" "$AI_DOCKER_TMP_DIR/shots"
echo '{}' > "$AI_DOCKER_TMP_DIR/notes/model.ipynb"; head -c 100 /dev/urandom > "$AI_DOCKER_TMP_DIR/shots/site.png"
# Provably rebuildable: a virtualenv with an unusual name, and the scanner's own copy.
mkdir -p "$AI_DOCKER_TMP_DIR/venv60/lib/site"; : > "$AI_DOCKER_TMP_DIR/venv60/pyvenv.cfg"; echo x > "$AI_DOCKER_TMP_DIR/venv60/lib/site/mod.py"
mkdir -p "$AI_DOCKER_TMP_DIR/ai-docker-rescue"; echo x > "$AI_DOCKER_TMP_DIR/ai-docker-rescue/ai_docker.sh"
run_scan
assert_eq "loose scripts, notebooks and images are work" 3 "$RUN_RC"
assert_contains "loose script is counted" "$RUN_OUTPUT" "1 loose file"
assert_contains "notebook folder is listed" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/notes"
assert_contains "screenshot folder is listed" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/shots"
assert_not_contains "virtualenv found by pyvenv.cfg is skipped" "$RUN_OUTPUT" "venv60"
assert_not_contains "the scanner's own copy is skipped" "$RUN_OUTPUT" "ai-docker-rescue"
run_scan --copy
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
[ -n "$dest" ] && [ -e "$dest$AI_DOCKER_TMP_DIR/analysis.py" ] && pass "loose script is rescued" || fail "loose script is rescued"
[ -n "$dest" ] && [ -e "$dest$AI_DOCKER_TMP_DIR/shots/site.png" ] && pass "screenshot is rescued" || fail "screenshot is rescued"

# Top-level dotfiles are app state (shell rc, markers, tool config), not work.
setup_case
: > "$HOME/.bashrc"; : > "$HOME/.cli_tools_installed"; : > "$HOME/.gitconfig"; : > "$AI_DOCKER_TMP_DIR/.lock-x"
echo notes > "$HOME/RECOVERY.md"
mkdir -p "$AI_DOCKER_TMP_DIR/proj"; echo SECRET=1 > "$AI_DOCKER_TMP_DIR/proj/.env"
run_scan
assert_contains "a real file in home is counted" "$RUN_OUTPUT" "$HOME/  (1 loose file"
assert_contains "a hidden file inside a project folder still counts" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/proj  (1 file"
assert_not_contains "top-level dotfiles in /tmp are not work" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/  ("

# Second review: an unreadable folder must make the scan incomplete, not clean.
if [ "$(id -u)" -ne 0 ]; then
    setup_case
    mkdir -p "$AI_DOCKER_TMP_DIR/locked"; head -c 300 /dev/urandom > "$AI_DOCKER_TMP_DIR/locked/only-copy.pdf"
    chmod 000 "$AI_DOCKER_TMP_DIR/locked"
    run_scan
    chmod 755 "$AI_DOCKER_TMP_DIR/locked"
    assert_eq "unreadable folder makes the scan incomplete (exit 4)" 4 "$RUN_RC"
    assert_contains "unreadable folder is named" "$RUN_OUTPUT" "could not be read: $AI_DOCKER_TMP_DIR/locked"
    assert_not_contains "incomplete scan never says nothing was found" "$RUN_OUTPUT" "Nothing found"
    chmod 000 "$AI_DOCKER_TMP_DIR/locked"
    run_scan --copy
    chmod 755 "$AI_DOCKER_TMP_DIR/locked"
    assert_eq "an incomplete scan cannot certify a rescue (exit 1)" 1 "$RUN_RC"
fi

# --- second review: repository work that still slipped through ---------------
# 2b: an ignored file of any type is not in the remote.
setup_case
clone_to "$HOME/src/ignjson"
printf 'data/\n' > "$HOME/src/ignjson/.gitignore"; git -C "$HOME/src/ignjson" add .gitignore
git -C "$HOME/src/ignjson" commit -qm ign && git -C "$HOME/src/ignjson" push -q origin HEAD 2>/dev/null
mkdir -p "$HOME/src/ignjson/data"; echo '{"m":1}' > "$HOME/src/ignjson/data/measurements.json"
run_scan
assert_contains "ignored data file in a pushed repo is work" "$RUN_OUTPUT" "src/ignjson"
assert_contains "ignored file reason" "$RUN_OUTPUT" "ignored file"

# 2c: a commit kept only by a local tag.
setup_case
clone_to "$HOME/src/tagonly"
git -C "$HOME/src/tagonly" checkout -q --detach
echo t >> "$HOME/src/tagonly/README"; git -C "$HOME/src/tagonly" commit -qam tagged
git -C "$HOME/src/tagonly" tag keep-me
git -C "$HOME/src/tagonly" checkout -q -
run_scan
assert_contains "tag-only commit is unpushed work" "$RUN_OUTPUT" "src/tagonly"

# 2d: an edit hidden from git status.
setup_case
clone_to "$HOME/src/hidden"
echo secret-edit >> "$HOME/src/hidden/README"
git -C "$HOME/src/hidden" update-index --assume-unchanged README
run_scan
assert_contains "assume-unchanged edit is work" "$RUN_OUTPUT" "src/hidden"
assert_contains "hidden-edit reason" "$RUN_OUTPUT" "hidden from git status"

# 3 (rescue side): a real file inside a virtualenv folder is still rescued.
setup_case
mkdir -p "$AI_DOCKER_TMP_DIR/proj/.venv/lib/python3/site-packages/pkg" "$AI_DOCKER_TMP_DIR/proj/.venv/bin"
: > "$AI_DOCKER_TMP_DIR/proj/.venv/pyvenv.cfg"; echo x > "$AI_DOCKER_TMP_DIR/proj/.venv/lib/python3/site-packages/pkg/m.py"
echo y > "$AI_DOCKER_TMP_DIR/proj/.venv/bin/activate"
head -c 400 /dev/urandom > "$AI_DOCKER_TMP_DIR/proj/.venv/only-copy.pdf"
run_scan
assert_contains "file placed inside a virtualenv is work" "$RUN_OUTPUT" "$AI_DOCKER_TMP_DIR/proj  (1 file"
run_scan --copy
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
[ -n "$dest" ] && [ -e "$dest$AI_DOCKER_TMP_DIR/proj/.venv/only-copy.pdf" ] && pass "file inside a virtualenv is rescued" || fail "file inside a virtualenv is rescued"

# 4: a --shared clone borrows objects from another repository.
setup_case
git clone -q "$CASE_DIR/remote.git" "$CASE_DIR/elsewhere/orig" 2>/dev/null
echo more >> "$CASE_DIR/elsewhere/orig/README"; git -C "$CASE_DIR/elsewhere/orig" commit -qam second
git clone -q --shared "$CASE_DIR/elsewhere/orig" "$HOME/src/shared" 2>/dev/null
echo mine >> "$HOME/src/shared/README"; git -C "$HOME/src/shared" commit -qam "local commit"
run_scan --copy
assert_eq "shared clone rescue succeeds" 0 "$RUN_RC"
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
rm -rf "$CASE_DIR/elsewhere"
assert_contains "rescued shared clone keeps full history without the original" "$(git -C "$dest$HOME/src/shared" log --format=%s 2>/dev/null)" "second"
[ ! -e "$dest$HOME/src/shared/.git/objects/info/alternates" ] && pass "rescued clone borrows no objects" || fail "rescued clone borrows no objects"
git -C "$dest$HOME/src/shared" fsck --connectivity-only >/dev/null 2>&1 && pass "rescued clone passes fsck on its own" || fail "rescued clone passes fsck on its own"

# 5: a symlink to a unique file that the rebuild will delete.
setup_case
git init -q "$HOME/src/linky"; echo a > "$HOME/src/linky/f"; git -C "$HOME/src/linky" add f; git -C "$HOME/src/linky" commit -qm a
mkdir -p "$AI_DOCKER_TMP_DIR/store"; echo unique-content > "$AI_DOCKER_TMP_DIR/store/unique.txt"
ln -s "$AI_DOCKER_TMP_DIR/store/unique.txt" "$HOME/src/linky/deliverable.txt"
ln -s f "$HOME/src/linky/inner-link"
run_scan --copy
assert_eq "rescue with a symlink succeeds" 0 "$RUN_RC"
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
rm -rf "$AI_DOCKER_TMP_DIR/store"
assert_eq "linked deliverable survives losing its target" "unique-content" "$(cat "$dest$HOME/src/linky/deliverable.txt" 2>/dev/null)"
[ -L "$dest$HOME/src/linky/inner-link" ] && pass "links inside the rescued folder stay links" || fail "links inside the rescued folder stay links"

# 7: staged changes in a worktree survive the rescue.
setup_case
git clone -q "$CASE_DIR/remote.git" "$CASE_DIR/elsewhere/main" 2>/dev/null
git -C "$CASE_DIR/elsewhere/main" worktree add -q -b staged "$HOME/src/wtstaged" 2>/dev/null
echo staged-edit >> "$HOME/src/wtstaged/README"; git -C "$HOME/src/wtstaged" add README
run_scan --copy
assert_eq "worktree with a staged change rescues" 0 "$RUN_RC"
dest=$(find "$AI_DOCKER_RESCUE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)
assert_contains "staged change is still staged in the copy" "$(git -C "$dest$HOME/src/wtstaged" diff --cached --name-only 2>/dev/null)" "README"

# Documents inside a repo are judged by the repo, not listed on their own.
setup_case
clone_to "$HOME/src/withdocs"
mkdir -p "$HOME/src/withdocs/docs"; head -c 800 /dev/urandom > "$HOME/src/withdocs/docs/spec.pdf"
git -C "$HOME/src/withdocs" add docs && git -C "$HOME/src/withdocs" commit -qm docs && git -C "$HOME/src/withdocs" push -q origin HEAD 2>/dev/null
run_scan
assert_eq "tracked document in a pushed repo is safe" 0 "$RUN_RC"
assert_not_contains "tracked document is not listed separately" "$RUN_OUTPUT" "spec.pdf"

# A rescued repo containing a skipped cache folder still verifies.
setup_case
clone_to "$HOME/src/cachey"; echo change >> "$HOME/src/cachey/README"
mkdir -p "$HOME/src/cachey/.cache/tool"; echo junk > "$HOME/src/cachey/.cache/tool/blob"
run_scan --copy
assert_eq "repo with a cache folder copies and verifies" 0 "$RUN_RC"

# A copy that cannot be written fails loudly (the rebuild must not proceed).
setup_case
head -c 500 /dev/urandom > "$AI_DOCKER_TMP_DIR/report.pdf"
mkdir -p "$AI_DOCKER_RESCUE_ROOT"; chmod 555 "$AI_DOCKER_RESCUE_ROOT"
run_scan --copy
chmod 755 "$AI_DOCKER_RESCUE_ROOT"
if [ "$(id -u)" -ne 0 ]; then
    assert_eq "unwritable destination fails the copy" 1 "$RUN_RC"
    assert_contains "failed copy says not to rebuild" "$RUN_OUTPUT" "Do not rebuild"
fi

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
