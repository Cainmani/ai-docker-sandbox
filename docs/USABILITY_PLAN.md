# AI Docker usability implementation plan

Draft revision 0.04, 9 October 2026. Baseline: main at `e903677`, released as v1.6.0 on 8 October 2026. Earlier revisions are retained in Git history.

Help Cainmani colleagues reach a working AI agent and return to useful work without maintainer assistance. The proposed 1.7 candidate focuses on health, native Claude/Codex connections and actionable diagnostics; coordinated repair follows separately. Decide whether a custom project screen is needed after testing Claude Desktop over localhost SSH. Recent folders remain a useful option, not the starting assumption.

PR #97 is documentation only; implementation belongs in separate focused PRs. No installation, SSH exposure, runtime change or staff trial has been performed. Keep this PR draft until the user approves merging the plan. Plan approval does not certify the pilot or implementation; their acceptance gates remain open. Release tagging is separate. Version 1.7 is a proposed target.

## Cainmani fit and boundaries

This is an extension of existing local AI infrastructure, with indirect benefit to engineering, analysis and document work. It does not own business Projects, Documents, Decisions or Credentials. A future local folder list stores shortcuts and preferences only; project records and source documents stay in their owning systems.

The first users to test are a colleague unfamiliar with CLI setup and an existing engineering/analysis user. A successful login is not sufficient: both must locate a saved result and continue unfinished work. Do not infer adoption from company headcount or promise measured savings before a pilot.

Company documents must remain in approved SharePoint locations or the relevant project source/data-room system. AI_Work is a working area, not a new authoritative document store. Before a pilot, identify the authoritative source, approved local-copy/sync method, source version and output-review/return route for that task. Do not add automatic SharePoint download, sync, upload or publication. Record only non-secret provenance in local task notes, and follow the existing Cainmani naming/version policy.

A separate PR in `cainmani-skills` should add ai-docker-sandbox to ECOSYSTEM.md as cross-cutting AI/dev infrastructure. Confirm the local-desktop exception and actual adoption before recording status; do not imply a deployed shared server or new entity ownership. This repository's PR does not edit that map.

## Delivery slices

| Slice | Scope | Gate |
| --- | --- | --- |
| 0 | Desktop SSH feasibility and task baseline using synthetic/public material only | Prove exposure/access boundaries, installation/config preservation, native resume and non-developer usability on a disposable environment |
| 1a, proposed 1.7 | Minimal capabilities/status contract, compact health and Claude/Codex native connections; no new install/update/repair actions | Correct legacy fallback, preserved settings, real Windows and colleague acceptance |
| 1b | Shared maintenance coordination and selected-tool repair | Independent focused PR; race, lock, interruption and recovery tests pass before enabling new mutation actions |
| 2 | Optional Desktop handoff and read-only reference access | Slice 0 result and verified data-access requirements; separate focused implementation PR |
| 3 | Custom recent-folder screen only if still needed | Demonstrated friction that vendor UI/native resume does not solve; separate focused implementation PR |
| Later | Templates, other tool adapters, published images, isolated profiles, editor/worktree UI or backend substitution | Specific observed need, owner and bounded maintenance effort |

Tracking issue: [#98](https://github.com/Cainmani/ai-docker-sandbox/issues/98). Merge #97 as a docs PR only after user approval; do not add implementation here. Use separate focused PRs for Slice 0 pilot tooling, Slice 1a and Slice 1b, and later features. Each slice has an independent review/release decision; staff do not wait for the entire roadmap.

## Verified baseline corrections

| Area | Current code at e903677 | Design consequence |
| --- | --- | --- |
| Locks | `auto_update.sh` takes update.lock; installer modes and the Vibe Kanban npm install do not. Busy exits 0; absent flock permits an unlocked run | Build shared coordination across mutations and explicit busy/unsupported outcomes; it is not an existing repair guarantee |
| Arguments | `ai-docker status --json` would return display text; unknown configure-tools options enter a menu; `--repair codex` ignores the extra selector | Never discover support by invoking a guessed action; version-gate known contracts before requesting capabilities |
| Configuration | configure_tools.sh can initialise/migrate Codex configuration and writes an OpenAI API-key export | Native login must bypass legacy configure actions that change settings |
| Launcher | Only AI_Docker_Complete.ps1 is compiled/released; the alternate launcher has separate logic and test references | One maintained product UI; deprecate the alternate UI into a thin developer wrapper after checking callers and updating tests/docs |
| Launch path | launch_claude.ps1 constructs a command through Windows Terminal and cmd; it opens at /workspace | Replace its command construction; preserve a compatibility wrapper for existing callers |
| Startup directory | Generated .bashrc ends with `cd /workspace`, including in 1.6 containers | Select the project directory after shell startup files run; docker exec -w alone is insufficient |
| Tool health | Installer health tests only executable presence for Codex and gh | Add bounded execution probes; selected reinstall must work even when a broken binary exists |
| SSH | Mobile override publishes SSH without a host-loopback prefix and also publishes Mosh; server disables forwarding | Do not enable that override unchanged for the Desktop test; use a dedicated loopback-only SSH configuration |
| CI | Docker Smoke is path-filtered; EXE smoke recognises startup log lines | Require runtime smoke evidence explicitly and exercise the new screen/background behavior in the compiled artifact |

## Slice 0 Desktop SSH and workflow test

Official [Claude Desktop documentation](https://code.claude.com/docs/en/desktop#ssh-sessions) supports SSH targets and project links. It also says Desktop installs Claude Code on the target. The link starts a new-session page; it does not itself prove resume works. First test installation and lifecycle against the container's native Claude installation and updater.

- [ ] Use a uniquely named disposable Compose project and synthetic/public, non-sensitive workspace. Record the actual authorised account/seat used, ideally a dedicated non-production subscription seat; do not assume Claude supplies test subscriptions. Keep account identifiers and credentials out of public PR evidence. Do not connect Desktop to the user's live container first.
- [ ] Add a dedicated pilot SSH mapping such as `127.0.0.1:2222:2222`, with no Mosh ports and no change to mobile-access defaults. Validate the actual listening interface from Windows and ensure another host cannot reach it. Handle a busy port explicitly.
- [ ] Use key authentication and verified host keys. Confirm SSH user, UID, HOME, working directory, PATH, native config locations, sudo access and credential visibility. SSH forwarding is disabled today: test Desktop requirements and avoid enabling it broadly to hide a failure.
- [ ] Record Claude executable paths/versions and non-secret configuration checksums before and after first connect, reconnect, container recreation and update. Establish who owns installation and updates; block adoption if Desktop silently replaces tools or loses config/session persistence.
- [ ] Confirm which account authenticates inference and which config/MCP/hooks/skills apply. Desktop login, remote SSH identity and persisted CLI login are separate concerns until demonstrated otherwise.
- [ ] Generate correctly URL-encoded links with an explicit user, loopback host, port and remote folder. Check installed Desktop version/account policy; do not include secrets or sensitive prompts in links. Test a plain non-Git folder as well as a repository.
- [ ] Test a new session, native continuation of yesterday's work, closing/reopening Desktop, missing folder, stopped container and failed authentication. Retain the terminal route for Codex and for Desktop failure.
- [ ] Test source access and writable scope using synthetic/public material. The shared home exposes stored credentials and passwordless sudo; a selected folder is not an enforced boundary. Slice 0 does not use confidential or other company project data.
- [ ] Before any later company-data trial, record the actual inference provider and account type (personal, Team/Enterprise or API), applicable data-use/training/retention terms and settings, and the responsible Cainmani approval for that data classification under the confidentiality policy. Source-access/read-only approval is a separate gate. Unclear or unapproved account terms mean no company data is sent; a container alone does not authorise vendor disclosure.
- [ ] Compare realistic software and document/analysis tasks using 1.6 and the pilot with the same synthetic/public inputs: time to first useful work, assistance required, source/output mistakes and next-day continuation. Provisional pass: a non-developer completes the agreed task and returns to it without maintainer intervention; inspect quality and source/version correctness too.
- [ ] After recording non-secret evidence, remove pilot-owned saved login state and SSH private-key copies from the disposable environment through an explicit teardown checklist, including any pilot keyring state. Verify ownership before removing pilot volumes; preserve useful outputs first. Do not delete or log out a user's existing Desktop/CLI account, revoke shared credentials or cancel the subscription as pilot cleanup.

Time-box technical feasibility to two working days. If blocked, record the specific unsupported behavior and keep terminal access; do not expand into a browser product. Gather weekly active use and support categories manually over two weeks, without collecting prompts, tokens or document contents. Native Desktop may serve Claude well and still leave a distinct Codex/folder-navigation need.

## Slice 1a Health and native connections

This slice adds observation, native authentication and safe launch only. Native login may write its own credentials; the launcher does not add installs, updates or repairs. Existing automatic maintenance remains baseline behavior, with its limitations disclosed. Slice 1b is separate by default, not a late scope reduction.

### Minimal contract and compatibility

- [ ] Define a small fixed adapter set for Claude and Codex. Other tools retain existing terminal/configuration routes; missing optional tools are not release blockers.
- [ ] Add a versioned capabilities operation and reject unknown arguments before taking any action. Use the inspected image product version/labels and a known feature-version table to decide whether it is safe to call that operation. Missing/unknown/1.6 capability support falls back to documented existing commands only, with timeouts and no guessed flags.
- [ ] Extend existing KEY=VALUE status/diagnostic records with explicit schema version, timestamps, supported actions and classified results. Keep human output and legacy consumers compatible. A future JSON option is unnecessary for the first slice.
- [ ] Read update-status as the update-health source of truth. status --brief is cheap and file-based; doctor runs network probes and must be an explicit action. Detailed checks run off the UI thread with bounded output/timeouts.
- [ ] Support Windows PowerShell 5.1 in the actual compiled EXE under Restricted policy. Load helper content from embedded Base64 through the existing ScriptBlock mechanism, not by dot-sourcing extracted files. Keep child scripts at -NoProfile and the existing explicit execution-policy invocation.
- [ ] Reduce AI_Docker_Launcher.ps1 to a documented developer wrapper for the one product implementation, after auditing references. Update version gates, tests and docs; do not silently break a script caller or delete a working alternate route without replacement.

### Beginner flow and native sign-in

Show one configured/default agent and a main Open action. Put other agents and detailed versions/resource figures behind Advanced/Details. Summarise actionability in plain language; do not claim Ready from credential-file presence alone. Keep installation, authentication evidence, connection outcome and freshness separate internally.

- [ ] Start native Claude authentication/interactive onboarding and `codex login` directly according to verified installed-version support. Do not call legacy configure-tools --codex/--openai as a sign-in shortcut or rewrite models, permissions, environment exports, MCP, hooks or instructions.
- [ ] Replace the generated shell banner's blanket API-key/configure-tools recommendation with native sign-in guidance that matches the new flow, while retaining legacy configuration access for users who choose it. Update the applicable managed-block/template migration and container baseline metadata; verify existing installs after recreation.
- [ ] Prefer native status interfaces. Support Codex credential-store modes; missing auth.json does not prove sign-out. Do not copy, inspect or reset token values. [Codex authentication](https://learn.chatgpt.com/docs/auth) documents file/keyring storage and beta device-code login requiring account/workspace enablement.
- [ ] Explain supported browser/device/manual flows and account prerequisites. Real Windows/container tests must prove callbacks or fallbacks work. Recheck when the user returns; process launch or terminal closure is not login success.
- [ ] Classify expired/rejected authentication versus network/TLS failure only when a native check gives that evidence. Otherwise report Unable to verify and a concrete next step. No implicit billable prompt for a status badge.
- [ ] Give Docker-not-running, WSL, proxy/CA and VPN failures appropriate guidance; a package reinstall is not their fix. Offer previewed, sanitised copyable support details, with no automatic message/upload.
- [ ] Give async operations IDs and tool/context ownership. Ignore stale/superseded results and avoid duplicate actions. Define cancellation for status/login separately; package-mutation cancellation belongs to Slice 1b. Closing the 1a window must not terminate existing background maintenance.

### Launch and environment

- [ ] Replace string-built launches through cmd/Windows Terminal with a PS5.1-compatible child launch contract. Allow only fixed actions and validated local identifiers; resolve any folder inside the child, never interpolate user text into executable shell code.
- [ ] Read actual container mounts/user from docker inspect; .env expresses requested state and can differ from a running container. Check expected image/container identity and missing or mismatched mounts before acting.
- [ ] Native interactive launch must match the plain terminal environment and select the working directory after startup files run. Use a fixed command such as `bash -li -c 'cd -- "$1" && exec claude' bash <validated-folder>`, with the folder passed as a positional argument through the safe child contract; use an equivalent fixed Codex command. The example describes argument boundaries, not a Windows command string to concatenate. Test .bashrc/.profile behavior and prove the tool starts in the selected folder on both new and real 1.6 containers despite their startup `cd /workspace`. Use explicit noninteractive environments for status probes rather than assuming bash -lc loads interactive exports/wrappers.
- [ ] Slice 1a acceptance: a missing, renamed or inaccessible selected folder shows a plain actionable message, does not start the agent in a different folder, and leaves an interactive shell open so the user can read the error. Test on new and 1.6 containers. The compact launch example above describes the success path; implementation must handle this failure explicitly.
- [ ] Test spaces, Unicode, apostrophes, dollar signs, semicolons, percent signs, carets, exclamation marks, double quotes, ampersands and pipes. No input can become a command, redirect, environment expansion or extra terminal tab.
- [ ] Keep native prompts/trust decisions visible. Do not bypass permissions or automatically accept repository trust. Resume uses vendor interfaces, not a new transcript store.

## Slice 1b Selected repair and maintenance coordination

- [ ] Introduce one maintenance contract across installer --repair/--force/--update, updater startup/cron/manual paths and Vibe Kanban's npm installation. Make lock absence a reported unsupported/failure state, not permission to mutate unlocked. Plan a documented lock order if multiple locks are needed.
- [ ] Return explicit success, failure, busy/skipped and unsupported outcomes. Existing exit-0 consumers must not turn busy into a successful update; preserve documented legacy command behavior or provide versioned new entry points.
- [ ] Add a validated selected-tool mode with bounded execution health probes and an explicit reinstall action for an executable that exists but fails. Preserve other tools, credentials/config and aggregate install-marker truth. Existing cleanup/ownership behavior must be audited before claiming a narrowly scoped repair.
- [ ] Coordinate launch admission with maintenance admission and active-session accounting; test a new launch arriving after the session check. Detect manually launched CLI/Desktop sessions where possible and report uncertainty. Shared maintenance locks cannot stop vendor self-updaters: account for them explicitly, especially in the Desktop pilot.
- [ ] Define interruption/recovery behavior, install-marker writes, package-stage handling and safe UI-close semantics. Never remove a working binary before validating its replacement. Show progress and actionable failure without logging secrets.
- [ ] Keep rescue checks on recreate/uninstall, volumes intact, and repositories/virtualenvs/scratch dependencies report-only. No generic reset or clean-everything action.

A repair control is enabled only after Slice 1b's coordination/recovery tests pass. Slice 1a can ship independently with accurate troubleshooting and an explicitly labelled existing recovery route; do not label a full repair as selected-tool repair or imply 1a fixes existing maintenance races.

## Read-only inputs and future folder screen

Slice 0's colleague trial uses synthetic/public inputs only. Any later company-data trial requires the vendor-account/confidentiality gate above and a verified reference-access decision before it starts, regardless of which delivery slice supplies that access. Do not mount entire SharePoint/sync trees. Verify a narrowly scoped read-only source mount or approved working-copy process. Existing writable mounts must not expose the same source through another path. A read-only bind protects that path, not all company data or shared credentials; stronger isolation needs separate container/identity design and must account for sudo. No staff release may claim project isolation while retaining one shared workspace/home.

Build a custom folder picker only if the pilot shows a remaining need. If approved:

- [ ] Keep ordinary folders first; Clone is secondary and never followed by automatic Open. Repository hooks, local MCP/config and instructions may affect an agent with access to the shared home; trust approval remains explicit.
- [ ] Keep preferences outside extracted docker-files, e.g. `%LOCALAPPDATA%\AI-Docker-CLI\projects.json`. Validate schema, size, depth, tool IDs and containment on every load; IDs are identifiers, not an authority to execute commands. Reject symlink/junction escapes and arbitrary commands.
- [ ] Use explicit JSON depth and a proven replacement/locking protocol for saves; ConvertTo-Json defaults and Move-Item -Force are not a persistence guarantee. Preserve malformed data for recovery and handle concurrent writers.
- [ ] Document that -RemoveAppData removes local preferences. Provide a deliberate preference export/recovery route if needed; no automatic backup or credential export.
- [ ] Offer Open in Explorer and native resume; removing a shortcut never deletes a folder. Check keyboard/high-DPI use. Do not create business project records.

A later New project option may carry approved folder structure, naming guidance, project instructions and skills. Validate against a real Cainmani task and the authoritative policy first; do not invent a project code, template engine or duplicate source store.

## Validation and acceptance

| Area | Required evidence |
| --- | --- |
| Legacy support | Real 1.6/unknown-version container never receives guessed flags; no interactive menu in a background probe; explicit unknown/busy/failure outcomes |
| Native compatibility | Claude/Codex supported-version table for launch/login/status/resume, native account modes, preserved custom settings/MCP/hooks, conditional authentication classification |
| Mutation safety, Slice 1b | Updater/installer/Vibe contention, missing flock, broken-but-present binaries, launch-versus-repair race, interrupted repair, active/manual/Desktop sessions and vendor self-update limits |
| Windows execution | PS5.1 plus applicable PS7 helper tests; both terminal hosts; hostile path characters; interactive environment parity; post-startup selected directory on new and 1.6 containers; async stale results and cancellation |
| Desktop pilot | Localhost-only SSH, recorded authorised seat/account type and actual user/home/auth/tool ownership, before/after installation checks, reconnect/recreate/resume, non-Git folder, synthetic/public inputs and pilot-only credential teardown |
| Later company-data trial | Vendor account/data-use settings and responsible confidentiality approval recorded separately from approved source/read-only/output handling; no confidential input before both gates pass |
| Persistence/migration | Existing 1.6 install retains work/volumes/config; mount drift detected; old-container terminal fallback; preference schema/recovery if picker is approved |
| Packaging/runtime | Pester, focused behavioral Bash, required lint, embedding/version checks; compiled EXE opens the new screen and exercises representative worker success/failure under Restricted policy; disposable Docker smoke on final relevant commit |
| Business usefulness | A non-developer completes the agreed source-backed task, locates a correctly named/versioned output and continues next day without maintainer help; compare time/errors/support with baseline |

Mock tools certify argument/error ordering, not real login or Desktop behavior. Use disposable Docker resources for destructive checks. Docker Smoke evidence is a merge gate even when path filters do not trigger it: dispatch/extend triggers as needed. Do not claim it is branch-protection-required without checking repository settings; changing those settings is separate work.

## Plan review and merge

- [ ] Reconcile review findings and ensure the plan has no contradictory pilot, directory or release requirements.
- [ ] Documentation checks and applicable existing CI pass on the final planning commit; no claim of runtime/pilot completion from docs CI.
- [ ] User approves merging documentation-only PR #97. The pilot and implementation gates below are not prerequisites for merging an agreed plan, and remain unchecked in their own PRs.

## Implementation release and review gates

- [ ] Tracking issue records agreed first-slice scope and later items; initial UI review covers simple Open and recovery, not a full dashboard.
- [ ] Desktop feasibility result is recorded before approving a custom folder UI; record unsupported behavior rather than work around it with silent config changes.
- [ ] Implementation commits/PRs remain focused; description and evidence match the actual slice. Later items do not block a completed smaller slice.
- [ ] Maintenance ownership, supported CLI versions and a bounded support budget are agreed; add adapters only after observed need.
- [ ] Required CI plus applicable runtime/Windows/native-login/colleague evidence pass on the final candidate commit for each slice. Mutation gates apply to Slice 1b, not as a blocker on observation/login-only Slice 1a. Keep evidence of mock, automated runtime and real-user checks distinct.
- [ ] Update migration, troubleshooting and truthful credential/folder boundaries. For the proposed container-side 1.7 changes, bump ContainerBaselineVersion to that release together with VERSION and required metadata. No bump in this planning revision.
- [ ] User approves final scope and candidate behavior before ready/merge; release tag/publication remains separate.

## Later alternatives and source discipline

Evaluate vendor Desktop/remote workflows before building browser chat or transcript management. CloudCLI licensing and native configuration writes need review before integration; compare DevPod for editor/container workflows. Do not select competitors by stars alone or assume their platforms, release freshness or licences from old snippets.

Keep UI actions behind a small backend boundary. [Docker Sandboxes installation](https://docs.docker.com/ai/sandboxes/install/) documents Windows 11/hypervisor requirements, and its [isolation model](https://docs.docker.com/ai/sandboxes/security/isolation/) differs from this shared container. Treat it as a later comparison, not a drop-in swap, support promise or reason to break existing Windows 10 users. Validate persistence, mounts, tools and credential behavior before choosing another backend.

Defer new browser UI, cross-provider sessions, isolated account profiles, published images and worktree/editor UI until a specific task justifies them. The next action is Slice 0 feasibility and the minimal first-slice design, followed by focused implementation; none of these checks is complete merely because it appears in this plan.
