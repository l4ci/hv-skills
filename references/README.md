# References

Project-root `references/` holds extracted choreography that two or more skills share — UX shapes, decision tables, multi-step protocols. Skills cite these inline; this index gives a top-down view of what each reference contains and which skills consume it.

See KNOWLEDGE.md "Skill Authoring: Prose & References" for the conventions that govern when to extract (≥30 lines of self-contained choreography), how to size the reference (per cohesive scope, not per consumer), and when to keep prose inline.

## Index

| Reference | Purpose | Cited by |
|-----------|---------|----------|
| [`ask-user-question-fallback.md`](ask-user-question-fallback.md) | Plain-text fallback shape for AskUserQuestion-less hosts. | `/hv-brainstorm`, `/hv-capture` (`--from-*`), `/hv-init`, `/hv-release`, `/hv-ship`, `/hv-vision`, `/hv-work` |
| [`authoring-conventions.md`](authoring-conventions.md) | Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold). | `/hv-capture`, `/hv-init`, `/hv-next`, `/hv-refactor`, `/hv-ship` |
| [`banner-preamble.md`](banner-preamble.md) | Banner-print rule shared by every skill. | `/hv-brainstorm`, `/hv-capture`, `/hv-config`, `/hv-debug`, `/hv-decide`, `/hv-go`, `/hv-init`, `/hv-learn`, `/hv-next`, `/hv-pause`, `/hv-plan`, `/hv-qa`, `/hv-refactor`, `/hv-release`, `/hv-review`, `/hv-ship`, `/hv-spike`, `/hv-update`, `/hv-vision`, `/hv-work` |
| [`context-load-protocol.md`](context-load-protocol.md) | K+D context loading sequence shared by every cycle-starting skill. | `/hv-plan`, `/hv-vision`, `/hv-work` (including `--preview`) |
| [`debug-hypothesize.md`](debug-hypothesize.md) | Both-modes hypothesize choreography (brief template, single vs competing, per-axis divergence) for `/hv-debug` Step 6. | `/hv-debug` |
| [`debug-escalate.md`](debug-escalate.md) | Fresh-context handoff brief template + dispatch mechanics + user-surfacing fallback for `/hv-debug` Step 7.5. | `/hv-debug` |
| [`design-exploration.md`](design-exploration.md) | Shared five-step spine for skills that negotiate what to build before downstream skills capture how. | `/hv-brainstorm`, `/hv-vision` |
| [`detail-files.md`](detail-files.md) | Detail-file template used when an item's input exceeds 3 sentences. | `/hv-capture` |
| [`docs-conventions.md`](docs-conventions.md) | Conventions for content under `docs/` (registration sites, audience split). | `/hv-ship` (Docs Mode) |
| [`handoff-template.md`](handoff-template.md) | Handoff-note template written by `/hv-pause` and read by `/hv-next`. | `/hv-pause` |
| [`humanizing-prose.md`](humanizing-prose.md) | Rule sheet + silent self-audit pass applied to user-facing prose (release notes, PR body, doc-page edits) before the draft is shown to the user. | `/hv-release`, `/hv-ship` |
| [`isolation-guard.md`](isolation-guard.md) | Why the parallel-waves-require-worktree-isolation guard fires, with the M02-S01 incident rationale and **Forbids / Permits** block for `/hv-work` Step 5. | `/hv-work` |
| [`isolation-patterns.md`](isolation-patterns.md) | Branch / worktree creation patterns per work.isolation + umbrella mode. | `/hv-work` |
| [`knowledge-consult.md`](knowledge-consult.md) | Canonical K+D query pattern (`hv-knowledge-query` + `hv-decisions-query`) used by every cycle-starting skill. | `/hv-debug`, `/hv-next`, `/hv-review`, `/hv-work` |
| [`loop-mode-plan-dispatch.md`](loop-mode-plan-dispatch.md) | Loop-mode auto-plan dispatch (uncertainty pre-flight, orchestrator-model contract) plus rename + link-sweep collision detection for `/hv-work` Step 4. | `/hv-work` |
| [`manual-gates.md`](manual-gates.md) | Steps that must always be manual regardless of autonomy.level (PR opening, upstream issues, runlog dispatch). | `/hv-capture` (`--remove`, `--from-*`), `/hv-learn`, `/hv-release`, `/hv-ship` |
| [`merge-strategy-gate.md`](merge-strategy-gate.md) | Merge-strategy decision UX (Direct vs PR) plus helper invocations. | `/hv-ship`, `/hv-work` |
| [`milestone-tagging.md`](milestone-tagging.md) | Milestone-tagging UX pattern used by capture/go skills. | `/hv-capture` |
| [`persistence-skills.md`](persistence-skills.md) | Shared spine and divergence axes for the persistence duo (`/hv-learn`, `/hv-decide`) — `/hv-learn` carries both topic-bullet learnings and `--term` Glossary entries. | `/hv-decide`, `/hv-learn` |
| [`post-cycle-trigger-gate.md`](post-cycle-trigger-gate.md) | Trigger condition + nudge-or-dispatch choreography for post-cycle skills. | `/hv-qa`, `/hv-ship`, `/hv-work` |
| [`refactor-explore.md`](refactor-explore.md) | Exploration-agent prompt + categories + stop condition for `/hv-refactor` single-repo mode. | `/hv-refactor` |
| [`refactor-design-approaches.md`](refactor-design-approaches.md) | Competing-design choreography (decisions consult, agent constraints, output shape) for `/hv-refactor` Step 5. | `/hv-refactor` |
| [`refactor-umbrella-fanout.md`](refactor-umbrella-fanout.md) | Per-repo fan-out logic for `/hv-refactor` in umbrella mode. | `/hv-refactor` |
| [`release-hosts.md`](release-hosts.md) | Release-host detection and routing (GitHub / GitLab / origin-less). | `/hv-release` |
| [`review-verdict-routing.md`](review-verdict-routing.md) | PASS / CONCERNS / FAIL routing for `/hv-review` consumers. | `/hv-qa`, `/hv-review`, `/hv-ship` |
| [`silent-failure-hunter.md`](silent-failure-hunter.md) | Rubric for detecting work that reports complete but didn't move the system, used in review passes. | `/hv-review`, `/hv-ship` |
| [`source-prefill.md`](source-prefill.md) | Source-prefill / promote-between-artifacts semantics for `/hv-decide`. | `/hv-decide` |
| [`subagent-dispatch.md`](subagent-dispatch.md) | Cross-skill rulebook for when and how skills push work into subagents instead of the orchestrator thread. | `/hv-debug`, `/hv-next`, `/hv-qa`, `/hv-vision` |
| [`task-list-init.md`](task-list-init.md) | Canonical task-list initialization block cited by every skill with three or more phases. | `/hv-brainstorm`, `/hv-capture`, `/hv-config`, `/hv-debug`, `/hv-decide`, `/hv-init`, `/hv-learn`, `/hv-next`, `/hv-pause`, `/hv-plan`, `/hv-qa`, `/hv-refactor`, `/hv-release`, `/hv-review`, `/hv-ship`, `/hv-spike`, `/hv-vision`, `/hv-work` |
| [`terminal-loop-surface.md`](terminal-loop-surface.md) | Canonical bash block for surfacing `[Auto:Loop]` decisions from terminal-path skills before halting. | `/hv-debug`, `/hv-next`, `/hv-pause`, `/hv-work` |
| [`tmux-dispatch.md`](tmux-dispatch.md) | Worker contract, pane classification, escalation relay, and merge gate for `work.dispatch: "tmux"`. | `/hv-work` |
| [`three-mode-skill-shape.md`](three-mode-skill-shape.md) | Three-mode skill shape (first-run / after-work / restructure) used by `/hv-ship` (Docs Mode) and `/hv-qa`. | `/hv-qa`, `/hv-ship` |
| [`umbrella-mode.md`](umbrella-mode.md) | Umbrella-mode helpers, registry shape, and `Repos:` field semantics. | `/hv-capture`, `/hv-qa`, `/hv-spike`, `/hv-work` |
| [`update-verdicts.md`](update-verdicts.md) | Update-check verdicts and routing for `/hv-update`. | `/hv-update` |

## Conventions

- **Path style.** Citations from SKILL.md use the form `references/<file>.md` (relative to the project root). The plugin installs the full tree so links resolve wherever a skill is loaded.
- **Inline vs. extracted.** Inline prose wins when it's local to its step and under 30 lines. Extract to `references/<topic>.md` when the same choreography appears in 2+ skills OR when extraction shrinks a SKILL.md by ≥30 lines of self-contained content (per the "Single-consumer references" KNOWLEDGE entry).
- **One-line purpose.** Each row's `Purpose` column is one sentence; longer context lives inside the reference file. If the one-liner needs a clause about scope or a noteworthy exception, keep it under 25 words.
- **Cited by.** The `Cited by` column is the canonical consumer set — derived by `grep -l "references/<name>" hv-*/SKILL.md`. A reference with no consumers should not exist; if you find one while running step 2 above, flag it in your completion report.

## Maintenance

When adding a new reference file, append a row to the Index table in alphabetical order, fill in `Purpose` and `Cited by`, and add at least one inline citation in a SKILL.md (otherwise the reference shouldn't exist yet — write it from a consumer's perspective).

When the consumer set for a reference changes, re-run the grep above and update the `Cited by` column.
