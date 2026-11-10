#!/usr/bin/env bash
# Operate exclusively on a fresh synthetic repository, with isolated Git config.
set -euo pipefail

fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-portability.XXXXXXXX")
trap 'printf "Synthetic Git fixture retained: %s\n" "$fixture"' EXIT

# Ignore inherited routing, injected configuration and credentials. This script
# never changes global trust, ownership or a user's real worktree registrations.
while IFS= read -r name; do
    case "$name" in GIT_*) unset "$name" ;; esac
done < <(compgen -e)
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_TERMINAL_PROMPT=0 GIT_ATTR_NOSYSTEM=1
export GIT_AUTHOR_NAME='Synthetic Test' GIT_COMMITTER_NAME='Synthetic Test'
export GIT_AUTHOR_EMAIL='test@example.invalid' GIT_COMMITTER_EMAIL='test@example.invalid'

mkdir -p "$fixture/before/repos" "$fixture/before/worktrees" "$fixture/templates"
main="$fixture/before/repos/main"
linked="$fixture/before/worktrees/linked"
git init --quiet --initial-branch=main --template="$fixture/templates" "$main"
printf 'synthetic worktree test\n' > "$main/example.txt"
git -C "$main" add example.txt
git -C "$main" -c commit.gpgSign=false commit --quiet -m 'Synthetic fixture'
head=$(git -C "$main" rev-parse HEAD)
git -C "$main" worktree add --quiet --relative-paths -b linked "$linked"

check_fixture() {
    local root=$1 checkout registration count
    for checkout in "$root/repos/main" "$root/worktrees/linked"; do
        test "$(git -C "$checkout" rev-parse HEAD)" = "$head"
        test -z "$(git -C "$checkout" status --porcelain=v1 --untracked-files=all)"
        git -C "$checkout" fsck --no-reflogs >/dev/null
    done
    registration=$(git -C "$root/repos/main" worktree list --porcelain)
    count=$(printf '%s\n' "$registration" | grep -c '^worktree ')
    test "$count" -eq 2
    if printf '%s\n' "$registration" | grep -q '^prunable'; then
        echo 'Relative registration was incorrectly considered prunable' >&2
        exit 1
    fi
    printf '%s\n' "$registration" | grep -Fxq "worktree $root/repos/main"
    printf '%s\n' "$registration" | grep -Fxq "worktree $root/worktrees/linked"
}

check_fixture "$fixture/before"
mv "$fixture/before" "$fixture/after"
check_fixture "$fixture/after"
echo 'PASS: relative worktrees remain readable, clean and registered after relocation'
