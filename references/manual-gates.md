# Manual gates

Certain operations are explicitly **manual gates — never auto-invoked**, regardless of `autonomy.level`. These produce externally-visible state or commit the project to a hard boundary. Loop mode auto-picks routing answers (drain the queue toward done) but never acceptance-of-risk answers (commit on the user's authority).

The rule lives inline at each call site per the authoring convention *"Imperative rules in autonomy-aware steps must live inline at every dispatch point"* (see `references/authoring-conventions.md` — autonomy-rule-must-stay-inline). This reference documents the canonical mechanic + the inventory of currently-known gates so future sites can match the convention.

## The mechanic

A manual gate has these properties:

- **Always manual.** The user presses the button regardless of `autonomy.level` (`"off"`, `"auto"`, or `"loop"` — all three honor the gate).
- **At the action site.** The callout text lives inline immediately before the action — it cannot be replaced by a reference cite alone. Readers approaching the action see the rule without dereferencing.
- **Pre-approved-elsewhere is allowed.** A separate prior step may collect user approval (e.g. `/hv-release` Step 7 reviews notes before Step 9 pushes the tag). The gate at the action site then runs *because of* that prior approval, not in spite of it. The gate is a structural assurance, not a redundant prompt.

The canonical callout shape (block-quote) is:

```
> **Manual gate — <one-line artifact name>.** <One sentence on what externally-visible state this creates.> This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. <Optional: how prior approval feeds this step.>
```

Sites with multi-paragraph prose (e.g. `/hv-learn` Steps 8.5 and 9) may use the *inline* form — a `**always manual** — never auto-invoked, regardless of \`autonomy.level\`` sentence embedded in the step's body. Both shapes are accepted; the block-quote is preferred for single-action steps.

## Inventory of current gates

| Skill | Step | Gates | Externally-visible state |
|-------|------|-------|--------------------------|
| `/hv-decide` | Step 5 (Confirmation) | Writing the decision to `.hv/DECISIONS.md` | Commits a hard boundary; future implementation choices are constrained until the entry is amended. |
| `/hv-learn` | Step 8.5 | Filing a hv-skills GitHub issue | Creates a public issue in `anthropics/claude-code` or the hv-skills repo. |
| `/hv-learn` | Step 9 | Authoring a runlog entry | Publishes signed/verified content to the cross-org runlog registry. |
| `/hv-ship` | Step 6a | Opening a GitHub PR | Pushes the branch and creates a public PR via `gh pr create`. |
| `/hv-release` | Step 8 (Push tag) | Pushing the annotated git tag | Tag becomes visible on the remote. |
| `/hv-release` | Step 9 (Publish release) | Creating the GitHub/GitLab release | Creates a release page tied to the tag. |
| `/hv-issues` | Step 7 (Apply label upstream) | Applying the `in-progress` label to upstream issues | Public label change on the remote; collaborators see issues marked as claimed. |
| `/hv-ship` | Step 6c (Direct-push close) | Closing upstream issues after direct merge | Posts a tracking comment and changes issue state on the remote. |
| `/hv-capture --remove` | Step R3 (De-tag upstream) | Removing the `in-progress` label upstream | Public label change on the remote when a captured item is removed. |

`/hv-ship` Step 3's *"Ship anyway"* option (in the CONCERNS-routing AskUserQuestion) is conceptually a manual gate too — see `references/review-verdict-routing.md` for why loop mode auto-picks *"Address via /hv-work"* but never *"Ship anyway"*. The pattern is the same: acceptance of risk is the user's choice; routing toward safe is not.

## Why not auto-invoke?

Loop mode's contract is *"drain the queue toward done"* — it auto-picks routing answers because those move the work forward without committing to anything irreversible. A manual gate IS the irreversible commit: a public PR, a release tag, a `DECISIONS.md` entry that constrains future code. Auto-picking these would replace the user with the loop on questions that genuinely require human judgment about reputation, external coordination, or long-term project shape.

The skip-route is configuration, not loop-mode-cleverness. If a project wants concerns ignored on every ship, set `ship.review` to `false` — don't try to teach the loop to ship-anyway.

## How sites cite this reference

Each call site keeps its inline callout (block-quote or inline-prose form) and optionally adds a brief trailing cite:

```
> **Manual gate — filing a public artifact.** Opening a PR creates externally-visible state. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The orchestrator may compose the title and body and run the `AskUserQuestion` prompt in Step 5 (Pick Strategy), but the user presses the button there before this step runs. See `references/manual-gates.md`.
```

The cite at the end gives a curious reader the inventory + mechanic; the callout itself does the load-bearing work at the action site.

## See also

- `references/authoring-conventions.md` rule *"Imperative rules in autonomy-aware steps must live inline at every dispatch point"* — why the callout body cannot be replaced by a reference cite.
- `references/authoring-conventions.md` rule #5 — *"routine routing/tagging auto-picks Recommended in loop mode"*; the complementary rule for routing-shaped (not acceptance-of-risk) questions.
- `references/review-verdict-routing.md` — *"Ship anyway"* is a manual-shaped option inside the CONCERNS-routing question; loop never auto-picks it.
