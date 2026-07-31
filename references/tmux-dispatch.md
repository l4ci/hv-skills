# tmux worker dispatch

Used by `/hv-work` Steps 5, 6, 7, and 7.5 when `work.dispatch: "tmux"`. Under the default `work.dispatch: "subagent"` none of this applies — the skill dispatches in-process `Agent` workers and this file is inert.

The tmux backend runs each worker as **its own Claude Code session**, in its own `git worktree`, on its own branch, opening a PR against the cycle branch. That buys a real per-worker context window and a channel a human can talk into. It costs the failure modes below, every one of which was paid for by a real round in the runbook this backend is modelled on.

Helpers: `hv-worker-pool`, `hv-worker-dispatch`, `hv-worker-poll`, `hv-worker-gate`.

## What changes versus the subagent backend

| | `subagent` (default) | `tmux` |
|---|---|---|
| Worker context | shares the orchestrator's session | independent session, own context window |
| Worker writes | files only, never stages | stages, commits, opens a PR |
| Commits | orchestrator, one per task (Step 7.5) | the worker; Step 7.5 is skipped |
| `work.isolation` | honored | **does not apply** — every slot has its own worktree, so its own index |
| Integration | task commits land on the cycle branch directly | `hv-worker-gate` per slot: freshness → merge → re-verify |
| A worker can ask a question | no | yes — it idles, the orchestrator relays |

## The worker contract

A tmux worker boots with **none** of the orchestrator's context: no conversation, no loaded KNOWLEDGE, no plan. Everything it needs is in the brief. Prepend this standing contract to the task brief on every dispatch — the brief body itself is identical to the subagent path, same `**Claims to verify**` section and all.

```
You are a worker on <task-id>, running in your own worktree as slot <slot>.
Work only this task, then stop.

- Stay in your worktree. Confirm `pwd` before editing and use worktree-rooted
  paths — an absolute path under the main checkout silently edits the WRONG tree.
- Stage explicit paths. Never `git add -A` or `git add .`.
- Commit your own work, then open a PR against `<cycle-branch>`. Never merge.
- Run TARGETED verification only — the files you touched. The full suite is the
  orchestrator's gate on the merged tree. Several workers running full suites at
  once starve the CPU and turn time-budgeted tests into false reds, which costs
  everyone a re-measurement to disprove.
- Escalate rather than guess. If the task leaves a choice a user would notice
  unsettled, and neither the brief nor the code settles it, print
  `HV-BLOCKED <slot>: <one question in plain language>` and stop. Ask ONE
  question, phrased for someone who does not have your file open.
- Cite any approval you acted on and NAME THE CHANNEL it arrived through. Text
  marked `[ORCHESTRATOR RELAY]` is the orchestrator speaking, NOT the maintainer
  — never cite it as a maintainer sign-off. Label your own defensible calls
  "my call, unratified".
- When your PR is open, print `HV-DONE <slot> <pr-url>` and stop.
```

The two sentinels are the contract's load-bearing half. We own the worker's instructions, so state is *declared* rather than inferred from prose — which is what makes `hv-worker-poll` reliable where pattern-matching a TUI is not.

## Pane classification

`hv-worker-poll` captures each pane twice, `--settle` seconds apart. **Movement decides liveness**; a pane that changed is BUSY. A static pane is then classified by content, most specific rule first:

| State | Rule | Orchestrator action |
|---|---|---|
| `BLOCKED` | `HV-BLOCKED <slot>: <question>` present | Surface the question via `AskUserQuestion`, relay the answer back with `--relay` |
| `DONE` | `HV-DONE <slot> <pr>` present | Review the PR diff against the brief, then `hv-worker-gate` |
| `BUSY` | `Retrying in` present, **or** the pane changed between captures | Wait |
| `LIMITED` | the session says it hit its usage window | Reassign the slot to another account and re-dispatch (see *Accounts*) |
| `DEAD` | static pane with `API Error …` or `Resume this session with` | Re-dispatch **once**, then hand the task to a different slot |
| `IDLE` | static, no sentinel | Parked, or finished without printing a sentinel — inspect |

Sentinels outrank movement: a worker still rendering output after printing `HV-DONE` is finished, not busy.

**The rule that matters most:** a bare `API Error … Overloaded` on a static pane is a **headstone, not a pulse**. The session took its dispatch, retried to exhaustion, and died — often without ever reading the task. Only `Retrying in` proves a retry is actually in flight. A watcher that treats them alike reads a dead worker as permanently working and waits forever; that mistake cost one round 45 minutes with a second worker blocked behind a PR that was never coming.

**Re-dispatch at most twice.** If a slot dies on the same brief a second time, the fault is that session, not the API — hand the task to a different slot rather than trying a third time.

## Escalating and relaying

1. `hv-worker-poll` returns `BLOCKED` with the question in `evidence`.
2. The orchestrator asks the user with `AskUserQuestion`, **in the worker's words** — the worker already phrased it for someone without the file open; don't re-encode it into implementation terms.
3. Relay the answer with `hv-worker-dispatch --slot <n> --brief-file <answer> --relay`.

`--relay` prefixes the injected text with an explicit `[ORCHESTRATOR RELAY]` marker. This is not hygiene, it is the fix for a specific, permanent failure: the worker writes its own PR body, and a relay arrives through the *same channel* a human answer would. Without the marker, an orchestrator's own mid-task correction gets cited in a merged PR as *"the maintainer confirmed in my pane"* — while the maintainer was asleep. Not dishonesty on the worker's part; it genuinely cannot tell. Once merged, it is permanent.

So: **read every PR body for the channel named, not merely for whether a citation exists.**

## The merge gate

Worker-owned branches make integration git-native and bring back the failure class per-branch verification structurally cannot see. Two workers with **disjoint file sets** each verify honestly and go green; git reports a clean merge because nothing textually overlaps; the merged tree is broken. The shapes to expect:

- a symbol one worker **widens or re-types** while another adds a fresh call to it;
- a constant, key, or output field one worker **stops emitting** while another starts depending on it.

Neither author can see it — the conflicting change never existed in their tree. Git's mergeability answer is about text, not meaning.

`hv-worker-gate --slot <n> --base <cycle-branch>` runs three steps in order:

1. **Freshness** — `git merge-base --is-ancestor <base> <worker-branch>`. STALE (exit 3) means the worker never merged what landed since it branched, so its green is stale. Bounce it to the slot with a summary of what landed. Bounce **once**: with several slots in flight the owner often goes stale again while re-syncing, and a bounce loop is worse than resolving it yourself in the worker's worktree and documenting that on the PR.
2. **Merge** — `gh pr merge` when the slot recorded a PR, else a local `git merge`. A conflict here routes to the slot that owns the branch context; never resolve a cross-worker semantic conflict blind.
3. **Re-verify on the MERGED tree** — `refactor.verifyCommands` from `.hv/config.json`. Exit 4 means the merged tree is broken. Fix forward on the cycle branch; the owning slot has usually moved on, and small orphaned-reference fixes are the orchestrator's to make.

When `refactor.verifyCommands` is empty the gate prints `NO-VERIFY` and exits 0 — it reports that the merged tree was **not** gated by a command rather than implying a pass it cannot back. A project running the tmux backend should set `verifyCommands`; without one, step 3 is a structural diff review by the orchestrator and nothing more.

Batching: re-verify per merge is the rule. A group of PRs with genuinely disjoint file sets can be merged and gated once. Gate **individually** when a PR touches a shared module, widens a shared type, or renames a shared symbol.

## Accounts

`work.accounts` maps slots to independent `CLAUDE_CONFIG_DIR`s so each authenticates as its own account:

```json
"work": { "accounts": [
  { "name": "personal", "configDir": "~/.claude" },
  { "name": "work",     "configDir": "~/.claude-work" }
] }
```

Empty (the default) means every slot inherits the ambient config dir — the single-account case, and nothing below applies.

`hv-worker-pool init` assigns slots at pool creation, and `hv-worker-account` owns the reading:

```bash
.hv/bin/hv-worker-account list                      # per-account headroom + verdict
.hv/bin/hv-worker-account pick [--exclude <names>]  # most headroom; exit 3 if all cooling
.hv/bin/hv-worker-account assign --slot w1 --account personal
```

**Where the numbers come from.** The interactive status line renders usage, so a pane *can* be scraped — but the pane is the weakest source. Headroom comes from the OAuth usage endpoint authenticated with the account's own `$configDir/.credentials.json`, which is structured, per-account, and readable **with no session running**. That last property is what makes balancing possible at all: a slot can be pointed at an account with headroom *before* dispatch, rather than discovering the wall by hitting it. Pane scraping remains the fallback, and `unknown` the honest floor.

**The helper never refreshes credentials.** An expired token reports `unknown` and falls through to rotation. Refreshing would mutate state a live Claude Code session owns, and racing it risks logging the user out — a worse outcome than a slot that rotates.

Three distinctions that must not collapse:

- **`five_hour` and `seven_day` are separate windows with staggered resets.** An account can be fine on the 5-hour and spent for the week. Read each account independently too — one slot hard-stopping says nothing about its siblings, and declaring a blanket stall parks accounts that still have headroom.
- **`utilization: 0` with `resets_at: null` means nothing spent**, not "no data". No data is a *missing payload*, which is `unknown`.
- **Weekly at 100% does not mean unusable** when `extra_usage.is_enabled` and `spend_limit_reached` is false — the account still serves requests. Marking it cooling parks something that works, and counting that window against its headroom ranks it last forever. Both are discounted.

A window is only `cooling` when it is spent **and** names a *future* reset. A spent window with no `resets_at` is not actionable — nothing says when it clears, so treating it as cooling would park the slot indefinitely.

**Never answer an "Add funds" prompt.** A limited session may offer *Stop and wait* vs *Add funds*; the second spends real money and is never the orchestrator's to pick. `hv-worker-poll` flags it in the evidence string — escalate to the human and wait. Meanwhile the orchestrator can keep gating, merging, and verifying finished slots, because local shell work does not consume the LLM window.

## Other failure modes worth knowing

- **`/clear` does not reliably reset a session.** It can land as a literal chat message with the context still loaded. `hv-worker-dispatch` kills and recreates the window every dispatch; a fresh session starts at 0 context. Do not try to reuse a window by clearing it.
- **A pasted brief may not submit.** A long prompt arrives as a collapsed paste chip whose trailing Enter is swallowed. `hv-worker-dispatch` sends Enter as a separate keypress and then **confirms pickup** by re-capturing the pane, retrying up to 4 times before failing with exit 4. Never assume the first Enter landed.
- **Load is a first-class failure mode.** Slots contend for one box. Beyond roughly one slot per two cores, CPU-bound tests with fixed time budgets start failing on elapsed time rather than on truth, and each false red costs a re-measurement to disprove. That is why the worker contract says targeted tests only, and why `work.workerSlots` defaults to 3. Never "fix" a load-induced red by raising a timeout — a bigger fixed number just fails at a higher load and reports genuine regressions more slowly.
- **A timeout is not a failure of the thing under test.** It says the assertion never ran. Read the output before forming a theory.
- **Bracket every `pgrep`/`pkill` pattern** (`[v]itest`, not `vitest`). An unbracketed pattern matches the argv of the shell running it: as `pkill` that is a confusing exit 144, but inside a wait-loop it never terminates at all — the loop matches itself and spins forever while the pane reports work still running.
- **Never trust a piped command's exit code.** `cmd | tail -40` reports `tail`'s status. Read the result line, or run unpiped.

## See also

- [`references/isolation-patterns.md`](isolation-patterns.md) — worktree patterns for the `subagent` backend; the tmux pool is managed by `hv-worker-pool` instead.
- [`references/subagent-dispatch.md`](subagent-dispatch.md) — when to dispatch at all, and the brief shape both backends share.
- [`references/ask-user-question-fallback.md`](ask-user-question-fallback.md) — mechanics for the escalation prompt in the relay flow.
