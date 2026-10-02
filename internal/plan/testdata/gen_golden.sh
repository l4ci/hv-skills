#!/usr/bin/env bash
# Regenerates the golden files from the OLD bin/ helpers. Usage: gen_golden.sh <repo> <outdir>
set -euo pipefail
REPO="$1"; OUT="$2"; BIN="$REPO/bin"
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; cd "$W"
mkdir -p .hv "$W/web" "$W/api"
printf '{"repos": [{"name": "web", "path": "web"}, {"name": "api", "path": "api"}, {"name": "web-docs", "path": "web-docs"}]}\n' > .hv/repos.json
mkdir -p web-docs
mask() { sed -E 's/^(created|finished): [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1: DATE/' "$1"; }
"$BIN/hv-design-add" B07 "Title: with colon & é" >/dev/null
"$BIN/hv-design-add" F12 "Second" >/dev/null
"$BIN/hv-plan-add" M01 slice "First slice" >/dev/null
"$BIN/hv-plan-add" M01 slice "Second slice" >/dev/null
"$BIN/hv-plan-add" M01 B07 "Item plan" >/dev/null
"$BIN/hv-plan-add" --repo "web,api" --design .hv/designs/B07.md M02 S05 "Repos and design" >/dev/null
"$BIN/hv-plan-add" M02 slice "After S05" >/dev/null
mkdir -p "$OUT/design" "$OUT/plan"
for f in .hv/designs/*.md; do mask "$f" > "$OUT/design/$(basename "$f")"; done
for f in .hv/plans/*.md; do mask "$f" > "$OUT/plan/$(basename "$f")"; done
"$BIN/hv-plan-list" | sed -E 's/"created": "[0-9-]+"/"created": "DATE"/' > "$OUT/plan/list.json"
"$BIN/hv-plan-list" M02 | sed -E 's/"created": "[0-9-]+"/"created": "DATE"/' > "$OUT/plan/list-M02.json"
"$BIN/hv-design-list" | sed -E 's/"created": "[0-9-]+"/"created": "DATE"/' > "$OUT/design/list.json"
# validate-docs: a plan with doc deliverables in several shapes
cat > .hv/plans/M03-B01.md <<'PLAN'
---
key: M03-B01
milestone: M03
unit: B01
unitKind: item
repo: web, api, ghost
title: t
status: planned
created: 2026-05-20
---

## Tasks

- **T1** — docs
  - Files: src/x.ts, docs/api/auth.md (new), `web/docs/guide.md:12`
  - Verify: build
- **T2** — more
  - **Files**:
    - docs/ref.md
    - _(placeholder)_
    - README.md
  - Verify: x

## Open questions
- Files: docs/ignored.md
PLAN
cp .hv/plans/M03-B01.md "$OUT/plan/validate-docs.plan.md"
"$BIN/hv-plan-validate-docs" M03-B01 | sed "s|$W|ROOT|g" > "$OUT/plan/validate-docs.out"
echo "$W" > /dev/null
# design amend goldens (consumed by internal/design tests)
"$BIN/hv-design-amend" B07 --section Goal --append $'first line\nsecond line\n\n' >/dev/null
"$BIN/hv-design-amend" B07 --section "Open questions" --append "- one more" >/dev/null
mask .hv/designs/B07.md > "$OUT/design/B07.amend-append.md"
"$BIN/hv-design-amend" B07 --section Design --replace "replaced body" >/dev/null
mask .hv/designs/B07.md > "$OUT/design/B07.amend-replace.md"
