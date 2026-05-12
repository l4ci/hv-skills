# References

Project-root `references/` holds extracted choreography that two or more skills share — UX shapes, decision tables, multi-step protocols. Skills cite these inline; this index gives a top-down view of what each reference contains and which skills consume it.

See KNOWLEDGE.md "Skill Authoring: Prose & References" for the conventions that govern when to extract (≥30 lines of self-contained choreography), how to size the reference (per cohesive scope, not per consumer), and when to keep prose inline.

## Index

| Reference | Purpose | Cited by |
|-----------|---------|----------|
| [`ask-user-question-fallback.md`](ask-user-question-fallback.md) | Plain-text fallback shape for AskUserQuestion-less hosts. | `/hv-docs`, `/hv-ship`, `/hv-vision`, `/hv-work` |
| [`authoring-conventions.md`](authoring-conventions.md) | Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold). | `/hv-capture`, `/hv-init`, `/hv-next`, `/hv-refactor`, `/hv-ship` |
| [`banner-preamble.md`](banner-preamble.md) | Banner-print rule shared by every skill. | `/hv-assume`, `/hv-c`, `/hv-capture`, `/hv-config`, `/hv-context`, `/hv-debug`, `/hv-decide`, `/hv-docs`, `/hv-go`, `/hv-init`, `/hv-learn`, `/hv-next`, `/hv-pause`, `/hv-plan`, `/hv-refactor`, `/hv-release`, `/hv-review`, `/hv-rm`, `/hv-ship`, `/hv-spike`, `/hv-update`, `/hv-vision`, `/hv-work` |
| [`context-load-protocol.md`](context-load-protocol.md) | K+D context loading sequence shared by every cycle-starting skill. | `/hv-assume`, `/hv-plan`, `/hv-vision` |
| [`context-umbrella-scoping.md`](context-umbrella-scoping.md) | Umbrella-mode resolution for the `/hv-context` artifact. | `/hv-context` |
| [`detail-files.md`](detail-files.md) | Detail-file template used when an item's input exceeds 3 sentences. | `/hv-capture` |
| [`docs-conventions.md`](docs-conventions.md) | Conventions for content under `docs/` (registration sites, audience split). | `/hv-docs` |
| [`handoff-template.md`](handoff-template.md) | Handoff-note template written by `/hv-pause` and read by `/hv-next`. | `/hv-pause` |
| [`isolation-patterns.md`](isolation-patterns.md) | Branch / worktree creation patterns per work.isolation + umbrella mode. | `/hv-work` |
| [`knowledge-consult.md`](knowledge-consult.md) | Canonical K+D query pattern (`hv-knowledge-query` + `hv-decisions-query`) used by every cycle-starting skill. | `/hv-debug`, `/hv-review`, `/hv-work` |
| [`manual-gates.md`](manual-gates.md) | Steps that must always be manual regardless of autonomy.level (PR opening, upstream issues, runlog dispatch). | `/hv-learn`, `/hv-release`, `/hv-ship` |
| [`merge-strategy-gate.md`](merge-strategy-gate.md) | Merge-strategy decision UX (Direct vs PR) plus helper invocations. | `/hv-ship`, `/hv-work` |
| [`milestone-tagging.md`](milestone-tagging.md) | Milestone-tagging UX pattern used by capture/go skills. | `/hv-capture` |
| [`persistence-skills.md`](persistence-skills.md) | Shared spine and divergence axes for the persistence trio (`/hv-context`, `/hv-learn`, `/hv-decide`). | `/hv-context`, `/hv-decide`, `/hv-learn` |
| [`post-cycle-trigger-gate.md`](post-cycle-trigger-gate.md) | Trigger condition for post-cycle nudges (2+ items / ≥5 files / hard bug). | `/hv-docs`, `/hv-ship`, `/hv-work` |
| [`refactor-umbrella-fanout.md`](refactor-umbrella-fanout.md) | Per-repo fan-out logic for `/hv-refactor` in umbrella mode. | `/hv-refactor` |
| [`release-hosts.md`](release-hosts.md) | Release-host detection and routing (GitHub / GitLab / origin-less). | `/hv-release` |
| [`review-verdict-routing.md`](review-verdict-routing.md) | PASS / CONCERNS / FAIL routing for `/hv-review` consumers. | `/hv-review`, `/hv-ship` |
| [`source-prefill.md`](source-prefill.md) | Source-prefill / promote-between-artifacts semantics for `/hv-decide`. | `/hv-decide` |
| [`three-mode-skill-shape.md`](three-mode-skill-shape.md) | Three-mode skill shape (first-run / after-work / restructure) used by `/hv-docs` and `/hv-map`. | `/hv-docs`, `/hv-map` |
| [`umbrella-mode.md`](umbrella-mode.md) | Umbrella-mode helpers, registry shape, and `Repos:` field semantics. | `/hv-capture`, `/hv-spike`, `/hv-work` |
| [`update-verdicts.md`](update-verdicts.md) | Update-check verdicts and routing for `/hv-update`. | `/hv-update` |

## Conventions

- **Path style.** Citations from SKILL.md use the form `references/<file>.md` (relative to the project root). The plugin installs the full tree so links resolve wherever a skill is loaded.
- **Inline vs. extracted.** Inline prose wins when it's local to its step and under 30 lines. Extract to `references/<topic>.md` when the same choreography appears in 2+ skills OR when extraction shrinks a SKILL.md by ≥30 lines of self-contained content (per the "Single-consumer references" KNOWLEDGE entry).
- **One-line purpose.** Each row's `Purpose` column is one sentence; longer context lives inside the reference file. If the one-liner needs a clause about scope or a noteworthy exception, keep it under 25 words.
- **Cited by.** The `Cited by` column is the canonical consumer set — derived by `grep -l "references/<name>" hv-*/SKILL.md`. A reference with no consumers should not exist; if you find one while running step 2 above, flag it in your completion report.

## Maintenance

When adding a new reference file, append a row to the Index table in alphabetical order, fill in `Purpose` and `Cited by`, and add at least one inline citation in a SKILL.md (otherwise the reference shouldn't exist yet — write it from a consumer's perspective).

When the consumer set for a reference changes, re-run the grep above and update the `Cited by` column.
