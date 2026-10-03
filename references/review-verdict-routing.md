# Review verdict routing

`/hv-review` ends with one of three verdicts — `PASS`, `CONCERNS`, or `FAIL` — and records it with `hv verdict add`, as do the `/hv-ship` second opinion and `/hv-qa` (which adds `INFRA-FAIL`). Callers route on the recorded verdict with `hv verdict route`, never on a report's last line. The routing table lives in code (`internal/verdict`, contract section "B2: verdicts" in `docs/design/5.0-verb-contract.md`); this reference holds what the code does not: what each verdict means, the question text, and the labels. Any future skill that gates on a pre-merge review consumes the same contract.

## Recording and routing

- **Producers** end their report with a fenced `json` block, `{"verdict", "summary", "findings": [{"severity", "title", "file", "line", "detail"}]}`, and the skill records it: `hv verdict add <branch> --kind review-spec|review-quality|second-opinion|qa --verdict <V> --body-file <block>`. Exit 2 names the malformed field; ask for the block again, never guess. `/hv-debug` records fix outcomes with `hv debug verdict <ID>`.
- **Consumers** run `hv verdict route <branch> --for ship-review|ship-second-opinion|ship-qa|queue --json` and act on `data.next`. Exit 3 means no verdict was recorded: rerun the producer.

## Verdict semantics

| Verdict | Meaning | Caller should |
|---------|---------|---------------|
| `PASS` | No concerns worth surfacing. The diff matches intent and respects conventions. | Continue silently. The reviewed work is integration-ready. |
| `CONCERNS` | The diff works, but surfaces should be flagged before merge — convention drifts, suboptimal patterns, or stale scaffolding. Not a regression. | Surface each concern, then route per `autonomy.level` (see Consumer routing below). |
| `FAIL` | Merging would regress behavior, break intent, or violate a hard-boundary `DECISIONS.md` entry. | Stop. Surface findings. Do **not** auto-route to ship/merge under any autonomy level. The user fixes via `/hv-work` or `/hv-debug` and reruns the review. |

## Consumer routing

`data.next` from `hv verdict route` says what to do:

- **`continue`** (PASS) — proceed to the next step silently. No surfacing needed.
- **`ask`** (CONCERNS, `autonomy.level` off or auto) — surface each concern inline, then use `AskUserQuestion`:
    - **Header:** `"Concerns"`
    - **Question:** *"Review surfaced N concerns on `<branch>`. How should I proceed?"*
    - **Options** (single-select):
      1. *"Address via `/hv-work` (Recommended)"* — *"Route the concerns to `/hv-work` as a fix list; rerun the calling skill after."*
      2. *"Ship anyway"* — *"Proceed with the integration despite the concerns."*
      3. *"Stop"* — *"Leave the branch as-is; no integration now."*
    - Plain-text fallback: *"Address first, ship anyway, or stop?"* (see `references/ask-user-question-fallback.md`).
- **`address`** (CONCERNS, loop) — surface each concern, then invoke `/hv-work` via the `Skill` tool with the concerns as the brief, and re-invoke the calling skill once the fixes are committed. This is the *"Address via `/hv-work` (Recommended)"* answer, auto-picked per the authoring convention *"routine routing/tagging auto-picks Recommended in loop mode"* (`references/authoring-conventions.md` rule #5).
- **`surface`** (an advisory gate: QA under `qa.gate: "advisory"`, any QA `INFRA-FAIL`, or a second opinion from the retired `codex` runner) — surface the findings and continue. `data.advisory` is true.
- **`stop`** (FAIL) — stop unconditionally. Surface the findings; do not auto-route to ship/merge. A `FAIL` stops loop mode as a guard failure regardless of autonomy.

## Why "Ship anyway" never auto-picks under loop

*"Address via /hv-work"* is the safe routing — it loops back through review on the next ship attempt and surfaces repeat concerns to the user. *"Ship anyway"* is a user-volition gate: it overrides surfaced concerns and produces a public artifact (merge or PR) on the user's authority. Loop mode auto-picks only the **routing** answer (drain the queue toward integration-ready state), not the **acceptance-of-risk** answer. If a project genuinely wants concerns ignored, set `ship.review` to `false` — don't try to teach the loop to ship-anyway.

## Queue routing (`/hv-review --queue`, issue mode)

The queue loop is the consumer (`hv verdict route --for queue`). It routes per PR / MR and always posts the verdict as a `feedback` comment on each linked item and on the PR.

| `data.next` | Verdict | Action |
|---------|---------|--------|
| `ask` | `PASS`, interactive | `AskUserQuestion` merge / skip / stop; merge runs `hv ship pr-merge <pr>` (exit 4 = not merged, an item unproven and set to `changes-requested`) |
| `merge` | `PASS`, loop | merge, no question |
| `request-changes` | `CONCERNS` or `FAIL` | findings as feedback, `hv item state <ID> --to changes-requested`; no merge. A `FAIL` still stops the surrounding loop as a guard failure |

Exit 3 / 4 from any helper stops the queue. Label lifecycle: `references/issue-mode.md`.

## Producer-side relay (standalone `/hv-review` runs)

When `/hv-review` is invoked directly (not from `/hv-ship`), it relays the verdict to the user as the final product instead of routing on it:

- **`PASS`** — tell the user *"Ready to ship. Run `/hv-ship`."*
- **`CONCERNS`** — print the concerns inline and suggest the next move: *"Address via `/hv-work` and rerun `/hv-review`, or accept and ship via `/hv-ship`."*
- **`FAIL`** — tell the user the merge would regress. Suggest fixing via `/hv-work` or `/hv-debug`. Don't route to `/hv-ship`.

When `/hv-review` is invoked from `/hv-ship`, the parent owns the routing — return the verdict and stop; do not run this relay.

## Per-skill carrier — what stays inline

- **`hv-review/SKILL.md` Step 5 (reviewer brief)** — the exact rubric text the reviewer evaluates against (intent match, convention compliance, etc.) is the producer's prompt-engineering content, not the verdict-routing pattern. Stays inline.
- **`hv-ship/SKILL.md` Step 3 (ship.review gate)** — the `ship.review` config check, the *"If `ship.review` is `false`, skip"* guard, and the cycle position (between commit-bundling and PR-body composition) are skill-local carriers. Stays inline.
- **The verdict rubric** — what makes a diff PASS, CONCERNS or FAIL is the reviewer's judgment and stays in each brief. Only the verdict-to-next-step mapping moved into code.
- **The `AskUserQuestion` call site itself** — the call lives at the consumer's step; only the option text and routing logic extract to this reference.

## Carrier-label override

When a non-canonical caller of this routing (e.g. `/hv-ship` Step 3.5 second-opinion gate, or any future producer that emits the same PASS/CONCERNS/FAIL verdict shape) surfaces concerns, the caller MAY label them with a carrier prefix so the user can distinguish them from the primary `/hv-review` concerns in a session that runs both.

Convention: prefix surfaced concern lines with the producer's name and a dash, e.g. *"Second-opinion concerns:"* before listing the bullets. The routing (`hv verdict route`) is unchanged — only the prose label differs. Codified for `/hv-ship` Step 3.5 second-opinion gate (F04); future producers follow the same shape.

## See also

- `references/ask-user-question-fallback.md` — canonical plain-text fallback mechanic.
- `references/authoring-conventions.md` rule #5 — *"routine routing/tagging auto-picks Recommended in loop mode"*.
- A future `references/manual-gates.md` may eventually capture the *"Ship anyway is a user-volition gate"* pattern alongside other manual gates (T37 captures the extraction). When that lands, this reference cites it instead of restating the rationale.
