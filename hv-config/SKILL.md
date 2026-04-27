---
name: hv-config
description: Change hv-skills configuration interactively — pick which settings to edit from a checklist showing current values, then choose new values from the same options used at init. Use on "change config", "switch to worktree mode", "turn on autonomy", "edit settings".
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  ⬛  hv-config  ·  change project settings interactively
  triggers: "change config", "edit settings"  ·  pairs: hv-init
════════════════════════════════════════════════════════════════════════
```

# hv-config — Edit `.hv/config.json` Interactively

Change one or more configuration values without hand-editing JSON. Same option vocabulary as `/hv-init`, but you pick exactly which keys to change and the rest stay untouched.

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

Branch on exit code:
- `0` — continue.
- `2` (uninitialized) — invoke `hv-init` via the `Skill` tool, then stop. There's nothing for `/hv-config` to edit yet; init writes the initial file interactively.
- `3` (partial install) — invoke `hv-init` to refresh helpers, then continue.

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
PY
```

Print the helper output verbatim — the user is about to edit it, so they need to see what they're starting from.

## Step 3 — Pick Which Keys to Change

One `AskUserQuestion` call, multiSelect:

- **Header:** `"Edit"`
- **Question:** *"Which settings do you want to change?"*
- **Options** (multiSelect; substitute the live values from Step 2 into each label so the user sees what they're replacing):
  1. *"Models — current: <profile>"*
  2. *"Isolation — current: <branch|worktree>"*
  3. *"Integration — current: <direct|pr>"*
  4. *"Ship review — current: <on|off>"*
  5. *"Verify learnings — current: <on|off>"*
  6. *"Confirm before refactor — current: <on|off>"*
  7. *"Autonomy — current: <off|auto|loop>"*

If the user selects nothing, print *"No changes."* and stop.

Plain-text fallback: ask once — *"Which settings do you want to change? List them by name (e.g. Autonomy, Isolation), or 'cancel' to exit."* — and parse the reply against the seven names above.

## Step 4 — Ask the Selected Questions

Build a single `AskUserQuestion` call containing **only** the questions for the keys the user selected in Step 3. Each question reuses the option vocabulary from `/hv-init` — same labels, same descriptions — but tags the user's *current* value as `(current)` instead of marking the install-time default as `(Recommended)`. This way the user always sees what they're replacing without confusing it with what was originally recommended.

| Selected key | Question to ask | Options (single-select) |
|--------------|-----------------|-------------------------|
| Models | *"Which model profile should hv-skills use?"* | Balanced (Opus + Sonnet) / Premium (Opus only) / Fast (Sonnet only) / Minimal (Sonnet + Haiku) |
| Isolation | *"How should `/hv-work` isolate changes from main?"* | Branch / Worktree |
| Integration | *"How should `/hv-work` and `/hv-ship` integrate finished work?"* | Direct merge / GitHub PR |
| Ship review | *"Run `/hv-review` before `/hv-ship` integrates?"* | On / Off |
| Verify learnings | *"Run the Opus verifier on new `/hv-learn` entries?"* | On / Off |
| Confirm before refactor | *"Pause for approval at `/hv-refactor` checkpoints?"* | On / Off |
| Autonomy | *"How autonomously should hv-skills chain to the next logical step?"* | Off / Auto chain / Full loop |

For each question, tag the matching option with `(current)`. If the user's current value doesn't match any option (custom config), don't tag any — every option is a real change.

If the user picks the `(current)` option on a question, treat that key as a no-op — no write, no diff line.

For descriptions on each option, copy the wording from `/hv-init` Q1–Q5 verbatim so users only learn the choices once. (See `hv-init/SKILL.md` Step 3 for the full descriptions.)

Plain-text fallback: ask each selected key as a one-shot prompt, take the reply, validate it against the allowed values, fall back to current on invalid input.

## Step 5 — Merge & Write

Read the existing file, mutate only the keys the user changed, write back:

```bash
python3 - <<PY
import json
from pathlib import Path
p = Path(".hv/config.json")
cfg = json.loads(p.read_text())

# For each key the user changed in Step 4, do exactly one targeted assignment.
# Use setdefault so existing keys in other sections aren't lost.
# Examples (only run the lines that apply):
#
# cfg.setdefault("models", {})["orchestrator"] = "opus"
# cfg.setdefault("models", {})["worker"] = "sonnet"
# cfg.setdefault("work", {})["isolation"] = "worktree"
# cfg.setdefault("work", {})["mergeStrategy"] = "pr"
# cfg.setdefault("ship", {})["review"] = False
# cfg.setdefault("learn", {})["verify"] = True
# cfg.setdefault("refactor", {})["confirmBeforeExecute"] = False
# cfg.setdefault("autonomy", {})["level"] = "loop"

p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
```

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

Keep notes short and only for state changes that materially alter how subsequent skills behave. Skip the note for cosmetic changes (model profile swap, single boolean flip).

## Rules

- **Never write keys the user didn't pick.** `setdefault` plus targeted assignment — no full-file rewrite.
- **Show current values everywhere.** Step 2 prints them; Step 3 shows them in checklist labels; Step 4 tags the matching option `(current)`. The user always sees what they're replacing.
- **Same vocabulary as `/hv-init`.** Don't invent new option labels — reuse Q1–Q5's wording so the choices are familiar.
- **Cancellation is silent.** Empty selection or all-`(current)` answers exit with *"No changes."* — no warnings, no nags.
- **One pass.** The skill asks once, writes once, reports once. To make further edits, the user re-invokes `/hv-config`.
