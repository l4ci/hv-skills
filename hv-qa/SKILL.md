---
name: hv-qa
description: QA the built product — not the diff. Detects testing surfaces per repo (web, API, CLI, mobile, lib), picks runners (Playwright, smoke, contract, lighthouse, ZAP, axe), and produces a scored report with executable pass/fail results plus audit-style usability findings. Strategy is per-repo in .hv/qa/<repo>.md so the skill never hardcodes "browser". Modes — first-run (probe + propose strategy), run (execute strategy, emit verdict), restructure (audit strategy files). Opt-in gate via ship.qa.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🧪  hv-qa  ·  QA the built product (not the diff)
  triggers: "qa this", "kick the tires"  ·  pairs: hv-review, hv-ship
════════════════════════════════════════════════════════════════════════
```

# hv-qa — Product Quality Assurance

`/hv-qa` and `/hv-review` are deliberately separate:

- **`/hv-review`** answers *"does this diff make sense"* — reads commits + diff, no execution.
- **`/hv-qa`** answers *"does the product work"* — runs tests, probes, scans against the built artifact.

They never call each other. `/hv-ship` may call both, each behind its own config flag.

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — model dispatching the runners (default `opus`).
- `qa.gate` — `"advisory"` (default) emits verdict, never blocks ship; `"blocking"` causes `ship.qa: true` invocations to halt on `FAIL`.
- `qa.afterWork` — `false` (default). When `true`, `/hv-work` invokes `/hv-qa run` post-cycle if touched files match a QA target's `Watch globs`.
- `ship.qa` — `false` (default). When `true`, `/hv-ship` calls `/hv-qa run` between `/hv-review` and the merge/PR step.

## When to Use

- *"QA this"*, *"kick the tires"*, *"does this actually work?"* — manual exploratory run.
- After a feature lands and before opening a PR, when you want product-level evidence (not just diff sanity).
- First-time setup on a new repo or new umbrella sub-repo — bootstrap the strategy file.

## When NOT to Use

- You want diff-level review → `/hv-review`. QA does not read commits.
- Nothing built yet → finish via `/hv-work` first. QA needs an artifact to probe.
- You want to change code based on findings → consume the report, then `/hv-work` or `/hv-debug`.

## Modes

`/hv-qa` shares the three-mode skeleton with `/hv-map` and `/hv-docs` (scaffold / after-work / audit) — see `references/three-mode-skill-shape.md`. Divergences:

| Aspect | `/hv-qa` |
|---|---|
| Artifact root | `.hv/qa/<target>.md` — per-target strategy files. In umbrella mode, `<target>` is a registered repo name; in single-repo mode, `<target>` is a user-named surface (`web`, `api`, `cli`, ...) |
| Audience | AI runners + contributors triaging findings |
| Mode-3 name | `restructure` (re-probe surfaces, retire dead strategies, fix broken commands) |
| After-work approval gate | opt-in via `qa.afterWork: true`; default off — QA runs are slow and may need infra |
| After-work trigger gate | `qa.afterWork: true` AND touched files match a target's `Watch globs` |
| Authoring tier | Tier S for `run` (banner, `TaskCreate`, integer Step headers); Tier C for `first-run` / `restructure` (mode-numbered lists) |
| Commit ownership | `run` does not commit (read-only verdict); `first-run` / `restructure` own a `chore(qa):` commit |

### Mode: first-run

Run when `.hv/qa/` is empty for the active scope (umbrella: per-repo; single-repo: when no `.hv/qa/*.md` files exist).

1. **Detect surfaces.** Inspect what kind of product this is — never assume browser:
   - `package.json` with `next` / `vite` / `react` / `vue` / `svelte` → web-UI surface
   - `App.swift` / `*.xcodeproj` / `Package.swift` with `@main` → macOS/iOS app surface
   - `openapi.yaml` / `swagger.json` / Express/FastAPI/Hono routes → HTTP-API surface
   - `bin/*` shell entry / `main.py` CLI / `cobra` / `clap` Rust → CLI surface
   - `lib/` or `src/` with no entry point + tests dir → library surface (unit + contract only)
   - Mixed → multiple targets, one strategy file each
2. **Detect existing test infra.** `find` for: `playwright.config.*`, `cypress.config.*`, `pytest.ini`, `jest.config.*`, `vitest.config.*`, `*XCTest*`, `*.smoke.sh`, `tests/`, `test/`, `__tests__/`, CI workflow files. Note what's already wired; missing tooling stays a note, not a proposal.
3. **Probe quality tooling.** Check for: Lighthouse / Pagespeed, axe-core / pa11y, ZAP / semgrep configs, dependency audit (`npm audit`, `pip-audit`, `cargo-audit`), perf budgets, contract tests. Presence only — never propose installing anything in this mode.
4. **Propose strategy.** For each target, draft a one-screen strategy with these sections — show the user before writing:
   - **Surface** — what kind of thing this is (web, API, CLI, mobile, lib)
   - **Watch globs** — paths whose changes should trigger after-work QA
   - **Executable checks** — runners with concrete commands, grouped by pillar (performance / security / functional). Each entry: `name` · `command` · `pass criterion`. Examples: `lighthouse --budget-path=.budget.json` · `pa11y http://localhost:3000` · `npm audit --audit-level=high` · `bash test/smoke.sh` · `playwright test --grep @smoke`.
   - **Audit checks** — usability dimensions to inspect by hand or LLM (empty states, error recovery, copy clarity, first-run flow). Rubric, no commands.
   - **Infra requirements** — what must be running for `run` mode (e.g. `npm run dev` on `:3000`, deployed staging URL, sandbox creds). Skill refuses to run if these aren't met.
   - **Out of scope** — explicit non-goals (e.g. "no load testing", "no real-payment flows").
5. **Approve & write.** Use `AskUserQuestion` with `Approve as drafted (Recommended)` / `Edit before writing` / `Cancel`. On approval, write `.hv/qa/<target>.md` with frontmatter (`target`, `surface`, `summary`, `created`, `touched`, `watch-globs`) and the five body sections.
6. **Index.** Run `.hv/bin/hv-qa-index` to regenerate the `## Project QA` block in `CLAUDE.md`.
7. **Commit.** `chore(qa): scaffold QA strategy for <target> (.hv/qa/, ## Project QA block)`.

### Mode: run

Tier S — banner already printed above.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Resolve scope* — which targets to QA (Step 2)
2. *Load strategies* — read `.hv/qa/<target>.md` for each (Step 3)
3. *Infra preflight* — verify `Infra requirements` are met (Step 4)
4. *Execute checks* — dispatch runner subagents (Step 5)
5. *Audit pass* — usability findings (Step 6)
6. *Score & verdict* — aggregate (Step 7)
7. *Report* — relay to user (Step 8)

#### Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

#### Step 2 — Resolve Scope

If user named a target (`/hv-qa run web`), use it. Otherwise:

- **Umbrella mode** (`.hv/repos.json` non-empty): default to the repo of the current branch (resolve via `.hv/bin/hv-resolve-repo`). User can pass `--repo <name>` or `--all`.
- **Single-repo mode**: default to all `.hv/qa/*.md` entries.

If no strategy file exists for the resolved scope, halt and tell the user to run `/hv-qa first-run`.

#### Step 3 — Load Strategies

For each target, read `.hv/qa/<target>.md` via `.hv/bin/hv-qa-query <target>`. Parse the five body sections. Reject any strategy missing `Executable checks` or `Infra requirements` — surface as a config error and route to `restructure`.

#### Step 4 — Infra Preflight

For each target, verify everything under `Infra requirements`:

- HTTP probes for dev/staging URLs (curl with 5s timeout)
- Process checks for required binaries (`command -v playwright`, etc.)
- Env-var presence for credentials (don't print values)

If any infra is missing, emit `INFRA-FAIL` with the missing items and halt — partial QA produces false confidence. Tell the user exactly what to start / install.

#### Step 5 — Execute Checks

Dispatch one subagent per check group (per pillar per target) in parallel via the Agent tool — see `references/subagent-dispatch.md`. Each subagent:

- Runs the commands from its assigned `Executable checks` entries.
- Captures stdout, exit code, and artifact paths (screenshots, HAR files, reports). Artifacts write under `.hv/qa-runs/<timestamp>/<target>/<check>/`.
- Returns a structured result: `{ name, command, exitCode, passCriterion, met, evidence }`.

The orchestrator does not run the checks itself — parallel dispatch is the point. Aggregate the results.

#### Step 6 — Audit Pass

Dispatch one subagent (Opus, no prior context) per target with the `Audit checks` rubric, screenshots from Step 5 if available, and read-only access to the running surface. Return: array of `{ dimension, severity (P0|P1|P2|P3), observation, evidence, suggested_fix }`.

Audit findings never produce automated pass/fail. They surface as a separate report section, severity-ranked.

#### Step 7 — Score & Verdict

Aggregate per target:

- **PASS** — all executable checks `met: true`, audit findings have no P0.
- **CONCERNS** — executable checks all met, but audit has P0/P1 findings, OR ≥1 executable check passed only with a warning. Ship is allowed; user owns the call.
- **FAIL** — any executable check `met: false`, OR audit has a P0 with `severity: blocker`.

In umbrella `--all` mode, the rollup verdict is the worst-of across targets. Per-target verdicts still report individually.

#### Step 8 — Report

Print a structured report:

```
QA verdict: <PASS|CONCERNS|FAIL>

Targets:
  <target-1>: <verdict>
    Executable checks: <n passed> / <n total>
    Audit findings: <n P0>, <n P1>, <n P2>, <n P3>
  ...

Failed executable checks:
  - <name> — <command> — <evidence>
  ...

Audit findings (P0/P1 inline; full list at <path>):
  - [P0] <dimension>: <observation>  — fix: <suggested_fix>
  ...

Evidence: .hv/qa-runs/<timestamp>/
```

Route per `references/review-verdict-routing.md` — same PASS/CONCERNS/FAIL contract; use carrier label `QA concerns:` when invoked from `/hv-ship` (per the routing reference's "Carrier-label override").

#### Step 9 — Routing

- Standalone: relay verdict to user per `Producer-side relay` in the verdict-routing reference.
- From `/hv-ship`: return the verdict only. `/hv-ship` consumes per `Consumer routing` table, gated by `qa.gate`:
  - `qa.gate: "advisory"` — `/hv-ship` reports findings but never halts.
  - `qa.gate: "blocking"` — `FAIL` halts; `CONCERNS` prompts the user.

### Mode: restructure

Run on demand when strategy files have drifted from the project (new surfaces, retired tools, dead targets).

1. Re-run the `Detect surfaces` and `Detect existing test infra` probes from `first-run`.
2. Diff against current `.hv/qa/*.md` — flag: targets with no matching surface (dead), surfaces with no target (uncovered), commands referencing tools not installed (broken), `Watch globs` matching no files (stale).
3. Propose changes — archive dead, draft new, fix broken, update globs — show to user before writing.
4. On approval, write the changes, run `.hv/bin/hv-qa-index`, commit `chore(qa): restructure QA strategy (<summary>)`.

## Rules

- **Strategy is data; runners are dispatched.** The skill never hardcodes Playwright, smoke, axe, or anything else. Every command comes from `.hv/qa/<target>.md`.
- **Three pillars, three shapes.** Performance + security = executable, pass/fail. Usability = audit, severity-ranked. Don't pretend usability is testable.
- **Read-only on `run`.** The verdict is the entire product. Never edit code; never stage. Artifacts write under `.hv/qa-runs/<timestamp>/`, gitignored.
- **Infra-fail fast.** Missing dev server, missing creds, missing binary → halt before running anything. Partial QA produces false confidence.
- **Evidence over opinion.** Every audit finding cites file:line, screenshot path, or a reproducer command. Vibes don't ship.
- **Stay separate from `/hv-review`.** Never read commits or diffs. If you find yourself wanting to, the request belongs to `/hv-review`.

## Failure Modes

- **No strategy file** — halt; tell user to run `/hv-qa first-run`. Don't auto-scaffold.
- **Infra unavailable** — `INFRA-FAIL` verdict; halt. User starts services, re-runs.
- **Runner subagent timeout** — that check is `met: false` with `evidence: "timeout after Ns"`. QA continues; verdict reflects the failed check.
- **Strategy references retired tool** — that check is `met: false` with `evidence: "command not found"`. Surface in `restructure` mode.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule.
- [`references/three-mode-skill-shape.md`](../references/three-mode-skill-shape.md) — Shared skeleton with `/hv-map` and `/hv-docs`.
- [`references/subagent-dispatch.md`](../references/subagent-dispatch.md) — Parallel runner pattern.
- [`references/review-verdict-routing.md`](../references/review-verdict-routing.md) — PASS / CONCERNS / FAIL contract; QA reuses it.
- [`references/umbrella-mode.md`](../references/umbrella-mode.md) — Per-repo resolution for `--repo` / `--all`.
- [`references/post-cycle-trigger-gate.md`](../references/post-cycle-trigger-gate.md) — When `qa.afterWork: true` should fire.
