---
name: hv-update
description: Check for a newer hv-skills release on GitHub and tell the user how to update — detects install type (plugin, stow, repo clone), compares plugin.json version against the latest release, and prints the exact update command. Read-only; does not run the update itself. Use on "check for updates", "is hv-skills up to date", before long /hv-work sessions.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🆙  hv-update  ·  check for newer hv-skills release
  triggers: "check for updates"  ·  pairs: —
════════════════════════════════════════════════════════════════════════
```

# hv-update — Check for hv-skills Updates

## When NOT to Use

- You explicitly pinned to an older version → skip this
- Offline / airgapped session → the check will fail gracefully but isn't useful

## Step 1 — Preflight

Requires `gh` on the `PATH`:

```bash
command -v gh >/dev/null 2>&1 || echo "gh not installed"
```

If missing, tell the user the check needs `gh` (or `brew install gh` / equivalent) and stop. Don't try to `curl` the GitHub API — users with `gh` get auth'd rate limits for free.

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

## Step 2 — Run the Check

```bash
.hv/bin/hv-update-check
```

Parses JSON output:

- `installType` — `plugin` | `stow` | `repo` | `override` | `unknown`
- `installRoot` — absolute path to the detected install
- `currentVersion` — semver from `plugin.json`
- `latestVersion` — semver of the latest GitHub release (empty if fetch failed)
- `status` — `behind` | `current` | `ahead` | `unknown`
- `updateCommand` — the exact shell command for the detected install type

## Step 3 — Present Verdict

One compact block. Adapt wording to `status`:

**`current`:**

```
hv-skills 1.2.0 — up to date.
Installed as plugin at ~/.claude/plugins/hv-skills.
```

**`behind`:**

```
hv-skills update available: 1.2.0 → 1.3.0
Installed as plugin at ~/.claude/plugins/hv-skills.

Update:
  claude plugin update hv-skills

After updating, run /hv-init in your project to refresh .hv/bin/ helpers.
```

**`ahead`:**

```
hv-skills 1.3.0 — ahead of the latest release (1.2.0).
Likely a local dev build or unpushed repo clone.
```

**`unknown`:**

```
Could not determine update status.
Current: <version or "unknown">
Latest: <not reachable — check `gh auth status` or network>
```

## Step 4 — Offer to Re-Init

Apply only when Step 2's `status` is `behind`. Skip entirely on `current`, `ahead`, or `unknown` — there's nothing to refresh.

Read `.hv/config.json#autonomy.level` (default `"off"`) and branch:

**`"off"` (default):**

Print one nudge line after the verdict block:

> After running the update command above, re-run `/hv-init` in this project to refresh `.hv/bin/` helpers and clear the drift nudge.

Don't auto-invoke. The user may want to update multiple projects before re-initialising any of them.

**`"auto"`:**

Use `AskUserQuestion`:

- **Header:** `"Re-init"`
- **Question:** *"Plugin update is `<current> → <latest>`. Already ran `claude plugin update hv-skills`? Run `/hv-init` now to refresh `.hv/bin/` helpers in this project?"*
- **Options** (single-select):
  1. *"Yes, run `/hv-init` now (Recommended)"* — *"Refreshes `.hv/bin/` and re-stamps `hvSkills.version` so drift detection clears."*
  2. *"Not yet — I'll run the update first"* — *"Skip; re-invoke `/hv-update` after running the update command."*
  3. *"Skip — I'll run `/hv-init` later"* — *"No-op; the drift nudge will keep firing on every preflight until then."*
- Plain-text fallback: ask once textually — *"Already ran `claude plugin update hv-skills`? Run `/hv-init` now to refresh helpers? (yes/no)"* — honor yes/no, default off (don't dispatch on ambiguous reply).

On answer 1: **dispatch `hv-init` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass no args (the skill knows what to do from cwd).

**`"loop"`:**

Skip the question entirely. Print one informational line first so the user sees the pick:

> Loop: dispatching `/hv-init` to refresh helpers (assumes plugin update already ran).

Then **dispatch `hv-init` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass no args.

If the plugin actually wasn't updated, `/hv-init`'s STALE migration just re-stamps the same version and is a no-op for everything else — the loop contract trades that edge case for full chaining.

---

Across projects: each project tracks its own `hvSkills.version`. Updating the plugin once leaves all projects drifted; re-run `/hv-init` per project to clear them.

## Rules

- **Read-only.** Never invoke the update command yourself. Surface it, let the user run it.
- **Network-dependent.** If `gh` can't reach the API, report `unknown` and stop — don't retry on a loop.
- **Honor dev builds.** An `ahead` status is not an error; contributors run that way.
- **Helpers refresh is separate.** Upgrading the plugin does not rewrite `.hv/bin/` in existing projects. Step 4 nudges (off), asks (auto), or auto-dispatches `/hv-init` (loop) — but per project. Multi-project users still re-run `/hv-init` in each project explicitly.
