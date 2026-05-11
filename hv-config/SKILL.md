---
name: hv-config
description: Change hv-skills configuration interactively — pick which settings to edit from a checklist showing current values, then choose new values from the same options used at init. Use on "change config", "switch to worktree mode", "turn on autonomy", "edit settings".
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🔧  hv-config  ·  change project settings interactively
  triggers: "change config", "edit settings"  ·  pairs: hv-init
════════════════════════════════════════════════════════════════════════
```

# hv-config — Edit `.hv/config.json` Interactively

Change one or more configuration values without hand-editing JSON. Same option vocabulary as `/hv-init`, but you pick exactly which keys to change and the rest stay untouched.

> **Authoring note (when adding a new flag):** boolean opt-in feature flags default to `false`. Owning skills flip them to `true` only via explicit user approval — never silently on first detection. `/hv-config` edits them explicitly. See the *Authoring rule* section in `hv-init/SKILL.md` for the full rule + exemptions.

## When to Use

- Toggle a single setting — *"switch to worktree isolation"*, *"turn autonomy on loop"*
- Adjust a few keys at once after the project has matured
- You forgot the exact JSON path for a setting

## When NOT to Use

- First-time setup → `/hv-init` writes the whole file from scratch
- Just inspecting current values → `cat .hv/config.json`
- Adding a brand-new key after a plugin upgrade → `/hv-init` runs the STALE migration and asks only for the missing key

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling. Variant: on exit `2`, invoke `hv-init` via `Skill` then stop — init writes the initial config interactively, so this skill has nothing to do afterward.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Pick keys", description="Stage category-then-keys selection via AskUserQuestion")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (user picks no keys, all values valid first try) get `completed` with the no-op reason in the description.

Phases:

1. *Pick keys* — category-then-keys two-stage selection (Steps 2–3)
2. *Validate* — new values normalized and checked against allowed sets (Step 4)
3. *Write* — `.hv/config.json` updated; managed CLAUDE.md blocks regenerated if relevant (Steps 5–6)

## Step 2 — Read & Display Current Config

```bash
python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path(".hv/config.json").read_text())

def profile(o, w):
    pairs = {
        ("opus","sonnet"): "Balanced",
        ("opus","opus"): "Premium",
        ("sonnet","sonnet"): "Fast",
        ("sonnet","haiku"): "Minimal",
    }
    return pairs.get((o,w), f"Custom ({o} + {w})")

m = cfg.get("models", {})
o, w = m.get("orchestrator"), m.get("worker")
print("Current configuration:")
print(f"  Models                   {profile(o, w)} ({o} + {w})")
print(f"  Isolation                {cfg.get('work',{}).get('isolation','branch')}")
print(f"  Integration              {cfg.get('work',{}).get('mergeStrategy','direct')}")
print(f"  Ship review              {'on' if cfg.get('ship',{}).get('review',True) else 'off'}")
print(f"  Verify learnings         {'on' if cfg.get('learn',{}).get('verify',True) else 'off'}")
print(f"  Confirm before refactor  {'on' if cfg.get('refactor',{}).get('confirmBeforeExecute',True) else 'off'}")
print(f"  Autonomy                 {cfg.get('autonomy',{}).get('level','off')}")
print(f"  Competing hypotheses     {'on' if cfg.get('debug',{}).get('competingHypotheses',False) else 'off'}")
print(f"  Docs path                {cfg.get('docs',{}).get('path','docs')}")
print(f"  Docs auto-create         {'on' if cfg.get('docs',{}).get('autoCreate',False) else 'off'}")
print(f"  Docs after-work          {'on' if cfg.get('docs',{}).get('afterWork',False) else 'off'}")
print(f"  Git base branch          {cfg.get('git',{}).get('baseBranch','') or '(auto-detect)'}")
print(f"  Umbrella mode            {'on' if cfg.get('umbrella',{}).get('enabled',False) else 'off'}")
print(f"  hv-skills version        {cfg.get('hvSkills',{}).get('version','') or '(unstamped)'}")
PY
```

Print the helper output verbatim — the user needs to see what they're editing. `hv-skills version` is auto-stamped by `/hv-init`; not in the edit list.

## Step 3 — Pick Which Keys to Change

The 13 configurable keys group into 4 categories; pick categories first, then drill into the keys in each. This two-stage flow keeps every question within `AskUserQuestion`'s 4-option UI cap.

### Stage A — Pick categories

One `AskUserQuestion` call, multiSelect:

- **Header:** `"Edit"`
- **Question:** *"Which areas of config do you want to edit?"*
- **multiSelect:** `true`
- **Options** (multiSelect):
  1. *"Work — models, isolation, integration, autonomy"*
  2. *"Quality gates — ship review, verify learnings, refactor confirm, competing hypotheses"*
  3. *"Docs — path, auto-create, after-work"*
  4. *"Other — umbrella mode, git base branch"*

If the user selects nothing, print *"No changes."* and stop.

### Stage B — Pick keys within each category

For each category the user selected in Stage A, issue one `AskUserQuestion` call with the keys in that category. Substitute the live values from Step 2 into each option label so the user sees what they're replacing. Aggregate the picks across all category calls into a single set before Step 4.

| Category | Keys (multiSelect, ≤4 per call) |
|----------|---------------------------------|
| Work | *"Models — current: <profile>"*, *"Isolation — current: <branch\|worktree>"*, *"Integration — current: <direct\|pr>"*, *"Autonomy — current: <off\|auto\|loop>"* |
| Quality gates | *"Ship review — current: <on\|off>"*, *"Verify learnings — current: <on\|off>"*, *"Confirm before refactor — current: <on\|off>"*, *"Competing hypotheses — current: <on\|off>"* |
| Docs | *"Docs path — current: <path>"*, *"Docs auto-create — current: <on\|off>"*, *"Docs after-work — current: <on\|off>"* |
| Other | *"Umbrella mode — current: <on\|off>"*, *"Git base branch — current: <branch\|(auto-detect)>"* |

If a Stage B call returns no selections (user picked the category in Stage A but skipped every key inside it), treat that category as a no-op — don't error.

If every Stage B call returns no selections, print *"No changes."* and stop.

Plain-text fallback: if the host doesn't surface `AskUserQuestion` options at all, ask once — *"Which settings do you want to change? List them by name (e.g. Autonomy, Isolation), or 'cancel' to exit."* — and parse the reply against the thirteen key names listed across the four categories above.

## Step 4 — Ask the Selected Questions

Build a single `AskUserQuestion` call containing **only** the questions for the keys the user selected in Step 3. The question wording and option vocabulary live in [`docs/reference/config-options.md`](../docs/reference/config-options.md) — that page is the canonical source for both Q1–Q5 and the additional `/hv-config` keys (docs path, docs auto-create, docs after-work, git base branch, umbrella mode). Use the labels and descriptions from that reference verbatim.

**Tag the user's current value as `(current)`.** Unlike `/hv-init` (which tags the install-time default as `(Recommended)`), `/hv-config` tags whichever option matches the user's current config value as `(current)` instead. This way the user always sees what they're replacing, not what was originally recommended.

If the user's current value doesn't match any option (custom config), don't tag any — every option is a real change.

If the user picks the `(current)` option on a question, treat that key as a no-op — no write, no diff line.

**Umbrella toggling.** When toggling `umbrella.enabled` **Off**, registered repos in `.hv/repos.json` remain — helpers will simply ignore umbrella mode until re-enabled. To add or remove repos from the registry, re-run `/hv-init` from the umbrella root (idempotent).

Plain-text fallback: ask each selected key as a one-shot prompt, take the reply, validate it against the allowed values listed in the reference, fall back to the current value on invalid input.

## Step 5 — Merge & Write

For each key the user changed in Step 4, call the shared helper once. Other keys are preserved automatically — the helper reads, mutates the one path, writes atomically:

```bash
# Examples (only run the lines that apply, one per key the user changed):
#
# .hv/bin/hv-config-set models.orchestrator opus
# .hv/bin/hv-config-set models.worker sonnet
# .hv/bin/hv-config-set work.isolation worktree
# .hv/bin/hv-config-set work.mergeStrategy pr
# .hv/bin/hv-config-set ship.review false
# .hv/bin/hv-config-set learn.verify true
# .hv/bin/hv-config-set refactor.confirmBeforeExecute false
# .hv/bin/hv-config-set autonomy.level loop
# .hv/bin/hv-config-set debug.competingHypotheses true
# .hv/bin/hv-config-set umbrella.enabled true
```

The helper parses each value as JSON (so `true`/`false`/numbers decode correctly); bare identifiers like `opus` / `loop` / `worktree` fall back to string. Run one call per key — do not batch.

Rule: never write keys the user didn't pick. No full-file rewrite, no "while we're here let's also normalize". Targeted edits only.

## Step 6 — Confirm

Print one compact diff block:

```
Updated .hv/config.json:
  autonomy.level   off → loop
  work.isolation   branch → worktree
```

Skip lines for keys the user picked `(current)` on — those didn't actually change. If nothing changed (user picked `(current)` everywhere, or selected nothing in Step 3), print *"No changes."* instead.

If the change has an immediate behavioral implication worth flagging (e.g. switching to `autonomy: "loop"` from `"off"`), append one line:

```
  Note: loop mode chains /hv-work → /hv-learn → /hv-next automatically. Stops on empty backlog or guard failure.
```

If the user toggled `umbrella.enabled` **on** and `.hv/repos.json` has an empty `repos: []` array, append:

```
  Note: umbrella mode is on, but no sub-repos are registered. Run `/hv-init` from the umbrella root to register children.
```

Keep notes short and only for state changes that materially alter how subsequent skills behave. Skip the note for cosmetic changes (model profile swap, single boolean flip).

## Rules

- **Never write keys the user didn't pick.** `setdefault` plus targeted assignment — no full-file rewrite.
- **Show current values everywhere.** Step 2 prints them; Step 3 shows them in checklist labels; Step 4 tags the matching option `(current)`. The user always sees what they're replacing.
- **Same vocabulary as `/hv-init`.** Don't invent new option labels — reuse Q1–Q5's wording so the choices are familiar.
- **Cancellation is silent.** Empty selection or all-`(current)` answers exit with *"No changes."* — no warnings, no nags.
- **One pass.** The skill asks once, writes once, reports once. To make further edits, the user re-invokes `/hv-config`.
