# Review verdict routing

`/hv-review` emits one of three verdicts on its final line, all caps — `PASS`, `CONCERNS`, or `FAIL`. Callers route on the verdict. Currently duplicated across `hv-review/SKILL.md` Step 10 (producer-side relay for standalone runs) and `hv-ship/SKILL.md` Step 3 (consumer-side routing); this reference is the canonical home. Any future skill that gates on a pre-merge review consumes the same contract.

## Verdict semantics

| Verdict | Meaning | Caller should |
|---------|---------|---------------|
| `PASS` | No concerns worth surfacing. The diff matches intent and respects conventions. | Continue silently. The reviewed work is integration-ready. |
| `CONCERNS` | The diff works, but surfaces should be flagged before merge — convention drifts, suboptimal patterns, or stale scaffolding. Not a regression. | Surface each concern, then route per `autonomy.level` (see Consumer routing below). |
| `FAIL` | Merging would regress behavior, break intent, or violate a hard-boundary `DECISIONS.md` entry. | Stop. Surface findings. Do **not** auto-route to ship/merge under any autonomy level. The user fixes via `/hv-work` or `/hv-debug` and reruns the review. |

## Consumer routing

When a skill invokes `/hv-review` and gates on the verdict, this is the canonical routing:

- **`PASS`** — proceed to the next step silently. No surfacing needed.
- **`CONCERNS`** — surface each concern inline, then branch on `autonomy.level`:
  - **`"off"` or `"auto"`** — use `AskUserQuestion`:
    - **Header:** `"Concerns"`
    - **Question:** *"Review surfaced N concerns on `<branch>`. How should I proceed?"*
    - **Options** (single-select):
      1. *"Address via `/hv-work` (Recommended)"* — *"Route the concerns to `/hv-work` as a fix list; rerun the calling skill after."*
      2. *"Ship anyway"* — *"Proceed with the integration despite the concerns."*
      3. *"Stop"* — *"Leave the branch as-is; no integration now."*
    - Plain-text fallback: *"Address first, ship anyway, or stop?"* (see `references/ask-user-question-fallback.md`).
  - **`"loop"`** — silently auto-pick *"Address via `/hv-work` (Recommended)"*: invoke `/hv-work` via the `Skill` tool with the concerns as the brief, then re-invoke the calling skill once the fixes are committed. Per the authoring convention *"routine routing/tagging auto-picks Recommended in loop mode"* (see `references/authoring-conventions.md` rule #5) — addressing surfaced concerns is the obvious safe routing.
- **`FAIL`** — stop unconditionally. Surface the findings; do not auto-route to ship/merge. A `FAIL` stops loop mode as a guard failure regardless of autonomy.

## Why "Ship anyway" never auto-picks under loop

*"Address via /hv-work"* is the safe routing — it loops back through review on the next ship attempt and surfaces repeat concerns to the user. *"Ship anyway"* is a user-volition gate: it overrides surfaced concerns and produces a public artifact (merge or PR) on the user's authority. Loop mode auto-picks only the **routing** answer (drain the queue toward integration-ready state), not the **acceptance-of-risk** answer. If a project genuinely wants concerns ignored, set `ship.review` to `false` — don't try to teach the loop to ship-anyway.

## Producer-side relay (standalone `/hv-review` runs)

When `/hv-review` is invoked directly (not from `/hv-ship`), it relays the verdict to the user as the final product instead of routing on it:

- **`PASS`** — tell the user *"Ready to ship. Run `/hv-ship`."*
- **`CONCERNS`** — print the concerns inline and suggest the next move: *"Address via `/hv-work` and rerun `/hv-review`, or accept and ship via `/hv-ship`."*
- **`FAIL`** — tell the user the merge would regress. Suggest fixing via `/hv-work` or `/hv-debug`. Don't route to `/hv-ship`.

When `/hv-review` is invoked from `/hv-ship`, the parent owns the routing — return the verdict and stop; do not run this relay.

## Per-skill carrier — what stays inline

- **`hv-review/SKILL.md` Step 5 (reviewer brief)** — the exact rubric text the reviewer evaluates against (intent match, convention compliance, etc.) is the producer's prompt-engineering content, not the verdict-routing pattern. Stays inline.
- **`hv-ship/SKILL.md` Step 3 (ship.review gate)** — the `ship.review` config check, the *"If `ship.review` is `false`, skip"* guard, and the cycle position (between commit-bundling and PR-body composition) are skill-local carriers. Stays inline.
- **The `AskUserQuestion` call site itself** — the call lives at the consumer's step; only the option text and routing logic extract to this reference.

## Carrier-label override

When a non-canonical caller of this routing (e.g. `/hv-ship` Step 3.5 second-opinion gate, or any future producer that emits the same PASS/CONCERNS/FAIL verdict shape) surfaces concerns, the caller MAY label them with a carrier prefix so the user can distinguish them from the primary `/hv-review` concerns in a session that runs both.

Convention: prefix surfaced concern lines with the producer's name and a dash, e.g. *"Second-opinion concerns:"* before listing the bullets. The routing logic (Consumer routing above) is unchanged — only the prose label differs. Codified for `/hv-ship` Step 3.5 second-opinion gate (F04); future producers follow the same shape.

## See also

- `references/ask-user-question-fallback.md` — canonical plain-text fallback mechanic.
- `references/authoring-conventions.md` rule #5 — *"routine routing/tagging auto-picks Recommended in loop mode"*.
- A future `references/manual-gates.md` may eventually capture the *"Ship anyway is a user-volition gate"* pattern alongside other manual gates (T37 captures the extraction). When that lands, this reference cites it instead of restating the rationale.
