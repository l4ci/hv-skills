# Changelog

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

