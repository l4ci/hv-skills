---
name: hv-config
description: Change hv-skills configuration interactively — pick which settings to edit from a checklist showing current values, then choose new values from the same options used at init. Also supports positional shortcuts: `/hv-config <key>` jumps to the value picker, `/hv-config <key>=<value>` applies directly. Use on "change config", "switch to worktree mode", "turn on autonomy", "edit settings".
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

> **Authoring note (when adding a new flag):** boolean opt-in feature flags default to `false`. Owning skills flip them to `true` only via explicit user approval — never silently on first detection. `/hv-config` edits them explicitly. See *Opt-in feature flags default to `false`* in `references/authoring-conventions.md` for the full rule + exemptions.

## When to Use

- Toggle a single setting — *"switch to worktree isolation"*, *"turn autonomy on loop"*
- Adjust a few keys at once after the project has matured
- You forgot the exact JSON path for a setting
- Apply a single known value fast — `/hv-config work.isolation=worktree`

## When NOT to Use

- First-time setup → `/hv-init` writes the whole file from scratch
- Just inspecting current values → `hv config show [<key>]` (value plus source layer)
- Adding a brand-new key after a plugin upgrade → `/hv-init` asks only for the missing keys and fills the rest with defaults

## Step 1 — Task List

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Parse positional args* — empty / `<key>` / `<key>=<value>` shapes resolved (Step 1.5)
2. *Pick keys* — category-then-keys two-stage selection (Steps 2–3)
3. *Validate* — new values normalized and checked against allowed sets (Step 4)
4. *Write* — `.hv/config.json` updated; managed CLAUDE.md blocks regenerated if relevant (Steps 5–6)

## Step 1.5 — Parse Positional Arguments

Inspect `$ARGUMENTS`. The skill supports three invocation shapes:

| Shape | Behavior |
|-------|----------|
| Empty / whitespace only | Run `hv config show` and print its output verbatim (every key, value and source layer), then continue to Step 2 — full guided flow. |
| `<key>` (no `=`) | Skip Step 2 and Step 3. Treat `<key>` as the single picked key; jump straight to Step 4. |
| `<key>=<value>` | Skip Steps 2–4. Validate, apply directly via `hv config set`, jump to Step 6. |

**Split on the FIRST `=` only.** Free-text keys (`docs.path`, `git.baseBranch`) may contain `=` in their values; later `=` characters belong to the value.

**Trim whitespace** around the key and around the value. `docs.path=` (empty value after `=`) is valid for free-text keys and writes the empty string.

**Validate `<key>`** against the schema: a valid key is one `hv config show` lists (exact match, case-sensitive), except `hvSkills.version`, which `/hv-init` stamps. The skill keeps no copy of the list; `hv config set` itself exits 2 on a key outside the schema.

Unknown key → stop with: *"Error: `<key>` is not a configurable setting. Run `/hv-config` with no arguments to see the full list."* Do **not** silently fall through to the guided flow — the positional invocation is an explicit ask for one specific key.

**Validate `<value>`** when present, against the allowed values for that key from `docs/reference/config-options.md`:

- Enum keys (`work.isolation`, `work.mergeStrategy`, `work.dispatch`, `ship.secondOpinionRunner`, `autonomy.level`, `models.orchestrator`, `models.worker`, `qa.gate`, `backlog.backend`, `issues.provider`) — value must be one of the documented options. `work.dispatch` accepts `subagent`, `tmux` or `herdr`. `ship.secondOpinionRunner` accepts `subagent` (`codex` was removed in 5.0; an existing `codex` value still runs the subagent gate in advisory mode). `qa.gate` accepts `advisory` or `blocking`. `backlog.backend` accepts `file` or `issues`. `issues.provider` accepts `auto`, `github` or `gitlab`.
- Boolean keys (`ship.review`, `ship.secondOpinion`, `learn.verify`, `refactor.confirmBeforeExecute`, `debug.competingHypotheses`, `docs.autoCreate`, `docs.afterWork`, `umbrella.enabled`, `ship.qa`, `qa.afterWork`, `loop.webResearch`, `issues.autoCreateLabel`, `issues.filterMineOnly`, `issues.providers.github`, `issues.providers.gitlab`) — accept `true`, `false`, `on`, `off` (case-insensitive). Normalize `on`/`off` to `true`/`false`. Anything else is invalid.
- JSON-array keys (`refactor.verifyCommands`, `work.accounts`) — value must parse as a JSON array; `work.accounts` entries need a `name` and a `configDir`. Not offered in the guided flow; set via `hv config set work.accounts '[{"name":"personal","configDir":"~/.claude"}]'`.
- Free-text keys (`docs.path`, `git.baseBranch`, `issues.label`, `work.workerCommand`, `work.operatorCommand`, the `issues.labels.*` names, `issues.homeRepo`, `release.checklistPath`) — accept any value including the empty string.
- Integer keys (`learn.promoteThreshold`, `work.workerSlots`, `issues.retryWaitSeconds`, `issues.bulkPaceMs`, `release.*` counts, `round.stallMinutes`, where `0` turns the stalled check off) — accept any non-negative integer (≥0) as a string of digits. Anything else (negative, non-numeric, decimal) is invalid. `work.workerSlots` additionally rejects `0` — a pool with no slots cannot dispatch.

Invalid value → stop with: *"Error: `<value>` is not a valid value for `<key>`. Allowed: <comma-separated list from config-options.md>."*

On the `<key>` (no `=`) path, carry the single key forward as the only picked key in Step 4 — that one question is asked, the user's answer is written, then jump to Step 6.

On the `<key>=<value>` path, write directly:

```bash
hv config set <key> <value>
```

Then jump to Step 6 to print the one-line diff.

## Step 2 — Read & Display Current Config

```bash
hv config show --json
```

`data.entries` holds every schema key with its `value` and `source`. Print this block, one row per line, from those values:

```
Current configuration:
  Models                   <profile> (<models.orchestrator> + <models.worker>)
  Isolation                <work.isolation>
  Integration              <work.mergeStrategy>
  Ship review              <ship.review: on|off>
  Ship second-opinion      <ship.secondOpinion: on|off>
  Verify learnings         <learn.verify: on|off>
  Confirm before refactor  <refactor.confirmBeforeExecute: on|off>
  Autonomy                 <autonomy.level>
  Competing hypotheses     <debug.competingHypotheses: on|off>
  Docs path                <docs.path>
  Docs auto-create         <docs.autoCreate: on|off>
  Docs after-work          <docs.afterWork: on|off>
  Git base branch          <git.baseBranch, or "(auto-detect)" when empty>
  Umbrella mode            <umbrella.enabled: on|off>
  Issues label             <issues.label>
  Issues auto-create label <issues.autoCreateLabel: on|off>
  Issues filter mine only  <issues.filterMineOnly: on|off>
  Issues GitHub provider   <issues.providers.github: on|off>
  Issues GitLab provider   <issues.providers.gitlab: on|off>
  hv-skills version        <hvSkills.version, or "(unstamped)" when empty>
```

`<profile>` from the model pair: opus+sonnet Balanced, opus+opus Premium, sonnet+sonnet Fast, sonnet+haiku Minimal, anything else `Custom (<orchestrator> + <worker>)`.

The user needs to see what they're editing. `hv-skills version` is auto-stamped by `/hv-init`; not in the edit list.

## Step 3 — Pick Which Keys to Change

Skip this step entirely when Step 1.5 parsed a `<key>` or `<key>=<value>` argument — the key is already picked (or already written).

The 18 configurable keys group into 5 categories; pick categories first, then drill into the keys in each. This two-stage flow keeps every question within `AskUserQuestion`'s 4-option UI cap.

### Stage A — Pick categories

Two `AskUserQuestion` calls in sequence (both multiSelect), because 5 categories exceed the 4-option ceiling. Aggregate the picks from both calls before Stage B.

**Call A1:**

- **Header:** `"Edit"`
- **Question:** *"Which areas of config do you want to edit? (1 of 2)"*
- **multiSelect:** `true`
- **Options:**
  1. *"Work — models, isolation, integration, autonomy"*
  2. *"Quality gates — ship review, verify learnings, refactor confirm, competing hypotheses"*
  3. *"Docs — path, auto-create, after-work"*
  4. *"Other — umbrella mode, git base branch"*

**Call A2:**

- **Header:** `"Edit"`
- **Question:** *"Any further areas? (2 of 2)"*
- **multiSelect:** `true`
- **Options:**
  1. *"Issues — label, auto-create label, filter mine only, providers"*

If the user selects nothing across both calls, print *"No changes."* and stop.

### Stage B — Pick keys within each category

For each category the user selected in Stage A, issue one `AskUserQuestion` call with the keys in that category. Substitute the live values from Step 2 into each option label so the user sees what they're replacing. Aggregate the picks across all category calls into a single set before Step 4.

| Category | Keys (multiSelect, ≤4 per call) |
|----------|---------------------------------|
| Work | *"Models — current: <profile>"*, *"Isolation — current: <branch\|worktree>"*, *"Integration — current: <direct\|pr>"*, *"Autonomy — current: <off\|auto\|loop>"* |
| Quality gates | Two calls (5 keys exceed cap): **call 1** — *"Ship review — current: <on\|off>"*, *"Ship second-opinion — current: <on\|off>"*, *"Verify learnings — current: <on\|off>"*, *"Confirm before refactor — current: <on\|off>"*; **call 2** — *"Competing hypotheses — current: <on\|off>"* |
| Docs | *"Docs path — current: <path>"*, *"Docs auto-create — current: <on\|off>"*, *"Docs after-work — current: <on\|off>"* |
| Other | *"Umbrella mode — current: <on\|off>"*, *"Git base branch — current: <branch\|(auto-detect)>"* |
| Issues | Two calls (5 keys exceed cap): **call 1** — *"Issues label — current: <label>"*, *"Auto-create label — current: <on\|off>"*, *"Filter mine only — current: <on\|off>"*, *"GitHub provider — current: <on\|off>"*; **call 2** — *"GitLab provider — current: <on\|off>"* |

If a Stage B call returns no selections (user picked the category in Stage A but skipped every key inside it), treat that category as a no-op — don't error.

If every Stage B call returns no selections, print *"No changes."* and stop.

Plain-text fallback: if the host doesn't surface `AskUserQuestion` options at all, ask once — *"Which settings do you want to change? List them by name (e.g. Autonomy, Isolation, Issues label), or 'cancel' to exit."* — and parse the reply against the eighteen key names listed across the five categories above.

## Step 4 — Ask the Selected Questions

When Step 1.5 captured a single `<key>` (no `=`), this step asks only that key's question — one question, not the full set.

Build a single `AskUserQuestion` call containing **only** the questions for the keys the user selected in Step 3. The question wording and option vocabulary live in [`docs/reference/config-options.md`](../docs/reference/config-options.md) — that page is the canonical source for both Q1–Q5 and the additional `/hv-config` keys (docs path, docs auto-create, docs after-work, git base branch, umbrella mode). Use the labels and descriptions from that reference verbatim.

**Tag the user's current value as `(current)`.** Unlike `/hv-init` (which tags the install-time default as `(Recommended)`), `/hv-config` tags whichever option matches the user's current config value as `(current)` instead. This way the user always sees what they're replacing, not what was originally recommended.

If the user's current value doesn't match any option (custom config), don't tag any — every option is a real change.

If the user picks the `(current)` option on a question, treat that key as a no-op — no write, no diff line.

**Umbrella toggling.** When toggling `umbrella.enabled` **Off**, registered repos in `.hv/repos.json` remain — `hv` verbs simply ignore umbrella mode until re-enabled. To add or remove repos from the registry, re-run `/hv-init` from the umbrella root (idempotent).

Plain-text fallback: ask each selected key as a one-shot prompt, take the reply, validate it against the allowed values listed in the reference, fall back to the current value on invalid input.

## Step 5 — Merge & Write

For each key the user changed in Step 4, call `hv config set` once. Other keys are preserved automatically — it reads, mutates the one path, writes atomically:

```bash
# Examples (only run the lines that apply, one per key the user changed):
#
# hv config set models.orchestrator opus
# hv config set models.worker sonnet
# hv config set work.isolation worktree
# hv config set work.mergeStrategy pr
# hv config set ship.review false
# hv config set learn.verify true
# hv config set refactor.confirmBeforeExecute false
# hv config set autonomy.level loop
# hv config set debug.competingHypotheses true
# hv config set umbrella.enabled true
# hv config set issues.label in-progress
# hv config set issues.autoCreateLabel true
# hv config set issues.filterMineOnly false
# hv config set issues.providers.github true
# hv config set issues.providers.gitlab true
```

`hv config set` parses each value as JSON (so `true`/`false`/numbers decode correctly); bare identifiers like `opus` / `loop` / `worktree` fall back to string. Run one call per key — do not batch.

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

- **Never write keys the user didn't pick.** One `hv config set` per changed key — no full-file rewrite.
- **Show current values everywhere.** Step 2 prints them; Step 3 shows them in checklist labels; Step 4 tags the matching option `(current)`. The user always sees what they're replacing.
- **Same vocabulary as `/hv-init`.** Don't invent new option labels — reuse Q1–Q5's wording so the choices are familiar.
- **Cancellation is silent.** Empty selection or all-`(current)` answers exit with *"No changes."* — no warnings, no nags.
- **One pass.** The skill asks once, writes once, reports once. To make further edits, the user re-invokes `/hv-config`.
- **Positional args bypass selection, not validation.** `<key>` must be a schema key (`hv config show`); `<value>` (when given) must match the allowed set from `docs/reference/config-options.md`. Unknown / invalid arguments stop the skill with an explicit error — never silently fall through to the guided flow.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
