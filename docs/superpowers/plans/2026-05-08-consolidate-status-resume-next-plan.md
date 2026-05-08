# Consolidate /hv-status, /hv-resume, /hv-next Implementation Plan

> **For agentic workers:** This plan executes through `/hv-work` Step 4's plan-as-artifact path. `/hv-work` will read this file and dispatch the tasks below as worker subagents under the F11 default (workers write files; orchestrator commits per task in Step 7.5). Steps within tasks use checkbox (`- [ ]`) syntax for tracking. The natural execution call is `/hv-work execute the plan at docs/superpowers/plans/2026-05-08-consolidate-status-resume-next-plan.md`.

**Goal:** Hard-delete `hv-status/` and `hv-resume/`, fold `/hv-resume`'s handoff-detection into `/hv-next` Step 2, bump to `2.0.0`, and sweep every cross-reference across SKILL.md, plugin manifests, docs, and managed CLAUDE.md blocks.

**Architecture:** Four sequential waves of parallel-safe tasks. Wave 1 modifies surviving SKILL.md prose (no deletions yet, so the existing `hv-resume/SKILL.md` remains as the canonical source for the handoff-read pattern T1 mirrors). Wave 2 performs the breaking changes: folder deletions, plugin.json drops, version bump, hv-skills-index heredoc edit. Wave 3 sweeps all docs in parallel. Wave 4 finalizes — KNOWLEDGE/DECISIONS bullet sweeps, CHANGELOG, regenerate managed CLAUDE.md blocks, run acceptance checks. Workers write only; the orchestrator commits each task with the suggested message.

**Tech Stack:** Bash, Python (for plugin.json edits), Markdown, the existing `bin/hv-skills-index` and `bin/hv-knowledge-index` helpers.

**Spec:** `docs/superpowers/specs/2026-05-08-consolidate-status-resume-next-design.md` (commit `1db2bc1`).

---

## Open questions — resolved inline

1. **Banner emoji for the merged `/hv-next`** → **keep `👉`**. The merged command is "the one entry point for current state"; `👉` reads as "look here / pick this up" which matches both the suggest-next semantics and the resume-after-clear semantics. Switching to `🔄` would over-index on the resume case.
2. **`docs/usage/next-and-status.md` filename** → **rename to `docs/usage/picking-work.md`**. With `/hv-status` gone, the dual-name title is misleading. `picking-work` matches the doc's actual subject (how to choose what to do next).
3. **`/hv-pause`'s mention of `/hv-resume`** → **mechanical replace with `/hv-next`**. Specific wording: every occurrence of `/hv-resume` in `hv-pause/SKILL.md` becomes `/hv-next`. The phrase *"so /hv-resume in a fresh session can pick up"* becomes *"so /hv-next in a fresh session can pick up"*.

## Assumptions

- No third-party docs reference `/hv-status` or `/hv-resume` beyond the files under `docs/` listed in this plan. (User-facing surface only — historical specs and plans under `docs/superpowers/` are intentionally preserved as-is.)
- `test/smoke.sh` does not enumerate `plugin.json` skill names by literal string — its `hv-status-*` / `hv-status-add` references are about the *helpers*, not the slash-command. (Verified via `git grep` survey before writing this plan.)
- `bin/hv-knowledge-index`, `bin/hv-skills-index`, `bin/hv-managed-block` continue to work after the deletions; they have no static dependency on the deleted skill folders.
- Existing `.hv/` runtime state (`status.json`, `handoff/`, etc.) does not need migration — schema unchanged.
- The CHANGELOG migration paragraph is the only forewarning given to consumers; no in-product deprecation notice is desired (per spec).

---

## File structure

**Created:**
- `docs/usage/picking-work.md` — renamed from `next-and-status.md`, prose updated for one-command world

**Modified:**
- `hv-next/SKILL.md` — Step 2 absorbs handoff detection + new "handoff present" question arm; banner triggers/pairs updated; frontmatter description updated
- `hv-pause/SKILL.md` — every `/hv-resume` reference becomes `/hv-next`; `pairs:` line updated
- `hv-debug/SKILL.md` — line 236 updates `/hv-resume / /hv-next` reference to `/hv-next`
- `hv-ship/SKILL.md` — line 36 ("resume a paused branch") and line 162 (umbrella note) update `/hv-resume` → `/hv-next`
- `hv-work/SKILL.md` — line 433 (umbrella note) updates `/hv-resume / /hv-next` → `/hv-next`
- `hv-learn/SKILL.md` — line 120 drops `/hv-status` and `/hv-resume` from the slash-command name list
- `plugin.json` — drops `./hv-status` and `./hv-resume` from `skills` array; bumps `version` to `2.0.0`
- `.claude-plugin/plugin.json` — same edits as `plugin.json`
- `bin/hv-skills-index` — heredoc body drops both from the "Capture & pick" group line
- `README.md` — drops two rows from slash-command index table; updates `## Pause/resume` prose; updates mermaid `STATUS`/`RESUME` nodes; updates marketing-grid bullets
- `docs/reference/slash-commands.md` — removes `## /hv-status` and `## /hv-resume` sections; updates `## /hv-next` description to mention handoff detection
- `docs/usage/pausing-and-resuming.md` — substantial rewrite of `/hv-resume` section as `/hv-next reading a handoff note`
- `docs/README.md` — updates the two cross-link bullets that name `/hv-status` and `/hv-resume`
- `docs/faq.md` — line 7 prose mention updated
- `docs/getting-started.md` — line 87 prose mention updated
- `docs/reference/hv-folder.md` — lines 23, 60, 82, 110 — replace `/hv-resume` and `/hv-status` references
- `docs/reference/preflight.md` — line 27 — drop `/hv-resume` from observe-only-skills list
- `docs/usage/parallel-work.md` — line 63 — drop `/hv-status` from the named skill list
- `docs/usage/umbrella-mode.md` — lines 115, 122 — replace `/hv-resume` and `/hv-status` references
- `.hv/KNOWLEDGE.md` — slash-command name list in any matching bullet updates (mechanical)
- `.hv/DECISIONS.md` — same mechanical update if any decision body mentions the dead names
- `CHANGELOG.md` — new `## 2.0.0` section prepended

**Deleted:**
- `hv-status/` (entire folder, currently `hv-status/SKILL.md` only)
- `hv-resume/` (entire folder, currently `hv-resume/SKILL.md` only)

---

## Wave 1 — Modify surviving SKILL.md prose

Three parallel write-only tasks. T1 is the substantive change; T2 and T3 are mechanical sweeps of remaining cross-references.

### Task 1: `hv-next/SKILL.md` absorbs `/hv-resume`'s handoff detection

**Files:**
- Modify: `hv-next/SKILL.md` (currently 193 lines; expected to land near 240-260)

- [ ] **Step 1: Update the YAML frontmatter description**

Open `hv-next/SKILL.md`. Replace lines 1-5 (the frontmatter block) with:

```yaml
---
name: hv-next
description: Review the backlog, reconcile active work against git state, archive old completions, show sorted tables with relationship clusters, suggest the next item, and route to /hv-work. Detects handoff notes from /hv-pause on active streams (post-/clear reorientation flow). Use on "what should I work on", "where was I", "pick up the next task", "resume", or when the user wants to see their backlog.
user-invocable: true
---
```

The added clause about handoff detection plus the trigger phrases ("where was I", "resume") gives Claude Code's skill matcher the signals it needs to route the old `/hv-resume` invocation patterns here.

- [ ] **Step 2: Update the banner**

Replace the existing banner block (lines 9-14) with:

```
════════════════════════════════════════════════════════════════════════
  👉  hv-next  ·  current state, handoff detection, next item
  triggers: "what's next", "where was I", "resume"  ·  pairs: hv-pause, hv-work
════════════════════════════════════════════════════════════════════════
```

The emoji stays `👉` (per resolved open question). The triggers line is broadened. The `pairs:` line drops `hv-status` (deleted) and changes `hv-work` → `hv-pause, hv-work` (the natural pairing for the handoff-detection use case).

- [ ] **Step 3: Extend Step 2 with handoff detection sub-step**

Find Step 2 (`## Step 2 — Reconcile Active Work`). After the existing `If needsAction is empty, produce no output and continue.` paragraph and BEFORE the line beginning `Otherwise, use the AskUserQuestion tool`, insert this new sub-step:

```markdown
**Read handoff notes per stream.** Before building the per-stream questions, resolve and read any `/hv-pause` handoff note for each `needsAction` entry. Reconcile output gives `.repo` per stream (may be `null`); the path resolves with an ordered fallback so umbrella streams pick up the `(branch, repo)`-keyed file while single-repo / pre-feature notes keep working:

\`\`\`bash
# Per stream — reconcile output gives BRANCH and REPO (REPO may be empty)
if [ -n "$REPO" ] && [ -f ".hv/handoff/${BRANCH}@${REPO}.md" ]; then
  HANDOFF=".hv/handoff/${BRANCH}@${REPO}.md"
elif [ -f ".hv/handoff/${BRANCH}.md" ]; then
  HANDOFF=".hv/handoff/${BRANCH}.md"
else
  HANDOFF=""
fi
[ -n "$HANDOFF" ] && cat "$HANDOFF"
\`\`\`

Issue these reads in parallel — one per stream — in the same tool-call batch as any other independent reads in this step. The bare `<branch>.md` form is a legacy fallback covering single-repo cycles and any handoff written before umbrella keying shipped; the umbrella-keyed `<branch>@<repo>.md` form is preferred whenever the stream has a non-null `repo`.

For each stream that has a handoff, extract the **Stage**, **Next planned step**, and **Current hypothesis** sections — those drive the question text and routing below. Streams without a handoff note keep today's behavior unchanged.
```

(The literal-backslash escapes in the heredoc fence above are because this plan file uses backtick-fenced code itself; the actual SKILL.md insertion uses standard \`\`\`bash fences with no escaping.)

- [ ] **Step 4: Add the "handoff present" question arm**

Within Step 2, find the `Options (single-select):` block that lists `hasCommits: true:` and `hasCommits: false:` arms. Insert a new arm at the top, BEFORE `hasCommits: true:`:

```markdown
  - **Handoff note present** (regardless of `hasCommits`):
    1. "Resume with `/hv-work` (Recommended)" — *"Pick up using the handoff brief; the note will be consumed on dispatch."*
    2. "Leave handoff for later" — *"No action now; the note stays in `.hv/handoff/` and surfaces again on next `/hv-next`."*
    3. "Abandon" — *"Delete the branch, clear `status.json`, and remove the handoff note."*
```

Update the question text examples block above the options (the bullet list starting `- hasCommits: true —`) to also include a handoff-present example:

```markdown
  - Handoff present — *"`hv/auth-refresh` was paused mid-investigation: 'verify the OAuth callback path'. What should I do?"* (substitute the handoff's **Next planned step** as the verb phrase)
```

- [ ] **Step 5: Extend the routing table**

Within Step 2, find the routing table (`| Answer | Action |`). Append two rows immediately after the existing `Leave as-is` row, but BEFORE the plain-text fallback paragraph:

```markdown
| Resume with `/hv-work` (handoff arm) | Invoke `hv-work` via the `Skill` tool with the branch + the handoff content as the brief; then `rm -f` the handoff path. |
| Leave handoff for later | Print *"Handoff for `<branch>` left in place — re-run `/hv-next` later."* and continue. |
```

The "Resume with `/hv-work`" arm of `hasCommits: true/false` already exists and routes to `Invoke hv-work on the existing branch`. The handoff-arm row distinguishes itself by also `rm -f`-ing the handoff path (consume-on-resolve behavior), and by passing the handoff content as the dispatched brief.

- [ ] **Step 6: Update the Rules section**

At the bottom of `hv-next/SKILL.md`, find the `## Rules` block. Append one rule:

```markdown
- **Handoff consumption is per-stream, on resolve.** When the user picks "Resume with `/hv-work`" on a handoff arm, `rm -f` the handoff file *only* for that stream. "Leave handoff for later" preserves the file. Other streams' handoff files are not touched.
```

- [ ] **Step 7: Verify the file parses and renders cleanly**

Run from the repo root:

```bash
head -20 hv-next/SKILL.md
grep -c "^## Step" hv-next/SKILL.md
```

Expected: header shows the new description with the handoff-detection clause; `grep -c` returns `7` (Step 1 through Step 8 was already there, plus Step 1.5 doesn't apply — so 7 unchanged from today's structure since we only added sub-steps within Step 2, not new top-level Steps).

Then verify the full sweep with:

```bash
grep -n "Handoff note present\|handoff content\|Pick up using the handoff" hv-next/SKILL.md
```

Expected: at least 3 hits proving Step 4-5 prose landed.

**Suggested commit message:** `feat(next): absorb /hv-resume's handoff detection into /hv-next Step 2 [F26]`

---

### Task 2: `hv-pause/SKILL.md` updates `/hv-resume` references

**Files:**
- Modify: `hv-pause/SKILL.md`

- [ ] **Step 1: Mechanical replace of all `/hv-resume` mentions**

Open `hv-pause/SKILL.md`. Apply these literal replacements (each must be a unique, single occurrence — verify by grep before replacing):

- Line 3 (description): `so /hv-resume in a fresh session` → `so /hv-next in a fresh session`
- Line 18: `/hv-resume reads and deletes the handoff note on the next session.` → `/hv-next reads and deletes the handoff note on the next session.`
- Line 95: `/hv-resume's lookup is keyed on (branch, repo)` → `/hv-next's lookup is keyed on (branch, repo)`
- Line 115: `/hv-resume should dispatch` → `/hv-next should dispatch`
- Line 128: `These four sections are exactly what /hv-resume reads.` → `These four sections are exactly what /hv-next reads.`
- Line 154 (single-entry confirm): `Resume with /hv-resume in a fresh session.` → `Resume with /hv-next in a fresh session.`
- Line 170 (wave-set confirm): `Resume with /hv-resume in a fresh session.` → `Resume with /hv-next in a fresh session.`
- Line 188 (Rules section): `/hv-resume owns cleanup. Once resume has read and routed, it deletes the note.` → `/hv-next owns cleanup. Once /hv-next has read and routed, it deletes the note.`

- [ ] **Step 2: Update the banner `pairs:` line**

Find the banner block in `hv-pause/SKILL.md`:

```
════════════════════════════════════════════════════════════════════════
  💤  hv-pause  ·  write handoff note for clean pause
  triggers: "pause", "hand off"  ·  pairs: hv-resume, hv-learn
════════════════════════════════════════════════════════════════════════
```

Change `pairs: hv-resume, hv-learn` → `pairs: hv-next, hv-learn`.

- [ ] **Step 3: Verify**

```bash
grep -n "/hv-resume\|hv-resume" hv-pause/SKILL.md
```

Expected: zero hits. (If any remain, they were missed by Step 1's mechanical replace — re-apply.)

**Suggested commit message:** `chore(pause): point handoff-consumer references at /hv-next [F26]`

---

### Task 3: Cross-skill SKILL.md prose updates

Single worker, sweeps four files. Each file gets a small surgical edit.

**Files:**
- Modify: `hv-debug/SKILL.md`, `hv-ship/SKILL.md`, `hv-work/SKILL.md`, `hv-learn/SKILL.md`

- [ ] **Step 1: `hv-debug/SKILL.md` line 236**

The existing line reads:

```
Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella sessions MUST pass `--repo` here or the active entry leaks into the next `/hv-resume` / `/hv-next`.
```

Change to:

```
Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella sessions MUST pass `--repo` here or the active entry leaks into the next `/hv-next`.
```

(Drop ` /hv-resume` /` from the trailing list.)

- [ ] **Step 2: `hv-ship/SKILL.md` line 36**

Existing:

```
- You want to resume a paused branch → `/hv-resume`
```

Change to:

```
- You want to resume a paused branch → `/hv-next`
```

- [ ] **Step 3: `hv-ship/SKILL.md` line 162**

Existing:

```
Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-resume` / `/hv-next`.
```

Change to:

```
Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-next`.
```

- [ ] **Step 4: `hv-work/SKILL.md` line 433**

Existing:

```
Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-resume` / `/hv-next`.
```

Change to:

```
Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-next`.
```

- [ ] **Step 5: `hv-learn/SKILL.md` line 120**

The existing line is the slash-command name enumeration in the trigger heuristic:

```
- A skill slash-command name: `/hv-init`, `/hv-config`, `/hv-capture`, `/hv-c`, `/hv-go`, `/hv-vision`, `/hv-next`, `/hv-status`, `/hv-resume`, `/hv-pause`, `/hv-plan`, `/hv-spike`, `/hv-assume`, `/hv-work`, `/hv-debug`, `/hv-decide`, `/hv-review`, `/hv-ship`, `/hv-learn`, `/hv-docs`, `/hv-refactor`, `/hv-update`, `/hv-release`.
```

Change to (drop `/hv-status` and `/hv-resume`):

```
- A skill slash-command name: `/hv-init`, `/hv-config`, `/hv-capture`, `/hv-c`, `/hv-go`, `/hv-vision`, `/hv-next`, `/hv-pause`, `/hv-plan`, `/hv-spike`, `/hv-assume`, `/hv-work`, `/hv-debug`, `/hv-decide`, `/hv-review`, `/hv-ship`, `/hv-learn`, `/hv-docs`, `/hv-refactor`, `/hv-update`, `/hv-release`.
```

- [ ] **Step 6: Verify**

```bash
git grep -nE "/hv-resume\b" hv-debug/SKILL.md hv-ship/SKILL.md hv-work/SKILL.md hv-learn/SKILL.md
git grep -nE "/hv-status\b" hv-debug/SKILL.md hv-ship/SKILL.md hv-work/SKILL.md hv-learn/SKILL.md
```

Expected: both return zero hits.

**Suggested commit message:** `chore: sweep /hv-resume, /hv-status from sibling SKILL.md prose [F26]`

---

## Wave 2 — Delete folders, drop manifest entries, bump version

Four parallel write-only tasks. T1, T2, and T3 from Wave 1 must complete and commit BEFORE Wave 2 starts (T4-T7), because T4 deletes `hv-resume/SKILL.md` and T5 deletes `hv-status/SKILL.md` — tasks in Wave 1 would lose their reference material if Wave 2 ran first.

### Task 4: Delete `hv-status/` folder

**Files:**
- Delete: `hv-status/` (entire folder; currently contains only `hv-status/SKILL.md`)

- [ ] **Step 1: Verify the folder contains only the SKILL.md before deletion**

```bash
ls hv-status/
```

Expected: `SKILL.md` only. If anything else is present, surface it before deleting.

- [ ] **Step 2: Delete the folder**

```bash
rm -rf hv-status/
```

- [ ] **Step 3: Verify**

```bash
test ! -e hv-status && echo OK
```

Expected: `OK`.

**Suggested commit message:** `feat!: remove /hv-status command (folded into /hv-next) [F26]`

---

### Task 5: Delete `hv-resume/` folder

**Files:**
- Delete: `hv-resume/` (entire folder; currently contains only `hv-resume/SKILL.md`)

- [ ] **Step 1: Verify the folder contains only the SKILL.md before deletion**

```bash
ls hv-resume/
```

Expected: `SKILL.md` only.

- [ ] **Step 2: Delete the folder**

```bash
rm -rf hv-resume/
```

- [ ] **Step 3: Verify**

```bash
test ! -e hv-resume && echo OK
```

Expected: `OK`.

**Suggested commit message:** `feat!: remove /hv-resume command (folded into /hv-next) [F26]`

---

### Task 6: Drop entries from both `plugin.json` files; bump to `2.0.0`

**Files:**
- Modify: `plugin.json` (root level — canonical)
- Modify: `.claude-plugin/plugin.json`

Both files have identical `skills` arrays and identical `version` fields. Apply the same edit to both.

- [ ] **Step 1: Edit `plugin.json` (root)**

In `plugin.json`, change line 3 from:

```json
  "version": "1.16.0",
```

to:

```json
  "version": "2.0.0",
```

In the same file, remove these two lines from the `skills` array (currently lines 27-28):

```json
    "./hv-status",
    "./hv-resume",
```

The surrounding `"./hv-vision"` and `"./hv-pause"` entries stay; comma handling: after the edit, `"./hv-vision",` is followed directly by `"./hv-pause",`.

- [ ] **Step 2: Edit `.claude-plugin/plugin.json`**

Apply the exact same two edits as Step 1 (version bump + drop two skills array lines).

- [ ] **Step 3: Verify both files**

```bash
python3 -c "import json; d=json.load(open('plugin.json')); assert d['version']=='2.0.0'; assert './hv-status' not in d['skills']; assert './hv-resume' not in d['skills']; print('plugin.json OK', len(d['skills']), 'skills')"
python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); assert d['version']=='2.0.0'; assert './hv-status' not in d['skills']; assert './hv-resume' not in d['skills']; print('.claude-plugin/plugin.json OK', len(d['skills']), 'skills')"
```

Expected output (both lines):

```
plugin.json OK 21 skills
.claude-plugin/plugin.json OK 21 skills
```

(23 skills today minus 2 removed = 21.)

**Suggested commit message:** `feat!: bump to 2.0.0; drop hv-status, hv-resume from plugin manifests [F26]`

---

### Task 7: Edit `bin/hv-skills-index` heredoc body

**Files:**
- Modify: `bin/hv-skills-index`

- [ ] **Step 1: Update the "Capture & pick" line in the heredoc**

In `bin/hv-skills-index`, find this line (currently line 15):

```
**Capture & pick** — `/hv-capture` (alias `/hv-c`), `/hv-go`, `/hv-next`, `/hv-status`, `/hv-resume`, `/hv-pause`
```

Change to:

```
**Capture & pick** — `/hv-capture` (alias `/hv-c`), `/hv-go`, `/hv-next`, `/hv-pause`
```

(Drop `/hv-status` and `/hv-resume` from the comma-separated list.)

- [ ] **Step 2: Verify**

```bash
grep -n "Capture & pick" bin/hv-skills-index
```

Expected: line 15 (or nearby) shows the updated list — exactly 4 commands inside the backticks (`/hv-capture`, `/hv-go`, `/hv-next`, `/hv-pause`) plus the `(alias /hv-c)` annotation.

```bash
grep -nE "/hv-(status|resume)\b" bin/hv-skills-index
```

Expected: zero hits.

**Suggested commit message:** `chore(skills-index): drop /hv-status, /hv-resume from heredoc [F26]`

---

## Wave 3 — Sweep all docs

Five parallel write-only tasks. Wave 2 must complete first so the doc updates are consistent with the deleted-state of `hv-status/`/`hv-resume/`.

### Task 8: `README.md` consolidates marketing + index

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the "Survives /clear" bullet**

Find line 25:

```
- **Survives `/clear`.** `/hv-pause` writes a handoff note with your current hypothesis, next step, and mid-edit files. `/hv-resume` reads it back in a fresh session.
```

Change to:

```
- **Survives `/clear`.** `/hv-pause` writes a handoff note with your current hypothesis, next step, and mid-edit files. `/hv-next` reads it back in a fresh session.
```

- [ ] **Step 2: Update marketing-grid bullets (lines 34-36)**

Line 34:

```
| 🚢 **Review-gated shipping** — `/hv-ship` runs `/hv-review` against original intent + conventions before PR or merge | 💾 **Context-clear recovery** — `/hv-resume` re-reads active streams with recent commits and routes you back to work |
```

Change to:

```
| 🚢 **Review-gated shipping** — `/hv-ship` runs `/hv-review` against original intent + conventions before PR or merge | 💾 **Context-clear recovery** — `/hv-next` re-reads active streams with recent commits and any handoff note, routing you back to work |
```

Line 35:

```
| 🔧 **Refactor cycles** — `/hv-refactor` explores friction, designs competing approaches, fixes in parallel | 🤝 **Graceful handoff** — `/hv-pause` writes what's in your head (hypothesis, next step, mid-edit files) so `/hv-resume` picks up after a `/clear` |
```

Change `/hv-resume` to `/hv-next`:

```
| 🔧 **Refactor cycles** — `/hv-refactor` explores friction, designs competing approaches, fixes in parallel | 🤝 **Graceful handoff** — `/hv-pause` writes what's in your head (hypothesis, next step, mid-edit files) so `/hv-next` picks up after a `/clear` |
```

Line 36:

```
| 🧭 **Vision & milestones** — `/hv-vision` brainstorms milestones using web research and a critique pass; `/hv-next`, `/hv-resume`, `/hv-pause`, and `/hv-status` keep work scoped to the active set | 🔗 **Loose milestone tags** — items can carry a `Milestone:` field; multi-active milestones run in parallel when their dependencies allow |
```

Change to (drop `/hv-resume` and `/hv-status`):

```
| 🧭 **Vision & milestones** — `/hv-vision` brainstorms milestones using web research and a critique pass; `/hv-next` and `/hv-pause` keep work scoped to the active set | 🔗 **Loose milestone tags** — items can carry a `Milestone:` field; multi-active milestones run in parallel when their dependencies allow |
```

- [ ] **Step 3: Update line 89 (Pause/resume narrative)**

Existing:

```
Need to step away mid-cycle? `/hv-pause` writes a handoff note (hypothesis, next step, mid-edit files) so a fresh session running `/hv-resume` picks up where you left off. See [docs/getting-started.md](docs/getting-started.md) for the fuller walkthrough.
```

Change to:

```
Need to step away mid-cycle? `/hv-pause` writes a handoff note (hypothesis, next step, mid-edit files) so a fresh session running `/hv-next` picks up where you left off. See [docs/getting-started.md](docs/getting-started.md) for the fuller walkthrough.
```

- [ ] **Step 4: Update line 148 (drift narrative)**

Existing:

```
Most workflows start that way and most stay there. Three things tend to drift, and hv-skills addresses each of them. (1) Commits stop being atomic — one PR ends up touching six unrelated things. (2) Knowledge stops accumulating — you re-discover the same gotcha three sessions in a row because nothing reads it back. (3) Sessions don't survive `/clear` — you lose the live hypothesis the moment you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, and `/hv-pause` / `/hv-resume` carry intent across context resets. If none of those bite you in practice, stock Claude Code is genuinely fine. If they do, that's the gap hv-skills is filling.
```

Change `/hv-pause` / `/hv-resume` → `/hv-pause` / `/hv-next`:

```
Most workflows start that way and most stay there. Three things tend to drift, and hv-skills addresses each of them. (1) Commits stop being atomic — one PR ends up touching six unrelated things. (2) Knowledge stops accumulating — you re-discover the same gotcha three sessions in a row because nothing reads it back. (3) Sessions don't survive `/clear` — you lose the live hypothesis the moment you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, and `/hv-pause` / `/hv-next` carry intent across context resets. If none of those bite you in practice, stock Claude Code is genuinely fine. If they do, that's the gap hv-skills is filling.
```

- [ ] **Step 5: Update slash-command index table (lines 161-163)**

Lines 161-163 currently:

```
| `/hv-status` | Compact read-only state glance — counts, active work, recent completions, knowledge topics |
| `/hv-resume` | Reorient after `/clear` — active streams with recent commits and any handoff notes, routes to `/hv-work`, `/hv-ship`, or `/hv-next` |
| `/hv-pause` | Gracefully stop mid-session — writes a handoff note (next step, hypothesis, mid-edit files) for the next session's `/hv-resume` |
```

Replace with two rows (drop the first two; update the third):

```
| `/hv-pause` | Gracefully stop mid-session — writes a handoff note (next step, hypothesis, mid-edit files) for the next session's `/hv-next` |
```

(`/hv-next` already has its own table row above this group; that row remains and gains an updated description if needed — verify lines 158-160 first.)

- [ ] **Step 6: Update mermaid diagram**

Line 194:

```
  STATUS["/hv-status"] -.reads.-> TODO
```

Delete this line entirely (the `STATUS` node is gone).

Line 204:

```
  RESUME["/hv-resume"] -.reads.-> TODO
```

Delete this line entirely (the `RESUME` node is gone).

If those nodes are referenced elsewhere in the mermaid block (e.g., as edge endpoints), remove those edges too. After editing, scan for any orphan reference:

```bash
grep -n "STATUS\[\|RESUME\[\|STATUS\b\|RESUME\b" README.md
```

Expected: zero hits to `STATUS[` or `RESUME[`. (Substring matches in unrelated prose are fine.)

- [ ] **Step 7: Verify**

```bash
grep -nE "/hv-(status|resume)\b" README.md
```

Expected: zero hits.

**Suggested commit message:** `docs(readme): drop /hv-status, /hv-resume; route handoff prose at /hv-next [F26]`

---

### Task 9: `docs/reference/slash-commands.md` removes two sections; updates `## /hv-next`

**Files:**
- Modify: `docs/reference/slash-commands.md`

- [ ] **Step 1: Remove the `## /hv-status` section**

Find the `## /hv-status` heading (currently around line 81). Delete the heading and its body paragraph (the section ends at the next `## /hv-X` heading or at a blank line followed by another section). Verify by reading the surrounding context first.

- [ ] **Step 2: Remove the `## /hv-resume` section**

Find the `## /hv-resume` heading (currently around line 65). Delete the heading and its body paragraph the same way.

- [ ] **Step 3: Update the `## /hv-next` description to mention handoff detection**

Find the `## /hv-next` section. Append the following sentence to its existing description paragraph (or rewrite the description if it makes the prose flow better):

> When active streams exist, also reads any handoff notes left by `/hv-pause` and surfaces Stage / Next planned step / Current hypothesis inline alongside each stream — this replaces the previous `/hv-resume` flow.

- [ ] **Step 4: Verify**

```bash
grep -nE "^## /hv-(status|resume)\b" docs/reference/slash-commands.md
```

Expected: zero hits.

```bash
grep -nE "/hv-(status|resume)\b" docs/reference/slash-commands.md
```

Expected: zero hits in the file body either (cross-references in `## /hv-next` should now name the deleted commands ZERO times — the new prose says "replaces the previous /hv-resume flow" but I'd actually rather we DON'T reference the dead name even in past tense; rephrase to *"replaces the previous post-/clear flow"*).

If the verify shows hits, re-edit Step 3's appended sentence to: *"When active streams exist, also reads any handoff notes left by `/hv-pause` and surfaces Stage / Next planned step / Current hypothesis inline alongside each stream — this is the post-`/clear` reorientation flow."*

**Suggested commit message:** `docs(slash-commands): drop /hv-status, /hv-resume sections; expand /hv-next [F26]`

---

### Task 10: Rewrite `docs/usage/pausing-and-resuming.md`

**Files:**
- Modify: `docs/usage/pausing-and-resuming.md`

- [ ] **Step 1: Read the current file end-to-end**

```bash
cat docs/usage/pausing-and-resuming.md
```

Capture the structure: `/hv-pause` section, `/hv-resume` section, "Recovering after /clear" walkthrough, "When to /hv-pause vs just commit" callout.

- [ ] **Step 2: Apply these section-level edits**

- Line 3 (intro paragraph): `/hv-pause writes what was in your head before you leave; /hv-resume picks it back up when you return.` → `/hv-pause writes what was in your head before you leave; /hv-next picks it back up when you return.`
- Line 30: `You don't need to manage this file directly. /hv-resume reads and deletes it.` → `You don't need to manage this file directly. /hv-next reads and deletes it on resolve.`
- Replace the heading `## /hv-resume` (line 32) with `## /hv-next reads handoff notes`. The section body's first paragraph (line 34) should be rewritten:

```markdown
When active streams exist, `/hv-next` reads any handoff note matching each stream and surfaces the **Stage**, **Next planned step**, and **Current hypothesis** inline. The path resolution mirrors `/hv-pause`'s write side: `.hv/handoff/<branch>@<repo>.md` for umbrella streams, with a fallback to `.hv/handoff/<branch>.md` for single-repo cycles or pre-umbrella handoffs.

If a handoff is present, `/hv-next`'s per-stream question offers "Resume with `/hv-work`" as the recommended action — the handoff brief flows into the dispatched `/hv-work`, and the note is `rm -f`-ed once the user confirms the resume. "Leave handoff for later" preserves the file so the next `/hv-next` invocation surfaces it again.
```

- "Recovering after /clear" walkthrough (lines 45-65): replace every `/hv-resume` mention with `/hv-next`. The narrative shape stays the same; only the command name changes.

- [ ] **Step 3: Verify**

```bash
grep -nE "/hv-resume\b" docs/usage/pausing-and-resuming.md
```

Expected: zero hits.

**Suggested commit message:** `docs(pausing-and-resuming): rewrite /hv-resume section as /hv-next handoff detection [F26]`

---

### Task 11: Rename `docs/usage/next-and-status.md` → `picking-work.md`; rewrite content

**Files:**
- Create: `docs/usage/picking-work.md`
- Delete: `docs/usage/next-and-status.md`

- [ ] **Step 1: Read the current content**

```bash
cat docs/usage/next-and-status.md
```

- [ ] **Step 2: Write the new file**

Use `git mv` to preserve history:

```bash
git mv docs/usage/next-and-status.md docs/usage/picking-work.md
```

Then edit `docs/usage/picking-work.md`:

- Line 1 (title): change to `# Picking work`
- Line 3 (intro): the existing prose says *"Three skills help you orient and pick what to do next. /hv-next reconciles git state and suggests work. /hv-status is a fast read-only glance. /hv-assume lets you peek at the orchestrator's plan before code lands."* — change to *"Two skills help you orient and pick what to do next. /hv-next reconciles git state, surfaces any /hv-pause handoff note for active streams, presents the backlog, and suggests work. /hv-assume lets you peek at the orchestrator's plan before code lands."*
- Lines 31-50 (the existing `## /hv-status` section): delete the entire section (heading + body).
- Any remaining occurrences of `/hv-status`: remove or rephrase.

- [ ] **Step 3: Update incoming links**

Search for any file that links to `next-and-status.md`:

```bash
git grep -l "next-and-status" -- ':!docs/superpowers/'
```

For each hit, update the link target from `next-and-status.md` to `picking-work.md`. Likely candidates: `docs/README.md`, `docs/reference/hv-folder.md`, `docs/usage/pausing-and-resuming.md` (link to the picking-work page from "see also"), `docs/usage/spikes.md`.

- [ ] **Step 4: Verify**

```bash
test ! -e docs/usage/next-and-status.md && test -f docs/usage/picking-work.md && echo OK
git grep -l "next-and-status" -- ':!docs/superpowers/'
grep -nE "/hv-status\b" docs/usage/picking-work.md
```

Expected: first command prints `OK`; second returns no live hits (only historical specs/plans, which are excluded by the pathspec); third returns zero hits.

**Suggested commit message:** `docs: rename next-and-status.md → picking-work.md; drop /hv-status section [F26]`

---

### Task 12: Doc cross-reference sweep across multiple small files

Single worker, sweeps all remaining doc files with one-line mentions. Each edit is mechanical (replace `/hv-resume` with `/hv-next`, drop `/hv-status` from comma-separated lists).

**Files:**
- Modify: `docs/README.md`
- Modify: `docs/faq.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/reference/hv-folder.md`
- Modify: `docs/reference/preflight.md`
- Modify: `docs/usage/parallel-work.md`
- Modify: `docs/usage/umbrella-mode.md`

- [ ] **Step 1: `docs/README.md`**

Lines 14 and 20:

```
- [Reviewing and picking work](usage/next-and-status.md) — `/hv-next`, `/hv-status`, `/hv-assume`
- [Pausing and resuming](usage/pausing-and-resuming.md) — `/hv-pause`, `/hv-resume`, recovering after `/clear`
```

Change to:

```
- [Picking work](usage/picking-work.md) — `/hv-next`, `/hv-assume`
- [Pausing and resuming](usage/pausing-and-resuming.md) — `/hv-pause`, recovering after `/clear`
```

- [ ] **Step 2: `docs/faq.md` line 7**

Existing:

```
…and `/hv-pause` / `/hv-resume` carry intent across context resets.
```

Change `/hv-resume` → `/hv-next`.

- [ ] **Step 3: `docs/getting-started.md` line 87**

Existing:

```
for systematic bug cycles, `/hv-pause` before stepping away, `/hv-resume` after `/clear`.
```

Change to:

```
for systematic bug cycles, `/hv-pause` before stepping away, `/hv-next` after `/clear`.
```

- [ ] **Step 4: `docs/reference/hv-folder.md`**

- Line 23 (handoff/ table row): `consumed by /hv-resume` → `consumed by /hv-next`
- Line 60: `so that /hv-next, /hv-resume, and /hv-pause can scope` → `so that /hv-next and /hv-pause can scope`
- Line 82: `See [../usage/next-and-status.md](../usage/next-and-status.md) for how /hv-next and /hv-status use this file...` → `See [../usage/picking-work.md](../usage/picking-work.md) for how /hv-next uses this file...`
- Line 110: `/hv-resume reads any matching note` → `/hv-next reads any matching note`

- [ ] **Step 5: `docs/reference/preflight.md` line 27**

Existing:

```
- **Observe-only skills** (`/hv-resume`, `/hv-pause`, `/hv-next`). These read state and route; they shouldn't auto-init for `2`. On exit `2`, surface a brief "nothing to show, `/hv-init` first" message and stop. On exit `3`, refresh via `hv-init` (helpers may be needed for the read).
```

Change to (drop `/hv-resume`):

```
- **Observe-only skills** (`/hv-pause`, `/hv-next`). These read state and route; they shouldn't auto-init for `2`. On exit `2`, surface a brief "nothing to show, `/hv-init` first" message and stop. On exit `3`, refresh via `hv-init` (helpers may be needed for the read).
```

- [ ] **Step 6: `docs/usage/parallel-work.md` line 63**

Existing:

```
`.hv/` and must run in the main worktree. `/hv-status`, `/hv-next`, and
```

Change to:

```
`.hv/` and must run in the main worktree. `/hv-next` and
```

(and ensure the surrounding sentence still reads cleanly — the next words on line 64 may need adjusting; read context).

- [ ] **Step 7: `docs/usage/umbrella-mode.md`**

- Line 115 (`/hv-pause` umbrella narrative): `/hv-resume reads the umbrella-keyed path first` → `/hv-next reads the umbrella-keyed path first`
- Line 122 (`/hv-status` description): delete the entire bullet (it's about `/hv-status`'s umbrella display, which no longer exists).

- [ ] **Step 8: Verify**

```bash
git grep -nE "/hv-(status|resume)\b" -- 'docs/' ':!docs/superpowers/'
```

Expected: zero hits.

**Suggested commit message:** `docs: sweep /hv-status, /hv-resume cross-references across docs/ [F26]`

---

## Wave 4 — Finalize

Three sequential tasks. T13, T14, T15 must run in order; T16 is the final acceptance gate.

### Task 13: Update `.hv/KNOWLEDGE.md` and `.hv/DECISIONS.md`

**Files:**
- Modify: `.hv/KNOWLEDGE.md`
- Modify: `.hv/DECISIONS.md`

`.hv/` is gitignored, but its content files are project state for hv-skills itself. Bullets that name the dead commands need updating where the rule still applies — most rules are about behavior, not the dead name.

- [ ] **Step 1: Survey current references**

```bash
grep -nE "/hv-(status|resume)\b" .hv/KNOWLEDGE.md .hv/DECISIONS.md 2>/dev/null
```

Capture the line numbers for each hit.

- [ ] **Step 2: For each hit, decide:**

- If the bullet is about a *behavior* (e.g., "place nudges on terminal/idle paths" mentions `/hv-resume` only as an example) — replace `/hv-resume` with `/hv-next` mechanically. The rule still applies.
- If the bullet is about a *deleted skill's specific behavior* (e.g., "/hv-status's display syntax in umbrella mode") — the rule no longer applies; remove the bullet entirely.
- Use `Edit` for surgical updates; never `Write` (preserves the rest of the file).

- [ ] **Step 3: Verify**

```bash
grep -nE "/hv-(status|resume)\b" .hv/KNOWLEDGE.md .hv/DECISIONS.md 2>/dev/null
```

Expected: zero hits, OR only hits inside HTML-comment date stamps `<!-- 2026-... -->` that mention historical commits (those are fine to keep — they're audit trail, not active rules).

**Suggested commit message:** `chore(knowledge): sweep /hv-status, /hv-resume from KNOWLEDGE.md and DECISIONS.md [F26]`

---

### Task 14: Prepend `## 2.0.0` section to `CHANGELOG.md`

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read the current top of CHANGELOG.md to match format**

```bash
head -20 CHANGELOG.md
```

Capture the existing version-section format (likely `## 1.16.0` followed by `### Added` / `### Changed` / `### Removed` blocks).

- [ ] **Step 2: Prepend the new section**

Insert immediately after the file header (before `## 1.16.0` or whatever the current top section is):

```markdown
## 2.0.0

### Breaking

- `/hv-status` and `/hv-resume` are removed in favor of `/hv-next`. `/hv-next` now reads `/hv-pause` handoff notes for active streams and surfaces `Stage` / `Next planned step` / `Current hypothesis` inline, replacing the post-`/clear` `/hv-resume` flow. The lightweight glance from `/hv-status` is no longer offered as a separate command — `/hv-next` is the single state-view entry point. Update muscle memory: anywhere you typed `/hv-status` or `/hv-resume`, type `/hv-next` instead. ([F26])

### Changed

- `bin/hv-skills-index` heredoc body drops `/hv-status` and `/hv-resume` from the "Capture & pick" group. Existing projects must re-run `/hv-init` to refresh the managed `<!-- hv-skills-start -->` block in `CLAUDE.md`.
- `docs/usage/next-and-status.md` is renamed to `docs/usage/picking-work.md` and rewritten to reflect the one-command world.

### Removed

- `hv-status/SKILL.md` and the `hv-status/` folder.
- `hv-resume/SKILL.md` and the `hv-resume/` folder.
```

- [ ] **Step 3: Verify**

```bash
grep -n "^## 2.0.0" CHANGELOG.md
grep -nE "F26" CHANGELOG.md
```

Expected: first command shows the section heading at line 3 or so (after the file's `# Changelog` title); second command shows at least one `[F26]` reference.

**Suggested commit message:** `docs(changelog): 2.0.0 — breaking removal of /hv-status, /hv-resume [F26]`

---

### Task 15: Regenerate managed CLAUDE.md blocks

**Files:**
- Modify: `CLAUDE.md` (via helpers)

- [ ] **Step 1: Run `bin/hv-skills-index`**

```bash
bin/hv-skills-index
```

Expected: silent (or prints `updated`). The managed `<!-- hv-skills-start --> ... <!-- hv-skills-end -->` block in `CLAUDE.md` is rewritten with the new heredoc body.

- [ ] **Step 2: Run `bin/hv-knowledge-index`**

```bash
bin/hv-knowledge-index
```

Expected: silent (or prints `updated`). This refreshes the `<!-- hv-knowledge-start -->` block to reflect any topic-list changes from Wave 4 Task 13.

- [ ] **Step 3: Verify the managed block in CLAUDE.md is current**

```bash
grep -n "Capture & pick" CLAUDE.md
```

Expected: shows the **Capture & pick** line in `CLAUDE.md` matching the one in `bin/hv-skills-index` (no `/hv-status` or `/hv-resume`).

```bash
grep -nE "/hv-(status|resume)\b" CLAUDE.md
```

Expected: zero hits.

**Suggested commit message:** `chore(claude.md): regenerate managed skills + knowledge blocks [F26]`

---

### Task 16: Acceptance verification

**Files:** none modified — this task only runs verification commands.

- [ ] **Step 1: Confirm the deleted folders are gone**

```bash
test ! -e hv-status && test ! -e hv-resume && echo "OK: folders deleted"
```

Expected: `OK: folders deleted`.

- [ ] **Step 2: Confirm plugin manifests are clean**

```bash
python3 -c "import json; \
d1=json.load(open('plugin.json')); \
d2=json.load(open('.claude-plugin/plugin.json')); \
assert d1['version']=='2.0.0' and d2['version']=='2.0.0', 'version mismatch'; \
assert './hv-status' not in d1['skills'] and './hv-resume' not in d1['skills']; \
assert './hv-status' not in d2['skills'] and './hv-resume' not in d2['skills']; \
print('OK: plugin manifests clean, version 2.0.0, %d skills' % len(d1['skills']))"
```

Expected: `OK: plugin manifests clean, version 2.0.0, 21 skills`.

- [ ] **Step 3: Confirm no live cross-references remain**

```bash
git grep -nE "/hv-(status|resume)\b" -- ':!CHANGELOG.md' ':!docs/superpowers/' ':!.hv/handoff/'
```

Expected: zero hits. The exclusions (CHANGELOG, historical specs/plans, gitignored handoff dir) are intentional — those are audit trail, not active references.

- [ ] **Step 4: Run the smoke test**

```bash
bash test/smoke.sh
```

Expected: ends with `All smoke tests passed.` (or equivalent). If any test fails, surface and fix before proceeding.

- [ ] **Step 5: Confirm CLAUDE.md managed block reflects new shape**

```bash
sed -n '/<!-- hv-skills-start -->/,/<!-- hv-skills-end -->/p' CLAUDE.md | grep "Capture & pick"
```

Expected: the line shows exactly four slash-commands: `/hv-capture`, `/hv-go`, `/hv-next`, `/hv-pause` (plus the `(alias /hv-c)` annotation).

- [ ] **Step 6: Manual smoke (optional but recommended)**

Run from the repo root in a fresh `claude` session:

```
/hv-pause
# (in a separate terminal, /clear and start a new session)
/hv-next
```

Expected: `/hv-next` detects the active stream, reads the handoff note, surfaces Stage / Next planned step / Current hypothesis inline, and offers "Resume with /hv-work (Recommended)" as the per-stream answer.

**Suggested commit message:** none — this task is verification only. If Step 4 or Step 5 surface a fix, commit that fix with a `fix(...): <reason> [F26]` message.

---

## Self-review notes

Cross-check completed against the spec:

- ✅ All `Removed` items in spec → covered by T4, T5, T6, T11 (rename of next-and-status), T12 (umbrella-mode bullet)
- ✅ All `Modified` items in spec → covered by T1 (hv-next), T2 (hv-pause), T3 (cross-skill SKILL.md), T6 (plugin.json + .claude-plugin/plugin.json), T7 (hv-skills-index), T8 (README), T9 (slash-commands.md), T10 (pausing-and-resuming.md), T11 (next-and-status.md rename), T12 (doc sweep), T13 (KNOWLEDGE/DECISIONS), T14 (CHANGELOG), T15 (regenerate)
- ✅ All `Out of scope` items honored → no `/hv-state`, no `--quiet` flag, no deprecation stubs, no banner cross-reference scheme, no new `bin/` helper
- ✅ All `Risks` mitigated → CHANGELOG (risk 1), `/hv-update` flow handles cache (risk 2), `/hv-next` is unchanged loop seam (risk 3), T16 acceptance grep covers risk 4, mirror-step threshold respected (risk 5), `[ -f $HANDOFF ] && cat` pattern adopted from hv-resume (risk 6)
- ✅ Open questions resolved inline at the top of this plan
- ✅ Acceptance criteria from spec all map to T16 verification steps

No placeholders. No "TBD". No "implement later". Every step has a code or command block. Type/method names referenced (`hv-skills-index`, `hv-knowledge-index`, `hv-managed-block`, `parse_todo_fields`, `load_repos`) are all existing and verified to exist.
