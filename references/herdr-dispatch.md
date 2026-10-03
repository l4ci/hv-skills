# herdr worker dispatch

Used by `/hv-work` Steps 5, 6, 7, and 7.5 when `work.dispatch: "herdr"`. Under the default `work.dispatch: "subagent"` none of this applies.

The herdr backend is the tmux backend on a different host. Each worker is its own Claude Code session in its own `git worktree`, on its own branch, opening a PR against the cycle branch. The difference is where the session lives: a **herdr tab** in the orchestrator's own workspace instead of a tmux window. herdr recognises the agent running in each tab and reports its state natively, which removes most of the guesswork tmux needs.

Everything that is about the *workers* rather than the *host* is shared with tmux and lives in [`worker-contract.md`](worker-contract.md) (the standing contract and [provenance](worker-contract.md#provenance)) and [`tmux-dispatch.md`](tmux-dispatch.md): [escalating and relaying](tmux-dispatch.md#escalating-and-relaying), [the merge gate](tmux-dispatch.md#the-merge-gate), [permissions](tmux-dispatch.md#permissions) and [accounts](tmux-dispatch.md#accounts). This file covers only what herdr changes.

Verbs: the same four (`hv worker pool`, `hv worker dispatch`, `hv worker poll`, `hv worker gate`) plus `hv worker session`. `hv` picks the herdr host instead of the tmux one from `work.dispatch`.

## Being inside herdr is a precondition

`/hv-work` must run in a herdr-managed pane. herdr injects `HERDR_ENV=1` and `HERDR_WORKSPACE_ID` into every pane it manages, and worker tabs open in that workspace, next to the orchestrator, where a human already is.

```bash
hv worker session check     # exit 0 inside herdr, exit 1 outside
```

**Outside herdr there is no handoff.** Under tmux, `ensure` creates a session and moves the cycle into it. Under herdr it refuses with exit 4 and tells the user to start `/hv-work` from a herdr pane. Outside herdr there is no workspace to open an operator tab in, and driving a herdr server from outside a managed pane is what herdr's own guide forbids: commands then land wherever a human happens to have focus.

## Slots are tabs

| | tmux | herdr |
|---|---|---|
| Session per slot | window `<session>:<slot>` | tab in the current workspace, labelled `<slot>` |
| `slot.handle` | `hv:w1`, stable | tab id `w1:t7`, **new on every dispatch** |
| Agent name | n/a | `hv-<slot>-<tab id>` (e.g. `hv-w1-w1-t7`) |
| Worktree | `.worktrees/wN` | same: adopted with `tab create --cwd` |
| Account | `CLAUDE_CONFIG_DIR=… claude` typed into the shell | `tab create --env CLAUDE_CONFIG_DIR=…` |

Slots keep hv-managed worktrees from `hv worker pool`. herdr's own `worktree create` is not used for slots (rounds provision with `--path .worktrees/<agent>`, the same root), so the pool, the gate and the account verbs work the same on both hosts.

Agent names are unique per herdr **server**, not per workspace, so a bare `w1` would collide with another repo's pool. Tab ids are never reused, which makes `hv-<slot>-<tab id>` unique.

## Dispatch

`hv worker dispatch <wN> --body-file <path> --task <id>`:

1. Closes the slot's previous tab (`/exit`, then `tab close`). A fresh session per task is still the only trustworthy reset.
2. `herdr tab create --workspace $HERDR_WORKSPACE_ID --cwd <worktree> --label <slot> --no-focus [--env …]`, reading `.result.tab.tab_id` and `.result.root_pane.pane_id`.
3. `herdr agent start <name> --kind claude --pane <pane> -- <worker args>`. herdr runs `claude` itself, so `work.workerCommand` must launch `claude`: leading `KEY=VALUE` assignments become `--env` on the tab and everything after the binary is passed through. A command that runs a wrapper instead fails with exit 5.
4. Startup dialogs. `agent start` returns `agent_not_ready` when the session opens on a dialog: the folder-trust prompt on a fresh worktree, or the Bypass Permissions warning on a config dir that has not accepted it. The two put their accepting option in different places, and a fixed `down enter` picks **No, exit** on the trust prompt. The verb reads the pane, finds the accepting option and the cursor, and sends the keys between them. An unrecognised dialog is refused (exit 5) rather than answered. Setting `skipDangerousModePermissionPrompt: true` per account still avoids the second dialog entirely.
5. `herdr agent prompt <name> <brief> --wait --until working --until blocked --timeout 60000`. This returns once the worker has **started**, not when it has finished. Plain `--wait` would hold until the whole task settled.
6. Records `handle`, `task` and `state: busy` in `.hv/workers.json`.

`--relay` skips steps 1 to 4 and prompts the running session. The worker asked the question, so the answer has to reach the session that asked it.

| Exit | Meaning |
|---|---|
| 0 | pickup confirmed (working or blocked observed) |
| 3 | pool, slot, worktree or body file missing, or `--relay` found no running session |
| 4 | the reset guard found the slot holding work, or `work.workerCommand` carries a resume flag |
| 5 | host failure, including outside herdr, a wrapper command and an unrecognised startup dialog; also `agent_blocked`: a dialog was already up, nothing was sent |
| 6 | `agent_prompt_stalled` or timeout: no activity after the prompt. Inspect the tab before resending; a stall does not prove the text was lost |

## Poll mapping

`hv worker poll` reads herdr's native agent state after the settle interval, then runs the same text classifier as tmux on the captured pane (`agent read --source recent-unwrapped`).

| herdr state | hv state |
|---|---|
| `working` | `busy` |
| `blocked` | `needs-permission` (a dialog is up), or `blocked` when the pane carries `HV-BLOCKED` |
| `idle`, `done` | text rules: `HV-DONE` → `done`, `HV-BLOCKED` → `blocked`, usage-limit phrasing → `limited`, `API Error` / `Resume this session` → `dead`, else `idle` |
| `unknown` | the same text rules, else **`unknown`** |
| no agent in the tab | `dead`: the session exited back to a shell |

Sentinels, `Retrying in` and `limited` outrank the native state, the same way they outrank movement under tmux.

**`unknown` is not done.** herdr reports it when an agent is present but it cannot classify the screen. Look at the tab before doing anything, and never route it to the gate.

A slot that newly turns `blocked` or `needs-permission` raises a herdr notification with sound (`notification show --sound request`), once per transition.

## The registry now carries state and PR

On both hosts, live polls write `slot.state` (the hv state) and, when `HV-DONE` carries a PR URL, `slot.pr`. `hv worker gate` then merges through `gh pr merge` (or `glab mr merge` on GitLab) instead of falling back to a local merge. A bare branch name after `HV-DONE` is not recorded, because handing a branch to `gh pr merge` fails where the local merge would have worked.

## Worker contract additions

Append to the [standing contract](worker-contract.md#the-standing-contract) under herdr:

```
- You are in a herdr tab. Never `herdr agent rename` yourself, never close a
  tab you did not create, and never run `herdr server stop`: it takes down
  every sibling's session with yours.
```

## Rules herdr adds

- **`focused: true` means a human is looking at that agent.** The `hv` verbs do not check it. Before a relay or a re-dispatch, check `herdr agent get hv-<slot>-<handle>`; if the tab is focused, someone is typing in it, so tell them instead of typing over them.
- **A timeout or stall does not prove the prompt was lost.** Read the tab (`herdr agent read <name>`) before sending the same brief again. A duplicate brief costs a worker its context.
- **Install the herdr Claude integration once per config dir** (`herdr integration`) when provisioning an account for herdr slots.

## See also

- [`worker-contract.md`](worker-contract.md): the standing worker contract and approval provenance.
- [`tmux-dispatch.md`](tmux-dispatch.md): relay, merge gate, permissions, accounts and failure modes both hosts share.
