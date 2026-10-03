---
name: hv-release
description: Cut a release — walk the project's per-project release checklist (`.hv/RELEASE.md`) as a pre-release gate, bump version (major/minor/patch), generate categorized release notes from commits since the last tag, prepend a section to CHANGELOG.md, create an annotated git tag, push, publish a release on GitHub or GitLab if origin is set, and offer to close any upstream issues still open for shipped items. Use on "release", "cut a release", "tag a release", "ship X.Y.Z".
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🏷️  hv-release  ·  bump version, tag, notes, CHANGELOG, publish
  triggers: "release", "cut release", "ship X.Y.Z"  ·  pairs: hv-ship
════════════════════════════════════════════════════════════════════════
```

# hv-release — Cut a Release

## Configuration

Read from `.hv/config.json` (all keys optional — defaults apply if absent):

| Key | Default | Notes |
|---|---|---|
| `release.versionFile` | (auto-detect) | Explicit path override; skips auto-detect search |
| `release.changelogPath` | `CHANGELOG.md` | Project-root relative |
| `release.checklistPath` | `.hv/RELEASE.md` | Per-project release checklist walked in Step 1.5; absent = offer scaffold |
| `release.tagPrefix` | `v` | Set to `""` for unprefixed tags |
| `release.draft` | `false` | Pass `--draft` to `gh`/`glab` |
| `release.requireCleanTree` | `true` | Set `false` to allow dirty releases (testing only) |
| `release.confirmLargePushCommits` | `10` | Threshold (commits) above which auto/loop autonomy still confirms before pushing unpushed HEAD |

## Step 1 — Guard

Run each check; stop with a one-liner on failure.

1. **Clean tree** — `git status --porcelain`. Non-empty and `release.requireCleanTree` true: stop, show `git status -s`, suggest commit/stash or `release.requireCleanTree: false`.
2. **On trunk** — branch must be `main`, `master` or `trunk`.
3. **HEAD pushed** — `git rev-parse HEAD` vs `@{u}`. A release ships the local commits, so unpushed commits are part of it, not an error. Branch on `autonomy.level`:
   - `"auto"` or `"loop"` — count `git rev-list @{u}..HEAD --count`. Below `release.confirmLargePushCommits`: run `git push origin <current-branch>` silently and continue. At or above it, ask once whatever the autonomy: header `"Large push"`, *"<N> unpushed commits about to be pushed as part of this release. Continue?"*, options `Push and continue (Recommended)` / `Abort`.
   - `"off"` — header `"Unpushed"`, *"HEAD has unpushed commits. Push them as part of this release?"*, options `Push and continue (Recommended)` / `Abort`.
   - Plain-text fallback: *"Push and continue, or abort?"*

**Initialize task list.** Follow `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase:

1. *Guard* — clean tree, on trunk, HEAD pushed (Step 1)
2. *Project checklist* — walk `.hv/RELEASE.md` items as gates (Step 2)
3. *Bump version* — level chosen, version file and CHANGELOG written (Steps 4-5, 7-8)
4. *Generate notes* — categorized notes drafted and approved (Steps 5-6)
5. *Tag & push* — annotated tag created, branch + tag pushed (Steps 9-10)
6. *Publish* — remote release published if origin matches (Step 11)
7. *Close upstream issues / milestone* — manual gate (Steps 12-13)
8. *Post-release nudges* — summary + docs (Steps 14-15)

`--dry-run` (any step): run the read-only verbs and the judgment questions, skip every write, commit, tag and push, and print what would happen instead.

## Step 2 — Project Checklist

Per-project release steps (sibling version files, lockfiles, docs version refs, infra rollouts) live in `release.checklistPath`, tracked and shared with the team. The skill hardcodes none of them. Skip in `--dry-run`: print the parsed items and `DRY RUN — checklist walk skipped.`

**File absent.** `autonomy.level` `"auto"`/`"loop"`: skip silently; never interrupt an unattended run to scaffold. `"off"`: header `"Checklist"`, *"No `<release.checklistPath>` found. Scaffold a starter checklist now, or continue without?"*, options `Scaffold starter (Recommended)` (write the template, let the user edit, re-read, walk it) / `Continue without` (summary says *"no project checklist"*) / `Abort`. Plain-text fallback: *"Scaffold checklist, continue without, or abort?"*

Starter template:

```markdown
# Release Checklist

Each `- [ ]` line is a gate `/hv-release` walks before bumping the version. Edit freely — nothing here is hardcoded. Items marked `- [x]` are ignored. Append `(manual)` to any item that must interject even in `autonomy.level: auto`/`loop`.

- [ ] Sibling version-bearing files are in sync (e.g., `.claude-plugin/marketplace.json`, lockfiles, docs version refs)
- [ ] CI is green on the release branch
- [ ] Migration notes for users on the prior version are written

(Add project-specific items below.)
```

**File present.** Every line matching `^\s*-\s+\[\s*\]\s+(.+)$` is a gate, in file order; `- [x]` lines are skipped. Zero gates: say *"Checklist has no open items — continuing."* For each gate:

- `"off"` — ask: header `"Checklist"`, *"Checklist item: \<text\>. Done?"*, options `Yes, continue (Recommended)` / `Fix it now and continue` (pause, re-ask the same item) / `Skip this item` (record `skipped: <text>`) / `Abort release` (*"Release aborted at checklist item: \<text\>. Nothing written."*). Plain-text fallback: *"Done, fix now, skip, or abort?"*
- `"auto"`/`"loop"` — auto-acknowledge items not ending in `(manual)`; ask the `"off"` question for items that do, so sensitive items stay confirmed in unattended runs.

## Step 3 — Milestone Gate (issue mode)

**Issue mode** (`backlog.backend: "issues"`; `references/issue-mode.md`): pick the milestone. `--milestone MNN` wins; else the single one from `hv milestone active`. Several active: `AskUserQuestion` (plain-text fallback: list the IDs); under `autonomy.level: "loop"`, stop unless exactly one is active. Then `hv release milestone-check <MNN> --json`.

Exit 1 means blocked: show each `data.blocked` entry (open issues labelled `in-progress`, `needs-review` or `changes-requested`) and stop. `data.stillOpen` entries do not block; show them and continue. Other exits (2, 3, 4, 5, 6): stop and report the verb's message.

**Umbrella** (`hv repo umbrella` exits 0): releases run per sub-repo. Pass `--repo <name>` to `release milestone-check`, `release notes --from issues` and `release close-milestone`; without it they exit 2. The milestone reads `shipped` only once every sub-repo's milestone MNN is closed.

## Step 4 — Version and Bump Level

`hv release version --json` gives `data` `{file, version, kind}`. Exit 3 (no version file or unparsable): surface the message and tell the user to set `release.versionFile` in `.hv/config.json`.

Accept a bump arg if given: `major`, `minor`, `patch` or an explicit `X.Y.Z`.

With no arg, get the previous tag (`git describe --tags --abbrev=0 2>/dev/null || true`; empty means full history, note it in the summary), run `hv release notes --from commits [--since <prev-tag>]` and read the bucket headings: `Breaking` recommends `major`, `New` recommends `minor`, otherwise `patch`. Ask: header `"Bump type"`, *"Current version: `<current>`. What bump type?"*, options `patch — <current> → <X.Y.Z+1>` / `minor — … → <X.Y+1.0>` / `major — … → <X+1.0.0>` (mark the recommended one) / `Explicit version` (exact string via Other) / `Abort`. Plain-text fallback: *"Bump type? (major / minor / patch / X.Y.Z / abort)"*

Compute the new version read-only: `hv release version --json --level <patch|minor|major>` (or `--to <X.Y.Z>`); `data.next` is `new_version`. An invalid or not-greater `--to` exits 1: surface it and stop.

If `Breaking` commits were found but the user chose `patch` or `minor`, ask before continuing: header `"Escalate"`, *"Commits contain `BREAKING CHANGE:` footers but bump type is `<chosen>`. Escalate to major?"*, options `Escalate to major (Recommended)` / `Keep <chosen>` / `Abort`. Plain-text fallback names the Recommended default on ambiguity (`references/ask-user-question-fallback.md`).

## Step 5 — Generate Release Notes

`hv release notes --from commits [--since <prev_tag>]` returns categorized Markdown (merges filtered). In issue mode use `hv release notes --from issues <MNN> [--since <prev_tag>]` instead. Exit 3/4/5/6: stop and report. The verb categorizes; editorial work is yours:

- **Compact dense buckets.** A bucket with 3+ entries on one feature or concern (7 `feat:` commits on one new skill) becomes one summary line for the theme, plus at most 1-2 bullets for the highest-impact pieces (a breaking change, a flag flip, a new public surface). Buckets under 3 stay as-is.
- **Stats.** Replace the verb's `## Stats` with `## Stats\n<N commits, M files changed, +X −Y lines>` from `git diff --shortstat <prev_tag>..HEAD` (drop `<prev_tag>..` with no previous tag).
- **Compare link.** With a previous tag, `hv release host --json` `data.host` picks the URL: `github`/`github-enterprise` → `https://<host>/<owner>/<repo>/compare/<prev_tag>...v<new_version>`; `gitlab`/`gitlab-self-hosted` → `https://<host>/<owner>/<repo>/-/compare/<prev_tag>...v<new_version>`. Append `**Full changelog:** <url>`. Host `none` or no previous tag: omit.
- **One-line summary.** Prepend one line on the top 2-3 themes. It becomes the release title suffix in Step 11.

Notes ship to GitHub/GitLab and live in CHANGELOG.md. Before showing the draft, silently apply the rules in `references/humanizing-prose.md` to all model-written prose; the user sees the post-audit draft.

## Step 6 — Review Notes

Show the full draft, then ask: header `"Notes"`, *"Release `v<new_version>` — notes look good? Yes pushes the tag and publishes the release."*, options `Looks good (Recommended)` / `Edit` (replacement text via Other replaces the draft verbatim; re-display it, one edit pass, no second prompt) / `Abort release` (*"Release aborted. Nothing written."*). Plain-text fallback: *"Proceed, edit, or abort?"*

This answer is the human approval for Steps 10 and 11. Keep it verbatim as `$APPROVAL` (the option label, or the replacement text's first line after Edit) for `--confirm-note`. Never auto-pick this question in any autonomy mode.

Write the approved notes to `NOTES_FILE=$(mktemp /tmp/hv-release-notes.XXXXXX.md)`.

## Step 7 — Write Version File and CHANGELOG

```bash
hv release bump --json --level <patch|minor|major>   # or --to <X.Y.Z>; same arguments as Step 4
hv release changelog <new_version> --body-file "$NOTES_FILE" [--path <release.changelogPath>]
```

If `data.to` differs from `new_version`, stop: the file may be partly modified, so surface the discrepancy for the user. Changelog exit 4 (section already exists): stop before committing. Skipped in `--dry-run`.

## Step 8 — Commit

`git add <version-file> <release.changelogPath>` then `git commit -m "chore: release v<new_version>"`. Skipped in `--dry-run`.

## Step 9 — Tag

`git tag -s` if `git config --get user.signingkey` is set, else `-a`: `git tag [-a|-s] v<new_version> -F "$NOTES_FILE"`. Skipped in `--dry-run`; print the command.

## Step 10 — Push

> **Manual gate — pushing the release tag.** The remote tag is public and hard to retract. This step always asks, in every autonomy mode; loop mode does not accelerate it. `hv release push` enforces the `tag-push` gate (exit 4 without `--confirm`). Step 6's answer is the approval. See `references/manual-gates.md`.

```bash
hv release push <new_version> --json --confirm --confirm-note "$APPROVAL"
```

One push carries the commit and the tag. Exit 3 (no origin) or 5 (push failed): stop; the error names the tag SHA for manual recovery. Skipped in `--dry-run`.

## Step 11 — Publish Remote Release

> **Manual gate — publishing the release.** Same rule: always asks, loop mode does not accelerate it. `hv release publish` enforces the `release-publish` gate and reuses Step 6's answer.

```bash
hv release publish <new_version> --json --title "v<new_version> — <one-line summary>" \
  --body-file "$NOTES_FILE" [--draft] --confirm --confirm-note "$APPROVAL"
```

Add `--draft` when `release.draft` is true and the host is GitHub (GitLab refuses it). Origin on neither host: the verb publishes nothing (`changed: false`) and the summary says `skipped`. `data.url` goes in the summary. Exit 5 (`gh`/`glab` missing): print the error and continue; the tag is already public. Skipped in `--dry-run`; print the command.

## Step 12 — Close Out the Milestone (issue mode)

After Steps 10 and 11, `hv release close-milestone <MNN> --release <new_version> [--repo <name>]` (bare `X.Y.Z`). It marks the milestone's completed issues `released`, closes the milestone and sets it `shipped`; tell the user `data.issues`. Exit 2-6: report the message. Skipped in `--dry-run`. Step 13 does not apply: the tracker is the backlog, nothing is imported.

## Step 13 — Close Upstream Issues

Closes upstream issues that shipped in this release but stayed open: work pushed straight to main, or `/hv-ship` chose "leave open". Same shape as `/hv-ship` Step 6c, scoped to the release range. Skip in `--dry-run`.

`hv issues imported --json --open-only` lists candidates (already-closed or unresolvable ones are dropped). Empty `data.entries`: skip silently.

> **Manual gate — closing public upstream issues.** Closing posts a tracking comment and changes issue state on the remote, visible to others. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`; loop mode stops here and waits for the user. The release already published; this decides whether to close the issues too. See `references/manual-gates.md`.

Ask (single-select): header `"Close"`, *"Close N upstream issue(s) released in `v<new_version>`? (`<#N list>`)"*, options `Yes, close all` / `Pick subset` / `No, leave open`.

- **Close all:** run `hv issues close <N> --commit <release-commit-sha> --item <ID> [--repo <name>]` per candidate, in one parallel batch. `--repo` only for entries with a non-null `repo`.
- **Pick subset:** multiSelect `AskUserQuestion` (header `"Pick issues"`, *"Which issue(s) should be closed?"*, options `"#N (item <ID>)"`, chunk at 4), then close the selection as above.
- **Leave open:** print *"Skipping upstream issue close — N issue(s) left open. Run `gh issue close <N>` / `glab issue close <N>` manually if desired."*

## Step 14 — Docs Nudge

Read `docs.afterWork` (default `false`); if false, skip. When on, a release is a natural docs trigger: notes and CHANGELOG often imply README, guide or reference updates. Skip in `--dry-run`; once per session. `"off"`: append to the summary *"Release shipped. Run `/hv-ship --docs` to review and update public docs (after-work mode)."* `"auto"`/`"loop"`: dispatch `hv-ship --docs` via `Skill` immediately, no prompt, with a brief naming the version, bump type and the one-line summary. `/hv-ship` self-skips if the docs path is missing or empty. Users opt in with `hv config set docs.afterWork true` or one manual `/hv-ship --docs`.

## Step 15 — Summary

```
Released v<new_version>
  Tag:      v<new_version> (<tag-SHA>)
  Commit:   <commit-SHA>
  CHANGELOG: <release.changelogPath>
  Remote:   <release-URL or "skipped">
  Checklist: <N> done / <M> skipped (or "no project checklist" / "skipped in dry-run")
  [No previous tag — full history used as range.]   ← only when no prev tag
```

List skipped checklist items under `Skipped checklist items:` so the release record is honest. In `--dry-run`, prefix the block with `DRY RUN — no changes written.`

## Edge Cases

- **Multiple version files** — first match wins; pin with `release.versionFile`.
- **`gh`/`glab` missing but origin matches** — Step 11 fails after the tag push. Recovery: install the CLI and re-run `hv release publish <X.Y.Z> --title … --body-file <path> --confirm --confirm-note "<answer>"`; to revert the tag, `git push --delete origin v<X.Y.Z>`.
- **No origin** — push exits 3; publish is skipped. Tag and CHANGELOG stay committed locally.
- **CHANGELOG without a `# Changelog` header** — the verb keeps existing content and inserts after the H1 if present, else prepends.

## Rules

- Never bump without a user-confirmed bump type.
- Never push the tag without the user approving the release notes (Step 6).
- Stop on any non-zero verb exit you have no branch for; do not continue past it.
- Never hardcode project-specific release steps here; they live in `release.checklistPath`.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/manual-gates.md`](../references/manual-gates.md) — The manual-gate registry (`hv gate list`): gates the verbs enforce with `--confirm`, and the skill-only callouts.
- [`references/task-list-init.md`](../references/task-list-init.md) — Task-list init pattern.
- [`references/issue-mode.md`](../references/issue-mode.md) — Issue-mode milestones and release.
- [`references/ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) — Plain-text fallback rule.
- [`references/humanizing-prose.md`](../references/humanizing-prose.md) — Self-audit for model-written notes.
