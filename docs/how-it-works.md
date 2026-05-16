# How hv-skills works

hv-skills is a set of slash commands that form a loop: capture, plan, execute with atomic commits, ship behind a review gate, persist the lessons. The diagram below shows how every skill connects to the artifacts it reads or writes, and which skills nudge or consult each other.

```mermaid
flowchart LR
  VISION["/hv-vision"] --> MILES[(MILESTONES.md)]
  VISION -.optional.-> SPIKE["/hv-spike"]
  VISION -.routes.-> PLAN["/hv-plan"]
  CAP["/hv-capture"] --> BACKLOG[(BACKLOG.md)]
  CAP -.tag.-> MILES
  CAP -.nudges.-> BRAIN["/hv-brainstorm"]
  ISSUES["/hv-issues"] -.sync.-> BACKLOG
  GO["/hv-go"] --> BACKLOG
  GO -.one-pass.-> WORK
  BACKLOG --> NEXT["/hv-next"]
  MILES -.scopes.-> NEXT
  NEXT -.suggests.-> ASSUME["/hv-assume"]
  NEXT -.suggests.-> PLAN
  NEXT -.nudges.-> BRAIN
  NEXT --> WORK["/hv-work"]
  BRAIN --> DESIGNS[(.hv/designs/)]
  DESIGNS -.soft input.-> PLAN
  PLAN --> PLANS[(.hv/plans/)]
  PLANS -.consults.-> WORK
  ASSUME -.reads.-> PLANS
  ASSUME -.peeks.-> WORK
  SPIKE --> SPIKES[(.hv/spikes/)]
  WORK -.pause.-> PAUSE["/hv-pause"]
  DEBUG -.pause.-> PAUSE
  PAUSE --> HANDOFF[(.hv/handoff/)]
  WORK --> COMMIT[(atomic commits)]
  DEBUG["/hv-debug"] --> COMMIT
  REFACTOR["/hv-refactor"] --> COMMIT
  COMMIT -.review.-> REVIEW["/hv-review"]
  REVIEW -.gate.-> SHIP["/hv-ship"]
  SHIP -.ship.qa.-> QA["/hv-qa"]
  QA -.strategy.-> QASTRAT[(.hv/qa/)]
  SHIP --> PR[(PR / merge)]
  SHIP -.rollback.-> UNDO["/hv-undo"]
  UNDO -.restores.-> BACKLOG
  WORK --> LEARN["/hv-learn"]
  DEBUG -.nudge/auto.-> LEARN
  SHIP -.loop.-> NEXT
  LEARN --> KNOW[(KNOWLEDGE.md)]
  KNOW -.consults.-> WORK
  KNOW -.consults.-> DEBUG
  KNOW -.consults.-> REVIEW
  DECIDE["/hv-decide"] --> DECISIONS[(.hv/DECISIONS.md)]
  DECISIONS -.consults.-> WORK
  DECISIONS -.consults.-> DEBUG
  DECISIONS -.consults.-> REVIEW
  CONTEXT["/hv-context"] --> CTX[(CONTEXT.md)]
  CTX -.consults.-> VISION
  CTX -.consults.-> CAP
  CTX -.consults.-> WORK
  CTX -.consults.-> DEBUG
  WORK -.post-cycle.-> MAP["/hv-map"]
  DEBUG -.post-cycle.-> MAP
  GO -.post-cycle.-> MAP
  MAP --> MAPS[(.hv/map/)]
  WORK -.post-cycle.-> DOCS["/hv-docs"]
  SHIP -.post-cycle.-> DOCS
  DOCS --> USERDOCS[(docs/)]
  SHIP -.cut.-> RELEASE["/hv-release"]
  RELEASE --> RELEASES[(GitHub releases)]
  UPDATE["/hv-update"] -.checks.-> RELEASES
```

Everything Claude reads or mutates lives under `.hv/` in your project. Git is the source of truth; `status.json` is just a cache, and `/hv-next` reconciles drift between the two whenever it runs.

## The five lanes

**Capture.** `/hv-capture` is the brain-dump entry point. It splits, classifies, and routes items to `BACKLOG.md` with auto-incrementing IDs (`B01`, `F01`, `T01`). `/hv-go` collapses capture and execute into a single pass for hot-path fixes. `/hv-issues` syncs open GitHub or GitLab issues into the backlog with `GH: #N` / `GL: #N` cross-references, and round-trips closing via `/hv-ship`. `/hv-rm` removes a captured item and cleans up its dependencies.

**Plan.** `/hv-vision` brainstorms milestones with Socratic discovery, web research, and a deliberate critique pass. `/hv-brainstorm` explores design for size-Major features or P0 bugs before planning. `/hv-plan` writes the implementation plan to its own file, keyed by milestone slice or item. `/hv-spike` runs throwaway feasibility experiments on a branch that never merges; only findings come back. `/hv-assume` previews the orchestrator's intended approach without writing anything, a cheap gate before code lands on high-stakes items.

**Execute.** `/hv-work` is the orchestrator. It reads the plan (or decomposes ad-hoc if none exists), dispatches worker subagents in parallel, commits one verifiable task at a time. `/hv-debug` runs a systematic reproduce → hypothesize → verify → fix cycle for bugs. `/hv-refactor` does the same shape for architectural friction. `/hv-pause` writes a handoff note when the context window is filling, so a fresh `/hv-next` session picks up cleanly.

**Ship.** `/hv-review` runs a two-stage pass over the branch — Stage 1 checks the diff against `PLAN.md` (spec compliance), Stage 2 checks code-quality plus a silent-failure-hunter rubric and `DECISIONS.md` violations — and returns `PASS` / `CONCERNS` / `FAIL`. `/hv-qa` answers the orthogonal question, *"does the product actually work?"*, by running per-target strategies (`.hv/qa/<target>.md`) with Playwright / smoke / lighthouse / axe / ZAP / contract runners. `/hv-ship` builds an ID-linked PR body or direct-merges based on configured strategy, with two opt-in gates layered after `/hv-review`: a fresh-eyes second-opinion review (`ship.secondOpinion`) and a product QA run (`ship.qa`). `/hv-undo` rolls back the last direct-merge cycle in one operation, restoring TODO entries.

**Persist.** `/hv-learn` writes durable session learnings to `KNOWLEDGE.md`, verified before they land. `/hv-decide` captures hard-boundary commitments to `DECISIONS.md` with explicit forbids and permits. `/hv-context` captures domain terms to `CONTEXT.md` (the project's canonical glossary). `/hv-map` keeps a thin subsystem map current, auto-bumped post-cycle. `/hv-docs` keeps the public docs in sync with the code.

**Maintenance.** `/hv-init` sets up `.hv/` once at the project root. `/hv-config` edits config interactively (never hand-edit JSON). `/hv-update` checks for newer hv-skills releases and prints the exact upgrade command. `/hv-release` cuts your project's own releases: version bump, categorized notes, tag, push, GitHub/GitLab release.

For the alphabetical reference of every skill see [the slash commands page](reference/slash-commands.md). For two worked examples that carry one concrete project end-to-end, see the [walkthroughs](walkthroughs/).
