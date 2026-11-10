# Git worktree compatibility

Version: 0.01. Date: 2026-11-10. Author: Codex. Status: Draft.

The container image must preserve support for relative worktree links when it
is rebuilt or recreated. An upgrade made only inside a running container does
not change its image.

Acceptance criteria:

- Build a pinned Git release from a checksum-verified upstream source archive.
- Include that installation and its runtime dependencies in the final image.
- Check relative worktrees before and after moving their containing directory.
- Repeat the image Git check after the disposable CI container is recreated.
- Keep existing user repositories, ownership and Git configuration untouched.

This change prepares future images. It does not update running containers,
convert existing worktrees, or make a backup/rebuild decision for the user.
