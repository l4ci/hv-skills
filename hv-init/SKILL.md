---
name: hv-init
description: Initialize the .hv/ folder structure with TODO.md, KNOWLEDGE.md, counters.json, config.json, status.json, and CLI helpers. Also seeds a managed knowledge-index block in CLAUDE.md so future /hv-work runs can consult learnings. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  🌱  hv-init  ·  initialize .hv/ folder structure
  triggers: auto-called by other hv skills  ·  pairs: all hv-*
════════════════════════════════════════════════════════════════════════
```

# hv-init — Initialize Project Backlog

Set up the `.hv/` folder with data files and CLI helpers for a project.

## Step 1 — Verify Environment

Make sure the tools we depend on are present — both are hard requirements:

```bash
command -v git >/dev/null 2>&1 || { echo "error: git is required but not installed" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required but not installed" >&2; exit 1; }
```

Then check whether the current directory is a git repo:

```bash
git rev-parse --git-dir >/dev/null 2>&1
```

If yes, continue to Step 2. Otherwise offer to initialize one — `/hv-work`, `/hv-debug`, `/hv-ship`, and `/hv-refactor` all require git, so without a repo only the backlog-capture subset works. Use `AskUserQuestion`:

- **Header:** `"Git"`
- **Question:** *"This directory isn't a git repository. Initialize one?"*
- **Options** (single-select):
  1. *"Yes, `git init` now (Recommended)"* — *"Enables all hv skills. Reversible with `rm -rf .git`."*
  2. *"No, backlog-only"* — *"Skip init; capture/next/learn/status still work. Git skills fail until you init manually."*
  3. *"Stop"* — *"Cancel `/hv-init`."*

On **Yes** — run `git init`, continue to Step 2, mention the created branch in the Step 5 summary. On **No** — continue but warn: *"Warning: not a git repository. /hv-work, /hv-debug, /hv-ship, /hv-refactor will fail until you run `git init`."* On **Stop** — exit.

Plain-text fallback: run `git init` straight through — it's the Recommended choice and reversible.

## Step 1.5 — Umbrella Detection (Optional)

If the current directory holds **two or more immediate child directories that are themselves git repos**, this is likely a multi-repo umbrella — `.hv/` should live here, but git operations should run inside the relevant sub-repo. Detect by scanning `*/.git`:

```bash
UMBRELLA_CANDIDATES=$(find . -maxdepth 2 -mindepth 2 -name .git -printf '%h\n' 2>/dev/null | sed 's|^\./||' | sort)
UMBRELLA_COUNT=$(echo "$UMBRELLA_CANDIDATES" | grep -c . || true)
```

If `UMBRELLA_COUNT >= 2`, offer umbrella mode via `AskUserQuestion`. Skip silently for 0 or 1 — that's the single-repo path and Step 1's git check covers it.

- **Header:** `"Umbrella"`
- **Question:** *"Found multiple git repos here: <list>. Enable umbrella mode? (`.hv/` stays at this level; helpers operate per sub-repo.)"*
- **Options** (single-select):
  1. *"Yes, enable umbrella mode (Recommended)"* — *"Registers child repos via `hv-umbrella-init` after bootstrap. Sets `umbrella.enabled: true` in config."*
  2. *"No, single-repo init"* — *"Skip umbrella; `/hv-init` proceeds as if the umbrella detection didn't fire. Existing single-repo behavior."*

On **Yes** — set `UMBRELLA_MODE=true` and `UMBRELLA_REGISTER="all"` (or ask a follow-up multiSelect to pick a subset of `$UMBRELLA_CANDIDATES`; `"all"` is the simpler default). Continue to Step 2.

On **No** — set `UMBRELLA_MODE=false`, continue to Step 2 unchanged.

Plain-text fallback: if `UMBRELLA_COUNT >= 2`, default to **Yes** with `UMBRELLA_REGISTER="all"` — it's the Recommended path and reversible by re-running `/hv-init` then choosing No, or by toggling `umbrella.enabled` via `/hv-config`.

## Step 2 — Bootstrap & Install Helpers

Resolve the source `bin/` from the installed plugin, then run `hv-bootstrap` to seed `.hv/` and copy every helper into `.hv/bin/`. Source resolution order: `$CLAUDE_PLUGIN_ROOT/bin/` first, then standard install locations, then a repo-local clone.

```bash
SRC=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/bin" ]; then
  SRC="$CLAUDE_PLUGIN_ROOT/bin"
else
  for candidate in \
    "$HOME"/.claude/plugins/*/hv-skills/bin \
    "$HOME"/.claude/plugins/hv-skills/bin \
    "$HOME"/.agents/skills/hv-skills/bin \
    "$HOME"/.agents/skills/bin; do
    [ -d "$candidate" ] && SRC="$candidate" && break
  done
fi
[ -z "$SRC" ] && { echo "error: could not locate hv-skills bin/ — set CLAUDE_PLUGIN_ROOT or install the plugin" >&2; exit 1; }

# Seed directories and data files (idempotent — never overwrites existing files).
"$SRC/hv-bootstrap"

# Install / refresh helpers — they're tools, not data.
cp "$SRC"/hv-* "$SRC"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
```

If Step 1.5 set `UMBRELLA_MODE=true`, register the sub-repos now (after bootstrap so `.hv/` exists):

```bash
if [ "${UMBRELLA_MODE:-false}" = "true" ]; then
  echo "$UMBRELLA_REGISTER" | .hv/bin/hv-umbrella-init >/dev/null
fi
```

The helper writes `.hv/repos.json` and (if the umbrella is itself a git repo) appends `.claude/`, `.hv/`, and `/<repo>/` lines to the umbrella's `.gitignore` under a `# ── hv umbrella ──` header. Idempotent — re-running `/hv-init` is safe.

`hv-bootstrap` creates `.hv/{bugs,features,tasks,milestones,plans,spikes,bin}`, seeds `TODO.md` / `KNOWLEDGE.md` / `MILESTONES.md` / `counters.json` / `status.json` if absent, adds `.hv/` to `.gitignore`, and runs the legacy preamble migration (`/hv:X` → `/hv-X` above the first `## Topic` heading). Data files are never overwritten. `config.json` is created interactively in the next step. All helpers require `python3`. See [`docs/reference/cli-helpers.md`](../docs/reference/cli-helpers.md) for the full helper reference.

## Step 3 — Configure (Interactive, with Upgrade Migration)

Detect the current config state — fresh projects take the full interactive path; upgrading projects keep every prior value and are only prompted for keys added since their config was written:

```bash
python3 - <<'PY'
import json
from pathlib import Path

EXPECTED = [
    ("models", "orchestrator"),
    ("models", "worker"),
    ("work", "isolation"),
    ("work", "mergeStrategy"),
    ("refactor", "confirmBeforeExecute"),
    ("learn", "verify"),
    ("ship", "review"),
    ("autonomy", "level"),
    ("debug", "competingHypotheses"),
    ("docs", "path"),
    ("docs", "autoCreate"),
    ("git", "baseBranch"),
    ("umbrella", "enabled"),
]
p = Path(".hv/config.json")
if not p.exists():
    print("FRESH"); raise SystemExit
try:
    cfg = json.loads(p.read_text())
    if not isinstance(cfg, dict): raise ValueError
except Exception:
    print("CORRUPT"); raise SystemExit
missing = [f"{s}.{k}" for s, k in EXPECTED
           if not isinstance(cfg.get(s), dict) or cfg.get(s, {}).get(k) is None]
print("UP_TO_DATE" if not missing else "STALE:" + ",".join(missing))
PY
```

Branch on the output:

- `UP_TO_DATE` — existing config already matches the current schema. Skip the rest of this step.
- `CORRUPT` — the file exists but isn't valid JSON. Tell the user to fix or delete `.hv/config.json`, then rerun `/hv-init`. Stop.
- `FRESH` — no config yet. Ask all five questions below, then write the full config (FRESH write block).
- `STALE:key1,key2,…` — upgrade path. Ask **only** the questions that map to the listed missing keys, then merge the answers into the existing file via the STALE write block — every value already in the file stays untouched.

Call `AskUserQuestion` with just the applicable questions in one call. The "(Recommended)" option on each is the current default; selecting it (or "Other" with no alternative) writes the default value. The user can decline with the native "skip" — if that happens, write the Recommended defaults for the pending keys only.

**Q1 — Models** (`header: "Models"`, single-select)

> *"Which model profile should hv-skills use for orchestration and implementation?"*

| Label | Description |
|-------|-------------|
| Balanced — Opus + Sonnet (Recommended) | Opus plans and verifies, Sonnet executes. Strong reasoning where it matters; fast execution elsewhere. |
| Premium — Opus only | Opus for everything. Highest quality, highest cost. |
| Fast — Sonnet only | Sonnet for both roles. Faster and cheaper; fine for well-specified tasks. |
| Minimal — Sonnet + Haiku | Sonnet plans, Haiku executes. Cheapest. Best for mechanical, low-risk work. |

**Q2 — Isolation** (`header: "Isolation"`, single-select)

> *"How should `/hv-work` isolate changes from main?"*

| Label | Description |
|-------|-------------|
| Branch (Recommended) | Feature branch in the current worktree. Simple, works everywhere. |
| Worktree | Isolated directory under `.claude/worktrees/`. Lets you keep using main while agents work; supports parallel sessions. |

**Q3 — Integration** (`header: "Integration"`, single-select)

> *"How should `/hv-work` and `/hv-ship` integrate finished work?"*

| Label | Description |
|-------|-------------|
| Direct merge (Recommended) | Merge into main with `--no-ff` and delete the branch. Fast solo iteration. |
| GitHub PR | Push the branch and open a PR with `gh pr create`. Required for team review. |

**Q4 — Quality gates** (`header: "Gates"`, `multiSelect: true`)

> *"Which quality gates should run by default? (Uncheck anything you want off.)"*

| Label | Description |
|-------|-------------|
| Review before ship (Recommended) | `/hv-ship` runs `/hv-review` first. FAIL blocks, CONCERNS ask, PASS flows through. |
| Verify learnings (Recommended) | `/hv-learn` dispatches an Opus verifier for a cold pass on new entries. Knowledge quality compounds. |
| Confirm before refactor (Recommended) | `/hv-refactor` pauses for approval after finding friction and after selecting a design. Off = full autonomy. |
| Competing hypotheses (debug) | `/hv-debug` dispatches 3 parallel hypothesis agents from different angles. Better diversity on hard bugs, ~3× orchestrator cost. |

**Q5 — Autonomy** (`header: "Autonomy"`, single-select)

> *"How autonomously should hv-skills chain to the next logical step?"*

| Label | Description |
|-------|-------------|
| Off (Recommended) | Skills nudge with a one-line suggestion at decision points. You stay in the driver's seat. |
| Auto chain | One-hop chaining: `/hv-work` → `/hv-learn`, `/hv-debug` → `/hv-ship`, `/hv-ship` → `/hv-learn`, refactor threshold → `/hv-refactor`. Stops after the chained step. |
| Full loop | Auto chain + after each cycle, invoke `/hv-next` and start the next item. Runs until the backlog drains, a guard fails, or a brief is genuinely ambiguous. |

Map answers to config values:

| Answer | Config |
|--------|--------|
| Q1 Balanced | `models: {orchestrator: "opus", worker: "sonnet"}` |
| Q1 Premium | `models: {orchestrator: "opus", worker: "opus"}` |
| Q1 Fast | `models: {orchestrator: "sonnet", worker: "sonnet"}` |
| Q1 Minimal | `models: {orchestrator: "sonnet", worker: "haiku"}` |
| Q2 Branch | `work.isolation: "branch"` |
| Q2 Worktree | `work.isolation: "worktree"` |
| Q3 Direct merge | `work.mergeStrategy: "direct"` |
| Q3 GitHub PR | `work.mergeStrategy: "pr"` |
| Q4 includes "Review before ship" | `ship.review: true` (else `false`) |
| Q4 includes "Verify learnings" | `learn.verify: true` (else `false`) |
| Q4 includes "Confirm before refactor" | `refactor.confirmBeforeExecute: true` (else `false`) |
| Q4 includes "Competing hypotheses" | `debug.competingHypotheses: true` (else `false`) |
| Q5 Off | `autonomy.level: "off"` |
| Q5 Auto chain | `autonomy.level: "auto"` |
| Q5 Full loop | `autonomy.level: "loop"` |

If the user picked "Other" with custom text, honor it only if it's a valid value for that key (`"opus"/"sonnet"/"haiku"`, `"branch"/"worktree"`, `"direct"/"pr"`, `"off"/"auto"/"loop"`); otherwise silently fall back to the Recommended value.

Plain-text fallback: write the Recommended defaults for any pending keys — don't stall the init on a missing tool.

### FRESH write block

Write the full resolved config:

```bash
python3 - <<PY
import json
import os
from pathlib import Path
umbrella_enabled = os.environ.get("UMBRELLA_MODE", "false").lower() == "true"
cfg = {
  "models":   {"orchestrator": "<Q1-orchestrator>", "worker": "<Q1-worker>"},
  "work":     {"isolation": "<Q2>", "mergeStrategy": "<Q3>"},
  "refactor": {"confirmBeforeExecute": <Q4-refactor>},
  "learn":    {"verify": <Q4-learn>},
  "ship":     {"review": <Q4-ship>},
  "autonomy": {"level": "<Q5>"},
  "debug":    {"competingHypotheses": <Q4-debug>},
  "docs":     {"path": "docs", "autoCreate": False},
  "git":      {"baseBranch": ""}
}
cfg.setdefault("umbrella", {})["enabled"] = umbrella_enabled
Path(".hv/config.json").write_text(json.dumps(cfg, indent=2) + "\n")
PY
```

Read `umbrella_enabled` from the `UMBRELLA_MODE` shell var Step 1.5 set (default `false` when single-repo). `UMBRELLA_MODE` must be exported (`export UMBRELLA_MODE=true`) before the heredoc runs so the Python subprocess inherits it.

### STALE write block

Read the existing file, merge only the keys the user answered (or Recommended defaults for any they skipped), preserve everything else:

```bash
python3 - <<PY
import json, os
from pathlib import Path
p = Path(".hv/config.json")
cfg = json.loads(p.read_text())

# Example: user answered Q4 "Review before ship" → ship.review was missing.
# Set only the keys from the STALE list; never overwrite existing values.
cfg.setdefault("ship", {})["review"] = True   # or answered value

# umbrella.enabled — honor UMBRELLA_MODE from Step 1.5 (re-run from an umbrella
# with "Yes" answers sets it to true). Default false on upgrade when the env var
# is unset (no migration prompt for users who didn't re-run from a parent).
cfg.setdefault("umbrella", {})["enabled"] = os.environ.get("UMBRELLA_MODE", "false") == "true"

p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
```

Rule: for each missing key in the `STALE:` list, do exactly one `cfg.setdefault(section, {})[key] = value` write. Never touch keys that were already present. `umbrella.enabled` is a special case — when missing on upgrade, honor `UMBRELLA_MODE` from Step 1.5 (default `False` when unset, `True` when the user opted in via Step 1.5's prompt). Re-running `/hv-init` from an umbrella with the "Yes" answer is the only path that flips it on; manual flips also possible via `/hv-config`.

Briefly confirm the chosen profile in the Step 5 summary. On a FRESH run with all Recommended, just show *"Config: defaults."*; on a STALE migration, list the added keys — *"Config migrated: added `ship.review` (Recommended)."* so the user knows what changed.

## Step 4 — Seed CLAUDE.md Skills, Knowledge, Vision & Decisions Blocks

Seed four managed blocks in `CLAUDE.md` (created if missing): the hv-skills slash-command index (static), knowledge topics (`/hv-learn`), active milestones (`/hv-vision`), and decision topics (`/hv-decide`). The skills block tells Claude *what* commands are available; the others tell it *what to consult* per work topic.

```bash
.hv/bin/hv-skills-index
.hv/bin/hv-knowledge-index
.hv/bin/hv-vision-index
.hv/bin/hv-decisions-index
```

Each helper creates, updates in place, or appends its own block. Other `CLAUDE.md` content is untouched.

## Step 5 — Confirm

Tell the user one compact block:

```
Initialized .hv/ in <project>.
Config: <summary — "defaults" if all Recommended, else a one-liner e.g. "Balanced models, worktree isolation, PR merges, verifier on">.
Next: /hv-capture to add items, /hv-next to pick work, /hv-learn to save learnings.
Edit .hv/config.json to change any of these later.
```

If `.hv/TODO.md` already existed, say it was already initialized and helper scripts were refreshed. Then:

- **Config up-to-date** → drop the config line entirely; nothing was asked.
- **Config migrated (STALE)** → replace the config line with *"Config migrated: added `<keys>` (Recommended)."* listing whichever keys were added.
- **Config fresh (no existing `.hv/config.json` despite an existing `TODO.md`)** → report as on a fresh init.

If `UMBRELLA_MODE=true` (Step 1.5 accepted), append one extra line to the summary block — *"Umbrella mode enabled — registered sub-repos: <list from `.hv/repos.json`>"* — read the list via `python3 -c 'import json; print(", ".join(r["name"] for r in json.load(open(".hv/repos.json"))["repos"]))'`. Otherwise omit.

Config keys: `models.{orchestrator,worker}`, `work.{isolation,mergeStrategy}`, `refactor.confirmBeforeExecute`, `learn.verify`, `ship.review`, `autonomy.level`, `debug.competingHypotheses`, `docs.{path,autoCreate}`, `git.baseBranch`, `umbrella.enabled`. See [`docs/usage/configuration.md`](../docs/usage/configuration.md) for the full reference.
