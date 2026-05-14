# Silent failure hunter

Shared rubric invoked by `/hv-review` Step 8 (Stage 2 reviewer brief) and bundled into the `/hv-ship` Step 3 review pass. Detects when work reports *complete* but didn't actually move the system — the most insidious failure mode because everything looks fine from the outside.

Inspired by the silent-failure-hunter archetype in the ECC agents catalog. Not a separate dispatch step or helper — it lives entirely as an additional rubric item that the existing reviewer evaluates alongside intent match, convention compliance, obvious quality, and stale scaffolding.

## What "silent failure" means

A silent failure leaves no surface error. The build is green, the test reports `OK`, the smoke section prints `PASS` — but the change didn't actually do the thing it claimed to do. The seven recurring shapes:

- **Tests pass but feature broken.** The new assertion targets the wrong path, or doesn't exercise the changed branch. Adding `assert True` would also pass.
- **Build succeeds but artifact missing.** Compiler exits 0; the binary, generated file, or deployable bundle isn't where downstream expects to find it.
- **Smoke OK but code path never exercised.** The asserted command runs; the new branch is guarded behind a flag the smoke fixture didn't flip.
- **Helper output asserted on the wrong shape.** A helper emits JSON; the test greps stdout for a substring that happens to occur in *every* run.
- **Idempotent helper called, state didn't move.** The no-op path runs (already-stamped, already-resolved, already-archived) and nothing visible distinguishes that from real work.
- **Mock returned the expected value before the code ran.** The test asserts on a fixture, not on a real call result.
- **CI runs in isolation but not in the real pipeline.** Local-only env vars, a missing service dependency, or a different working directory in CI keeps the new path dark.

## Rubric — apply to every verification claim in the diff

For each test, smoke section, or assertion the diff adds or relies on, answer the four questions below. If any answer is *no* or *unclear*, mark the claim `SILENT-FAIL` with file:line evidence and a one-sentence explanation.

1. **What does this verify, concretely?** Name the specific behavior the change introduces, not the general feature. ("Asserts hv-merge prints the merge hash on stdout" beats "tests hv-merge.")
2. **Is the asserted-on thing the same thing the real consumer reads?** Output shape, file path, exit code, env var, JSON key — all must match where the rest of the system actually looks for that signal.
3. **Was the new code path exercised?** Trace: did the fixture set the flag, hit the route, or pass the input that triggers the new branch the diff added? If the new branch lives behind an `if config.featureX:` check, did the test enable `featureX`?
4. **If you deleted the new code, would the assertion still pass?** If yes, the assertion is not actually testing the change. Flag.

## Output contract

For each `SILENT-FAIL` flag, surface one bullet under a `### Silent failure check` section in the reviewer's verdict block:

```
### Silent failure check
- test/sections/08_ship.sh:42 — asserts `grep "merged" output` but `hv-merge` prints "Merged" with a capital M; assertion would pass before the change too.
- references/foo.md:17 — claims "loop mode exits cleanly on empty backlog" but no smoke section flips autonomy.level to "loop" with an empty backlog.
```

`SILENT-FAIL` flags route as `CONCERNS` in the verdict — they don't break the build by themselves, but the user sees them before merging. A diff that gets `PASS` on intent + convention + quality but has `SILENT-FAIL` flags becomes `CONCERNS`. A diff that's already at `FAIL` stays `FAIL` (regression beats silence).

## Invocation contract

`/hv-review` Step 8 (Stage 2 — Code Quality) carries the rubric as the silent-failure check item ("Silent failure check — apply the four-question rubric from `references/silent-failure-hunter.md` to every verification claim in the diff"). The reviewer prompt links to this file so the full text is one Read away when needed. Variant A of the Stage 2 brief (used when Stage 1 ran) places it as rubric item #4; Variant B (no-plan fallback / `--stage quality`) places it as rubric item #5 after the legacy intent-match item.

`/hv-ship` Step 3 inherits the check automatically through `/hv-review` — no separate dispatch. The point of bundling is that the reviewer already has the diff and the intent loaded; running a second adversarial pass for silent-failure-only would double the cost without changing the verdict shape.

`/hv-ship` does **not** call this rubric when `ship.review: false` — opting out of review opts out of the hunter too. The rubric is a review-quality augmentation, not a separate gate.

## See also

- `references/review-verdict-routing.md` — how `CONCERNS` (including silent-failure flags) routes through `/hv-ship` per `autonomy.level`.
- `hv-review/SKILL.md` Step 8 — the Stage 2 reviewer brief that carries the rubric inline.
