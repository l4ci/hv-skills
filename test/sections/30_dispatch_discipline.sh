echo "F73: subagent-dispatch discipline"

# Reference file must exist with all six sections.
[ -f "$REPO/references/subagent-dispatch.md" ] \
  || fail "F73: references/subagent-dispatch.md not created"

grep -q '^## When to dispatch' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: section 'When to dispatch' missing"
grep -q '^## Small-brief template' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: section 'Small-brief template' missing"
grep -q '^## Return-shape contract' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: section 'Return-shape contract' missing"
grep -q '^## Model tier per work type' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: section 'Model tier per work type' missing"
grep -q '^## Parallel fan-out pattern' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: section 'Parallel fan-out pattern' missing"
grep -q '^## What stays on the orchestrator' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: section 'What stays on the orchestrator' missing"

# Worktree-isolation cross-reference must be inline (not just a link).
grep -q 'DECISIONS.md' "$REPO/references/subagent-dispatch.md" \
  || fail "F73: reference must cite .hv/DECISIONS.md worktree-isolation rule"

# No TBD/TODO leftovers.
if grep -qiE '(TBD|TODO|FIXME|XXX)' "$REPO/references/subagent-dispatch.md"; then
  fail "F73: reference contains placeholders"
fi

pass "subagent-dispatch reference has all six sections and no placeholders"
