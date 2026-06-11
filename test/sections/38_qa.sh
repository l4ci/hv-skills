echo "hv-qa-query + hv-qa-index"

# Build a .hv/qa/ tree with one well-formed target.
mkdir -p .hv/qa
cat > .hv/qa/web.md <<'EOF'
---
target: web
surface: web-ui
summary: Public marketing site QA — perf budgets + a11y + smoke
created: 2026-05-15
touched: 2026-05-15
watch-globs:
  - "src/**/*.tsx"
  - "src/**/*.css"
---

## Surface

Web UI (Next.js, deployed at staging.example.com).

## Watch globs

- `src/**/*.tsx`
- `src/**/*.css`

## Executable checks

- **lighthouse-perf** · `lighthouse https://staging.example.com --budget-path=.budget.json` · all budgets met
- **pa11y-a11y** · `pa11y https://staging.example.com` · 0 errors
- **smoke** · `bash test/smoke.sh` · exit 0

## Audit checks

- Empty states (rubric in references/usability-rubric.md)
- First-run flow
- Error recovery copy

## Infra requirements

- Staging URL reachable: `curl -fsS https://staging.example.com >/dev/null`
- `command -v lighthouse pa11y`

## Out of scope

- Load testing
- Real-payment flows
EOF

# hv-qa-query prints body of named target.
"$BIN/hv-qa-query" web > /tmp/qa-query-out.txt
grep -q "^## Executable checks" /tmp/qa-query-out.txt || fail "hv-qa-query body missing Executable checks heading"
grep -q "^## Audit checks" /tmp/qa-query-out.txt || fail "hv-qa-query body missing Audit checks heading"
grep -q "^---" /tmp/qa-query-out.txt && fail "hv-qa-query leaked frontmatter into stdout"
pass "hv-qa-query prints body, strips frontmatter"

# Missing target is silent (exit 0, empty stdout).
"$BIN/hv-qa-query" nonexistent > /tmp/qa-query-miss.txt
[ ! -s /tmp/qa-query-miss.txt ] || fail "hv-qa-query emitted output for missing target"
pass "hv-qa-query silent on missing target"

# Multi-target ordering: requested order is preserved.
cat > .hv/qa/api.md <<'EOF'
---
target: api
surface: http-api
summary: REST API contract + auth probes
created: 2026-05-15
touched: 2026-05-15
---

## Surface

HTTP API.
EOF
"$BIN/hv-qa-query" api web > /tmp/qa-query-multi.txt
FIRST_HEAD=$(grep -m1 "^## " /tmp/qa-query-multi.txt)
[ "$FIRST_HEAD" = "## Surface" ] || fail "hv-qa-query order not preserved"
pass "hv-qa-query preserves argument order"

# hv-qa-index regenerates the managed block.
"$BIN/hv-qa-index" >/dev/null
grep -q "<!-- hv-qa-start -->" CLAUDE.md || fail "hv-qa managed block not in CLAUDE.md"
grep -q "^## Project QA" CLAUDE.md || fail "Project QA heading missing"
grep -q "\*\*web\*\*" CLAUDE.md || fail "web target bullet missing from index"
grep -q "\*\*api\*\*" CLAUDE.md || fail "api target bullet missing from index"
pass "hv-qa-index seeds Project QA block"

# Re-running is idempotent (no duplicate markers).
"$BIN/hv-qa-index" >/dev/null
COUNT_START=$(grep -c "hv-qa-start" CLAUDE.md)
[ "$COUNT_START" = "1" ] || fail "hv-qa managed block duplicated on re-run"
pass "hv-qa-index updates in place"

# Empty .hv/qa/ renders the no-strategy hint.
rm -f .hv/qa/web.md .hv/qa/api.md
"$BIN/hv-qa-index" >/dev/null
grep -q "no QA strategy yet" CLAUDE.md || fail "empty-state hint missing"
pass "hv-qa-index renders empty-state hint"

# Cleanup so later sections start fresh.
rm -rf .hv/qa
"$BIN/hv-qa-index" >/dev/null
