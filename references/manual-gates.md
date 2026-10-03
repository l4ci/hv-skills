# Manual gates

Certain operations are **manual gates**: no `autonomy.level` (`"off"`, `"auto"` or `"loop"`) may pass them on its own. They produce externally-visible state or commit the project to a hard boundary. Loop mode auto-picks routing answers (drain the queue toward done) but never acceptance-of-risk answers (commit on the user's authority).

The registry lives in code. `hv gate list` prints every gate, whether a verb enforces it, the verbs and skills involved, and the state it creates. There are two kinds.

## Enforced gates: the verb refuses

| Gate | Verb | Skill site |
|------|------|------------|
| `tag-push` | `hv release push` | `/hv-release` Step 12 |
| `release-publish` | `hv release publish` | `/hv-release` Step 13 |
| `public-filing` | `hv tracker suggest-upstream` | `/hv-learn` Step 8.5 |
| `merge-approval` | `hv ship merge`, `hv ship pr-merge`, `hv worker gate`, when `ship.mergeApproval` covers the merge (`all`, or `paths` matching `ship.mergeApprovalPaths`) | `/hv-ship` Step 6b, `/hv-review --queue`, `/hv-work` gate step |
| `debug-reset` | `hv debug reset <ID> --reason <why>` (starts an item's failed-fix count again after the Iron Law halted it) | `/hv-debug` Step 9.5 |

The verb exits 4 with `data.blockedBy: "manual gate"` and `data.gate` unless it gets `--confirm --confirm-note "<answer>"`, at every autonomy level. `merge-approval` adds `data.paths`, the changed files that matched (`worker gate` reports `data.verdict: "approval-required"`). A cleared gate appends one line to `.hv/gate-audit.jsonl` (gitignored): gate, verb, target, time, the quoted answer and the autonomy level.

The skill's side:

- **Ask first, in an `AskUserQuestion` loop mode never auto-picks.** An earlier question counts when it names the action: `/hv-release` Step 7 asks about the notes *and* says yes pushes and publishes, so Steps 12 and 13 reuse its answer.
- **Pass the answer verbatim** in `--confirm-note`. Never invent one, and never pass `--confirm` without a human answer behind it.
- **On exit 4 with `blockedBy: "manual gate"`, ask and re-run.** Nothing changed on the refusal, so the re-run is safe.

Call sites show the flags and the exit-4 handling; they don't restate the rule, which the verb now enforces.

## Skill-only gates: the callout holds the line

Closing and labelling upstream issues stay out of code (maintainer ruling, B1), and some gates have no verb to put the check in. These keep the inline callout immediately before the action, per the authoring convention *"Imperative rules in autonomy-aware steps must live inline at every dispatch point"* (see `references/authoring-conventions.md`, autonomy-rule-must-stay-inline). A reference cite cannot replace it.

The canonical callout shape (block-quote) is:

```
> **Manual gate — <one-line artifact name>.** <One sentence on what externally-visible state this creates.> This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. <Optional: how prior approval feeds this step.>
```

Sites with multi-paragraph prose may use the *inline* form, a `**always manual** — never auto-invoked, regardless of \`autonomy.level\`` sentence embedded in the step's body. Both shapes are accepted; the block-quote is preferred for single-action steps. A prior step may collect the approval (pre-approved elsewhere); the gate at the action site then runs *because of* that approval.

| Gate | Skill | Step | Externally-visible state |
|------|-------|------|--------------------------|
| `decision-write` | `/hv-decide` | Step 5 (Confirmation) | Commits a hard boundary to `.hv/DECISIONS.md`; future implementation choices are constrained until the entry is amended. |
| `runlog-entry` | `/hv-learn` | Step 8.6 | Publishes signed content to the public runlog registry. |
| `pr-open` | `/hv-ship` | Step 6a | Pushes the branch and creates a public PR or MR. |
| `issue-label` | `/hv-capture --from-github` / `--from-gitlab` | Step I6 (Apply label upstream) | Applies the `in-progress` label to upstream issues; collaborators see them claimed. |
| `issue-label` | `/hv-capture --remove` | Step R3 (De-tag upstream) | Removes the `in-progress` label upstream when a captured item is removed. |
| `issue-close` | `/hv-ship` | Step 6c (Direct-push close) | Posts a tracking comment and closes upstream issues after a direct merge. |
| `issue-close` | `/hv-release` | Step 13.4 | Closes upstream issues still open for shipped items. |

`/hv-ship` Step 3's *"Ship anyway"* option (in the CONCERNS-routing AskUserQuestion) is manual-shaped too; see `references/review-verdict-routing.md` for why loop mode auto-picks *"Address via /hv-work"* but never *"Ship anyway"*. Acceptance of risk is the user's choice; routing toward safe is not.

## Why not auto-invoke?

Loop mode's contract is *"drain the queue toward done"*: it auto-picks routing answers because those move the work forward without committing to anything irreversible. A manual gate IS the irreversible commit: a public PR, a release tag, a `DECISIONS.md` entry that constrains future code. Auto-picking these would replace the user with the loop on questions that need human judgment about reputation, external coordination, or long-term project shape.

The skip-route is configuration, not loop-mode cleverness. If a project wants concerns ignored on every ship, set `ship.review` to `false`; if it wants no human on merges, leave `ship.mergeApproval` at `none`.

## See also

- `references/authoring-conventions.md` rule *"Imperative rules in autonomy-aware steps must live inline at every dispatch point"*: why a skill-only callout cannot be replaced by a reference cite.
- `references/authoring-conventions.md` rule #5, *"routine routing/tagging auto-picks Recommended in loop mode"*: the complementary rule for routing-shaped questions.
- `references/review-verdict-routing.md`: *"Ship anyway"* is a manual-shaped option inside the CONCERNS-routing question; loop never auto-picks it.
