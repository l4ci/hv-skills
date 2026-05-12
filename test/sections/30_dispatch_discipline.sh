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

echo "F73: authoring-conventions citation"
grep -q '^## Dispatch heavy work to subagents' "$REPO/references/authoring-conventions.md" \
  || fail "F73: authoring-conventions.md missing 'Dispatch heavy work to subagents' rule"
grep -q 'references/subagent-dispatch.md' "$REPO/references/authoring-conventions.md" \
  || fail "F73: authoring-conventions.md missing cross-reference to subagent-dispatch.md"
pass "authoring-conventions cites subagent-dispatch reference"

echo "F73: hv-next dispatch wave"
grep -q 'Worker A.*[Rr]econcile' "$REPO/hv-next/SKILL.md" \
  || fail "F73: hv-next missing Worker A (reconcile)"
grep -q 'Worker B.*[Aa]rchive' "$REPO/hv-next/SKILL.md" \
  || fail "F73: hv-next missing Worker B (archive)"
grep -q 'Worker C.*[Mm]ilestone' "$REPO/hv-next/SKILL.md" \
  || fail "F73: hv-next missing Worker C (milestone)"
grep -q 'Worker D.*[Rr]elevance' "$REPO/hv-next/SKILL.md" \
  || fail "F73: hv-next missing Worker D (relevance)"
grep -q 'single parallel wave' "$REPO/hv-next/SKILL.md" \
  || fail "F73: hv-next missing 'single parallel wave' phrasing"
grep -q 'references/subagent-dispatch.md' "$REPO/hv-next/SKILL.md" \
  || fail "F73: hv-next missing reference cite"
pass "hv-next retrofitted with parallel dispatch wave"

echo "F73: hv-vision dispatch retrofits"
grep -q 'context-bundle worker' "$REPO/hv-vision/SKILL.md" \
  || fail "F73: hv-vision Step 2 missing context-bundle worker"
grep -q 'haiku' "$REPO/hv-vision/SKILL.md" \
  || fail "F73: hv-vision Step 2 missing haiku tier"
grep -q 'research worker' "$REPO/hv-vision/SKILL.md" \
  || fail "F73: hv-vision Step 4 missing research worker dispatch"
grep -q 'per angle' "$REPO/hv-vision/SKILL.md" \
  || fail "F73: hv-vision Step 4 missing per-angle fan-out"
grep -q 'references/subagent-dispatch.md' "$REPO/hv-vision/SKILL.md" \
  || fail "F73: hv-vision missing reference cite"
pass "hv-vision retrofitted with context-bundle + research fan-out workers"
