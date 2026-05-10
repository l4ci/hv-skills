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

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Detect environment & umbrella", description="Verify git/python3, scan for sub-repos")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (no umbrella, config already up-to-date) get `completed` with the no-op reason in the description.

Phases:

1. *Detect* — environment + umbrella decision (Steps 1, 1.5)
2. *Write artifacts* — bootstrap `.hv/` and install helpers (Step 2)
3. *Configure* — interactive config (FRESH or STALE migration, Step 3)
4. *Seed CLAUDE.md blocks* — skills, knowledge, vision, decisions, map indices (Step 4)

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

Plain-text fallback: ask once textually — *"Found N git repos here: <list>. Enable umbrella mode? (yes/no)"* — and honor the user's reply. If the host can't render the question and no reply is captured, default to **No** with a one-line follow-up note: *"Skipping umbrella mode. Re-run `/hv-init` from this cwd to enable, or toggle `umbrella.enabled` via `/hv-config` later."* The default is **No** rather than Yes because `umbrella.enabled` is an opt-in feature flag — per the *Authoring conventions / Opt-in feature flags default to `false`* rule below, the cwd signal alone (multiple sub-repos detected) is not user approval; explicit user approval is required.

> **Architecture rule — umbrella mode does not use git submodules.** Sub-repos under an umbrella are independent git repositories with no version-pinning at the umbrella level.
>
> *Why.* Submodules add version-pin friction (surprise-checkouts when SHAs drift, manual `git submodule update` discipline) and couple sub-repo evolution to umbrella commits — the wrong dependency direction. hv-skills's wedge is shared **coordinator + knowledge + decisions** at the umbrella, not shared version state.
>
> **Forbids.** `git submodule add` anywhere in an umbrella tree; `.gitmodules` at the umbrella root; "umbrella commit pins sub-repo SHA" patterns; designs that synchronize or pin sub-repo versions through the umbrella.
>
> **Permits.** Independent sub-repos checked out side-by-side under the umbrella; registry via `.hv/repos.json` by absolute or relative path; each sub-repo evolving on its own branch/tag/release schedule; sub-repos that are themselves submodule-using internally — the boundary applies *between umbrella and direct children*, not inside any sub-repo.

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
  if [ -z "$SRC" ]; then
    SRC=$(ls -d "$HOME"/.claude/plugins/cache/hv-skills/hv-skills/*/bin 2>/dev/null | sort -V | tail -1)
    [ -d "$SRC" ] || SRC=""
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

`hv-bootstrap` creates `.hv/{bugs,features,tasks,milestones,plans,spikes,map,bin}`, seeds `TODO.md` / `KNOWLEDGE.md` / `DECISIONS.md` / `MILESTONES.md` / `MAP.md` / `counters.json` / `status.json` if absent, adds `.hv/` to `.gitignore`, and runs the legacy preamble migration (`/hv:X` → `/hv-X` above the first `## Topic` heading). Data files are never overwritten. `config.json` is created interactively in the next step. All helpers require `python3`. See [`docs/reference/cli-helpers.md`](../docs/reference/cli-helpers.md) for the full helper reference.

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
    ("docs", "afterWork"),
    ("git", "baseBranch"),
    ("umbrella", "enabled"),
    ("hvSkills", "version"),
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

## Authoring conventions

These conventions constrain how new hv-skills (or new behavior in existing skills) is authored. They live here in `hv-init/SKILL.md` because /hv-init is the canonical entry point — the place a new author touches first when they ship a new flag, skill, or umbrella feature.

### Skills are self-contained — no shared contract file

Each skill owns its rules inline. A "shared contract" reference file (an old `GUIDE.md` was one) is a smell when every rule has a single owner. Audit the cross-refs before retaining a shared file: if each rule is already mirrored inline at the call site (preflight 3-exit codes, plain-text fallback, autonomy off/auto/loop dispatch, learn trigger thresholds, etc.), the central file is vestigial pointer-chasing. Build a shared file only when N≥3 callers need the same long rule verbatim.

### Imperative rules in autonomy-aware steps must live inline at every dispatch point

Steps that branch on `autonomy.level` (off/auto/loop) and dispatch the next skill via `Skill` ("no prompt, no confirmation, no 'want me to' question") must repeat the directive verbatim alongside each `Skill`-tool invocation. Readers don't chase cross-refs to a single source of truth, and the harness drifts toward asking when only the rule's name is at the dispatch site. Redundancy is cheaper than scattered authority.

### Don't ask what the code can answer

Before a skill calls `AskUserQuestion`, check whether the answer is derivable from the codebase, git history, or `.hv/` state — `grep`, `Read`, `git log`, `TODO.md`, `KNOWLEDGE.md`, `status.json`, helper output. If it is, derive the answer (with a one-line note inline about what was found and where) and skip the question. `AskUserQuestion` is for genuine ambiguity — open requirements, opposing reasonable interpretations, the user's risk tolerance on a destructive op — not a forced-yes ritual confirming state the skill could discover.

Codified from grill-with-docs (2026-05-10): *"If a question can be answered by exploring the codebase, explore the codebase instead."* Companion to the *AskUserQuestion option list capped at 4* rule (`KNOWLEDGE.md`, 2026-05-08) — that one constrains the option list when asking is the right move; this one constrains whether to ask at all.

### Surface multi-step skill progress with TaskCreate

Skills with three or more distinct phases must declare a visible task list at the end of Step 1 via `TaskCreate`, then mark each phase `in_progress` when starting it and `completed` when its observable outcome lands. The user sees a checklist instead of unannotated bash output; the agent stays oriented across long cycles. Without this, every multi-step run looks identical in the transcript to a single-step nudge — progress is invisible until the final report.

The block lives at the end of Step 1's body, never as a new `Step 1.5`. The decimal-step rule (`KNOWLEDGE.md` / `DECISIONS.md`, 2026-05-08) reserves `.5/.6/.7` slots for sequential additions; this convention is content within Step 1, not a new step. On hosts where `TaskCreate` is not loaded (non-Claude-Code platforms), the boilerplate self-skips silently — loading is conditional on `ToolSearch select:TaskCreate,TaskUpdate`.

Per-site shape (adapt phase list per skill):

> **Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="<phase 1 name>", description="<phase 1 outcome>")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases get `completed` with the no-op reason in the description.
>
> Phases:
>
> 1. *<phase title>* — *<one-line outcome>*
> 2. *<phase title>* — *<one-line outcome>*
> *(skill-specific list — 3 to 7+ phases)*

**Forbids.**
- Adding the block to single-phase or trivial skills (Tier C: `hv-assume`, `hv-go`, `hv-c`, `hv-update`, `hv-map`) — the checklist UX is overhead when there's nothing to tick off.
- Placing it as a new `Step 1.5` — the decimal-step rule reserves those slots; this is content within Step 1.
- Cross-skill alignment of phase names — each skill's phase list reflects its own structure; phrasing is local to the SKILL.md.
- Calling `TaskCreate` from inside subagent dispatches — the orchestrator owns the task list; workers focus on their assigned tasks and report back.

**Permits.**
- Per-site phase counts from 3 to 7+ — the rule fires at "multi-step", not a fixed number. Use phase boundaries that match the skill's natural structure, not the integer step count.
- Per-site boilerplate prose variations — this is a cross-cutting autonomy-shaped rule; per the 2026-05-09 `KNOWLEDGE.md` entry on cross-cutting prose, byte-equivalent repetition of the shell across 18 sites is acceptable when phase lists dominate.
- Phases that absorb decimal sub-steps (e.g. `/hv-work` 13.5/13.7 fold into one "post-cycle nudges" phase) — phase boundaries are coarser than step boundaries by design.
- Tracking spawned waves as nested tasks via `addBlocks`/`addBlockedBy` when a skill orchestrates parallel work — `/hv-work` may use this for its dispatched waves.

Codified from F37 (2026-05-10): rolled out across Tier S/A/B SKILL.md files (hv-init + 17 others). Tier C skills stay untouched. Companion to the *AskUserQuestion option list capped at 4* rule (`KNOWLEDGE.md`, 2026-05-08): both make the host's UI primitives load-bearing for skill UX.

### Routine routing/tagging auto-picks Recommended in loop mode

When `autonomy.level == "loop"`, AskUserQuestion calls that present a single clear `(Recommended)` option for **routine routing or tagging** must silently auto-pick the Recommended option without invoking AskUserQuestion. The host's question UI never fires; the skill proceeds as if the user picked the Recommended answer.

This is what makes loop mode actually loop — a single "Tag with M01?" or "Resume vs ship?" prompt mid-queue stalls every subsequent item until the user types an answer. Loop mode's contract is "drain the queue until empty / guard / interrupt"; intermediate routine prompts violate it.

Routine = the kind of question where the Recommended option is the obvious right answer, not a design pick. Examples: milestone tagging (`/hv-capture` Step 4.5), sub-repo tagging (`/hv-capture` Step 4.6), reconcile resolution (`/hv-next` Step 2 — resume / ship / leave), CONCERNS routing (`/hv-ship` Step 3 — "Address via /hv-work"), refactor scope and candidate gates.

**Forbids.** Auto-picking on:
- **Design decisions with open questions** — competing approaches, version-bump escalation, novel pattern choice. These belong to F32 (loop-mode auto-planning, with `[Auto:Loop]` decision logging). A `(Recommended)` flag on a design pick is a *suggestion*, not a routine answer; the loop must surface them.
- **Manual gates that are never auto-invoked regardless of autonomy** — `/hv-decide` approvals, `/hv-learn` Step 8.5 issue filing, `/hv-learn` Step 9 runlog filing, `/hv-ship` Step 5 PR strategy, `/hv-release` push/publish gates. These have explicit `**Manual gate — ...**` callouts in their SKILL.md. Loop mode honors the gate — it does not auto-pick.
- **Config-flip questions** — `/hv-init` initial setup, `/hv-config` edits, `/hv-docs` after-work-mode opt-in. These flip user-preference flags; the opt-in-defaults-to-`false` rule (below) requires explicit user approval, not loop-mode synthesis.

**Permits.**
- Routine routing/tagging with one clear Recommended option (the use cases listed above and any future analogue).
- Sites that already implement the pattern explicitly (`/hv-next` Step 7 work-on-suggested-item, `/hv-update` Step 4 re-init) — same shape, already inline; new sites follow their lead.
- Per-site phrasing variations — each site's loop branch states the auto-pick locally because the autonomy-rule-must-live-inline convention (above) forbids cross-refs to a single source of truth.

The dispatch site should add a short loop branch alongside the existing `"off"` AskUserQuestion arm. Pattern (adapt phrasing per site):

> **Loop mode:** when `autonomy.level == "loop"`, silently auto-pick the Recommended option without invoking AskUserQuestion — `<one-line summary of what gets dispatched>`.

Codified after F33 caught loop-mode discontinuity from `/hv-capture` milestone tagging and `/hv-next` reconcile gates breaking the `/hv-work` → `/hv-learn` → `/hv-next` → `/hv-work` chain.

### User-volition gates enforced at exactly one point

Manual confirmation gates (`/hv-decide`'s manual-only contract, the public-artifact gate in `/hv-learn` Step 8.5, etc.) must be enforced at exactly ONE point in a skill, never propagated across orchestrator + called skill. The gate is architecture-enforced — only the owning skill can ask the question, and no other skill dispatches the gated skill via `Skill`. Putting a confirmation check in a skill that other skills can invoke breaks the contract under autonomy.

### Stage features across slices using pass-through stubs

Multi-slice features ship the SHAPE early via pass-through stubs that explicitly name the future-slice wiring point (e.g. *"Layer-1 filter is a pass-through stub; `bin/hv-docs-filter` lands in M01-S03"*). This signals what consumers should NOT rely on yet. **Companion rule:** when the milestone flips to `shipped`, sweep all `M0X-S0Y` slice references — they were placeholders and become stale after merge.

### Helper-centric V2-surface extension

When scaling a feature surface from "single X" to "list of X" (e.g. one repo → many) across N skills, push parsing/validation/dispatch into `bin/` helpers and confine each SKILL.md edit to a single guard paragraph: *"if the value resolves to ≥2 entries, call helper-X; otherwise unchanged."* Single-X path stays byte-identical, multi-X complexity lives in code (exercised by smoke), per-skill prose stays ≤15 lines.

### Opt-in feature flags default to `false`

When adding a new boolean config flag whose purpose is to enable additional skill behavior or auto-invocation:

- **Default `false`** in both the FRESH write block and the STALE migration's setdefault.
- **Never silently flip to `true`** anywhere — not on first detection, not on first invocation, not via cwd-inferred heuristics.
- The owning skill flips the flag to `true` only via explicit user approval: first-run scaffold approval (the user opted in by approving), or `AskUserQuestion` on existing state with default "Leave off".
- `/hv-config` edits the flag explicitly (the flag is never read-only).
- **Exempt:** standard-on settings with opt-out semantics (e.g. `learn.verify: true`, `ship.review: true`) — these are not opt-in flags. Mode switches inside an already-enabled feature (e.g. `docs.autoCreate: false→true`) are also exempt.

Codified after F15 introduced `docs.afterWork`. Without this rule, opt-in flags drift toward auto-flip-on-first-detect, which makes them on-by-default in practice — defeating the opt-in semantics. Mirror reminder lives in `hv-config/SKILL.md`.

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
  "docs":     {"path": "docs", "autoCreate": False, "afterWork": False},
  "loop":     {"webResearch": False},
  "git":      {"baseBranch": ""}
}
cfg.setdefault("umbrella", {})["enabled"] = umbrella_enabled
cfg.setdefault("hvSkills", {})["version"] = os.environ.get("HV_PLUGIN_VERSION", "")
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

# docs.afterWork — silent default. No question; the toggle UX lives in
# /hv-config (interactive checklist) and /hv-docs first-run (auto-flips
# the flag when the user approves a fresh scaffold).
cfg.setdefault("docs", {}).setdefault("afterWork", False)

# loop.webResearch — silent default. Gates whether /hv-plan --auto-loop
# (F32) calls WebSearch when an open question references an external
# library/API/protocol. Off by default per the opt-in-flags-default-false
# rule — loop mode makes no external network calls without explicit user
# opt-in via /hv-config.
cfg.setdefault("loop", {}).setdefault("webResearch", False)

# umbrella.enabled — honor UMBRELLA_MODE from Step 1.5 (re-run from an umbrella
# with "Yes" answers sets it to true). Default false on upgrade when the env var
# is unset (no migration prompt for users who didn't re-run from a parent).
cfg.setdefault("umbrella", {})["enabled"] = os.environ.get("UMBRELLA_MODE", "false") == "true"

# hvSkills.version — re-stamped on every /hv-init so the project's recorded
# version follows the currently-installed plugin. hv-preflight nudges to
# re-init when the value drifts from the live plugin.
cfg.setdefault("hvSkills", {})
cfg["hvSkills"]["version"] = os.environ.get("HV_PLUGIN_VERSION", "")

p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
```

Rule: for each missing key in the `STALE:` list, do exactly one `cfg.setdefault(section, {})[key] = value` write. Never touch keys that were already present. `umbrella.enabled` is a special case — when missing on upgrade, honor `UMBRELLA_MODE` from Step 1.5 (default `False` when unset, `True` when the user opted in via Step 1.5's prompt). Re-running `/hv-init` from an umbrella with the "Yes" answer is the only path that flips it on; manual flips also possible via `/hv-config`. `hvSkills.version` is special-cased on the upgrade path too — STALE migration ALWAYS rewrites it from `HV_PLUGIN_VERSION`, even when the key is already present, because re-running `/hv-init` is the canonical way to clear drift. Other keys preserve user values; this one is auto-managed.

Briefly confirm the chosen profile in the Step 5 summary. On a FRESH run with all Recommended, just show *"Config: defaults."*; on a STALE migration, list the added keys — *"Config migrated: added `ship.review` (Recommended)."* so the user knows what changed.

## Step 4 — Seed CLAUDE.md Skills, Knowledge, Vision & Decisions Blocks

Seed four managed blocks in `CLAUDE.md` (created if missing): the hv-skills slash-command index (static), knowledge topics (`/hv-learn`), active milestones (`/hv-vision`), and decision topics (`/hv-decide`). The skills block tells Claude *what* commands are available; the others tell it *what to consult* per work topic.

```bash
.hv/bin/hv-skills-index
.hv/bin/hv-knowledge-index
.hv/bin/hv-vision-index
.hv/bin/hv-decisions-index
.hv/bin/hv-map-index
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

Config keys: `models.{orchestrator,worker}`, `work.{isolation,mergeStrategy}`, `refactor.confirmBeforeExecute`, `learn.verify`, `ship.review`, `autonomy.level`, `debug.competingHypotheses`, `docs.{path,autoCreate,afterWork}`, `loop.webResearch`, `git.baseBranch`, `umbrella.enabled`, `hvSkills.version`. See [`docs/usage/configuration.md`](../docs/usage/configuration.md) for the full reference.
