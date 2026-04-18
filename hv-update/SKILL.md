---
name: hv:update
description: Check for a newer hv-skills release on GitHub and tell the user how to update — detects install type (plugin, stow, repo clone), compares plugin.json version against the latest release, and prints the exact update command. Read-only; does not run the update itself. Use on "check for updates", "is hv-skills up to date", before long /hv:work sessions.
user-invocable: true
---

# hv:update — Check for hv-skills Updates

Diagnose whether the installed hv-skills is current, and tell the user how to update if not. Never runs the update itself — too many install paths to get right automatically.

## When to Use

- Before starting a long `/hv:work` session and you want current helpers
- *"Is hv-skills up to date?"*, *"Check for updates"*, *"What version am I on?"*
- After noticing a skill behaves unexpectedly — maybe the install is stale

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

If the helper is absent or exits non-zero, invoke `hv:init` via the `Skill` tool to refresh helpers, then continue. See GUIDE.md § Preflight for exit codes.

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

After updating, run /hv:init in your project to refresh .hv/bin/ helpers.
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

Only when `status` is `behind` and the user has run the update command: a fresh release may ship new helpers or config defaults. Tell them to run `/hv:init` in each project that uses hv-skills to refresh `.hv/bin/` scripts.

Don't auto-invoke `/hv:init` — the user may want to update multiple projects.

## Rules

- **Read-only.** Never invoke the update command yourself. Surface it, let the user run it.
- **Network-dependent.** If `gh` can't reach the API, report `unknown` and stop — don't retry on a loop.
- **Honor dev builds.** An `ahead` status is not an error; contributors run that way.
- **Helpers refresh is separate.** Upgrading the plugin does not rewrite `.hv/bin/` in existing projects. The user runs `/hv:init` per project to pick up new helpers.
