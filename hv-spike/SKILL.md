---
name: hv-spike
description: Throwaway feasibility experiment on a dedicated git branch — answers a specific question without polluting main or the backlog. Creates spike/<name> branch and .hv/spikes/<name>.md for question + findings + decision. Branch is never merged; only findings come back. Use when you need to try X before committing to it ("can we use SSE?", "does this library handle our scale?").
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  🧪  hv-spike  ·  throwaway feasibility experiment on a branch
  triggers: "spike X", "feasibility"  ·  pairs: hv-vision, hv-plan
════════════════════════════════════════════════════════════════════════
```

# hv-spike — Throwaway Feasibility Experiment

**Code on the spike branch is reference, not product.**

Two modes:

- **Start mode** — open a new spike with a question
- **Finish mode** — extract findings from work done on a spike branch into the spike file

## Step 1 — Preflight & Mode

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

Determine the mode silently:

- *"spike SSE for live updates"*, *"try X"*, *"feasibility check on Y"* → **Start mode**
- *"spike done"*, *"finish the SSE spike"*, *"extract findings"* → **Finish mode**
- Ambiguous → ask once

In Finish mode, list existing open spikes via `.hv/bin/hv-spike-list` and ask which one if not specified.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Question", description="Sharpen the spike's yes/no question")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (Finish mode skips Question/Branch, Start mode skips Findings/Decision/Promote) get `completed` with the no-op reason in the description.

Phases:

1. *Question* — Start: yes/no/conditional question sharpened (Step 2)
2. *Branch* — Start: `spike/<name>` created, scratch file seeded (Steps 2.5–4)
3. *Investigate* — Start: experiment runs to a clear answer (between Start and Finish)
4. *Findings* — Finish: spike file's findings section written from the branch state (Steps 5–6)
5. *Decision* — Finish: verdict (yes / no / conditional / inconclusive) recorded (Step 6)
6. *Promote / cleanup* — Finish: optional `/hv-decide --from-spike`, branch deleted (Steps 6.5–7)

## Step 2 (Start mode) — Sharpen the Question

A spike answers a *yes/no/conditional* question. Push back if the question is vague:

- ❌ *"Try Server-Sent Events"* — too open
- ✅ *"Can we use SSE for live updates over our existing nginx setup without proxy buffering issues?"*

Name the spike with a short kebab-case identifier (`sse-feasibility`, `auth-rotation`, `migration-cost`). The name becomes the branch suffix and the spike file's stem.

## Step 2.5 (Start mode) — Resolve Sub-Repo (umbrella mode only)

Skip this step entirely when umbrella mode is off (`hv-umbrella-on` returns `no`). See `references/umbrella-mode.md` for what umbrella mode means and how the registry works.

In umbrella mode, the spike branch must land in a specific sub-repo (the umbrella root often is not a git repo at all). Resolve `<repo>` via the 3-step fallback codified in KNOWLEDGE 2026-05-02:

1. If the user named a sub-repo in their input (e.g. *"spike SSE feasibility in web"*) — use it.
2. Else, run `.hv/bin/hv-resolve-repo` from the current cwd; if it succeeds, default to the resolved name.
3. Else, ask via `AskUserQuestion`:
   - **Header:** `"Repo"`
   - **Question:** *"Which sub-repo should `spike/<name>` live in?"*
   - **Options:** one per registered sub-repo (read names from `.hv/repos.json` via `load_repos()`), single-select.

Carry `<repo>` into Step 4's helper invocation as `--repo <repo>`. The spike file still lands at the umbrella's `.hv/spikes/<name>.md` — only the git branch lives in the sub-repo, per the umbrella-vs-sub-repo `.git/` distinction in `references/umbrella-mode.md`.

## Step 3 (Start mode) — Confirm Before Branching

Before mutating git state, confirm with the user via `AskUserQuestion`:

- **Header:** `"Spike"`
- **Question:** *"Create branch `spike/<name>` and switch to it now?"* (umbrella mode: *"Create branch `spike/<name>` in `<repo>` and switch to it now?"*)
- **Options:**
  1. *"Yes, create and switch (Recommended)"* — *"Branches off current HEAD; you'll be on the spike branch immediately."*
  2. *"Create only, stay on this branch"* — *"Useful when you want to switch on your own time."*
  3. *"Cancel"* — *"Don't do anything."*

Plain-text fallback: if the working tree is clean, default to "create and switch"; otherwise default to "create only" so dirty changes don't follow.

## Step 4 (Start mode) — Create the Spike

```bash
# Single-repo:
BRANCH=$(.hv/bin/hv-spike-add <name> "<question>")
# Umbrella mode — spike lives in <repo>:
BRANCH=$(.hv/bin/hv-spike-add --repo <repo> <name> "<question>")
```

The helper:

- Creates branch `spike/<name>` off the current HEAD (in the sub-repo's git history when `--repo` is set)
- Writes `.hv/spikes/<name>.md` with frontmatter + question + section stubs
- Spike file `.hv/spikes/<name>.md` lives at the umbrella root regardless of `--repo`; only the git branch lands in the sub-repo. The frontmatter records `repo: <name>` so `/hv-spike done` and listings know which sub-repo to operate against.

If the user picked "create and switch" in Step 3, run `git checkout "$BRANCH"` — in umbrella mode, `cd` into `<repo>` first (or `git -C <repo-path> checkout "$BRANCH"`).

Compact handoff:

```
Spike opened: spike/<name>           # umbrella: Spike opened: spike/<name> (in <repo>)
Question: <one line>
File: .hv/spikes/<name>.md

Hack freely on the branch. When done, return to main and run:
  /hv-spike done <name>
```

No further work in this skill — the user drives the experiment.

## Step 5 (Finish mode) — Read the Spike Branch

Read `repo:` from `.hv/spikes/<name>.md`'s frontmatter first (parallel-load with the spike-file content). When set, run the `git log` / `git diff` calls in the sub-repo (resolve via `.hv/repos.json` / `load_repos()`); when unset, run them in the cwd. Inspect git either by `cd`-ing into the sub-repo before the call or by passing `git -C <sub-repo path>`:

```bash
# Single-repo (no `repo:` in frontmatter) — run in cwd:
git log spike/<name> --oneline
git diff main...spike/<name> --stat

# Umbrella mode (`repo: <name>` in frontmatter) — run against the sub-repo:
git -C <sub-repo path> log spike/<name> --oneline
git -C <sub-repo path> diff main...spike/<name> --stat
```

Read `.hv/spikes/<name>.md` for the original question and any notes the user already wrote (the file always lives at the umbrella root, regardless of `repo:`).

Ask the user for the verbal summary if they haven't already given one — what they learned, viable or not, and why.

## Step 6 (Finish mode) — Write the Findings

Use the `Edit` tool on `.hv/spikes/<name>.md` to fill in:

- **What was tried** — concrete commands run, libraries pulled in, files touched (cite from the diff stat)
- **Findings** — 3–5 bullets, what you learned. Honest reporting — bad findings are as valuable as good
- **Decision** — `viable` / `not viable` / `depends-on-X` / `inconclusive`
- **Recommended approach** — only if viable. Describe the shape of the *real* implementation. Do not paste spike code

Then mark the spike done:

```bash
.hv/bin/hv-spike-finish <name>
```

The helper sets `status: done` and `finished: <date>` in the spike file. The branch is left as-is — historical reference, never merged.

## Step 6.5 (Finish mode) — Promote Finding to Decision (nudge)

Read back the `Decision` field Step 6 just wrote. Skip this step entirely — no nudge, no question, no log — when the decision is `inconclusive` or empty. An inconclusive spike doesn't have enough evidence to be a hard boundary.

When the decision is `viable`, `not viable`, or `depends-on-X`, ask via `AskUserQuestion`:

- **Header:** `"Decide"`
- **Question:** *"This spike concluded `<verdict>`. Promote the finding to a hard-boundary decision in `DECISIONS.md`?"* (substitute the verbatim verdict)
- **Options:**
  1. *"Yes, promote (Recommended)"* — *"Invoke `/hv-decide --from-spike <name>`. The spike's question + decision + recommended approach pre-fill the rule and why; you'll articulate the forbids/permits."*
  2. *"Skip — keep finding in spike file only"* — *"No decision is captured. The finding stays in `.hv/spikes/<name>.md` for reference."*

Plain-text fallback: *"Promote to a decision?"* — yes / no.

On **Yes**, dispatch `hv-decide` via the `Skill` tool with `--from-spike <name>` as the argument, then continue to Step 7 once it returns.

On **Skip**, print one line — *"Spike finding stays in `.hv/spikes/<name>.md`. Run `/hv-decide --from-spike <name>` later if you change your mind."* — then continue to Step 7.

## Step 7 (Finish mode) — Optional Follow-Up

If the decision is `viable` and the user is ready to act, offer one of:

- *"Capture the real implementation as a backlog item? (`/hv-capture`)"*
- *"Write a plan for it now? (`/hv-plan`)"*

If not viable or inconclusive, the spike is its own conclusion. Don't push to capture work that the spike just argued against.

## Key Principles

- **One question per spike.** Multiple questions → multiple spikes.
- **The branch never merges.** Findings come back as a markdown file; code stays on the branch as reference.
- **Honest reporting beats salvage.** A "not viable" conclusion is just as valuable as "viable".
- **No stubs or partial work back to main.** Anything on main is real implementation.
- **Spikes are scoped, not open-ended.** A spike open >2 weeks without a decision is stale — close it `inconclusive` and recapture if needed.
- **Spikes feed decisions, not the other way around.** A `viable` / `not viable` / `depends-on-X` finish is a natural moment to ask whether the conclusion is a commitment future work must respect; an `inconclusive` finish is not.
- **Umbrella spikes are per-repo.** A spike's branch lives in the sub-repo named in its frontmatter `repo:` field; the spike file itself stays at the umbrella root.
