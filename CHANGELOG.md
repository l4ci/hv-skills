# Changelog

## v2.0.0 — 2026-05-08

Hard-merge of `/hv-status` and `/hv-resume` into `/hv-next`. Single state-view entry point.

## Breaking

- `/hv-status` and `/hv-resume` are removed in favor of `/hv-next`. `/hv-next` now reads `/hv-pause` handoff notes for active streams and surfaces `Stage` / `Next planned step` / `Current hypothesis` inline alongside each stream — replacing the post-`/clear` `/hv-resume` flow. The lightweight glance from `/hv-status` is no longer offered as a separate command. Update muscle memory: anywhere you typed `/hv-status` or `/hv-resume`, type `/hv-next` instead. [F26]

## Changed

- `bin/hv-skills-index` heredoc body drops `/hv-status` and `/hv-resume` from the "Capture & pick" group. Existing projects must re-run `/hv-init` to refresh the managed `<!-- hv-skills-start -->` block in `CLAUDE.md`. [F26]
- `docs/usage/next-and-status.md` is renamed to `docs/usage/picking-work.md` and rewritten to reflect the one-command world. [F26]

## Removed

- `hv-status/SKILL.md` and the `hv-status/` folder. [F26]
- `hv-resume/SKILL.md` and the `hv-resume/` folder. [F26]

## v1.16.0 — 2026-05-08

Knowledge-loop intelligence (stats + upstream-issue suggestion), `/hv-docs` after-work hook, and a 4-round architectural refactor centered on a sourceable umbrella resolver.

## New

- wire `/hv-docs` after-work into `/hv-work` + `/hv-ship` behind `docs.afterWork` gate [F15] (`ef938f8`)
- `/hv-learn` suggests filing an upstream `hv-skills` issue when a learning surfaces a tool gap [F14] (`754b3de`)
- `hv-knowledge-stats` + fat-topic nudge in `/hv-learn` [F13] (`3bfd8fe`)
- write-only workers + orchestrator-side commits as `/hv-work`'s default [F11] (`b6bb138`)
- `hv-reconcile` scans commit history for TODO.md drift [F09] (`84a2c3c`)
- `hv-self-locate.sh` — sourceable umbrella resolver, threaded through 25 state-only helpers [F10] (`5762b68`, `d16372b`)
- umbrella-aware cwd guards on `hv-base-branch` / `hv-merge` / `hv-pr` / `hv-ship-body` / `hv-review-scope` [B02] (`e6fd4f6`)
- `hv-ship-body` emits `Closes #N` from GH refs in TODO bodies [F12] (`d253140`)

## Fixed

- `hv-vision-index` counts only planned milestones in the elif body [B10] (`f8c39bc`)
- `/hv-config` Step 3 picklist chunked into category + key stages [B11] (`4764342`)
- `/hv-init` umbrella plain-text fallback now defaults to No, not Yes [T11] (`8ee7b7b`)
- `chmod +x` in the git index for 9 helpers that were tracked as 100644 [B09] (`fc47e87`)
- `hv-reconcile` tolerates upfront `hv-base-branch` failure [B02] (`c693ef5`)
- `hv-complete` recognises scoped `refactor(scope):` subjects [B04] (`f8bcd47`)
- `hv-next-id` self-heals against TODO / ARCHIVE drift [B03] (`5340bdd`)

## Changed

Four-round architectural refactor (`hv-refactor` rounds 1-4 + post-F11 alignment): tightened helper boundaries, removed redundant cwd assumptions, collapsed duplicated logic, and synced surrounding skills.

- 5 + 4 + 6 + 8 architectural improvements across rounds 1-4 (`39e2e77`, `984c717`, `bb51256`, `b4d6a87`)
- 3 architectural alignments after F11 [post-merge] (`7611eaf`)
- `.hv/DECISIONS.md` cleared + redundant `KNOWLEDGE.md` entries swept (`0a3f76c`)
- CLAUDE.md vision block refreshed after M03 shipped (`f35c11e`)

## Documentation

- post-round-4 sync (worktree-path helper, `reconcile noBase`, smoke count) (`a2413e5`)
- inline cross-project rules from `.hv/` into SKILL.md prose [T12][T13][T14][T15][T16] (`6c50ec5`)
- codify opt-in-flag rule in `hv-init` + `hv-config` SKILL.md (`10287e7`)

## Stats

26 commits, 72 files changed, +1781 −535 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.15.1...v1.16.0

## v1.15.1 — 2026-05-05

Umbrella-aware tooling fixes — hv-guard-clean / hv-spike-add now handle umbrella-cwd properly, and hv-preflight no longer false-positive-flags sourced shell libraries on every release run.

## Fixed

- treat sourced shell libs as files, not executables (hv-preflight) (`007a473`)
- umbrella-aware tooling for hv-guard-clean and hv-spike-add (bin) (`322cc0d`)

## Stats

2 commits, 3 files changed, +100 −10 lines

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.15.0...v1.15.1

## v1.15.0 — 2026-05-03

Multi-repo dispatch lands as one cohesive feature surface across 6 helpers and 4 skills, with `/hv-pause` now treating multi-repo waves as one logical handoff and a small refactor consolidating Repos: CSV validation.

## New

- **Multi-repo dispatch foundation (M03-S01).** A single backlog item with `Repos: a, b` now produces commits on `hv/<branch>` in every named sub-repo via one `/hv-work` invocation. Adds four new helpers (`hv-resolve-repos`, `hv-multi-branch-create`, `hv-status-add-multi`, plus `hvlib.parse_repos_csv`) and threads the multi-repo list through `hv-capture`, `hv-plan`, `hv-assume`, and `hv-work`. Single-repo path stays byte-identical.
- `hv-pause` treats multi-repo waves as one logical pause set — no per-repo `AskUserQuestion`; one handoff file per `(branch, repo)`; combined wave confirmation. `cd` into a sub-repo to scope the pause to that one entry. ([F08], `7f5c242`)

## Changed

- consolidate Repos: CSV validation into hvlib (`192ff27`)
- mark M01/M02 shipped, activate M03 (`8914492`)

## Documentation

- humanize README and docs/ prose (`17c3979`)

## Stats

10 commits, 33 files changed, +703 −263 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.14.0...v1.15.0

## v1.14.0 — 2026-05-03

**Umbrella mode V1 (M02) substantively shipped: every read-side helper, plus `/hv-plan`, `/hv-spike`, `/hv-pause`, `/hv-assume`, `/hv-refactor` now route work to the resolved sub-repo. Single-repo behavior is unchanged.**

## New

Closes the M02 follow-up wave so the umbrella surface lands end-to-end across plan, spike, pause/resume, assume, and refactor. Items can carry a `Repos:` tag to route work to a registered sub-repo; helpers gain `--repo <name>` for direct calls.

- `/hv-refactor` umbrella-aware fanout: asks which scope (all sub-repos, all + umbrella, umbrella only, subset) and dispatches parallel sub-agents per target (`3534415`).
- `/hv-pause` handoff filenames key on `(branch, repo)` — `<branch>@<repo>.md` instead of `<branch>.md` so two sub-repos sharing a branch name don't clobber each other's notes (`de650e3`). `/hv-resume` reads the umbrella-keyed path with legacy fallback.
- `/hv-spike --repo` runs the spike branch in the resolved sub-repo; spike file stays at the umbrella with a `repo:` frontmatter line (`973aba8`).
- `/hv-plan --repo` records the target sub-repo in plan frontmatter (`c2c0915`).
- `/hv-assume` peek displays the resolved sub-repo for items with `Repos:` (`56bc0d4`).

## Changed

- Architectural sweep: 11 improvements covering the umbrella read-side (`hv-base-branch` walk-up, `hv-review-scope --repo`, `hv-status-add/-remove --repo`, `hv-summary` / `hv-backlog` repo display, `hv-preflight` validates `repos.json`), plus umbrella-aware threading through `/hv-work`, `/hv-ship`, `/hv-debug` call sites (`d9afb4b`).
- Architectural sweep: 5 improvements to release helpers (`hv-release-bump-version --dry-run`, `parse_toml_version` lifted to `hvlib`) and one default flip — `docs.autoCreate: true → false` for fresh `/hv-init` runs, pending the M01-S03 LLM safety review (existing configs unaffected) (`3c1bc02`).

## Documentation

- Umbrella-mode guide refresh: `docs/usage/umbrella-mode.md` rewritten for the shipped surface, dropping all "S01/S02" hedging; new "Per-skill behavior" section listing the umbrella behavior of every affected skill plus the helper `--repo` matrix (`0feaf8c`).
- README updated: features grid gains an Umbrella mode row; config example shows `umbrella` and `docs` keys with `autoCreate: false`; architecture tree notes `repos.json` and `(branch, repo)` keying.
- Skills surface in `docs/usage/`: prose-only umbrella documentation in `/hv-go`, `/hv-review`, `/hv-status` (`1f719c2`).
- Earlier in the cycle: README quickstart + getting-started Path A and Path B walkthroughs got fleshed out (`d7442b8`, `475a394`); `/hv-decide`, `/hv-docs`, `/hv-release` surfaced in the README diagram and reference (`4cd20a7`).

## Stats

12 commits, 44 files changed, +1347 −308 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.13.0...v1.14.0

## v1.13.0 — 2026-05-02

**Umbrella Mode V1 — coordinate backlog and work across multiple sub-repos from a single `.hv/`.**

## New

- **Umbrella Mode foundation (M02-S01)** — opt-in detection, sub-repo registry (`.hv/repos.json`), and resolvers so a single `.hv/` can coordinate work across multiple repos. Adds `hv-umbrella-init`, `hv-resolve-umbrella`, `hv-resolve-repo` helpers; `hv-bootstrap` seeds an empty registry; `hv-init` Step 1.5 prompts for umbrella opt-in; `hv-config` exposes a toggle.
- **Umbrella Mode command awareness (M02-S02)** — `--repo` flag plumbed through `hv-status-add`, `hv-status-remove`, `hv-merge`, `hv-pr`, `hv-worktree-clear`, and `hv-reconcile` (per-entry git scoping). `/hv-capture` Step 4.6 tags items with their target repo; `/hv-work` creates branches in the right sub-repo with isolation guards.

## Changed

- Refreshed CLAUDE.md managed blocks (decisions index, vision index — M02 marked active).
- Fixed exec bit on `hv-resolve-repo`.

## Documentation

- New umbrella-mode user-guide page.

## Stats

24 commits, 18 files changed, +946 −46 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.12.2...v1.13.0

## v1.12.2 — 2026-05-02

Single bugfix surfaced one release after `/hv-release` shipped.

## Fixed

- **`bin/hv-skills-index` now lists `/hv-release` under Maintenance** (`b7ea9f8`). The helper has a hand-curated body (intentionally not auto-derived from `plugin.json` so the editorial categorization survives), and the F03 integration worker brief covered `plugin.json` + `slash-commands.md` + `cli-helpers.md` + `README.md` but missed this helper. Re-running `hv-skills-index` regenerates the managed `<!-- hv-skills -->` block in `CLAUDE.md`.

Users on v1.12.0 / v1.12.1 saw a stale skills index; v1.12.2 corrects it. Captured the gap as a Skill Authoring learning so the next worker brief catches it.

## Stats

1 commit · 2 files · +2 / −2 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.12.1...v1.12.2

## v1.12.1 — 2026-05-02

Two follow-up improvements to `/hv-release` surfaced while dogfooding it for the v1.12.0 cut.

## Changed

- **Step 1 unpushed HEAD** — `autonomy: auto`/`loop` now silently runs `git push` and continues; `autonomy: off` prompts via `AskUserQuestion` (`Push and continue (Recommended)` / `Abort`). Removes the ceremonial "go push, then re-run me" friction — a release intends to ship the local commits.
- **Step 6 dense-bucket compaction** — when a bucket has 3+ entries on the same theme, the orchestrator collapses them into a single summary line plus 1-2 highlight bullets (the merge commit, a follow-up fix). Buckets with fewer than 3 entries stay raw. The helper still emits raw categorization; editorial collapse is the skill's job.

## Stats

1 commit · 1 file · +12 / −1 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.12.0...v1.12.1

## v1.12.0 — 2026-05-02

## Highlights

- **New skill: `/hv-release`** — cuts a release end-to-end. Bumps the project version (`major`/`minor`/`patch` or explicit semver), generates categorized release notes from commits since the last tag, prepends a section to `CHANGELOG.md` (creating it if absent), creates an annotated git tag, pushes commit + tag, and publishes a release on GitHub or GitLab when origin is set. Auto-detects the version source across `.claude-plugin/plugin.json`, `package.json`, `pyproject.toml`, `Cargo.toml`, and plain `VERSION` / `version.txt`; honors a `release.versionFile` override in `.hv/config.json`.
- **5 new bin helpers**, each small / atomic / stdlib-only:
  - `hv-release-detect-version` — emit `{file, version, kind}` JSON
  - `hv-release-bump-version` — apply a semver bump (or explicit version) in-place via atomic write
  - `hv-release-changelog-from-commits` — categorize commits in a git range by Conventional Commits prefix; detects `BREAKING CHANGE:` footer
  - `hv-release-update-changelog` — prepend a release section to `CHANGELOG.md` (creates the file with `# Changelog` header if absent); idempotent — refuses if the version section already exists
  - `hv-release-detect-host` — classify origin URL as `github` / `github-enterprise` / `gitlab` / `gitlab-self-hosted` / `none`
- **22 new smoke assertions** cover every helper across each version-file kind, all semver bump rules, full bucket categorization including BREAKING CHANGE, idempotent CHANGELOG prepend, and host detection over SSH/HTTPS variants.

## Configuration

New keys under `release.*` in `.hv/config.json` (all optional):

| Key | Default | Notes |
|---|---|---|
| `release.versionFile` | (auto-detect) | Explicit path override |
| `release.changelogPath` | `CHANGELOG.md` | Project-root relative |
| `release.tagPrefix` | `v` | Set to `""` for unprefixed tags |
| `release.draft` | `false` | Pass `--draft` to `gh` / `glab` |
| `release.requireCleanTree` | `true` | Set `false` to allow dirty releases (testing only) |

## Stats

9 commits · 11 files · +1,130 / −1 lines · all smoke tests pass.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.11.0...v1.12.0

