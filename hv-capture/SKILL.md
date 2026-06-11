---
name: hv-capture
description: Capture bugs, features, and tasks into BACKLOG.md without executing them. Classifies each item, assigns priority/size, mints zero-padded IDs ([B01], [F01], [T01]). Also supports `--remove <ID>[,<ID>...]` to delete captured items and clean up cross-references (dry-run + confirmation gate), and `--from-github` / `--from-gitlab` to pull open upstream issues into the backlog with `GH: #N` / `GL: #N` cross-refs and round-trip closing via `/hv-ship`. Use when the user brain-dumps work, says "capture", "add to backlog", "note this bug", "/hv-capture", "remove [B07]", "delete this entry", "drop this item", "/hv-rm", "import issues", "pull open issues from GitHub", "list issues", "/hv-issues", or describes a problem without asking for an immediate fix. Records only — for an immediate fix use /hv-go; for items already in BACKLOG use /hv-work.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  📥  hv-capture  ·  capture work items into .hv/BACKLOG.md
  triggers: "capture", "log bug"  ·  pairs: hv-go, hv-next
════════════════════════════════════════════════════════════════════════
```

# hv-capture — Capture & Manage Work Items

Quick-capture bugs, features, and tasks into `.hv/BACKLOG.md` with just enough context to act on them later. Handles multiple items and mixed types in one pass. Two management flags reach into the backlog after capture: `--remove <ID>` strips an item and its dependencies (the local inverse of capture), and `--from-github` / `--from-gitlab` pull open upstream issues into the backlog with `GH: #N` / `GL: #N` cross-references (round-trip closing happens via `/hv-ship`).

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases differ by mode (see Step 1.5):

**Capture mode (default):**

1. *Mode / dispatch* — single brain-dump or per-item parsing path resolved (Step 2)
2. *Audit code state* — when capturing from a milestone spec, surface candidates that look shipped (Step 2.5)
3. *Classify* — type (bug / feature / task), priority, size assigned (Step 3)
4. *Dedupe* — existing TODO entries scanned for overlap (Step 4)
5. *Append* — entries written to `BACKLOG.md` with milestone + repo tags (Steps 5–6)
6. *Report* — compact summary printed (Step 7)

**Remove mode (`--remove`):**

1. *Resolve IDs* — args parsed, each ID matched to a TODO entry (Step R1)
2. *Dry-run preview* — removal plan rendered, cross-references identified (Step R2)
3. *De-tag upstream issues* — optional manual gate to remove the upstream label before local delete (Step R3)
4. *Confirm* — three-option `AskUserQuestion` gate (apply / abort / customize) (Step R4)
5. *Apply removals + cross-ref sweep* — TODO entries deleted, detail files removed, cross-references swept (Step R5)

**Import mode (`--from-github` / `--from-gitlab`):**

1. *Resolve repos* — target repo set determined (Step I1)
2. *Discover candidates* — open issues fetched per repo, already-imported subtracted (Steps I2–I3)
3. *Pick issues* — user selects which issues to capture (Step I4)
4. *Capture* — IDs minted, detail files written, BACKLOG.md entries appended (Step I5)
5. *Label upstream* — `in-progress` label applied behind the manual gate (Step I6)
6. *Report* — compact summary printed (Step I7)

## Step 1.5 — Mode Dispatch

Inspect the first argument and route to the right mode:

| First arg | Mode | Routes to |
|-----------|------|-----------|
| `--remove <ID>[,<ID>...]` | Remove items from the backlog | [Remove Mode](#remove-mode) (Step R1+) |
| `--from-github` | Pull GitHub issues into the backlog | [Import Mode](#import-mode) (Step I1+) |
| `--from-gitlab` | Pull GitLab issues into the backlog | [Import Mode](#import-mode) (Step I1+) |
| (anything else / nothing) | Capture from user input | Step 2 onward (capture flow below) |

`--from-github` and `--from-gitlab` set the provider filter for Import Mode; in umbrella mode the resolved sub-repo set determines which repos are scanned (the flag still picks the provider type within those repos). The capture-mode flow is the default — when no flag is present, the user's text is parsed for items. Skip the entire `## Step 2 — Step 7` block when routing to a non-capture mode.

## Step 2 — Parse & Classify

The user will provide a keyword, short phrase, or longer description — possibly covering multiple issues or mixing bugs with feature requests and tasks.

**Split the input into distinct items.** Each item is a separate concern that would get its own ID. Clues that you're looking at multiple items:

- Separate sentences about unrelated problems
- "Also…", "and another thing…", "plus…"
- A list (numbered, bulleted, or comma-separated)
- Mixed language: some items describe broken behavior (→ bug), some describe desired behavior that doesn't exist yet (→ feature), some describe chores or maintenance (→ task)

**Classify each item:**

| Goes to | When the item describes… |
|---------|--------------------------|
| `## Bugs` | Broken behavior — something that worked and stopped, or doesn't work as expected |
| `## Features` | New or enhanced behavior — something that doesn't exist yet but should |
| `## Tasks` | Chores and maintenance — refactoring, dependency updates, docs, CI, cleanup |

## Step 2.5 — Audit Against Code State (milestone-spec capture only)

Fires only when the input is a capture *from a milestone spec* — i.e., the user's text references one of:

- An `M<NN>` tag (e.g., *"capture items from M04"*, *"seed M01 from the milestone spec"*)
- A path to a milestone file (`.hv/milestones/M04.md`, `milestones/M01.md`)

If neither pattern is present, skip this step entirely — ordinary brain-dump capture doesn't need the audit. Detection regexes: `M\d{1,2}\b` for the tag, `milestones/M\d{1,2}\.md` for the path.

**Why this step exists.** Milestone specs drift behind code state. A spec written months ago enumerates acceptance criteria that have since shipped under different IDs. Capturing those criteria as fresh items creates duplicate work and — under `autonomy.level: loop` — silently dispatches `/hv-work` against already-done work. The audit catches the drift before items land in the backlog. (Captured from real-session F27 incident: 11 captures from a stale milestone spec, 10 already shipped under different IDs, loop mode dispatched on one.)

**Run the audit.** Pass each parsed title (Step 2's output) as a positional arg:

```bash
.hv/bin/hv-capture-audit "<title 1>" "<title 2>" [...]
```

Exit codes:

- **0** — no ship evidence for any title. Continue to Step 3 silently.
- **2** — at least one title has plausible ship evidence; stdout carries the report (one `===` block per matching title, with `[STRONG]` / `[MEDIUM]` / `[PATH]` lines).
- **1** — usage error (no titles supplied). Surface and stop.

**On exit 2, surface the audit report to the user and ask per matching title.**

Print the helper's stdout verbatim first, then route by `autonomy.level`:

- **`"loop"`** — auto-skip every flagged title. Print one line per skipped title: *"Skipped `<title>` — ship evidence in `<top-match-hash>`."* Continue to Step 3 with the surviving titles. Per the authoring convention "routine routing/tagging auto-picks Recommended in loop mode" — invisible captures of already-shipped work is exactly what the loop must NOT do.
- **`"off"` / `"auto"`** — use `AskUserQuestion` to resolve each flagged title. Batch up to 4 flagged titles into one call; if more, present the rest in a second call after the first resolves.

For each flagged title, build one question:

- **Header:** `"Item N"` (with N = 1-based index within the flagged batch)
- **Question:** *"`<short-title>` looks shipped — `<top-match-hash>` `<top-match-subject>`. What now?"*
- **Options** (single-select):
  1. *"Skip this item (Recommended)"* — drop the title from this capture run; don't append.
  2. *"Capture anyway"* — the user has reviewed the matches and confirms this item is genuinely distinct (e.g., the prior commit was an incomplete first pass). Proceed with appending.
  3. *"Stop the whole capture"* — abort the entire capture. The user reconciles the milestone spec via `/hv-vision` or rewrites it by hand before retrying.

Route each resolution:

| Answer | Action |
|--------|--------|
| Skip (Recommended) | Remove the title from the survivors list; continue with the rest |
| Capture anyway | Keep the title in the survivors list; continue |
| Stop the whole capture | Exit `/hv-capture` immediately, print *"Capture aborted — reconcile the milestone spec before retrying."*, do not write anything to BACKLOG.md |

Plain-text fallback: *"Skip, capture anyway, or stop?"* per flagged item.

**Carry the survivors list into Step 3 and onward.** Filtered titles never reach `## Bugs` / `## Features` / `## Tasks`.

## Step 3 — Gather Context

For each item, gather **just enough context** to make it actionable later. Ask 2–4 quick questions total across all items — not per item.

**Caller caps.** If the invoking args carry a speed-path signal from an upstream skill (e.g., a `(hv-go — cap clarification at 1-2 questions)` prefix), respect it — usually 1-2 questions max, often zero. `/hv-go` prioritizes speed over thoroughness; honoring the cap is what keeps that contract.

Pick from:

**For bugs:**
- What's the expected vs. actual behavior? (if not obvious)
- How do you trigger it? (steps or conditions)
- Does it happen every time or intermittently?
- Which view/screen/component is affected?
- Any error messages or console output?

**For features:**
- What's the user-facing behavior? (if not obvious)
- Which part of the app does this touch?
- Is there an existing workaround?
- What triggers the need for this?

**For tasks:**
- What's the goal or desired outcome? (if not obvious)
- Which area of the codebase does this touch?
- Is there a deadline or dependency?
- Any relevant context (error output, PR link, conversation reference)?

**Skip questions the user already answered.** If the input is detailed enough, you may not need to ask anything.

## Step 4 — Assign Priority / Size

For **bugs**, assign one of:

| Tag | Meaning |
|-----|---------|
| `[P0]` | Blocks usage — crash, data loss, can't complete core workflow, security issue |
| `[P1]` | Degrades experience — wrong behavior, broken feature, ugly but usable, workaround exists |
| `[P2]` | Minor annoyance — cosmetic glitch, edge case, slightly wrong state, user unlikely to notice |

For **features**, assign one of:

| Tag | Meaning |
|-----|---------|
| `[Major]` | Large scope — new screens, significant rework, breaks existing patterns, multi-day effort |
| `[Minor]` | Contained change — new option, small UI addition, touches 1–3 files, hours of work |
| `[Cosmetic]` | Visual polish — spacing, color, label tweak, animation refinement, minutes of work |

**Tasks** get no priority or size tag.

## Step 4.5 — Tag Active Milestone (when applicable)

Use the milestone-tagging UX pattern in `references/milestone-tagging.md`. The pattern covers: the `hv-vision-active` gate, the one-active vs multiple-active question shapes (verbatim AskUserQuestion text), caller-cap handling for the `/hv-go` speed path, loop-mode auto-pick semantics, plain-text fallback, and the outcome mapping.

Carry the chosen milestone(s) as a comma-separated list into Step 6's `Milestone:` suffix on the TODO entry. If the user picked the "leave untagged" option (or skipped the question), omit the suffix.

## Step 4.6 — Tag Sub-Repo (when umbrella mode is on)

Use the umbrella-mode gate from `references/umbrella-mode.md` — when `hv-umbrella-on` returns `yes` AND `.hv/repos.json` registers ≥1 sub-repo (the registry is the truth, not the config flag), ask which sub-repo(s) each item belongs to. Otherwise skip this step silently.

The question shape:

- **Header:** `"Repos"`
- **Question:** *"Which sub-repo(s) does this item belong to?"* (include the item's short title for context)
- **multiSelect:** `true`
- **Options** (one per registered repo + an explicit untag option):
  - One option per `name` in `.hv/repos.json` (mark the most likely match `(Recommended)` if the item's text mentions a repo name)
  - *"None / unsure — leave untagged"* (last option)

Multi-select means the user can pick one sub-repo (single-repo item), two or more (multi-repo item — `/hv-work` will create the same branch in each via `bin/hv-multi-branch-create`, see `references/umbrella-mode.md` *Branch creation*), or just *"None / unsure"* to leave the item untagged. If the user picks *"None / unsure"* alongside concrete repo names, treat the concrete picks as authoritative.

Plain-text fallback: ask once. If the reply is ambiguous, default to leaving the item untagged — `/hv-work` will then refuse to dispatch the item with a clear error pointing back to `/hv-capture`.

**Caller cap:** if invoked with the `(hv-go — cap clarification at 1-2 questions)` prefix and there's exactly one registered repo, auto-tag without asking. With ≥2 registered repos, the cap is exempt for this single question — silently skipping would force `/hv-work` to bail later.

**Loop mode:** if `autonomy.level == "loop"`, auto-pick the `(Recommended)` sub-repo option when one is flagged (item text mentions a repo name). If no option carries `(Recommended)` (item is ambiguous about sub-repo), fall through to AskUserQuestion or the caller-cap path; this is exactly the kind of ambiguity that should surface. Honors the authoring convention "routine routing/tagging auto-picks Recommended in loop mode" (see `references/authoring-conventions.md` rule #5).

Carry the chosen sub-repo name(s) as a comma-separated string into Step 6's `Repos:` suffix on the TODO entry. If only *"None / unsure"* was picked (or nothing was picked), omit the suffix.

## Step 5 — Handle Large Input

Use the detail-files pattern in `references/detail-files.md` when an item's input is bulky enough to bloat the TODO entry beyond ~3 sentences (crash dumps, stack traces, logs, specs, checklists, config snippets, long reproduction steps). The reference covers the markdown template, the ordering (get ID → write detail file → append TODO entry with `Detail:` reference), and the `Detail:` reference format.

Skip this step entirely for items that fit comfortably in 1–3 sentences. Most entries won't need a detail file.

## Step 6 — Write All Entries

**Consult the Glossary.** Before composing the bullet, scan the `## Glossary` topic of `.hv/KNOWLEDGE.md` (via `hv-glossary-read` if you have a candidate term, or by reading the topic directly when scoping multiple). If the user's phrasing maps to a canonical term (or one of its aliases), use the canonical name in the captured bullet so the backlog stays consistent with the rest of the project's vocabulary. If the captured idea introduces a *new* domain concept the user names explicitly, suggest `/hv-learn --term <name>` after the capture commits — never auto-invoke.

For each item, get the next ID and append the entry in a single command:

```bash
ID=$(.hv/bin/hv-next-id bugs) && .hv/bin/hv-append "## Bugs" "- **[$ID] [P1] Short title.** Description. Related: [F02]"
```

Change the type (`bugs`, `features`, `tasks`), section (`## Bugs`, `## Features`, `## Tasks`), and entry content for each item.

**Entry formats:**

- Bug: `- **[$ID] [Priority] Short title.** What happens, when, what should happen instead. Related: [F02], [T01] Milestone: M01 Repos: web`
- Feature: `- **[$ID] [Size] Short title.** What it does, where it lives, why it matters. Related: [B01], [T03] Milestone: M02 Repos: api`
- Task: `- **[$ID] Short title.** What needs to happen and why. Related: [F01], [B02] Milestone: M01, M03 Repos: web`

With detail file, insert `Detail: \`.hv/{type}/{ID}.md\`` before `Related:`.

**Field order:** title.description. then any combination of `Detail:`, `Related:`, `Milestone:`, `Repos:`, and `Subsystem:` (optional). Each is independently optional. `Related:` is for cross-item links; `Milestone:` is for milestone tagging from Step 4.5; `Repos:` is for sub-repo tagging from Step 4.6 (umbrella mode only — comma-separated list of registered sub-repos; a single name is the common case, two or more turns the item into a multi-repo dispatch via `/hv-work`); `Subsystem:` is the project-map subsystem this item belongs to.

**`Since:` is auto-stamped.** `hv-append` appends ` Since: <short-hash>` (HEAD at capture time) to every new bullet that doesn't already carry the field, when invoked inside a git repo with at least one commit. The Since anchor lets `hv-todo-drift` ignore commits older than capture — prevents false-positives when IDs are reused across machine syncs. Don't include `Since:` in the entry string manually; let `hv-append` stamp it.

**Subsystem inference (optional).** Scan filenames and skill references in the user's text against the entries in `.hv/map/` (or the `## Project Map` block in CLAUDE.md). If a match is clear — e.g. the user mentions `hv-work`, `bin/hv-staleness`, or `hv-init` — append `Subsystem: <name>` (the closest map entry name) to the captured row. If no confident match exists, omit the field entirely. **Never block or delay capture for a missing Subsystem.** The field is a soft hint for map hygiene, not a required tag.

Example:
```
Before: - **[B07] [P1] Title.** Description. Milestone: M01 Captured: 2026-05-09
After:  - **[B07] [P1] Title.** Description. Milestone: M01 Subsystem: capture Captured: 2026-05-09
```

The `Related:` suffix is optional — only add it when an item clearly relates to an existing entry. **Items created in the same batch can reference each other.** Scan `## Bugs`, `## Features`, and `## Tasks` in `.hv/BACKLOG.md` and also `.hv/ARCHIVE.md` (if it exists) for obvious connections before writing. Don't force links that aren't there.

### Examples

Single bug:
```markdown
- **[B05] [P1] Timer badge shows stale duration after pause.** When you pause a running timer and reopen the panel 5+ minutes later, the menubar badge still shows the duration from when it was paused, not the current elapsed. Refreshes correctly after any interaction. Likely a timer invalidation issue in MenuBarManager. Related: [F03]
```

Single feature:
```markdown
- **[F03] [Minor] Quick-switch between recent projects.** Cmd+Tab-style overlay that shows the 3 most recent projects for fast switching without opening the project picker. Useful for consultants bouncing between clients throughout the day. Related: [B05]
```

Single task:
```markdown
- **[T02] Update Swift toolchain to 6.2.** Current project uses 5.10. Needed before adopting typed throws and the new concurrency features in the next milestone. Related: [F04]
```

Bug with detail file:
```markdown
- **[B07] [P0] App crashes on launch after iOS 18.2 update.** EXC_BAD_ACCESS in CoreData stack during migration. Affects all users on 18.2+, 100% repro rate. Detail: `.hv/bugs/B07.md` Related: [F12]
```

Feature tagged with the active milestone:
```markdown
- **[F08] [Minor] OAuth token rotation.** Refresh tokens 5 minutes before expiry; transparent retry on 401. Milestone: M01
```

Feature tagged with sub-repo (umbrella mode):
```markdown
- **[F09] [Minor] Sticky header on scroll.** Keep the top nav fixed when the user scrolls past 100px. Milestone: M02 Repos: web
```

Mixed input — user says *"the sidebar flickers on hover, also we should add keyboard shortcuts for the top 5 actions, and update the linter config to enable the new rules"*:
```markdown
## Bugs
- **[B03] [P2] Sidebar flickers on hover.** Hover state causes a visible flicker, likely a re-render or transition conflict in the sidebar component.

## Features
- **[F04] [Minor] Keyboard shortcuts for top actions.** Add keyboard shortcuts for the 5 most-used actions to speed up power-user workflows.

## Tasks
- **[T06] Update linter config for new rules.** Enable the recently added lint rules in the project config. Related: [B03]
```

## Step 7 — Brainstorm Nudge

Fires only when the captured batch includes at least one `[Major]` feature OR one `[P0]` bug. Skip silently for `[Minor]` / `[Cosmetic]` features and `[P1]` / `[P2]` bugs — design exploration is a poor fit for small contained work.

Append one line to the capture report for each qualifying ID, in every autonomy mode (`off` / `auto` / `loop`):

> *"Run `/hv-brainstorm [ID]` before `/hv-plan` to negotiate the design."*

Place this line after any existing post-capture nudges (e.g., release-pending), separated by one blank line.

**Never invoke `/hv-brainstorm` from this skill.** Capture is pure intake; pulling the user into design exploration mid-brain-dump conflates two phases the workflow keeps separate. Autonomous advancement lives where "advance without asking" semantics belong: `/hv-next` Step 6 auto-dispatches `/hv-brainstorm` for the suggested item in `auto` mode, and `/hv-work` Step 4 auto-dispatches `/hv-brainstorm --auto-loop` for Major + Milestone-tagged items without a design in `loop` mode. The nudge line above is the bridge to either path.

---

## Remove Mode

The inverse of the capture flow above: remove one or more items from the backlog and clean up every trace — the BACKLOG.md entry, Related cross-references, the detail file (`.hv/{bugs,features,tasks}/<ID>.md`), and any plan keyed to the item (`.hv/plans/<milestone>-<ID>.md`). The safe default is dry-run: every invocation previews what would change before touching anything. Items currently active in `status.json` are refused outright unless `--force` is passed, which strips them with a warning. The ARCHIVE.md historical record is preserved by default; pass `--scrub-archive` alongside `--force` to remove it too — opt-in only, since a removed item's ARCHIVE entry is the only audit trail left. Counters do not decrement — minted IDs stay claimed forever.

### Step R1 — Parse Arguments

Pass the user's argument verbatim as `<CSV>` to `bin/hv-rm` in Step R2. The helper validates IDs (split-and-strip on commas — `B01, F03` and `B01,F03` resolve identically), exits 1 with a usage message on empty or missing argv, and exits 1 again on unknown IDs (not in BACKLOG.md or ARCHIVE.md). No skill-side validation needed.

### Step R2 — Dry-Run Preview

Run the helper with no `--force` flag; it defaults to dry-run and prints what would change:

```bash
.hv/bin/hv-rm <CSV>
```

Exit codes:

- **0** — preview printed successfully. Surface the full stdout to the user verbatim, then continue to Step R3.
- **1** — one of the IDs was not found in BACKLOG.md or ARCHIVE.md, or an unrecognised flag was given. Surface the stderr message to the user verbatim and **stop** — do not proceed to Step R3.
- **2** — one or more IDs are currently active in `status.json`. Surface the stderr message verbatim and inform the user: *"The item is active. Proceeding via Step R4 with `--force` will strip it from the active stream and leave a warning in the output."*

### Step R3 — De-tag Upstream Issues (manual gate)

> **Manual gate — removing the upstream label.** Removing the `in-progress` label on the upstream issue is externally-visible — collaborators see the issue no longer claimed. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The item delete proceeds regardless; this step decides whether to clean up the label upstream too. See `references/manual-gates.md`.

Run the lookup helper to discover cross-references for the items about to be removed:

```bash
.hv/bin/hv-issues-imported
```

The helper always exits 0 and emits a JSON array. Filter it to entries whose `item_id` is in the to-be-removed set (the `<CSV>` from Step R1):

```bash
# Example: CSV = "F69,B12"
IDS_JSON=$(echo "<CSV>" | tr ',' '\n' | jq -Rn '[inputs | gsub("^\\s+|\\s+$"; "")]')
REFS=$(
  .hv/bin/hv-issues-imported \
  | jq --argjson ids "$IDS_JSON" '[.[] | select(.item_id as $id | $ids | index($id) != null)]'
)
```

Read the label name from config (default `"in-progress"`):

```bash
LABEL=$(jq -r '.issues.label // "in-progress"' .hv/config.json 2>/dev/null || echo "in-progress")
```

**If `$REFS` is an empty array (`[]`), skip the gate entirely and proceed to Step R4.**

If `$REFS` is non-empty, surface the `AskUserQuestion` below. **In loop mode this question is still surfaced and never auto-picked — it is a manual gate.**

- **Header:** `"De-tag"`
- **Question:** `"Remove the \`<label>\` label on <N> upstream issue(s)? <list of #N>."`
  (Substitute `<label>` from `$LABEL`, `<N>` from `$REFS | length`, and list each `#<issue>` from `$REFS`.)
- **Options** (single-select):
  1. `"Yes, remove the label upstream"` — for each entry in `$REFS`, call in parallel:
     ```bash
     .hv/bin/hv-issues-label remove --issue <issue> --label "$LABEL" [--repo <repo>]
     ```
     Include `--repo <repo>` only when the entry's `repo` field is non-null. Propagate exit 1 if any call fails.
  2. `"No, just delete the item"` — print the warning below and continue:
     ```
     Note: upstream issues still carry the `<label>` label. Remove via
     `gh issue edit <N> --remove-label <label>` or `glab issue update <N> --unlabel <label>` if desired.
     ```

Proceed to Step R4 regardless of which option was chosen.

### Step R4 — Confirmation Gate

Use a single `AskUserQuestion` call. Show the dry-run output above the question so the user can review the plan before committing.

- **Header:** `"Apply"`
- **Question:** `"Apply this removal plan for <CSV>?"`
- **Options** (single-select):
  1. `"Apply (Recommended)"` — runs `.hv/bin/hv-rm --force <CSV>`. Strips the TODO entry and Related cross-references; ARCHIVE entries stay intact as the historical record.
  2. `"Apply + scrub ARCHIVE"` — runs `.hv/bin/hv-rm --force --scrub-archive <CSV>`. Same as Apply, plus removes the ARCHIVE.md historical entry and strips any Related cross-references there too.
  3. `"Cancel"` — print *"No changes."* and stop; nothing is written.

Plain-text fallback (when `AskUserQuestion` is not available): ask once — *"Apply changes? (yes/no/scrub-archive)"* — `yes` → Apply; `scrub-archive` → Apply + scrub ARCHIVE; anything else → Cancel.

> Per the `hv-init` authoring convention "manual gates that are destructive or file public artifacts are never auto-invoked regardless of autonomy", the confirmation gate always surfaces to the user — loop mode does not accelerate it.

### Step R5 — Apply (when not Cancel)

Invoke the chosen helper command. The helper prints a per-ID summary line for each item processed. Pass the full output through to the user verbatim. Then stop — do not nudge any other skill.

### When to Use Remove Mode

Use `--remove` when:

- An item was captured as a duplicate and the original already covers it.
- The underlying premise turned out to be wrong — the bug doesn't exist, or the feature was based on a misunderstanding.
- Another item's implementation made this one obsolete before it was started.
- The item was captured against the wrong project context (wrong repo, wrong milestone scope).
- A spike or decision ruled out the approach the item depended on.
- You simply changed your mind and the work is no longer worth doing.

`--remove` is the local inverse of capture — it does **not** close upstream GitHub/GitLab issues. If the removed item has a linked issue, Step R3 offers to remove the `in-progress` label upstream; closing the issue itself is always manual. Counters intentionally do not decrement; minted IDs remain claimed so there is never ambiguity about what `[F36]` referred to.

---

## Import Mode

Inventory-driven capture: fetch open issues from the upstream GitHub or GitLab repo(s), subtract ones already in the backlog, let the user pick which to capture, mint IDs, write detail files, and apply an `in-progress` label upstream behind a manual gate. The provider is fixed by the dispatching flag — `--from-github` scans GitHub repos, `--from-gitlab` scans GitLab repos. Round-trip closing is handled separately by `/hv-ship` and `bin/hv-issues-close`.

### Step I1 — Resolve Target Repo Set

Read `issues.providers.github` and `issues.providers.gitlab` from `.hv/config.json` (default `true` when the key is absent — `/hv-init` seeds both as `true`, but pre-schema-visibility configs may lack them); if the resolved value for the provider matching the invoking flag is literally `false`, stop with: *"Provider disabled: set `issues.providers.<github|gitlab>` to `true` in `.hv/config.json` to enable."*

**Single-repo mode:** when `.hv/bin/hv-umbrella-on` prints `no` (or `.hv/repos.json` registers 0 sub-repos), target is cwd's repo. Skip the picker and proceed to Step I2 with that single target. If the cwd's `hv-issues-provider` doesn't match the dispatching flag (e.g. user passed `--from-github` but cwd is a GitLab repo), stop with: *"Provider mismatch: --from-<flag> requires a <flag> remote; cwd resolves to <other>."*

**Umbrella mode:** when `.hv/bin/hv-umbrella-on` prints `yes` AND `.hv/repos.json` registers ≥1 sub-repo:

- Read sub-repo names from `.hv/repos.json`.
- Filter to those whose `hv-issues-provider --repo <name>` matches the dispatching flag (mismatched repos are silently dropped — they live on a different provider).
- Present the matching set in an AskUserQuestion (multiSelect) chunked to ≤4 options at a time. Header `"Repos"`. Question: *"Which sub-repos to pull issues from?"*. One option per filtered repo name; mark all `(Recommended)` when no single repo is obviously favored.
- Include a *"All repos"* option (first option, `Recommended`) and a *"None / cancel"* option (last option).
- **Loop mode:** when `autonomy.level == "loop"`, silently auto-pick the `(Recommended)` option (all repos) without invoking AskUserQuestion — loop mode drains the queue.
- Plain-text fallback: ask once — *"Which repos? (all / <name> / none)"* — `all` picks all; a repo name picks that one; anything ambiguous defaults to all repos.
- If 0 sub-repos resolve after the pick, fall through to single-repo mode.

### Step I2 — Discover Candidates Per Repo

For each target repo, dispatch a **parallel tool-call batch** (all three calls in a single turn):

```bash
.hv/bin/hv-issues-provider [--repo <name>]
.hv/bin/hv-issues-list [--repo <name>] [--mine]
.hv/bin/hv-issues-imported [--repo <name>]
```

Read `issues.filterMineOnly` from `.hv/config.json`. When `true`, pass `--mine` to `hv-issues-list`; when `false` or absent, omit it. The helper maps `--mine` to the provider's author-self filter (`--author @me` for both `gh` and `glab`). Never pass `--label @me` — that would filter for a label literally named `@me`.

Read `issues.label` from `.hv/config.json` (default `"in-progress"`) — this is the target label applied upstream in Step I6 for round-trip tagging. Never pass it to `hv-issues-list` as a filter; it is not a source filter, which is why the call above takes no `--label` argument.

Exit-code handling per repo:

- `hv-issues-provider` always exits 0. If it prints anything other than the dispatching provider, skip that repo with: `skipped: <repo> — provider mismatch`.
- `hv-issues-list` exits 0 on success (even empty). If it exits 1 (CLI missing or unauthed), skip that repo with: `skipped: <repo> — <stderr from hv-issues-list>`.
- `hv-issues-imported` always exits 0.

Never hard-fail the whole step on a single repo failure. Continue with the repos that succeeded.

### Step I3 — Subtract Already-Imported Issues

For each repo, filter the `hv-issues-list` output against the `hv-issues-imported` index.

An issue is already imported when a `(provider, repo, issue_number)` triple from `hv-issues-imported` matches. For single-repo mode, `repo` is `null` in the imported index — match on `(provider, issue_number)` only.

Count and report: *"Repo `<name>`: N candidates, K already imported — showing M."*

If the total remaining candidates across all repos is 0, print:

> Nothing to capture — all open issues are already in BACKLOG.md or ARCHIVE.md.

Then stop.

### Step I4 — Show Candidates and Pick

Present candidates in AskUserQuestion (multiSelect) chunked to ≤4 issues at a time. For each chunk:

- **Header:** `"Issues"`
- **Question:** `"Which issues to capture? (<range> of <total>)"`
- **Options** (one per candidate): label `"#<N>: <title truncated to 60 chars>"`, description `"<labels-list> · by @<author> · <url>"`.
- When there is only one chunk (≤4 candidates), omit the range indicator from the question: `"Which issues to capture?"`.

Plain-text fallback: ask once — *"Which issue numbers to capture? (comma-separated, e.g. 12,47,83, or 'none')"* — parse the reply as a comma-separated list of issue numbers; `none` or empty → stop.

**Loop mode:** when `autonomy.level == "loop"`, auto-pick all remaining candidates without invoking AskUserQuestion — loop mode captures everything not already imported. Per the manual-gate rule below, loop mode still surfaces Step I6.

### Step I5 — Classify and Capture Each Pick

For each selected issue:

**I5a — Classify section from remote labels.**

| Remote label | Section |
|---|---|
| `bug`, `kind/bug` | `## Bugs` |
| `enhancement`, `feature`, `kind/feature` | `## Features` |
| anything else (or no labels) | `## Tasks` |

When a label maps unambiguously to a section, classify silently (no question). When none of the labels match any classifier key, default to `## Tasks` silently.

**I5b — Assign priority / size.**

- Bugs classified from `bug`/`kind/bug` → default `[P1]` silently. Ask only when the issue body suggests `[P0]` (crash, data loss, production outage language) or `[P2]` (cosmetic, wording).
- Features classified from enhancement/feature → default `[Minor]` silently. Ask when the body describes clearly `[Major]` scope (new screens, significant rework, multi-repo).
- Tasks → no tag.

When asking is warranted: one AskUserQuestion per pick (single-select, ≤4 options). Header: `"Classify #<N>"`. Question: `"Priority / size for '<title>'?"`. Options: up to 4 choices relevant to the section (e.g. for Bugs: `"[P0] — crash / data loss"`, `"[P1] — broken feature (Recommended)"`, `"[P2] — cosmetic / edge case"`, `"Leave default"`).

**Loop mode:** when `autonomy.level == "loop"`, skip classification AskUserQuestion calls entirely — use the silent defaults above for every issue.

**I5c — Mint ID and write detail file.**

```bash
ID=$(.hv/bin/hv-next-id <bugs|features|tasks>)
```

Write `.hv/<bugs|features|tasks>/<ID>.md` with the issue body as markdown passthrough, followed by:

```markdown
---
**Upstream:** <url>
**Captured from:** <provider> #<N>
```

**I5d — Append BACKLOG.md entry.**

```bash
.hv/bin/hv-append "## <Section>" "- **[<ID>] [<Tag>] <Title>.** <first-sentence-or-two-of-body>. Detail: \`.hv/<kind>/<ID>.md\` <provider-tag> Repos: <name>"
```

Where `<provider-tag>` is `GH: #<N>` for GitHub or `GL: #<N>` for GitLab. Omit `Repos: <name>` in single-repo mode. Omit `[<Tag>]` for Tasks (no priority/size tag).

Entry shapes:

- Bug: `- **[B##] [P1] Title.** First sentence of body. Detail: `.hv/bugs/B##.md` GH: #N Repos: <name>`
- Feature: `- **[F##] [Minor] Title.** First sentence of body. Detail: `.hv/features/F##.md` GL: #N Repos: <name>`
- Task: `- **[T##] Title.** First sentence of body. Detail: `.hv/tasks/T##.md` GH: #N Repos: <name>`

Process all selected issues serially in this step (mint → write detail → append) to avoid counter collisions from parallel ID minting.

### Step I6 — Apply the `in-progress` Label Upstream

> **Manual gate — labeling upstream issues.** Applying the `in-progress` label (or the configured `issues.label` value) upstream is externally-visible state — collaborators see the issues marked as claimed. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The orchestrator may stage which issues to label, but the user confirms before any label is written. See `references/manual-gates.md`.

Read `issues.label` from `.hv/config.json` (default `"in-progress"`). Present a single AskUserQuestion (single-select):

- **Header:** `"Label upstream"`
- **Question:** `"Apply \`<label>\` to these <N> issues upstream?"` followed by a summary list of picked issue titles and numbers.
- **Options:**
  1. `"Yes — apply \`<label>\` to all (Recommended)"`
  2. `"No — skip labeling"`

Plain-text fallback: ask once — *"Apply `<label>` to these issues upstream? (yes/no)"* — `yes` applies; anything else skips. Default: skip (opt-in-off — this is externally-visible state; silence is not consent).

On **Yes**: fan out parallel `.hv/bin/hv-issues-label` calls — one per picked issue:

```bash
.hv/bin/hv-issues-label apply --issue <N> --label <label> [--repo <name>]
```

On any `hv-issues-label` failure (exit 1), print the error inline and continue with remaining issues — do not abort.

On **No**: print *"Labeling skipped. Issues are captured in BACKLOG.md but not marked upstream."* and continue to Step I7.

**Loop mode:** auto-picking `Yes` is **forbidden** here. This is a manual gate — externally-visible state requires user confirmation. In loop mode, surface the AskUserQuestion and pause the loop until the user resolves it. This matches the `/hv-ship` Step 6a pattern: loop mode never auto-picks acceptance-of-risk answers.

### Step I7 — Compact Report

```
Captured <N> issues:
- [ID1] Title 1 (GH #42 → in-progress)
- [ID2] Title 2 (GL #7 → in-progress)
Skipped <K> issues (already imported).
```

When the label step was skipped (user picked "No" or fallback defaulted to skip), replace `→ in-progress` with `→ not labeled` for each pick.

When repos were skipped in Step I2 (provider mismatch or missing CLI), append a `Skipped repos:` section listing each with its reason.

---

## Rules

**Capture mode:**

- **Never remove or reorder existing entries** — append only
- **Don't investigate now** — just capture
- **Confirm what you wrote** — show the user every entry you added, grouped by section
- **Always increment counters** — even if you're unsure, every ID must be unique

**Remove mode:**

- Default is dry-run; `--force` is the only way to apply changes.
- Active-stream items (in `status.json`) are refused without `--force`; with `--force`, the ID is stripped and a warning surfaces in the output.
- ARCHIVE.md is preserved by default; `--scrub-archive` is opt-in.
- Counters do not decrement — minted IDs stay claimed.
- Upstream `in-progress` labels are removed only when the user approves the Step R3 manual gate; closing upstream issues is always manual.

**Import mode:**

- Issues already in BACKLOG.md or ARCHIVE.md are never re-imported. Index by `GH: #N` / `GL: #N` via `hv-issues-imported`. The triple `(provider, repo, issue_number)` is the uniqueness key.
- Label application is always behind the manual gate (Step I6). No `autonomy.level` value bypasses it.
- Loop mode auto-picks routine routing answers (which repo(s) to pull from, which issues to capture) but never the label-application gate.
- Writes to `.hv/BACKLOG.md` — no commits are produced. Captured items move forward via `/hv-work` like any other item, which bundles backlog updates into the cycle's close-the-loop commit.
- The `GH: #N` cross-reference on the BACKLOG entry is the signal `hv-ship-body` uses to emit `Closes #N` in PR bodies (F12). Include it exactly.
- `issues.providers.github` / `issues.providers.gitlab` config flags gate provider access per-type. When a flag is `false`, the matching `--from-<provider>` flag stops with a config error.

## References

| Reference | Purpose |
|-----------|---------|
| [`authoring-conventions.md`](../references/authoring-conventions.md) | Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold). |
| [`banner-preamble.md`](../references/banner-preamble.md) | Banner-print rule shared by every skill. |
| [`detail-files.md`](../references/detail-files.md) | Detail-file template used when an item's input exceeds 3 sentences. |
| [`manual-gates.md`](../references/manual-gates.md) | Manual-gate callout shape (Step R3 de-tag, Step R4 apply gate, Step I6 label upstream). |
| [`milestone-tagging.md`](../references/milestone-tagging.md) | Milestone-tagging UX pattern used by capture/go skills. |
| [`umbrella-mode.md`](../references/umbrella-mode.md) | Umbrella-mode helpers, registry shape, and `Repos:` field semantics. |
