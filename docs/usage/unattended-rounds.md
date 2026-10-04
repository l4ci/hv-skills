# Unattended rounds

A round can run for hours with no one at the keyboard. Four pieces keep it going: hooks that make the
orchestrator hand off before its context fills, a supervisor that restarts it, a watcher that waits out
usage limits, and an opt-in switch that moves the orchestrator to another account before a limit hits.
All of it is opt-in and acts only on the orchestrator, the session that holds the
[round lease](parallel-rounds.md#starting-a-round). Workers are not touched.

What you need first is a working round: [parallel rounds](parallel-rounds.md). Without any of this,
`/hv-pause` and `/hv-work` (no argument) are the manual route; see [pausing and resuming](pausing-and-resuming.md).

| Piece | Verb | Stops | Config |
|---|---|---|---|
| Handoff hooks | `hv hook install` | an orchestrator whose context is at `handoffThreshold` | `orchestrator.handoff*` |
| Keepalive | `hv keepalive run` | nothing: it restarts the orchestrator after a handoff exit | `orchestrator.keepalive*` |
| Usage limits | `hv limit watch` | a session stalled on a 5-hour or weekly limit | `limits.*` |
| Account switch | `orchestrator.switchOnUsage` | an orchestrator close to a limit, before it hits | `orchestrator.usageThreshold` |

A typical unattended start: `hv hook install`, then in the orchestrator's pane
`hv keepalive run -- claude --model opus`. The keepalive supervisor runs the limit watcher beside the
command, so there is nothing more to start.

## Orchestrator handoff

A parallel-round orchestrator runs for hours, and its context fills. Two hooks make it hand off before that happens, with no one at the keyboard. They act only on the orchestrator, the session that holds the round lease (`hv round start`).

**Install it** once per project:

```
hv hook install                      # .claude/settings.local.json, per developer, not committed
hv hook install --wrap-statusline    # when you already have a statusLine
```

`install` merges into the settings file and never replaces anything it did not write. It adds a `Stop` hook (`hv hook stop`), a `SessionStart` hook (`hv hook session-start`) and a statusline (`hv statusline dump`). Hook entries end in `# hv-hook`, so a second run updates them instead of stacking copies. `--scope project` writes `.claude/settings.json` (committed), `--scope user` your Claude config dir.

**Your own statusline keeps working.** With a statusline already set, plain `install` refuses (exit 4). `--wrap-statusline` rewrites it to `hv statusline dump --then '<your command>'` and keeps the original beside it as `hvWrapped`. The dump records the session state, then runs your command with the same input and output, so your bar looks the same. `hv hook uninstall` removes the hooks and puts your command back. The file is rewritten as two-space JSON; if it already is, the round trip is byte for byte.

**What happens at the threshold.** Every statusline refresh writes the session's state (context percentage, rate limits) under the git common dir, `hv/session/<session_id>.json`. When the orchestrator tries to stop and the state shows `orchestrator.handoffThreshold` percent (default 75) or more, the Stop hook blocks and tells it to write `.hv/handoff/<base>.md` and run `/exit`. If it was told twice and still wrote nothing, the hook gives up and records `handoffFailed` in the state, so a session that cannot write a handoff is not held forever. The percentage comes from `context_window.used_percentage`, else from `current_usage` over `context_window_size`.

**The next session.** The SessionStart hook fires on `startup` and `clear`. When the new session holds the lease and the handoff exists, it injects the file as context and moves it to `<base>.md.consumed`. A restarted orchestrator has not run `hv round start` yet, so it holds no lease: a fresh handoff written by the Stop hook (first line `<!-- hv-handoff: orchestrator -->`) is injected anyway. Its first act is `hv round start`, then it reads the handoff. `resume` and `compact` keep the file.

`hv doctor` reports whether the statusline runs the dump and the hooks are in place (`statusline`, `stop-hook`). The hooks are opt-in: until `hv hook install` has written something, both checks skip. After that they fail on a partial or broken install (one hook missing, a statusline without the dump, a hook command that no longer resolves). Restarting the orchestrator after the exit is the next section; usage limits follow it. Without the hooks, `/hv-pause` and `/hv-work` (no argument) are the manual route ([pausing and resuming](pausing-and-resuming.md)).

## Keepalive

The hooks end an orchestrator session cleanly. `hv keepalive run` starts the next one. Start the orchestrator under it, in the pane it will own:

```
hv keepalive run -- claude --model opus       # everything after -- is the command
```

`hv keepalive run` is the pane's foreground process and `claude` is its child, so it learns the exit from the child's own status and needs neither herdr nor tmux to notice it. This is a supervisor, not a watcher of the pane. The cost is that an orchestrator not started under `run` is not restarted.

**When it restarts.** On every exit it looks for a fresh handoff, `.hv/handoff/<base>.md` no older than `orchestrator.handoffMaxAgeSeconds`. With one, it waits `orchestrator.keepaliveBackoffSeconds` (5) and starts the command again with the restart prompt, `orchestrator.restartPrompt`, appended as the last argument. The first start never gets the prompt. Without one, it stops: that is how `/exit` from you ends the loop.

**The lease.** `run` takes the [round lease](parallel-rounds.md#starting-a-round) and holds it across restarts, and tells its child through `HV_ROUND_HOLDER_PID`. So `hv round start` and the hooks inside the orchestrator see the supervisor as the holder: the round number survives a restart, and the SessionStart hook injects the handoff at once, without `hv round start` first. A second `run`, or an orchestrator started by hand, is refused while it lives (`hv round start` exits 4). `hv keepalive status` shows the supervisor and the lease; a supervisor killed with SIGKILL leaves a stale lease, which the next `run` reclaims.

**The breaker.** A restarted orchestrator that dies before it reads the handoff (bad auth, a hook error) leaves the same file behind. `run` counts a restart as progress only when the handoff changed, a new write with different content. After `orchestrator.keepaliveBreaker` (3) restarts in a row without progress it stops, and after `orchestrator.keepaliveMaxRestarts` (10) restarts in total it stops regardless. Both stops post an escalation comment on issue `orchestrator.escalateIssue` through `hv round escalate send`, and raise the herdr notification. With `escalateIssue` unset, which is the default, you get the notification and a warning only. The handoff is kept; fix the cause and run it again.

**How it stops.** The supervisor stops when the orchestrator leaves no fresh handoff (`no-handoff`), on the breaker or the restart limit (exit 1), or when you interrupt it: SIGINT and SIGTERM go to the child, the supervisor waits for it and does not restart (`interrupted`). It then releases the lease and records `status: stopped` in `<git-common-dir>/hv/keepalive.json`. It never deletes the handoff; only the SessionStart hook consumes it.

The flags `--max-restarts`, `--breaker`, `--backoff` and `--prompt` override the config for one run. `--no-limits` leaves out the usage-limit watcher the supervisor otherwise runs beside the command (see [usage limits](#usage-limits)). `--json` prints one envelope when the loop ends, not before.

## Usage limits

A 5-hour or weekly usage limit stops a session until the window resets. `hv limit watch` keeps a round from stalling on that: it notices the limit, waits for the reset, and types a resume prompt into the pane. Under `hv keepalive run` the same loop runs inside the supervisor, so there is nothing more to start. For an orchestrator not started under `run`, start the verb in the background or in a pane of its own:

```
hv limit watch            # blocks for the life of the round
hv limit status           # the log, and whether anything is watching
```

`watch` needs the round lease, because moving work between accounts is the orchestrator's act. It refuses to start (exit 4) without it, under a live `hv keepalive run` (which already watches) or beside another watcher.

**How it notices.** For the orchestrator it reads the rate limits the statusline dump stores: a window at 100 percent with its reset still ahead is a limit, and the later reset wins if both are. For a worker slot it reads the account meter (`hv worker account list`), but only after the slot's pane shows a limit message, never on a timer. The message itself is the fallback: on herdr 0.9.x the loop subscribes to `pane.output_matched` with the phrases `hv worker poll` already uses for LIMITED, on tmux (or if herdr refuses the subscription) it captures the panes every `--settle` seconds. A message with no data behind it gets its reset time from the text (`resets at 3pm` reads as the next 3pm in your time zone, within 8 days), and otherwise sleeps `limits.fallbackSleepSeconds`. "Approaching your usage limit" is a warning and starts nothing.

**Sleep or switch.** `limits.mode` is `switch` (default) or `sleep`.

- `sleep` waits for the reset.
- `switch` applies to a worker slot only. It uses the rule `hv round assign` uses: keep the slot's account unless it is cooling, otherwise take the account with the most headroom (`hv worker account pick --exclude <account>`). With such an account and an idle slot on it, the slot's issue moves there with `hv round transfer`, so the work continues from its pushed branch and a handoff comment. With no usable account, or no idle slot on it, the limit sleeps instead, and the entry says why.
- **The orchestrator only sleeps.** A limited session cannot write a handoff, and a restarted one with no handoff has nothing to continue from. Moving it to another account is opt-in and happens before the limit, not at it: see [switching the orchestrator's account](#switching-the-orchestrators-account).

**Resuming.** At the reset plus `limits.resumeMarginSeconds` (60) the loop types `limits.resumePrompt` into the pane and keeps watching it. A pane still limited after the prompt starts another cycle, up to `limits.maxResumes` (3) for one limit. Past that the entry is `failed` and the loop posts an escalation on issue `orchestrator.escalateIssue`, or raises a host notification when that is unset. Stop the watcher with Ctrl-C or SIGTERM and the waiting entries stay waiting: the next watcher resumes any whose reset has already passed.

**Where the log is.** The `limits` list in `.hv/workers.json`, beside `slots` and `escalations`. Each entry (`l1`, `l2`, ...) records the session (`orchestrator` or a slot), the window, whether the reset came from data or text, when it resets, the action, its status (`waiting`, `resumed`, `switched` or `failed`) and a note. `hv limit status` reads it back, and `hv round status` and `hv round reconcile` list the ones still waiting. Nothing prunes resolved entries.

**Config.** Five keys under `limits`, all silent defaults: `mode` (`switch`), `resumeMarginSeconds` (60), `fallbackSleepSeconds` (1800), `maxResumes` (3) and `resumePrompt` (`The usage limit has reset. Continue where you left off.`). See [configuration](configuration.md#limits-keys).

## Switching the orchestrator's account

Off by default. With `orchestrator.switchOnUsage` set to `true`, an orchestrator that is close to its usage limit hands off and restarts under another account, instead of running into the limit and sleeping. The usage-limit sleep stays the behavior when the key is off, and for anything the switch does not cover.

```
hv config set orchestrator.switchOnUsage true
hv config set orchestrator.usageThreshold 90      # percent, the default
```

**What it needs.** The Stop hook installed (`hv hook install`), the orchestrator started under `hv keepalive run` (without a supervisor nothing would restart it, so the hook does not ask), and at least two accounts with a `configDir` in `work.accounts`. `hv doctor` has a `switch` check, but it covers only the Stop hook and two accounts with a `configDir`. It cannot tell whether the orchestrator runs under `hv keepalive run`. The account it moves to also needs the statusline dump, which the `statusline` check covers.

**At the threshold.** When the larger of the 5-hour and weekly `used_percentage` reaches `orchestrator.usageThreshold`, the Stop hook blocks the way it does for context and asks for the handoff and `/exit`, and records which window tripped. A session with no rate-limit reading (API billing) is never asked.

**The restart.** When the orchestrator exits with that handoff, the supervisor picks the account. It never keeps the current one: the target is the account with the most headroom whose meter is `free`, that has a `configDir`, and whose headroom is above `100 - usageThreshold`. An account whose meter is `unknown` is not taken. The restarted `claude` runs with `CLAUDE_CONFIG_DIR` set to that account, and every later restart of the same run keeps it. It reads its handoff through the SessionStart hook as after any restart. The switch counts as a restart against `orchestrator.keepaliveMaxRestarts`.

**With no usable account** the supervisor restarts at once on the same account and holds the switch until the window's reset (`switchHold` in `keepalive.json`; `limits.fallbackSleepSeconds` when there is no reset time). While the hold lasts the hook passes on usage, so the session works on and the in-session limit sleep handles the real limit at 100 percent. A context handoff is not held. A hold with no reset time lasts `limits.fallbackSleepSeconds` (30 minutes by default), so while usage stays at or above the threshold, handoffs repeat after each hold until `orchestrator.keepaliveMaxRestarts` stops the supervisor.

**The figure is not a limit.** The threshold reads the session file's `used_percentage`, which carries no `extra_usage` information, so a weekly window at the threshold counts even when extra usage is enabled and would keep the account going. For an opt-in this is the simple choice; set `usageThreshold` to 100 to wait for the window to fill.

**The log.** Each decision is an entry in the `limits` list: `action` `switch` (`status` `switched`) with the account left in `account` and the account switched to in `note`, or `action` `restart` (`status` `resumed`) when no account was usable, with why and the hold's end in `note`. `hv limit status` shows them. `keepalive.json` gains `account`, `switches` and `switchHold`.

The herdr agent integration is per account (`herdr integration install claude` with that `CLAUDE_CONFIG_DIR`); `hv doctor`'s `hook` check covers it. The project-local hooks apply to every account.
