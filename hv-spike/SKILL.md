---
name: hv-spike
description: Throwaway feasibility experiment on a dedicated git branch — answers a specific question without polluting main or the backlog. Creates spike/<name> branch and .hv/spikes/<name>.md for question + findings + decision. Branch is never merged; only findings come back. Use when you need to try X before committing to it ("can we use SSE?", "does this library handle our scale?").
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  🟨  hv-spike  ·  throwaway feasibility experiment on a branch
  triggers: "spike X", "feasibility"  ·  pairs: hv-vision, hv-plan
════════════════════════════════════════════════════════════════════════
```

# hv-spike — Throwaway Feasibility Experiment

Answer a *specific feasibility question* on a dedicated `spike/<name>` branch. The branch is never merged — only the findings come back to main, in `.hv/spikes/<name>.md`. Code on the spike branch is reference, not product.

Two modes:

- **Start mode** — open a new spike with a question
- **Finish mode** — extract findings from work done on a spike branch into the spike file

## Step 1 — Preflight & Mode

```bash
.hv/bin/hv-preflight
```

If absent or non-zero, invoke `hv-init` via the `Skill` tool, then continue.

Determine the mode silently:

- *"spike SSE for live updates"*, *"try X"*, *"feasibility check on Y"* → **Start mode**
- *"spike done"*, *"finish the SSE spike"*, *"extract findings"* → **Finish mode**
- Ambiguous → ask once

In Finish mode, list existing open spikes via `.hv/bin/hv-spike-list` and ask which one if not specified.

## Step 2 (Start mode) — Sharpen the Question

A spike answers a *yes/no/conditional* question. Push back if the question is vague:

- ❌ *"Try Server-Sent Events"* — too open
- ✅ *"Can we use SSE for live updates over our existing nginx setup without proxy buffering issues?"*

Name the spike with a short kebab-case identifier (`sse-feasibility`, `auth-rotation`, `migration-cost`). The name becomes the branch suffix and the spike file's stem.

## Step 3 (Start mode) — Confirm Before Branching

Before mutating git state, confirm with the user via `AskUserQuestion`:

- **Header:** `"Spike"`
- **Question:** *"Create branch `spike/<name>` and switch to it now?"*
- **Options:**
  1. *"Yes, create and switch (Recommended)"* — *"Branches off current HEAD; you'll be on the spike branch immediately."*
  2. *"Create only, stay on this branch"* — *"Useful when you want to switch on your own time."*
  3. *"Cancel"* — *"Don't do anything."*

Plain-text fallback: if the working tree is clean, default to "create and switch"; otherwise default to "create only" so dirty changes don't follow.

## Step 4 (Start mode) — Create the Spike

```bash
BRANCH=$(.hv/bin/hv-spike-add <name> "<question>")
```

The helper:

- Creates branch `spike/<name>` off the current HEAD
- Writes `.hv/spikes/<name>.md` with frontmatter + question + section stubs

If the user picked "create and switch" in Step 3, run `git checkout "$BRANCH"`.

Compact handoff:

```
Spike opened: spike/<name>
Question: <one line>
File: .hv/spikes/<name>.md

Hack freely on the branch. When done, return to main and run:
  /hv-spike done <name>
```

No further work in this skill — the user drives the experiment.

## Step 5 (Finish mode) — Read the Spike Branch

Gather what was tried:

```bash
git log spike/<name> --oneline
git diff main...spike/<name> --stat
```

Read `.hv/spikes/<name>.md` for the original question and any notes the user already wrote.

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
