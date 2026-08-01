---
name: hv-init
description: Initialize the .hv/ folder structure with BACKLOG.md, KNOWLEDGE.md, counters.json, config.json, status.json, and CLI helpers. Also seeds a managed knowledge-index block in CLAUDE.md so future /hv-work runs can consult learnings. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

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

Then run both state checks before deciding which prompt (if any) to issue:

```bash
# Is the cwd already a git repo?
git rev-parse --git-dir >/dev/null 2>&1 && IS_GIT_REPO=true || IS_GIT_REPO=false

# Are there 2+ immediate child git repos? (umbrella signal)
UMBRELLA_CANDIDATES=$(find . -maxdepth 2 -mindepth 2 -name .git -printf '%h\n' 2>/dev/null | sed 's|^\./||' | sort)
UMBRELLA_COUNT=$(echo "$UMBRELLA_CANDIDATES" | grep -c . || true)
```

Branch on the combination of `IS_GIT_REPO` and `UMBRELLA_COUNT`:

**Case A — `IS_GIT_REPO=true` and `UMBRELLA_COUNT < 2`:** Continue silently to Step 2. No prompt.

**Case B — `IS_GIT_REPO=true` and `UMBRELLA_COUNT >= 2`:** This is an existing git repo that also holds sub-repos. Offer umbrella mode via `AskUserQuestion`:

- **Header:** `"Umbrella"`
- **Question:** *"Found multiple git repos here: \<list\>. Enable umbrella mode? (`.hv/` stays at this level; helpers operate per sub-repo.)"*
- **Options** (single-select):
  1. *"Yes, enable umbrella mode (Recommended)"* — *"Registers child repos via `hv-umbrella-init` after bootstrap. Sets `umbrella.enabled: true` in config."*
  2. *"No, single-repo init"* — *"Skip umbrella; `/hv-init` proceeds as if the umbrella detection didn't fire. Existing single-repo behavior."*

On **Yes** — set `UMBRELLA_MODE=true` and `UMBRELLA_REGISTER="all"` (or ask a follow-up multiSelect to pick a subset of `$UMBRELLA_CANDIDATES`; `"all"` is the simpler default). Continue to Step 2. On **No** — set `UMBRELLA_MODE=false`, continue to Step 2 unchanged.

Plain-text fallback: ask once textually — *"Found N git repos here: \<list\>. Enable umbrella mode? (yes/no)"* — and honor the user's reply. If no reply is captured, default to **No** with a one-line follow-up note: *"Skipping umbrella mode. Re-run `/hv-init` from this cwd to enable, or toggle `umbrella.enabled` via `/hv-config` later."* The default is **No** rather than Yes because `umbrella.enabled` is an opt-in feature flag — per the *Authoring conventions / Opt-in feature flags default to `false`* rule, the cwd signal alone is not user approval; explicit user approval is required.

**Case C — `IS_GIT_REPO=false` and `UMBRELLA_COUNT < 2`:** This directory isn't a git repo and has at most 1 sub-repo. Offer to initialize one — `/hv-work`, `/hv-debug`, `/hv-ship`, and `/hv-refactor` all require git, so without a repo only the backlog-capture subset works. Use `AskUserQuestion`:

- **Header:** `"Git"`
- **Question:** *"This directory isn't a git repository. Initialize one?"*
- **Options** (single-select):
  1. *"Yes, `git init` now (Recommended)"* — *"Enables all hv skills. Reversible with `rm -rf .git`."*
  2. *"No, backlog-only"* — *"Skip init; capture/next/learn/status still work. Git skills fail until you init manually."*
  3. *"Stop"* — *"Cancel `/hv-init`."*

On **Yes** — run `git init`, set `UMBRELLA_MODE=false`, continue to Step 2, mention the created branch in the Step 5 summary. On **No** — set `UMBRELLA_MODE=false`, continue but warn: *"Warning: not a git repository. /hv-work, /hv-debug, /hv-ship, /hv-refactor will fail until you run `git init`."* On **Stop** — exit.

Plain-text fallback: run `git init` straight through — it's the Recommended choice and reversible.

**Case D — `IS_GIT_REPO=false` and `UMBRELLA_COUNT >= 2`:** This is the non-git umbrella greenfield case. Both conditions are true simultaneously, so fold them into a single `AskUserQuestion` call instead of two separate prompts. Build a short candidate list for the question text — use the first 3 candidate names; if there are 4+, append *"and N more"* so the prompt stays readable. Use `AskUserQuestion`:

- **Header:** `"Setup"`
- **Question:** *"Found multiple git repos here: `<comma-separated list, max 3 names, plus 'and N more' if 4+>`. This directory isn't itself a git repo. How should `/hv-init` set up?"*
- **Options** (single-select):
  1. *"Umbrella mode (Recommended)"* — *"Register the child repos via `hv-umbrella-init`; `.hv/` stays here. No `git init` at this level — the umbrella is intentionally a non-git wrapper."*
  2. *"`git init` here, single-repo"* — *"Initialize this directory as a git repo; ignore sub-repos. Use this if the sub-repos are accidental (vendored, leftover clones)."*
  3. *"Skip git, backlog-only"* — *"Don't `git init`, don't enable umbrella. Capture/next/learn/status work; `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-refactor` fail until you init manually."*
  4. *"Stop"* — *"Cancel `/hv-init`."*

Routing per answer:
- Option 1 (Umbrella) → set `UMBRELLA_MODE=true`, `UMBRELLA_REGISTER="all"`; continue to Step 2.
- Option 2 (git init single-repo) → run `git init`, set `UMBRELLA_MODE=false`; mention the created branch in the Step 5 summary; continue to Step 2.
- Option 3 (backlog-only) → set `UMBRELLA_MODE=false`; warn *"Warning: not a git repository. /hv-work, /hv-debug, /hv-ship, /hv-refactor will fail until you run `git init`."*; continue to Step 2.
- Option 4 (Stop) → exit `/hv-init`.

Plain-text fallback: ask once textually — *"Found N git repos here: `<list>`. This directory isn't a git repo. (1) Umbrella mode, (2) git init here, (3) Skip git, (4) Stop?"* — and honor a number or first-word reply. If no reply is captured, default to **Option 1 (Umbrella)** with a one-line note: *"Defaulting to umbrella mode — `.hv/` will stay here and child repos will be registered. Re-run `/hv-init` to change."* The Recommended option is the default for a no-reply situation per the AUQ fallback convention (`references/ask-user-question-fallback.md`).

> **Architecture rule — umbrella mode does not use git submodules.** Sub-repos under an umbrella are independent git repositories with no version-pinning at the umbrella level.
>
> *Why.* Submodules add version-pin friction (surprise-checkouts when SHAs drift, manual `git submodule update` discipline) and couple sub-repo evolution to umbrella commits — the wrong dependency direction. hv-skills's wedge is shared **coordinator + knowledge + decisions** at the umbrella, not shared version state.
>
> **Forbids.** `git submodule add` anywhere in an umbrella tree; `.gitmodules` at the umbrella root; "umbrella commit pins sub-repo SHA" patterns; designs that synchronize or pin sub-repo versions through the umbrella.
>
> **Permits.** Independent sub-repos checked out side-by-side under the umbrella; registry via `.hv/repos.json` by absolute or relative path; each sub-repo evolving on its own branch/tag/release schedule; sub-repos that are themselves submodule-using internally — the boundary applies *between umbrella and direct children*, not inside any sub-repo.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Detect* — environment + umbrella decision (Step 1)
2. *Write artifacts* — bootstrap `.hv/` and install helpers (Step 2)
3. *Configure* — interactive config (FRESH or STALE migration, Step 3)
4. *Seed CLAUDE.md blocks* — skills, knowledge, vision, decisions, map, context indices (Step 4)

## Step 2 — Bootstrap & Install Helpers

Resolve the source `bin/` from the installed plugin, then run `hv-bootstrap` to seed `.hv/` and copy every helper into `.hv/bin/`. Source resolution order: `$CLAUDE_PLUGIN_ROOT/bin/` first, then standard install locations, then a repo-local clone.

```bash
# Mirror of bin/hv-resolve-plugin-root --bin — kept inline for bootstrap
# (hv-init runs before .hv/bin/ exists, so the helper isn't callable yet).
# Order MUST match hvlib.resolve_plugin_root: HV_INSTALL_ROOT override,
# CLAUDE_PLUGIN_ROOT, ~/.claude/plugins/*/hv-skills, ~/.claude/plugins/hv-skills,
# ~/.claude/plugins/cache/hv-skills/hv-skills/<version>/, ~/.agents/skills/...
SRC=""
if [ -n "${HV_INSTALL_ROOT:-}" ] && [ -d "$HV_INSTALL_ROOT/bin" ]; then
  SRC="$HV_INSTALL_ROOT/bin"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/bin" ]; then
  SRC="$CLAUDE_PLUGIN_ROOT/bin"
else
  for candidate in \
    "$HOME"/.claude/plugins/*/hv-skills/bin \
    "$HOME"/.claude/plugins/hv-skills/bin; do
    [ -d "$candidate" ] && SRC="$candidate" && break
  done
  # Claude Code plugin cache: pick the newest installed version.
  # Glob loop, not `ls | sort -V | tail -1` — the latter aborts under
  # set -euo pipefail when the glob misses (ls exits 2, propagates up the
  # command substitution). Iteration order is lexicographic, so the last
  # match wins — good enough since the cache normally holds one version
  # at a time; mirrors bin/hv-preflight's idiom. The strict resolver in
  # hvlib.resolve_plugin_root uses tuple-of-int version-sort for full
  # accuracy across double-digit minors.
  if [ -z "$SRC" ]; then
    for cand in "$HOME"/.claude/plugins/cache/hv-skills/hv-skills/*/bin; do
      [ -d "$cand" ] && SRC="$cand"
    done
  fi
  if [ -z "$SRC" ]; then
    for candidate in \
      "$HOME"/.agents/skills/hv-skills/bin \
      "$HOME"/.agents/skills/bin; do
      [ -d "$candidate" ] && SRC="$candidate" && break
    done
  fi
fi
[ -z "$SRC" ] && { echo "error: could not locate hv-skills bin/ — set CLAUDE_PLUGIN_ROOT or install the plugin" >&2; exit 1; }

# Stamp the resolved plugin's version so Step 3 can record it in config.json.
HV_PLUGIN_VERSION=$(python3 -c "
import json
try:
    print(json.load(open('$SRC/../.claude-plugin/plugin.json')).get('version', ''))
except Exception:
    print('')
" 2>/dev/null || true)
export HV_PLUGIN_VERSION

# Seed directories and data files (idempotent — never overwrites existing files).
"$SRC/hv-bootstrap"

# Install / refresh helpers — strict mirror of canonical bin/, not just an overlay.
# Step 1: strip stale helpers so renamed/cut binaries (e.g. v3 → v4) don't linger.
# Step 2: copy fresh helpers from $SRC and chmod +x. Two-step is intentional —
# a brief window exists where .hv/bin/ has no helpers, irrelevant since /hv-init
# is not concurrent-safe by design.
find .hv/bin/ -maxdepth 1 \( -name 'hv-*' -o -name 'hvlib*.py' \) -type f -delete
cp "$SRC"/hv-* "$SRC"/hvlib*.py .hv/bin/ && chmod +x .hv/bin/hv-*
```

If Step 1 set `UMBRELLA_MODE=true`, register the sub-repos now (after bootstrap so `.hv/` exists):

```bash
if [ "${UMBRELLA_MODE:-false}" = "true" ]; then
  echo "$UMBRELLA_REGISTER" | .hv/bin/hv-umbrella-init >/dev/null
fi
```

The helper writes `.hv/repos.json` and (if the umbrella is itself a git repo) appends `.claude/`, `.hv/`, and `/<repo>/` lines to the umbrella's `.gitignore` under a `# ── hv umbrella ──` header. Idempotent — re-running `/hv-init` is safe.

`hv-bootstrap` creates `.hv/{bugs,features,tasks,milestones,plans,spikes,map,bin}`, seeds `BACKLOG.md` / `KNOWLEDGE.md` / `DECISIONS.md` / `MILESTONES.md` / `MAP.md` / `counters.json` / `status.json` if absent, adds per-file ignores for `.hv/bin/`, `.hv/status.json`, `.hv/repos.json`, `.hv/config.local.json`, `.hv/handoff/`, `.hv/qa-runs/`, and `.hv/**/*.lock` to `.gitignore` under a `# ── hv-skills ──` header (the rest of `.hv/` is tracked so backlog and knowledge travel with the repo), and runs the legacy preamble migration (`/hv:X` → `/hv-X` above the first `## Topic` heading). Data files are never overwritten; legacy blanket `.hv/` lines in `.gitignore` are stripped so the per-file pattern takes effect. `config.json` is created interactively in the next step. All helpers require `python3`. See [`docs/reference/cli-helpers.md`](../docs/reference/cli-helpers.md) for the full helper reference.

`.hv/bin/` is strictly canonical-mirrored — every `/hv-init` run strips matching `hv-*` and `hvlib*.py` files (the `hvlib*` glob catches the split modules `hvlib.py`, `hvlib_io.py`, `hvlib_version.py`), then copies fresh from `$SRC`. Custom helpers dropped there will be removed on next `/hv-init`; place your own scripts outside `.hv/`. Non-`hv-*` files (notably `__pycache__/`, generated by Python at runtime) survive untouched. If a future canonical `bin/` introduces patterns outside `hv-*` and `hvlib*.py`, update the mirror's `find` filter alongside.

## Step 3 — Configure (Interactive, with Upgrade Migration)

Detect the current config state — fresh projects take the full interactive path; upgrading projects keep every prior value and are only prompted for keys added since their config was written:

```bash
.hv/bin/hv-config-schema-check
```

The helper owns the expected-key list — see `bin/hv-config-schema-check` for the canonical `EXPECTED` tuples. Output: `FRESH` | `UP_TO_DATE` | `STALE:<sec>.<key>,...` | `CORRUPT`.

Branch on the output:

- `UP_TO_DATE` — existing config already matches the current schema. Skip the rest of this step.
- `CORRUPT` — the file exists but isn't valid JSON. Tell the user to fix or delete `.hv/config.json`, then rerun `/hv-init`. Stop.
- `FRESH` — no config yet. Ask all five questions below, then write the full config (FRESH write block).
- `STALE:key1,key2,…` — upgrade path. Ask **only** the questions that map to the listed missing keys, then merge the answers into the existing file via the STALE write block — every value already in the file stays untouched.

Call `AskUserQuestion` with the applicable questions in one call. Use the question wording and option vocabulary from [`docs/reference/config-options.md`](../docs/reference/config-options.md) — that page is the canonical source for Q1–Q5 labels, descriptions, and the mapping from answers to JSON config values. The reference also covers the `/hv-config` validation rules (Other-with-valid-value handling, plain-text fallback to Recommended defaults) so they need not be restated here.

On `FRESH`, ask all five questions; on `STALE:k1,k2,…`, ask only the questions that map to the listed missing keys. The "(Recommended)" tag on each option is the install-time default; selecting it (or "Other" with no alternative) writes the default value. If the user declines via the native skip, write the Recommended defaults for the pending keys only.

## Authoring conventions

The 9 conventions that constrain how new hv-skills (or new behavior in existing skills) are authored live in [`references/authoring-conventions.md`](../references/authoring-conventions.md). They live there (not inline here) so the rule set is one Read away for any skill author and isn't tangled with `/hv-init`'s own configuration logic. Skill authors writing or modifying any `hv-*/SKILL.md` consult that file before landing new behavior.

Inventory (in order — see the reference for each rule's full body, *Why*, **Forbids**, **Permits**):

| # | Rule |
|---|------|
| 1 | Skills are self-contained — no shared contract file |
| 2 | Imperative rules in autonomy-aware steps must live inline at every dispatch point |
| 3 | Don't ask what the code can answer |
| 4 | Surface multi-step skill progress with TaskCreate |
| 5 | Routine routing/tagging auto-picks Recommended in loop mode |
| 6 | User-volition gates enforced at exactly one point |
| 7 | Stage features across slices using pass-through stubs |
| 8 | Helper-centric V2-surface extension |
| 9 | Opt-in feature flags default to `false` |
| 10 | Adjective thresholds in skill prose erode at the runtime model — bake the number at authoring time |
| 11 | `AskUserQuestion` option list capped at 4 |
| 12 | Nudges on terminal/idle paths only |
| 13 | Helper docstring is the contract — SKILL.md prose paraphrasing drifts |
| 14 | Inventory table beside a citation when ≥4 sibling rules extracted |
| 15 | Avoid `&` in `TaskCreate`/`TodoWrite` payloads |

When adding a new rule to the convention set, edit `references/authoring-conventions.md` directly — not this SKILL.md. The inventory table above gets a new row in the same edit.

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
  "work":     {"isolation": "<Q2>", "mergeStrategy": "<Q3>",
               "dispatch": "subagent", "workerSlots": 3, "workerCommand": "",
               "accounts": [], "operatorCommand": ""},
  "refactor": {"confirmBeforeExecute": <Q4-refactor>, "verifyCommands": []},
  "learn":    {"verify": <Q4-learn>, "promoteThreshold": 3},
  "ship":     {"review": <Q4-ship>, "secondOpinion": False, "qa": False},
  "qa":       {"gate": "advisory", "afterWork": False},
  "autonomy": {"level": "<Q5>"},
  "debug":    {"competingHypotheses": <Q4-debug>},
  "docs":     {"path": "docs", "autoCreate": False, "afterWork": False},
  "loop":     {"webResearch": False},
  "git":      {"baseBranch": ""},
  "issues":   {"providers": {"github": True, "gitlab": True}}
}
cfg.setdefault("umbrella", {})["enabled"] = umbrella_enabled
cfg.setdefault("hvSkills", {})["version"] = os.environ.get("HV_PLUGIN_VERSION", "")
Path(".hv/config.json").write_text(json.dumps(cfg, indent=2) + "\n")
PY
```

Read `umbrella_enabled` from the `UMBRELLA_MODE` shell var Step 1 set (default `false` when single-repo). `UMBRELLA_MODE` must be exported (`export UMBRELLA_MODE=true`) before the heredoc runs so the Python subprocess inherits it.

### STALE write block

Loop over the keys from the STALE list — call the shared helper once per key, passing the answered or Recommended-default value. The helper preserves every other key already in the file:

```bash
# Example: user answered Q4 "Review before ship" → ship.review was missing.
# Set only the keys from the STALE list; never overwrite existing values.
.hv/bin/hv-config-set ship.review true   # or answered value

# ship.secondOpinion — silent default. No question; opt-in feature flag
# (Rule 9) gating the fresh-eyes pre-merge gate in /hv-ship Step 3.5.
# Users enable via /hv-config when they want a no-prior-context adversarial
# review in addition to /hv-review.
.hv/bin/hv-config-set ship.secondOpinion false

# work.dispatch — silent default. Opt-in feature flag (Rule 9) selecting the
# /hv-work worker backend. "subagent" (default) dispatches in-process Agent
# workers; "tmux" runs each worker as its own Claude Code session in its own
# worktree, owning a branch and a PR. tmux mode needs a tmux binary and a
# working `claude` on PATH, so it never auto-enables.
.hv/bin/hv-config-set work.dispatch subagent

# work.workerSlots — silent default. Size of the tmux worker pool. Ignored
# under work.dispatch=subagent. 3 fits an 8-core box; more slots contend for
# CPU, which turns time-budgeted tests into false reds.
.hv/bin/hv-config-set work.workerSlots 3

# work.workerCommand — silent default. Empty means "build the launch command
# from models.worker" (`claude --model <worker> --permission-mode acceptEdits`).
# Set it when workers need a wrapper, an alias, or looser permissions — that
# choice is the user's to make explicitly, never this skill's to assume.
.hv/bin/hv-config-set work.workerCommand ''

# work.accounts — silent default. Array of {name, configDir} mapping tmux
# worker slots to their own CLAUDE_CONFIG_DIR, so slots authenticate
# independently. Empty means every slot inherits the ambient config dir,
# which is the single-account default. Only meaningful under
# work.dispatch=tmux.
.hv/bin/hv-config-set work.accounts '[]'

# work.operatorCommand — silent default. Command used to relaunch the
# ORCHESTRATOR inside tmux when /hv-work is invoked from a terminal that is
# not already in a tmux session. Empty builds
# `claude --continue --model <models.orchestrator>`; --continue resumes the
# current conversation so the cycle keeps its plan instead of restarting cold.
.hv/bin/hv-config-set work.operatorCommand ''

# learn.promoteThreshold — silent default. No question; integer knob
# (default 3) gating F03 knowledge-lifecycle auto-promotion. Users adjust
# via /hv-config or hv-config-set when they want stricter (5+) or looser
# (1-2) confidence thresholds.
.hv/bin/hv-config-set learn.promoteThreshold 3

# docs.afterWork — silent default. No question; the toggle UX lives in
# /hv-config (interactive checklist) and /hv-ship --docs first-run (auto-flips
# the flag when the user approves a fresh scaffold).
.hv/bin/hv-config-set docs.afterWork false

# ship.qa — silent default. Opt-in feature flag (Rule 9) gating the
# /hv-qa product-QA gate in /hv-ship Step 3.75. Off because QA runs are
# slow and may require infra (dev server, creds). Users enable via
# /hv-config when they want every ship to consult product-level checks.
.hv/bin/hv-config-set ship.qa false

# qa.gate — silent default. "advisory" emits the verdict but never halts;
# "blocking" halts /hv-ship on FAIL when ship.qa is true. Default
# advisory keeps QA findings informational; users opt into blocking via
# /hv-config when their workflow can tolerate the slower gate.
.hv/bin/hv-config-set qa.gate advisory

# qa.afterWork — silent default. Opt-in feature flag (Rule 9) gating
# whether /hv-work invokes /hv-qa run post-cycle on touched watch globs.
# Off because QA is heavy; users enable in tight feedback-loop projects.
.hv/bin/hv-config-set qa.afterWork false

# loop.webResearch — silent default. Gates whether /hv-plan --auto-loop
# (F32) calls WebSearch when an open question references an external
# library/API/protocol. Off by default per the opt-in-flags-default-false
# rule — loop mode makes no external network calls without explicit user
# opt-in via /hv-config.
.hv/bin/hv-config-set loop.webResearch false

# refactor.verifyCommands — silent default. No question; user enables
# by adding project CI-shape gates via `hv-config-set` or hand-editing
# the config. Empty array preserves existing behavior (read-only
# verification).
.hv/bin/hv-config-set refactor.verifyCommands '[]'

# umbrella.enabled — honor UMBRELLA_MODE from Step 1 (re-run from an umbrella
# with "Yes" answers sets it to true). Default false on upgrade when the env var
# is unset (no migration prompt for users who didn't re-run from a parent).
.hv/bin/hv-config-set umbrella.enabled "${UMBRELLA_MODE:-false}"

# issues.providers.{github,gitlab} — silent defaults. No question; gate
# `/hv-capture --from-github` / `--from-gitlab` per-provider. Defaulted to
# `true` because the de-facto behavior before schema visibility was
# "enabled when absent" — make it discoverable in `.hv/config.json` so
# users can toggle off via `/hv-config` instead of guessing.
.hv/bin/hv-config-set issues.providers.github true
.hv/bin/hv-config-set issues.providers.gitlab true

# hvSkills.version — re-stamped on every /hv-init so the project's recorded
# version follows the currently-installed plugin. hv-preflight nudges to
# re-init when the value drifts from the live plugin. (Always re-written
# on the upgrade path; never preserved.)
.hv/bin/hv-config-set hvSkills.version "${HV_PLUGIN_VERSION:-}"
```

Rule: for each missing key in the `STALE:` list, run exactly one `hv-config-set <dotted.path> <value>` call. The helper preserves every other key in the file. Never touch keys that were already present. `umbrella.enabled` is a special case — when missing on upgrade, honor `UMBRELLA_MODE` from Step 1 (default `false` when unset, `true` when the user opted in via Step 1's prompt). Re-running `/hv-init` from an umbrella with the "Yes" answer is the only path that flips it on; manual flips also possible via `/hv-config`. `hvSkills.version` is special-cased on the upgrade path too — STALE migration ALWAYS rewrites it from `HV_PLUGIN_VERSION`, even when the key is already present, because re-running `/hv-init` is the canonical way to clear drift. Other keys preserve user values; this one is auto-managed.

Briefly confirm the chosen profile in the Step 5 summary. On a FRESH run with all Recommended, just show *"Config: defaults."*; on a STALE migration, list the added keys — *"Config migrated: added `ship.review` (Recommended)."* so the user knows what changed.

## Step 4 — Seed CLAUDE.md Skills, Knowledge, Vision & Decisions Blocks

Seed six managed blocks in `CLAUDE.md` (created if missing): the hv-skills slash-command index (static), knowledge topics including the pinned `## Glossary` term store (`/hv-learn`, `/hv-learn --term`), active milestones (`/hv-vision`), decision topics (`/hv-decide`), the project map (subsystems in `.hv/map/<name>.md`, auto-bumped by cycle skills), and QA strategy index (`/hv-qa`). The skills block tells Claude *what* commands are available; the others tell it *what to consult* per work topic. Before regenerating, the `hv-managed-block-strip-deprecated` helper removes managed blocks left behind by previous hv-skills versions whose v4 helper has been cut (currently `<!-- hv-context-* -->`, from F18) — keeps `CLAUDE.md` from pointing at retired skills.

```bash
.hv/bin/hv-managed-block-strip-deprecated
.hv/bin/hv-skills-index
.hv/bin/hv-managed-block knowledge
.hv/bin/hv-vision-index
.hv/bin/hv-managed-block decisions
.hv/bin/hv-map-index
.hv/bin/hv-qa-index
```

Each helper creates, updates in place, or appends its own block. Other `CLAUDE.md` content is untouched.

## Step 5 — Confirm

Tell the user one compact block:

```
Initialized .hv/ in <project>.
Config: <summary — "defaults" if all Recommended, else a one-liner e.g. "Balanced models, worktree isolation, PR merges, verifier on">.
Next: /hv-capture to add items, /hv-next to pick work, /hv-learn to save learnings, /hv-learn --term <name> for glossary terms.
Edit .hv/config.json to change any of these later.
```

If `.hv/BACKLOG.md` already existed, say it was already initialized and helper scripts were refreshed. Then:

- **Config up-to-date** → drop the config line entirely; nothing was asked.
- **Config migrated (STALE)** → replace the config line with *"Config migrated: added `<keys>` (Recommended)."* listing whichever keys were added.
- **Config fresh (no existing `.hv/config.json` despite an existing `BACKLOG.md`)** → report as on a fresh init.

If `UMBRELLA_MODE=true` (Step 1 umbrella option accepted), append one extra line to the summary block — *"Umbrella mode enabled — registered sub-repos: <list from `.hv/repos.json`>"* — read the list via `python3 -c 'import json; print(", ".join(r["name"] for r in json.load(open(".hv/repos.json"))["repos"]))'`. Otherwise omit.

**Version line.** Append one line to the summary block from `.hv/bin/hv-update-check`'s JSON, branched on `status`:

- `current` → *"hv-skills `<currentVersion>` (latest)"*
- `behind` → *"hv-skills `<currentVersion>` → `<latestVersion>` available — run `/hv-update`"*
- `ahead` → *"hv-skills `<currentVersion>` (ahead of `<latestVersion>` — likely a dev install)"*
- `unknown` (network failure, install-type detection failed, etc.) → *"hv-skills `<currentVersion>`"* (no freshness hint)

The helper handles network access (via `gh`) and install-type resolution. Treat a non-zero exit or empty JSON as `unknown`. `hvSkills.version` in `.hv/config.json` carries the same `currentVersion` value — re-stamped this run.

Config keys: `models.{orchestrator,worker}`, `work.{isolation,mergeStrategy}`, `refactor.{confirmBeforeExecute,verifyCommands}`, `learn.{verify,promoteThreshold}`, `ship.{review,secondOpinion}`, `autonomy.level`, `debug.competingHypotheses`, `docs.{path,autoCreate,afterWork}`, `loop.webResearch`, `git.baseBranch`, `umbrella.enabled`, `hvSkills.version`. See [`docs/usage/configuration.md`](../docs/usage/configuration.md) for the full reference.

## References

- [`references/authoring-conventions.md`](../references/authoring-conventions.md) — Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold).
- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
