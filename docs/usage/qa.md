# Product QA

`/hv-qa` answers a question `/hv-review` cannot: *"does the product actually work?"* `/hv-review` reads commits and the diff. `/hv-qa` executes runners against the built artifact (Playwright, smoke scripts, contract tests, Lighthouse, axe, ZAP, whatever the target's strategy declares).

The two skills are separate and never call each other. `/hv-ship` may invoke both, each behind its own opt-in config flag.

## Per-target strategy files

QA strategy lives in `.hv/qa/<target>.md`, one file per testable surface. In single-repo mode, `<target>` is a user-named surface (`web`, `api`, `cli`, ...). In [umbrella mode](umbrella-mode.md), `<target>` is a registered sub-repo name.

Each strategy file has five body sections:

| Section | Purpose |
|---------|---------|
| **Surface** | What kind of thing this is: web UI, HTTP API, CLI, mobile app, library |
| **Watch globs** | Paths whose changes should trigger post-cycle QA when `qa.afterWork: true` |
| **Executable checks** | Runners with concrete commands, grouped by pillar (performance / security / functional). Each entry: name · command · pass criterion |
| **Audit checks** | Usability dimensions to inspect by hand or LLM (empty states, error recovery, copy clarity, first-run flow). Rubric, no commands |
| **Infra requirements** | What must be running for `run` mode (e.g. `npm run dev` on `:3000`, deployed staging URL, sandbox creds). QA refuses to run if these aren't met |

Strategies are written once via `/hv-qa first-run`, which probes the repo for testing infra, proposes a draft, and writes the file after explicit approval.

## Modes

| Mode | What it does |
|------|-------------|
| `first-run` | Probes surfaces, detects existing test infra, proposes per-target strategy, writes `.hv/qa/<target>.md` after approval. Never installs tooling. |
| `run` | Executes the strategy: infra preflight, parallel runner dispatch, audit pass, scored verdict. Read-only against the codebase; writes artifacts to `.hv/qa-runs/<timestamp>/`. |
| `restructure` | Re-probes surfaces, retires dead strategies, fixes broken commands. Audit equivalent for strategy files. |

## Verdicts

`/hv-qa run` emits one of three verdicts on its final line:

| Verdict | Meaning |
|---------|---------|
| `PASS` | All executable checks met their pass criteria; no audit blockers found |
| `CONCERNS` | Findings worth surfacing but not blocking; usability or non-critical regressions |
| `FAIL` | One or more executable checks failed against their pass criteria |

A fourth shape, `INFRA-FAIL`, surfaces when required infra is missing (dev server down, binary not installed, creds absent). QA can't run; treat it as advisory, not as a quality signal.

## Invocation

Manual:

```
/hv-qa run             # all targets in active scope
/hv-qa run web         # specific target
/hv-qa run --repo api  # umbrella mode, scoped to one sub-repo
/hv-qa run --all       # umbrella mode, every registered sub-repo
```

Triggered by `/hv-ship` when `ship.qa: true`. Runs after `/hv-review` and the second-opinion gate, before merge or PR. Route is controlled by `qa.gate`:

| `qa.gate` | `PASS` | `CONCERNS` | `FAIL` |
|---|---|---|---|
| `"advisory"` (default) | continue silently | surface findings, continue | surface findings, continue (advisory means advisory) |
| `"blocking"` | continue silently | surface, branch on autonomy level | stop; user fixes via `/hv-work` or `/hv-debug` and reruns `/hv-ship` |

## When to use

- *"QA this"*, *"kick the tires"*, *"does this actually work?"*: manual exploratory run after a feature lands.
- Before opening a PR when you want product-level evidence, not just diff sanity.
- First-time setup on a new repo or umbrella sub-repo: bootstrap the strategy file once via `first-run`.

## When NOT to use

- Diff-level review → `/hv-review`. `/hv-qa` does not read commits.
- Nothing built yet → finish via `/hv-work` first. QA needs an artifact to probe.
- Change code based on findings → consume the report, then `/hv-work` or `/hv-debug`.

## Configuration

`/hv-qa` reads three keys from `.hv/config.json`:

- `qa.gate`: `"advisory"` (default) or `"blocking"`. Controls whether `FAIL` halts `/hv-ship` invocations.
- `qa.afterWork`: `false` (default). When `true`, `/hv-work` invokes `/hv-qa run` post-cycle if touched files match a target's `Watch globs`.
- `ship.qa`: `false` (default). When `true`, `/hv-ship` calls `/hv-qa run` between review and the merge/PR step.

See [configuration](configuration.md#shipqa) for the full block.

## See also

- [Review and ship](review-and-ship.md): diff-level review and the `/hv-ship` flow that calls `/hv-qa`
- [Configuration](configuration.md): full key reference
