echo "F32: loop-mode auto-planning helpers"

# (a) /hv-plan SKILL.md exposes --auto-loop with the inline dispatch language.
grep -q -- '--auto-loop' "$REPO/hv-plan/SKILL.md" \
  || fail "F32: hv-plan/SKILL.md must document the --auto-loop flag"
grep -q 'Auto-loop mode' "$REPO/hv-plan/SKILL.md" \
  || fail "F32: hv-plan/SKILL.md must include the dedicated 'Auto-loop mode' section"

# (b) /hv-work Step 4 carries the inline loop-mode auto-plan dispatch directive.
grep -q 'Loop-mode auto-plan dispatch' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must contain the loop-mode auto-plan dispatch language"
grep -q '/hv-plan --auto-loop' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must reference /hv-plan --auto-loop"

# (c) Surfacing call sites — exactly /hv-next, /hv-pause, /hv-work invoke hv-auto-decisions-since.
# (hv-plan/SKILL.md mentions the helper in prose only; the test below is for actual `.hv/bin/`-prefixed invocations.)
SURFACING_SITES=$(grep -l '\.hv/bin/hv-auto-decisions-since' "$REPO"/hv-*/SKILL.md \
  | sed -E 's@.*/(hv-[a-z-]+)/SKILL\.md@\1@' \
  | sort -u | tr '\n' ' ' | sed 's/ $//')
[ "$SURFACING_SITES" = "hv-next hv-pause hv-work" ] \
  || fail "F32: .hv/bin/hv-auto-decisions-since invocation expected in exactly hv-next/hv-pause/hv-work, got '$SURFACING_SITES'"

# (d) hv-loop-stamp wired into /hv-next (start) and /hv-pause + /hv-work (clear).
grep -q 'hv-loop-stamp start' "$REPO/hv-next/SKILL.md" \
  || fail "F32: hv-next/SKILL.md must call hv-loop-stamp start"
grep -q 'hv-loop-stamp clear' "$REPO/hv-pause/SKILL.md" \
  || fail "F32: hv-pause/SKILL.md must call hv-loop-stamp clear"
grep -q 'hv-loop-stamp clear' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must call hv-loop-stamp clear"

# (e) hv-init seeds loop.webResearch=False in both fresh + STALE config paths.
grep -q '"loop":.*"webResearch": False' "$REPO/hv-init/SKILL.md" \
  || fail "F32: hv-init must seed loop.webResearch in the fresh config block"
grep -q 'hv-config-set loop.webResearch false' "$REPO/hv-init/SKILL.md" \
  || fail "F32: hv-init must seed loop.webResearch in the STALE migration block"
pass "F32: SKILL.md wiring + config defaults"

# (f) hv-loop-stamp: start writes ISO timestamp; idempotent first-write; clear removes; read is silent-empty.
F32_TMP="$(mktemp -d)"
(
  cd "$F32_TMP"
  mkdir .hv
  echo '{"active": []}' > .hv/status.json
  # read on empty
  OUT=$("$BIN/hv-loop-stamp" read)
  [ -z "$OUT" ] || fail "F32(f): hv-loop-stamp read on unset must be empty, got '$OUT'"
  # start writes
  "$BIN/hv-loop-stamp" start
  T1=$("$BIN/hv-loop-stamp" read)
  echo "$T1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
    || fail "F32(f): hv-loop-stamp start must write ISO timestamp, got '$T1'"
  # idempotent first-write — second start must not overwrite
  sleep 1
  "$BIN/hv-loop-stamp" start
  T2=$("$BIN/hv-loop-stamp" read)
  [ "$T1" = "$T2" ] || fail "F32(f): hv-loop-stamp start must be idempotent first-write (T1='$T1' T2='$T2')"
  # active array preserved
  grep -q '"active": \[\]' .hv/status.json \
    || fail "F32(f): hv-loop-stamp must preserve the active array"
  # clear removes
  "$BIN/hv-loop-stamp" clear
  OUT=$("$BIN/hv-loop-stamp" read)
  [ -z "$OUT" ] || fail "F32(f): hv-loop-stamp clear must remove loopStartedAt, got '$OUT'"
)
rm -rf "$F32_TMP"
pass "F32(f): hv-loop-stamp start/clear/read"

# (g) hv-auto-decision-log: writes placeholder template + footer; idempotent on (topic, rule-title).
F32_TMP="$(mktemp -d)"
(
  cd "$F32_TMP"
  mkdir .hv
  echo "# Decisions" > .hv/DECISIONS.md
  echo "" >> .hv/DECISIONS.md
  "$BIN/hv-auto-decision-log" "Test Topic" "Test rule" "Because reasons" "M04-F32" "2026-05-09"
  grep -q '## Test Topic' .hv/DECISIONS.md \
    || fail "F32(g): topic header missing"
  grep -q '### Test rule' .hv/DECISIONS.md \
    || fail "F32(g): rule heading missing"
  grep -q '_(Unresolved — user must articulate)_' .hv/DECISIONS.md \
    || fail "F32(g): placeholder Forbids/Permits missing"
  grep -q '\[Auto:Loop\] M04-F32 2026-05-09' .hv/DECISIONS.md \
    || fail "F32(g): provenance footer missing or malformed"
  # idempotent — second run must not duplicate the entry
  "$BIN/hv-auto-decision-log" "Test Topic" "Test rule" "Because reasons" "M04-F32" "2026-05-09"
  COUNT=$(grep -c '### Test rule' .hv/DECISIONS.md)
  [ "$COUNT" = "1" ] || fail "F32(g): hv-auto-decision-log must be idempotent on (topic, rule-title), got $COUNT entries"
)
rm -rf "$F32_TMP"
pass "F32(g): hv-auto-decision-log placeholder template + idempotent"

# (h) hv-auto-decisions-since: filters by loopStartedAt date; lookup-empty when no match.
F32_TMP="$(mktemp -d)"
(
  cd "$F32_TMP"
  mkdir .hv
  cat > .hv/status.json <<'EOFJ'
{"active": [], "loopStartedAt": "2026-05-09T00:00:00Z"}
EOFJ
  cat > .hv/DECISIONS.md <<'EOFD'
# Decisions

## Topic A

### Pre-loop rule

*Why.* Decided yesterday.

**Forbids.**
- Specific thing.

**Permits.**
- Other thing.

<!-- [Auto:Loop] M04-F32 2026-05-08 — review and articulate Forbids/Permits -->

### In-loop rule

*Why.* Decided today.

**Forbids.**
- _(Unresolved — user must articulate)_

**Permits.**
- _(Unresolved — user must articulate)_

<!-- [Auto:Loop] M04-F32 2026-05-09 — review and articulate Forbids/Permits -->
EOFD
  OUT=$("$BIN/hv-auto-decisions-since")
  echo "$OUT" | grep -q 'In-loop rule' \
    || fail "F32(h): post-loopStart entry missing from output: $OUT"
  echo "$OUT" | grep -q 'Pre-loop rule' \
    && fail "F32(h): pre-loopStart entry must be filtered out: $OUT"
  echo "$OUT" | grep -q 'Forbids/Permits unresolved' \
    || fail "F32(h): unresolved status tag missing: $OUT"
  # lookup-empty when loopStartedAt is unset
  echo '{"active": []}' > .hv/status.json
  OUT=$("$BIN/hv-auto-decisions-since")
  [ -z "$OUT" ] || fail "F32(h): empty when loopStartedAt unset, got '$OUT'"
)
rm -rf "$F32_TMP"
pass "F32(h): hv-auto-decisions-since filter + lookup-empty"

# --- hvlib: parse_frontmatter & iter_map_entries -------------------
mkdir -p .hv/map
cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into TODO.md
touched: 2026-05-09
related-topics: [Skill Authoring]
---

## Purpose
One paragraph.
EOF
cat > .hv/map/plan.md <<'EOF'
---
subsystem: plan
summary: Plans before execution
touched: 2026-04-01
---
body
EOF
# malformed: no frontmatter
echo "no frontmatter here" > .hv/map/broken.md

PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import parse_frontmatter, iter_map_entries
fm, body = parse_frontmatter(open(".hv/map/capture.md").read())
assert fm["subsystem"] == "capture", fm
assert fm["summary"] == "Captures items into TODO.md", fm
assert "## Purpose" in body, body
assert fm["related-topics"] == ["Skill Authoring"], fm

# malformed body: empty frontmatter dict, full content as body
fm2, body2 = parse_frontmatter(open(".hv/map/broken.md").read())
assert fm2 == {}, fm2
assert body2.strip() == "no frontmatter here", body2

entries = list(iter_map_entries(".hv/map"))
names = sorted(e[0] for e in entries)
assert names == ["capture", "plan"], names  # malformed file is skipped
PY
echo "ok hvlib parse_frontmatter / iter_map_entries"

# --- hv-map-query --------------------------------------------------
out="$("$BIN/hv-map-query" capture)"
[[ "$out" == *"## Purpose"* ]] || { echo "FAIL: hv-map-query body missing"; exit 1; }
out="$("$BIN/hv-map-query" capture plan)"
[[ "$out" == *"## Purpose"* && "$out" == *"body"* ]] || { echo "FAIL: hv-map-query multi"; exit 1; }
out="$("$BIN/hv-map-query" nonexistent)"
[[ -z "$out" ]] || { echo "FAIL: hv-map-query missing should be empty, got: $out"; exit 1; }
echo "ok hv-map-query"

# --- hv-map-stats --------------------------------------------------
# Add an entry-point referencing this very file to test the file:line check
mkdir -p src
echo "line1" > src/sample.txt
echo "line2" >> src/sample.txt
cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Orchestrator-driven execution
touched: 2026-05-09
---

## Entry points
- src/sample.txt:2 — second line
- src/missing.txt:42 — broken ref
EOF
out="$("$BIN/hv-map-stats")"
echo "$out" | grep -q '"name": "capture"' || { echo "FAIL: stats missing capture"; exit 1; }
echo "$out" | grep -q '"broken_refs"' || { echo "FAIL: stats missing broken_refs"; exit 1; }
# work has 1 broken ref out of 2 entry points
echo "$out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
work = next(s for s in data["subsystems"] if s["name"] == "work")
assert work["broken_refs"] == 1, work
assert work["entry_points"] == 2, work
'
echo "ok hv-map-stats"

# --- hv-map-index --------------------------------------------------
[ -f CLAUDE.md ] || : > CLAUDE.md
"$BIN/hv-map-index" >/dev/null
grep -q '<!-- hv-map-start -->' CLAUDE.md || { echo "FAIL: map block not in CLAUDE.md"; exit 1; }
grep -q '## Project Map' CLAUDE.md || { echo "FAIL: heading missing"; exit 1; }
grep -q '\*\*capture\*\* — Captures items into TODO.md' CLAUDE.md || { echo "FAIL: capture summary missing"; exit 1; }
# Idempotence
sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
"$BIN/hv-map-index" >/dev/null
sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
[ "$sha1" = "$sha2" ] || { echo "FAIL: hv-map-index not idempotent"; exit 1; }
# Empty case: hide the block when .hv/map/ has no valid entries
mv .hv/map .hv/map.bak
mkdir .hv/map
"$BIN/hv-map-index" >/dev/null
grep -q '_(no subsystems yet' CLAUDE.md || { echo "FAIL: empty placeholder missing"; exit 1; }
mv .hv/map .hv/map.empty
mv .hv/map.bak .hv/map
echo "ok hv-map-index"

# --- hv-staleness --------------------------------------------------
# Capture (touched 2026-04-01) is older than 30 days from "today=2026-05-09";
# work is touched 2026-05-09 and should not be flagged at days=30.
out="$("$BIN/hv-staleness" map --days 30 --today 2026-05-09)"
echo "$out" | grep -q '^plan ' || { echo "FAIL: plan should be stale"; exit 1; }
echo "$out" | grep -q '^work ' && { echo "FAIL: work should NOT be stale"; exit 1; }
# days=0 lists all
out="$("$BIN/hv-staleness" map --days 0 --today 2026-05-09)"
[ "$(echo "$out" | wc -l)" -ge 2 ] || { echo "FAIL: days=0 should list all"; exit 1; }
# Knowledge: KNOWLEDGE.md exists from bootstrap-style fixture; should not error
"$BIN/hv-staleness" knowledge --days 0 >/dev/null
echo "ok hv-staleness"

# --- hv-stale-summary ---------------------------------------------
# Wraps hv-staleness × 3 into one summary line; zero-kinds suppressed.
out="$("$BIN/hv-stale-summary" --days 0 --today 2026-05-09 map)"
case "$out" in
  "stale: map="*) ;;
  *) echo "FAIL: hv-stale-summary did not emit stale: map=N (got: $out)"; exit 1 ;;
esac
# All-fresh: --days 999999 yields zero stale → empty output
out="$("$BIN/hv-stale-summary" --days 999999 --today 2026-05-09)"
[ -z "$out" ] || { echo "FAIL: hv-stale-summary should be silent when nothing is stale (got: $out)"; exit 1; }
echo "ok hv-stale-summary"

# --- hv-bootstrap seeds map ---------------------------------------
TMP2=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP2"' EXIT
(
  cd "$TMP2"
  git init -q
  "$BIN/hv-bootstrap" >/dev/null
  [ -d .hv/map ] || { echo "FAIL: .hv/map not created"; exit 1; }
  [ -f .hv/MAP.md ] || { echo "FAIL: .hv/MAP.md not seeded"; exit 1; }
  grep -q "Project map" .hv/MAP.md || { echo "FAIL: .hv/MAP.md content missing"; exit 1; }
)
echo "ok hv-bootstrap seeds map"

# --- skill touchpoints reference map ------------------------------
grep -q "hv-map-stats\|hv-map after-work" "$REPO/hv-work/SKILL.md" || { echo "FAIL: hv-work has no map touchpoint"; exit 1; }
grep -q "hv-map after-work" "$REPO/hv-debug/SKILL.md" || { echo "FAIL: hv-debug has no map after-work"; exit 1; }
grep -q "hv-map after-work" "$REPO/hv-go/SKILL.md" || { echo "FAIL: hv-go has no map after-work"; exit 1; }
echo "ok skill touchpoints (work/debug/go)"

# --- status/next/resume reference hv-stale-summary ---------------
# Note: hv-status and hv-resume were merged into hv-next (F26).
# hv-next now uses bin/hv-stale-summary as a single wrapper (F48).
grep -q "hv-stale-summary" "$REPO/hv-next/SKILL.md"        || { echo "FAIL: hv-next missing stale-summary call"; exit 1; }
grep -q "Subsystem:" "$REPO/hv-capture/SKILL.md"           || { echo "FAIL: hv-capture missing Subsystem field"; exit 1; }
echo "ok status/next/resume/capture touchpoints"

# --- end-to-end: scaffold + after-work bump + consolidate prep ----
TMP3=$(mktemp -d)
trap 'rm -rf "$TMP3" "$TMP" "$TMP2"' EXIT
(
  cd "$TMP3"
  git init -q
  git config user.email test@example.com
  git config user.name Test
  "$BIN/hv-bootstrap" >/dev/null
  : > CLAUDE.md
  cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into TODO.md
touched: 2026-05-09
created: 2026-05-09
---

## Purpose
Capture flow.

## Entry points
- bin/hv-bootstrap:1 — broken ref (file does not exist in fixture)
EOF
  cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Captures items into TODO.md  # near-duplicate summary
touched: 2025-12-01
created: 2025-12-01
---

## Purpose
Work flow.
EOF
  "$BIN/hv-map-index" >/dev/null

  python3 - <<'PY'
from pathlib import Path
p = Path(".hv/map/capture.md")
text = p.read_text().replace("touched: 2026-05-09", "touched: 2026-05-10")
p.write_text(text)
PY
  grep -q "touched: 2026-05-10" .hv/map/capture.md || { echo "FAIL: after-work bump"; exit 1; }

  out="$("$BIN/hv-staleness" map --days 30 --today 2026-05-10)"
  echo "$out" | grep -q "^work " || { echo "FAIL: work should be stale at days=30"; exit 1; }

  count=$("$BIN/hv-map-stats" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["subsystems"]))')
  [ "$count" = "2" ] || { echo "FAIL: stats count $count != 2"; exit 1; }

  "$BIN/hv-map-index" >/dev/null
  sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  "$BIN/hv-map-index" >/dev/null
  sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  [ "$sha1" = "$sha2" ] || { echo "FAIL: integration idempotence"; exit 1; }
)
echo "ok end-to-end map flow"

# --- parse_todo_fields handles Subsystem ---------------------------
PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import parse_todo_fields
line = "- [B07] [P1] Title. Repos: web Subsystem: capture Captured: 2026-05-09"
fields = parse_todo_fields(line)
assert fields.get("repos") == "web", f"repos={fields.get('repos')!r}"
assert fields.get("subsystem") == "capture", f"subsystem={fields.get('subsystem')!r}"

line2 = "- [B07] [P1] Title. Milestone: M01 Subsystem: capture Captured: 2026-05-09"
fields2 = parse_todo_fields(line2)
assert fields2.get("milestone") == "M01", f"milestone={fields2.get('milestone')!r}"
assert fields2.get("subsystem") == "capture", f"subsystem={fields2.get('subsystem')!r}"
PY
echo "ok parse_todo_fields handles Subsystem"

