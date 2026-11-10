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

## Image behavior

The Dockerfile builds Git 2.56.0 in a separate Ubuntu 24.04 stage, verifies the
upstream archive SHA-256, and copies the installation into `/usr/local` in the
runtime image. Build and runtime stages share the same Ubuntu image digest.
The final stage explicitly installs the required OpenSSL curl, Expat, PCRE2,
zlib and Perl runtime dependencies. HTTPS helpers are included. Rust, Tcl/Tk
GUI tools and translated messages are disabled; normal Git CLI and Perl
commands are included. Ubuntu's packaged Git remains at `/usr/bin/git`.

The normal PATH selects `/usr/local/bin/git`, including for direct Docker exec
calls. There is no startup download and no dependency on a workspace-specific
binary, symlink, shell alias or personal Git configuration. Updating this pin
requires changing both the version and verified checksum and rerunning CI.

`tests/test_git_worktree_portability.sh` creates an isolated synthetic repository
with relative links, checks both worktrees, moves their common containing
folder, and checks them again. It clears inherited Git routing/configuration
and retains its disposable fixture path as test evidence. CI runs this test
with the image Git as the normal user before and after recreating its disposable
container. CI also checks HTTPS against the public upstream repository.

Git 2.48 or newer is required on every client that opens relative worktrees;
older clients can reject the repository's format extension. This image change
does not convert existing repositories. Existing launchers embedding older
Dockerfiles require a later normal release/update to use this image recipe;
merging this source change alone does not update a running installation.
