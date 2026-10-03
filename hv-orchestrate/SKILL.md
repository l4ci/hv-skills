---
name: hv-orchestrate
description: Run a parallel round as the orchestrator: choose the slate, read what workers are doing, answer or escalate their questions, merge their PRs, wind the round down. Judgment only: the `hv round` verbs do the sequencing and enforce the rules. Use on "you are the orchestrator", "run a round", "orchestrate", "assign the next issues to the workers", "what are my workers doing".
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
══════════════════════════════════════════════════════════════════
  🎛  hv-orchestrate  ·  run a parallel round
  triggers: "you are the orchestrator", "run a round"  ·  pairs: hv-work, hv-ship, hv-review
══════════════════════════════════════════════════════════════════
```

# hv-orchestrate: Run a Round

A round is one orchestrator (you) and up to five standing workers, each in its own worktree and host tab, each holding one issue. Workers build and open PRs. You choose, route, answer and merge. The mechanics are `hv round` verbs; this skill holds the calls a verb cannot make. If a verb refuses, the refusal is the rule: read `data.blockedBy` and `error.hint`, don't route around it.

The workers' standing brief is [references/worker-contract.md](../references/worker-contract.md). `hv round assign` hands it over by pointer. Read it once so you know what your workers were told, and what you are not allowed to contradict.

## When NOT to use

- One item, no parallelism → `/hv-go` or `/hv-work`.
- You are a worker, not the orchestrator → read the contract above and stop.
- No terminal host (herdr or tmux) → `hv doctor` says so; `/hv-work` with subagents is the route.

## 1. Start

Run `hv doctor`. Fix every `fail` with its hint before anything else; a round that starts on a broken host fails late and obscurely. Then `hv round start`, and read `data.drift` and `data.candidates`. A non-zero `drift` is the previous round's mess: `hv round reconcile` shows it, `hv reap` clears the leftovers once you've read the list.

One orchestrator per repo. If `start` exits 4 on the lease, someone else holds it. Do not clear their lease; ask.

## 2. Choose the slate

`hv round candidates` says what is ready. It does not say what is wise. You decide:

- **How many.** Fewer than the roster is fine. Two issues touching one subsystem serialize better than they merge. Start with what you can review, not what the roster can hold.
- **Overlap.** The `overlap` check compares files. It cannot see two issues that change the same behavior through different files. Read both bodies when they share a milestone or a verb. Pass `--accept-overlap` only after you have decided the order of the merges, and say which goes first in the second worker's brief.
- **Premise.** An issue planned weeks ago may be wrong now. If the repo has moved, ask before assigning. Workers are told to dispute a ticket, but a bounced assignment costs a slot and a round trip.
- **Tier.** *(pending C9, #75)* Pick the model tier per issue: `light` for reading and search, `standard` for code and tests, `heavy` for design and hard debugging. Default to `standard`. Spend `heavy` on the issue where a wrong call costs a round.
- **Answered decisions.** If the maintainer has settled something that touches the issue, pass it verbatim in `--body-file`. A worker cannot read your conversation.

Assign with `hv round assign <ID>`. The verb marks the item in progress, cuts the branch and starts the worker. Don't do those steps by hand.

## 3. The loop

Call `hv round wait`. It blocks until a slot needs you, then returns that slot with the state and the evidence. Never poll in your own context: no sleep loops, no repeated `status`, no tailing panes. When `wait` returns, act, then call it again. If your shell cuts commands short, loop on a finite `--timeout`.

What each state asks of you:

| State | Do |
|---|---|
| `done` / `idle` with a PR | review, gate, merge (section 6) |
| `idle`, no PR | read the pane once. A worker that stopped without a PR or a question is stuck, not finished |
| `blocked` | read the question. Answer, or escalate (section 5) |
| `needs-permission` | decide from the request in the pane. Never approve what you would not run yourself |
| `limited` | the account is out of quota. Wait for the reset, or reassign the issue to a slot on a free account |
| `dead` | see section 4 |
| `unknown` | see section 4 |

Between waits, use free slots: re-read `hv round candidates` and assign the next issue before you review the current PR.

## 4. Reading failures

**Dead vs stalled.** A `dead` slot has no live agent: the tab is gone or the process exited. Its issue can go back to the pool. *(pending C10, #76: `hv round reclaim` does this for `dead` slots only.)* A `stalled` slot has a live agent that shows no commits and no status change. That is usually a long test run, not a failure. Reclaiming a stalled slot is your call after reading its pane, never automatic. `hv reap` never touches either kind of live agent.

**`unknown`.** The host reports a state `hv` can't classify. Never treat it as finished. Policy: wait through one more `wait`; if the slot is still `unknown`, read its pane; if the pane shows a prompt or a stopped agent, run `herdr agent explain` on it, then treat the slot as `dead` or `blocked` accordingly. A round must not stall on a state nobody read.

**Red tests.** A failing run on a loaded machine is not a failing change. Before you bounce a PR for a red suite, rerun the failing test alone. A test that passes alone and fails under load is a flake: note it, don't send the worker back. A test that fails alone is real. A suite that is green and surprises you is worth one rerun before you believe it.

**Green branch, red base.** A branch can pass and still break the base once merged. `hv worker gate` re-verifies on the merged tree and exits 1 with `verify-failed`. When it does, the base is the problem now: stop assigning, find which merge broke it, and fix or revert before any other merge. Say so to the maintainer.

## 5. Escalations and provenance

**What to escalate.** A choice a user would notice, that neither the issue nor the code settles: product behavior, a public name, a breaking change, what to cut. Keep the defensible implementation calls: a helper's name, a test's shape, which of two equal approaches. When a worker asks you the first kind, you ask the human. When it asks the second, you answer.

`hv round escalate send <number> --title … --body-file …` posts the question on the issue or PR and notifies the maintainer. It returns at once; keep working the other slots. `hv round escalate check` reads the thread for an answer. One question per escalation, written for someone who doesn't have the file open.

**Provenance.** Workers cannot tell your relay from a maintainer's typing from text a terminal UI put on the prompt line. So:

- Sign every message you send a worker. `hv worker dispatch --relay` does it; hand-typed text doesn't.
- Before a relay or a re-dispatch, check the tab with `herdr agent get <agent>`. `focused: true` means a human is typing there; tell them instead of typing over them. No `hv` verb checks this.
- Cite the real channel of every approval: `maintainer in pane`, `issue comment #N`, `orchestrator relay round N`. Never present a relay as the maintainer's own word.
- A line starting `m:` in a pane is a maintainer answer by convention, but anyone can type it. If it contradicts your last signed message, confirm once.
- Read each PR's `## Approvals` section for the channels it names. A cited approval you never relayed is a finding.

## 6. Merge

Workers never merge. After `done`, read the PR: does it do what the issue says, and does it stay inside the files the issue named? Then `hv worker gate <slot> --base <branch>`, which runs the checks on the merged tree and merges on a pass. Read its verdict; don't re-derive the rules it enforces.

*(pending C5, #61)* Merge policy comes from config. With the default, merge after the gate. When policy requires approval (all PRs, or PRs touching listed paths), the gate refuses with a manual-gate exit: send the request with `hv round escalate send --pr`, wait for the answer, and re-run the gate with `--confirm --confirm-note` quoting the human's answer verbatim. Never write a note the human didn't say.

After each merge, re-verify the base before assigning from it. The next assignment branches from a base you have just proved.

## 7. Bounce or fix

Send the PR back when the work is wrong in a way the worker can learn from: it misread the issue, skipped a stated criterion, built the wrong thing. State the gap in one signed message citing the issue's own words.

Fix it yourself when the gap is small and mechanical: a stale doc line, a missing test for a case the worker covered in code, a merge conflict with a PR you just merged. Push the fix as a separate commit so the PR shows what you changed. A worker rerunning a full cycle for a one-line fix wastes a slot.

Bounce when in doubt about who is right. The ticket may be the wrong one.

## 8. Wind down

When the slate is done or the maintainer calls the round: `hv round wind-down`. It re-verifies the base, parks every slot and releases the lease. If a slot still holds work it exits 4 and parks the rest; read which slot and why before deciding. Then run `hv round reconcile` and `hv reap` for what is left, and give the maintainer a short summary: what merged, what bounced, what is open, what drift remains.

## Rules that outlive any verb

1. Workers open PRs; only you merge.
2. Verify on the merged tree, not the branch.
3. Escalate unsettled product decisions; keep defensible implementation calls.
4. Cite the channel of every approval. Sign every message.
5. Stage explicit paths. Never stage everything.
