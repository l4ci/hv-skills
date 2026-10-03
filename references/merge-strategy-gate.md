# Merge-strategy gate

The `work.mergeStrategy` config flag (`"direct"` | `"pr"` | unset) drives whether a feature branch integrates via `hv ship merge` (a `--no-ff` merge into main, branch deleted) or `hv ship pr` (push `-u` + `gh pr create`). Consumed by `hv-work/SKILL.md` Step 10 at the tail of a cycle, and by `hv-ship/SKILL.md` Steps 5/6a/6b where the merge-vs-PR decision is the central question. Extracted because both call sites duplicated the verb-invocation prose and drift had set in — `hv-ship` was missing the `--repo` umbrella variants that `hv-work` carries.

## Config flag

- `work.mergeStrategy` in `.hv/config.json`.
- Values: `"direct"`, `"pr"`, or unset.
- `"direct"` → use `hv ship merge`. `"pr"` → use `hv ship pr`. Unset → the strategy picker fires (next section).
- `/hv-config` is the canonical UI for changing this; the field's full vocabulary lives in `docs/reference/config-options.md`.

## Issue mode

With `backlog.backend: "issues"` the strategy is forced to `pr`: `work.mergeStrategy` is ignored, no picker fires, and `hv ship merge` is never used. `hv ship pr` takes `--items <ID[,ID...]>` to append `Closes #<n>` lines and opens a GitLab MR (`glab mr create`) when the provider is GitLab. Merging is `/hv-review --queue`'s job. See `references/issue-mode.md`.

## Strategy picker

Used by skills that have to decide (currently `hv-ship`). When to ask:

- `work.mergeStrategy` is unset, OR
- the user has signaled the other option in this session.

`AskUserQuestion` shape:

- **Header:** `"Strategy"`
- **Question:** *"How should I integrate `<branch>`?"*
- **Options** (single-select):
  1. Whichever matches `work.mergeStrategy` carries `(Recommended)`; default to `"Direct merge"` Recommended when unset.
  2. The other strategy as a peer option.
- Option labels and descriptions:
  - `"Direct merge"` — *"Merge into main with `--no-ff` and delete the branch."*
  - `"GitHub PR"` — *"Push and `gh pr create` with the body."*

Plain-text fallback: *"Ship `<branch>` as a PR or direct merge?"* — canonical mechanic in `references/ask-user-question-fallback.md` (default-to-Recommended bucket).

When `work.mergeStrategy` is set and the user hasn't overridden in-session: use it silently, no `AskUserQuestion`.

## Direct merge — `hv ship merge`

```bash
# Single-repo:
printf 'merge: <summary>\n\n- item 1\n- item 2\n' | hv ship merge <branch> --body-file -

# Umbrella mode:
printf 'merge: <summary>\n\n- item 1\n- item 2\n' | hv ship merge --repo <repo> <branch> --body-file -
```

The verb removes any worktree for the branch, checks out main, merges `--no-ff` with the piped message, deletes the branch, and reports the merge commit (`data.sha`; the short hash in text mode).

## Open a PR — `hv ship pr`

```bash
# Single-repo:
printf '%s' "$BODY" | hv ship pr <branch> --title "<short title>" --body-file -

# Umbrella mode:
printf '%s' "$BODY" | hv ship pr --repo <repo> <branch> --title "<short title>" --body-file -
```

`$BODY` is markdown — typical sections `## Summary`, `## Items resolved`, `## Test plan`. Canonical template:

```
## Summary
- item 1
- item 2

## Items resolved
- [B01] Title
- [F03] Title

## Test plan
- [ ] ...
```

Title rules: derived from the strongest commit subject, ≤70 chars, no `[B##]` tags. The helper removes any worktree, pushes `-u origin <branch>`, runs `gh pr create --title --body`. Prints the PR URL on stdout.

> **Manual gate — filing a public artifact.** Opening a PR creates externally-visible state. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The orchestrator composes title and body, the strategy picker (above) asks once with the user pressing the button, and only then does this verb invocation run.

## Umbrella mode

- `--repo <name>` is required in umbrella mode. Both verbs exit 2 from the umbrella root without it, since the umbrella root has no `.git/`.
- `<repo>` comes from the wave's resolved sub-repo. See `references/umbrella-mode.md` for the resolution path and registry shape.

## Per-skill carrier — what stays inline

- **In `hv-work` Step 10** — the integration is the tail of a cycle; the skill picks based on config silently, no `AskUserQuestion`. The merge-or-PR decision was implicitly made when the user configured `work.mergeStrategy`.
- **In `hv-ship` Steps 5/6a/6b** — the strategy picker IS the central question; Step 5 runs `AskUserQuestion`, then routes to Step 6a (PR) or 6b (direct). The Manual gate callout above lives inline at the head of `hv-ship` Step 6a as a reminder before the `hv ship pr` invocation.
- The exact PR body shape, the commit-derived title rules, and the post-integration cleanup (`hv status rm` etc) are skill-local — each skill has its own follow-up step.

## See also

- `references/ask-user-question-fallback.md` — canonical plain-text fallback mechanic.
- `references/umbrella-mode.md` — `--repo` flag semantics and sub-repo resolution.
- `docs/reference/config-options.md` — full `work.mergeStrategy` vocabulary and other config keys.
