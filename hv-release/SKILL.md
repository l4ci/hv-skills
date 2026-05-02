---
name: hv-release
description: Cut a release — bump version (major/minor/patch), generate categorized release notes from commits since the last tag, prepend a section to CHANGELOG.md, create an annotated git tag, push, and publish a release on GitHub or GitLab if origin is set. Use on "release", "cut a release", "tag a release", "ship X.Y.Z".
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

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
| `release.tagPrefix` | `v` | Set to `""` for unprefixed tags |
| `release.draft` | `false` | Pass `--draft` to `gh`/`glab` |
| `release.requireCleanTree` | `true` | Set `false` to allow dirty releases (testing only) |

## Step 1 — Preflight & Guard

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

Then verify:

1. **Clean tree** — run `git status --porcelain`. If output is non-empty and `release.requireCleanTree` is `true` (default), stop: *"Working tree is dirty. Commit or stash changes first, or set `release.requireCleanTree: false`."* Show `git status -s` in the error.
2. **On main/trunk** — `git rev-parse --abbrev-ref HEAD`. If not `main`, `master`, or `trunk`, stop with a one-liner.
3. **HEAD pushed** — `git rev-parse HEAD` vs `git rev-parse @{u}`. If they differ, branch on `autonomy.level` from `.hv/config.json`:

   - `"auto"` or `"loop"` — silently run `git push origin <current-branch>` and continue. A release intends to ship the local commits; an unpushed HEAD is part of the release, not a pre-flight error.
   - `"off"` (default) — use `AskUserQuestion`:
     - **Header:** `"Unpushed"`
     - **Question:** *"HEAD has unpushed commits. Push them as part of this release?"*
     - **Options:**
       1. `"Push and continue (Recommended)"` — runs `git push origin <current-branch>`, then proceed
       2. `"Abort"` — stop without writing anything
     - Plain-text fallback: *"Push and continue, or abort?"*

## Step 2 — Detect Version Source

```bash
.hv/bin/hv-release-detect-version
```

Parse JSON output `{file, version, kind}`:

- `file` — absolute path to the version-bearing file
- `version` — current semver string (e.g., `1.10.0`)
- `kind` — `plugin-json` | `package-json` | `pyproject` | `cargo` | `plain`

If exit 1, surface the stderr message verbatim and stop. If output indicates multiple candidates, use `release.versionFile` to disambiguate — document that the user should set it in `.hv/config.json`.

## Step 3 — Determine Bump Type

Accept an arg if the user supplied one: `major`, `minor`, `patch`, or an explicit `X.Y.Z` string. Also accept `--dry-run` flag — run all steps but skip all writes, commits, tags, and pushes; print what would happen.

If no arg, first generate the commit-range preview for a recommendation:

```bash
.hv/bin/hv-release-changelog-from-commits <prev-tag>..HEAD
```

Scan output for bucket headings:
- `## Breaking` present → recommend `major`
- `## New` present (no Breaking) → recommend `minor`
- else → recommend `patch`

Then use `AskUserQuestion`:
- **Header:** `"Bump type"`
- **Question:** *"Current version: `<current>`. What bump type?"*
- **Options** (single-select, mark recommended):
  1. `patch — <current> → <X.Y.Z+1>` (mark Recommended if applicable)
  2. `minor — <current> → <X.Y+1.0>`
  3. `major — <current> → <X+1.0.0>`
  4. `Explicit version` — prompt for the exact string via Other
  5. `Abort`

Plain-text fallback: *"Bump type? (major / minor / patch / X.Y.Z / abort)"*

If the user picks explicit, validate: must be valid semver and strictly greater than current. If invalid, stop with an error.

## Step 4 — Compute New Version

Use the helper's `--dry-run` mode so version computation has one source of truth — Step 8 will repeat the call without `--dry-run` to actually write the file.

```bash
new_version=$(.hv/bin/hv-release-bump-version --dry-run <file> <kind> <bump>)
```

`<file>` and `<kind>` come from Step 2; `<bump>` is `patch`, `minor`, `major`, or the explicit semver from Step 3. The helper validates the bump (must be valid semver and strictly greater than `current` for the explicit path) and prints the new version. If validation fails, the helper exits 1 with a message — surface it and stop.

Store `new_version` for use in Steps 6, 7, 8, 9, 10, 11, 12, 13, 14.

If BREAKING CHANGE commits were detected (Step 3 scan) but the user chose `patch` or `minor`, interject with `AskUserQuestion` before continuing:
- **Header:** `"Breaking change detected"`
- **Question:** *"Commits contain `BREAKING CHANGE:` footers but bump type is `<chosen>`. Escalate to major?"*
- **Options:** `Escalate to major (Recommended)` / `Keep <chosen>` / `Abort`

## Step 5 — Detect Previous Tag

```bash
git describe --tags --abbrev=0 2>/dev/null || true
```

If empty (no tags exist), range = full history; set `prev_tag = ""`. Note this in the Step 14 summary. If a tag exists, set `prev_tag = <value>` and `range = <prev_tag>..HEAD`.

## Step 6 — Generate Release Notes

```bash
.hv/bin/hv-release-changelog-from-commits <range>
```

Captures categorized Markdown (buckets in helper-emit order: Breaking, New, Fixed, Performance, Changed, Documentation, Other). Merge commits are filtered by the helper.

**Compact dense buckets.** When a bucket has 3+ entries that clearly belong to the same feature or concern (e.g., 7 `feat:` commits all touching one new skill), replace the raw list with a single model-written summary line capturing the theme, optionally followed by 1-2 bullets naming the most significant pieces (a merge commit, a follow-up fix). Buckets with fewer than 3 entries stay as-is — the noise floor is low and the model adds little value. The helper's job is the raw categorization; *editorial collapse is yours*.

Append stats line — run:

```bash
git diff --shortstat <prev_tag>..HEAD   # omit <prev_tag>.. when no previous tag
```

Format as `## Stats\n<N commits, M files changed, +X −Y lines>`.

Build compare URL (only when `prev_tag` is non-empty):

```bash
.hv/bin/hv-release-detect-host
```

- `github` or `github-enterprise` → `https://<host>/<owner>/<repo>/compare/<prev_tag>...v<new_version>`
- `gitlab` or `gitlab-self-hosted` → `https://<host>/<owner>/<repo>/-/compare/<prev_tag>...v<new_version>`
- `none` → omit compare URL

Append `**Full changelog:** <compare-url>` to the notes (or omit if no prev tag or no host).

Prepend a model-written one-line summary scoped to the top 2-3 themes from the buckets. This summary also becomes the release title suffix in Step 13.

## Step 7 — Review Notes

Display the full notes draft to the user, then use `AskUserQuestion`:

- **Header:** `"Notes"`
- **Question:** *"Release `v<new_version>` — notes look good?"*
- **Options** (single-select):
  1. `Looks good (Recommended)`
  2. `Edit` — accept replacement text via Other (free-text replaces the draft verbatim)
  3. `Abort release`

Plain-text fallback: *"Proceed, edit, or abort?"*

If the user picks **Edit**, accept the replacement text and store it. Re-display the edited notes before continuing (no second prompt — one edit pass only).

If the user picks **Abort**, stop with one line: *"Release aborted. Nothing written."*

Write the (possibly edited) notes to a temp file:

```bash
NOTES_FILE=$(mktemp /tmp/hv-release-notes.XXXXXX.md)
```

## Step 8 — Update Version File

```bash
written=$(.hv/bin/hv-release-bump-version <file> <kind> <bump>)
```

Same arguments as Step 4's `--dry-run` call; this writes the file and prints the new version. Assert `written == new_version`; if they diverge, stop with an error (the file may be partially modified — surface the discrepancy and let the user investigate).

Skip in the skill's `--dry-run` mode (different from the helper's flag); print what would be written instead.

## Step 9 — Update CHANGELOG.md

```bash
.hv/bin/hv-release-update-changelog <new_version> "$NOTES_FILE" [--path <release.changelogPath>]
```

If exit 1 (version section already exists), surface the error and stop — do not proceed to commit.

Skip in `--dry-run` mode; print what would be prepended instead.

## Step 10 — Commit

```bash
git add <version-file> <release.changelogPath>
git commit -m "chore: release v<new_version>"
```

Skip in `--dry-run` mode.

## Step 11 — Tag

Check whether `user.signingkey` is set:

```bash
git config --get user.signingkey 2>/dev/null
```

If set, use `git tag -s`; otherwise `git tag -a`:

```bash
git tag [-a|-s] v<new_version> -F "$NOTES_FILE"
```

Skip in `--dry-run` mode; print the tag command that would run.

## Step 12 — Push

```bash
git push origin <current-branch> v<new_version>
```

Single call — pushes both the commit and the tag atomically. If this fails (e.g., origin not set), stop and print the tag SHA for manual recovery.

Skip in `--dry-run` mode.

## Step 13 — Create Remote Release

```bash
.hv/bin/hv-release-detect-host
```

Branch on output:

- **`github` or `github-enterprise`** →
  ```bash
  gh release create v<new_version> \
    --title "v<new_version> — <one-line summary>" \
    --notes-file "$NOTES_FILE" \
    [--draft]   # add when release.draft: true
  ```
  Capture the release URL.

- **`gitlab` or `gitlab-self-hosted`** →
  ```bash
  glab release create v<new_version> --notes "$(cat "$NOTES_FILE")"
  ```
  If `glab` is not on the PATH, print: *"glab not found. Create the release manually: `glab release create v<new_version> --notes-file <path>`"* and continue (don't fail the whole flow).

- **`none`** → print *"No recognized remote — skipping remote release creation."* and continue.

Release title: `v<new_version> — <one-line summary>` where summary comes from Step 6.

Skip in `--dry-run` mode; print the `gh`/`glab` command that would run.

## Step 14 — Summary

Print one compact block:

```
Released v<new_version>
  Tag:      v<new_version> (<tag-SHA>)
  Commit:   <commit-SHA>
  CHANGELOG: <release.changelogPath>
  Remote:   <release-URL or "skipped">
  [No previous tag — full history used as range.]   ← only when no prev tag
```

In `--dry-run` mode, prefix the block with `DRY RUN — no changes written.`

## Edge Cases

- **No previous tag** — full history range; add the one-liner to the Step 14 summary. Omit compare URL from notes.
- **Multiple version files** — currently first-match wins; set `release.versionFile` in `.hv/config.json` to pin the file explicitly.
- **Working tree dirty** — fail at Step 1 unless `release.requireCleanTree: false`; show `git status -s` in the error message.
- **BREAKING CHANGE with patch/minor bump** — escalate via `AskUserQuestion` in Step 4 before any writes.
- **`gh`/`glab` not installed but origin matches** — fail at Step 13 *after* tag push; print recovery: `gh release create v<X.Y.Z> --notes-file <path>` and the push-delete command to revert the tag if needed: `git push --delete origin v<X.Y.Z>`.
- **No origin** — Step 13 silently skipped; tag and CHANGELOG still committed locally.
- **CHANGELOG section already exists for this version** — helper exits 1 at Step 9; surface the error and stop.
- **Existing CHANGELOG.md without `# Changelog` header** — helper preserves existing content; inserts after H1 if present, else prepends.
- **Compare URL when no previous tag** — omit the `Full changelog:` line from the notes.

## Rules

- Never bump without an explicit user-confirmed bump type.
- Never push the tag without the user reviewing and approving release notes (Step 7).
- Never duplicate a CHANGELOG section — the helper enforces this; stop if it exits 1.
- Atomic writes only — all file mutations go through the helpers which use atomic write semantics.
- Surface failures from any helper immediately; do not continue past a non-zero exit.
- `--dry-run` skips all writes, commits, tags, and pushes — output shows what would happen.
