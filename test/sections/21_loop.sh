echo "F32: loop-mode auto-planning helpers"

# (a) /hv-plan SKILL.md exposes --auto-loop with the inline dispatch language.
# white-box-begin: A9 #53 doclint
grep -q -- '--auto-loop' "$REPO/hv-plan/SKILL.md" \
  || fail "F32: hv-plan/SKILL.md must document the --auto-loop flag"
grep -q 'Auto-loop mode' "$REPO/hv-plan/SKILL.md" \
  || fail "F32: hv-plan/SKILL.md must include the dedicated 'Auto-loop mode' section"
# white-box-end

# (b) /hv-work Step 4 carries the inline loop-mode auto-dispatch chain directive (renamed under B28).
# white-box-begin: A9 #53 doclint
grep -q 'Loop-mode auto-dispatch chain' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must contain the loop-mode auto-dispatch chain language"
grep -q '/hv-plan --auto-loop' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must reference /hv-plan --auto-loop"
# white-box-end

# (c) Surfacing call sites — pre-execution skills reference hv-auto-decisions-since
# to consult recent decisions before suggesting an approach. The original intent
# was to invoke the helper explicitly from /hv-next, /hv-pause, /hv-work on terminal
# paths; current SKILL.md prose in hv-brainstorm and hv-plan documents that pathway
# but the explicit invocations have not landed. This assertion guards against the
# helper becoming orphaned — if neither prose nor invocations reference it, the
# helper exists with no consumer. Update the expected set when explicit invocations
# land in the terminal-path skills.
# white-box-begin: A9 #53 doclint
SURFACING_SITES=$(grep -l 'hv-auto-decisions-since' "$REPO"/hv-*/SKILL.md 2>/dev/null \
  | sed -E 's@.*/(hv-[a-z-]+)/SKILL\.md@\1@' \
  | sort -u | tr '\n' ' ' | sed 's/ $//' || true)
[ "$SURFACING_SITES" = "hv-brainstorm hv-plan" ] \
  || fail "F32: hv-auto-decisions-since reference expected in exactly hv-brainstorm/hv-plan SKILL.md, got '$SURFACING_SITES'"
# white-box-end

# (d) hv-loop-stamp wired into /hv-next (start) and /hv-pause + /hv-work (clear).
# white-box-begin: A9 #53 doclint
grep -q 'hv-loop-stamp start' "$REPO/hv-next/SKILL.md" \
  || fail "F32: hv-next/SKILL.md must call hv-loop-stamp start"
grep -q 'hv-loop-stamp clear' "$REPO/hv-pause/SKILL.md" \
  || fail "F32: hv-pause/SKILL.md must call hv-loop-stamp clear"
grep -q 'hv-loop-stamp clear' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must call hv-loop-stamp clear"
# white-box-end

# (e) hv-init seeds loop.webResearch=False in both fresh + STALE config paths.
# white-box-begin: A9 #53 doclint
grep -q '"loop":.*"webResearch": False' "$REPO/hv-init/SKILL.md" \
  || fail "F32: hv-init must seed loop.webResearch in the fresh config block"
grep -q 'hv-config-set loop.webResearch false' "$REPO/hv-init/SKILL.md" \
  || fail "F32: hv-init must seed loop.webResearch in the STALE migration block"
pass "F32: SKILL.md wiring + config defaults"
# white-box-end

# (f) status loop: start writes ISO timestamp; idempotent first-write; clear removes; show is null when unset.
F32_TMP="$(mktemp -d)"
trap 'rm -rf "$F32_TMP"' EXIT
(
  cd "$F32_TMP" && mkdir .hv
  echo '{"active": []}' > .hv/status.json
  OUT=$(hvj status loop show)
  [ "$(jget data.loopStartedAt <<<"$OUT")" = "null" ] \
    || fail "F32(f): status loop show on unset must be null, got '$OUT'"
  OUT=$(hvj status loop start)
  T1=$(jget data.loopStartedAt <<<"$OUT")
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$T1" \
    || fail "F32(f): status loop start must write ISO timestamp, got '$T1'"
  [ "$(jget data.changed <<<"$OUT")" = "true" ] || fail "F32(f): first start must report changed: $OUT"
  [ "$(jget data.loopStartedAt <<<"$(hvj status loop show)")" = "$T1" ] \
    || fail "F32(f): status loop show must return the stamp start wrote"
  # idempotent first-write: a second start must not overwrite
  sleep 1
  OUT=$(hvj status loop start)
  [ "$(jget data.loopStartedAt <<<"$OUT")" = "$T1" ] \
    || fail "F32(f): status loop start must be idempotent first-write (T1='$T1' got: $OUT)"
  [ "$(jget data.changed <<<"$OUT")" = "false" ] || fail "F32(f): repeat start must report changed=false: $OUT"
  # active array preserved
  python3 -c 'import json; d = json.load(open(".hv/status.json")); assert d["active"] == [] and d["loopStartedAt"]' \
    || fail "F32(f): status loop must preserve the active array"
  # clear removes
  OUT=$(hvj status loop clear)
  [ "$(jget data.changed <<<"$OUT")" = "true" ] || fail "F32(f): clear of a set stamp must report changed: $OUT"
  [ "$(jget data.loopStartedAt <<<"$(hvj status loop show)")" = "null" ] \
    || fail "F32(f): status loop clear must remove loopStartedAt"
  [ "$(jget data.changed <<<"$(hvj status loop clear)")" = "false" ] \
    || fail "F32(f): clear of an unset stamp must report changed=false"
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$F32_TMP"
pass "F32(f): status loop start/clear/show"

# (g) decisions auto-log: writes placeholder template + footer; idempotent on (topic, rule-title).
F32_TMP="$(mktemp -d)"
trap 'rm -rf "$F32_TMP"' EXIT
(
  cd "$F32_TMP" && mkdir .hv
  echo "# Decisions" > .hv/DECISIONS.md
  echo "" >> .hv/DECISIONS.md
  OUT=$(hvj decisions auto-log --topic "Test Topic" --title "Test rule" --why "Because reasons" \
    --plan-key "M04-F32" --date "2026-05-09")
  [ "$(jget data.changed <<<"$OUT")" = "true" ] || fail "F32(g): first auto-log must report changed: $OUT"
  [ "$(jget data.topic <<<"$OUT")" = "Test Topic" ] || fail "F32(g): data.topic missing: $OUT"
  [ "$(jget data.title <<<"$OUT")" = "Test rule" ] || fail "F32(g): data.title missing: $OUT"
  grep -q '## Test Topic' .hv/DECISIONS.md \
    || fail "F32(g): topic header missing"
  grep -q '### Test rule' .hv/DECISIONS.md \
    || fail "F32(g): rule heading missing"
  grep -q '_(Unresolved — user must articulate)_' .hv/DECISIONS.md \
    || fail "F32(g): placeholder Forbids/Permits missing"
  grep -q '\[Auto:Loop\] M04-F32 2026-05-09' .hv/DECISIONS.md \
    || fail "F32(g): provenance footer missing or malformed"
  # idempotent — second run must not duplicate the entry
  OUT=$(hvj decisions auto-log --topic "Test Topic" --title "Test rule" --why "Because reasons" \
    --plan-key "M04-F32" --date "2026-05-09")
  [ "$(jget data.changed <<<"$OUT")" = "false" ] || fail "F32(g): repeat auto-log must report changed=false: $OUT"
  COUNT=$(grep -c '### Test rule' .hv/DECISIONS.md)
  [ "$COUNT" = "1" ] || fail "F32(g): decisions auto-log must be idempotent on (topic, rule-title), got $COUNT entries"
  # required flags: missing --why is a usage error
  rc=0; hvj decisions auto-log --topic "T" --title "R" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "F32(g): auto-log without --why must exit 2, got $rc"
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$F32_TMP"
pass "F32(g): decisions auto-log placeholder template + idempotent"

# (h) decisions auto-since: filters by loopStartedAt date; empty when no loop.
F32_TMP="$(mktemp -d)"
trap 'rm -rf "$F32_TMP"' EXIT
(
  cd "$F32_TMP" && mkdir .hv
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
  OUT=$(hvj decisions auto-since)
  [ "$(jget data.since <<<"$OUT")" = "2026-05-09T00:00:00Z" ] || fail "F32(h): data.since missing: $OUT"
  [ "$(jget data.decisions <<<"$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" = "1" ] \
    || fail "F32(h): only the post-loopStart entry must remain: $OUT"
  [ "$(jget 'data.decisions[0].title' <<<"$OUT")" = "In-loop rule" ] \
    || fail "F32(h): post-loopStart entry missing from output: $OUT"
  [ "$(jget 'data.decisions[0].topic' <<<"$OUT")" = "Topic A" ] || fail "F32(h): topic wrong: $OUT"
  [ "$(jget 'data.decisions[0].date' <<<"$OUT")" = "2026-05-09" ] || fail "F32(h): date wrong: $OUT"
  [ "$(jget 'data.decisions[0].status' <<<"$OUT")" = "unresolved" ] \
    || fail "F32(h): unresolved status missing: $OUT"
  # no loop: decisions is empty and since is absent
  echo '{"active": []}' > .hv/status.json
  OUT=$(hvj decisions auto-since)
  [ "$(jget data.decisions <<<"$OUT")" = "[]" ] || fail "F32(h): empty when loopStartedAt unset, got '$OUT'"
  jget data.since <<<"$OUT" >/dev/null && fail "F32(h): since must be absent without a loop: $OUT"
  true
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$F32_TMP"
pass "F32(h): decisions auto-since filter + lookup-empty"

# --- hvlib: parse_frontmatter & iter_map_entries -------------------
mkdir -p .hv/map
cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into BACKLOG.md
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

# white-box-begin: go-unit A3 #47
PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import parse_frontmatter, iter_map_entries
fm, body = parse_frontmatter(open(".hv/map/capture.md").read())
assert fm["subsystem"] == "capture", fm
assert fm["summary"] == "Captures items into BACKLOG.md", fm
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
# white-box-end

# --- map query -----------------------------------------------------
out="$(hvj map query capture | jget data.text)"
[[ "$out" == *"## Purpose"* ]] || { echo "FAIL: map query body missing"; exit 1; }
out="$(hvj map query capture plan | jget data.text)"
[[ "$out" == *"## Purpose"* && "$out" == *"body"* ]] || { echo "FAIL: map query multi"; exit 1; }
out="$(hvj map query nonexistent | jget data.text)"
[[ -z "$out" ]] || { echo "FAIL: map query missing should be empty, got: $out"; exit 1; }
rc=0; hvj map query >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: map query with no name must exit 2, got $rc"; exit 1; }
echo "ok map query"

# --- map stats -----------------------------------------------------
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
hvj map stats | python3 -c '
import json, sys
data = json.load(sys.stdin)["data"]
names = [s["name"] for s in data["subsystems"]]
assert "capture" in names, names
assert data["count"] == len(data["subsystems"]), data
work = next(s for s in data["subsystems"] if s["name"] == "work")
# work has 1 broken ref out of 2 entry points
assert work["brokenRefs"] == 1, work
assert work["entryPoints"] == 2, work
assert work["touched"] == "2026-05-09", work
assert "cap" not in data, data
' || { echo "FAIL: map stats shape"; exit 1; }
# --cap adds the advisory fields and never fails
hvj map stats --cap | python3 -c '
import json, sys
data = json.load(sys.stdin)["data"]
assert data["cap"] == 20 and data["overCap"] is False, data
' || { echo "FAIL: map stats --cap shape"; exit 1; }
echo "ok map stats"

# --- map index -----------------------------------------------------
[ -f CLAUDE.md ] || : > CLAUDE.md
OUT="$(hvj map index)"
[ "$(jget data.key <<<"$OUT")" = "map" ] || { echo "FAIL: map index data.key: $OUT"; exit 1; }
[ "$(jget data.changed <<<"$OUT")" = "true" ] || { echo "FAIL: first map index must report changed: $OUT"; exit 1; }
grep -q '<!-- hv-map-start -->' CLAUDE.md || { echo "FAIL: map block not in CLAUDE.md"; exit 1; }
grep -q '## Project Map' CLAUDE.md || { echo "FAIL: heading missing"; exit 1; }
grep -q '\*\*capture\*\* — Captures items into BACKLOG.md' CLAUDE.md || { echo "FAIL: capture summary missing"; exit 1; }
# Idempotence
sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
OUT="$(hvj map index)"
sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
[ "$sha1" = "$sha2" ] || { echo "FAIL: map index not idempotent"; exit 1; }
[ "$(jget data.status <<<"$OUT")" = "unchanged" ] || { echo "FAIL: repeat map index must be unchanged: $OUT"; exit 1; }
[ "$(jget data.changed <<<"$OUT")" = "false" ] || { echo "FAIL: repeat map index must report changed=false: $OUT"; exit 1; }
# Empty case: hide the block when .hv/map/ has no valid entries
mv .hv/map .hv/map.bak
mkdir .hv/map
hvj map index >/dev/null
grep -q '_(no subsystems yet' CLAUDE.md || { echo "FAIL: empty placeholder missing"; exit 1; }
mv .hv/map .hv/map.empty
mv .hv/map.bak .hv/map
echo "ok map index"

# --- backlog stale -------------------------------------------------
# Plan (touched 2026-04-01) is older than 30 days from "today=2026-05-09";
# work is touched 2026-05-09 and should not be flagged at days=30.
out="$(HV_TEST_TODAY=2026-05-09 hvj backlog stale --kind map --days 30 | jget data.entries)"
grep -q '"name":"plan"' <<<"$out" || { echo "FAIL: plan should be stale"; exit 1; }
if grep -q '"name":"work"' <<<"$out"; then echo "FAIL: work should NOT be stale"; exit 1; fi
# days=0 lists all
HV_TEST_TODAY=2026-05-09 hvj backlog stale --kind map --days 0 | jget 'data.entries[1].name' >/dev/null \
  || { echo "FAIL: days=0 should list all"; exit 1; }
# Nothing is stale when the window is huge (what hv-stale-summary reported as silence)
out="$(HV_TEST_TODAY=2026-05-09 hvj backlog stale --kind map --days 999999 | jget data.entries)"
[ "$out" = "[]" ] || { echo "FAIL: backlog stale should be empty when nothing is stale (got: $out)"; exit 1; }
# Knowledge: KNOWLEDGE.md exists from bootstrap-style fixture; should not error
hvj backlog stale --kind knowledge --days 0 >/dev/null
echo "ok backlog stale"

# --- init seeds map ------------------------------------------------
TMP2=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP2"' EXIT
(
  cd "$TMP2" && git init -q
  "$HV_BIN" init >/dev/null
  [ -d .hv/map ] || { echo "FAIL: .hv/map not created"; exit 1; }
  [ -f .hv/MAP.md ] || { echo "FAIL: .hv/MAP.md not seeded"; exit 1; }
  grep -q "Project map" .hv/MAP.md || { echo "FAIL: .hv/MAP.md content missing"; exit 1; }
)
echo "ok init seeds map"

# --- skill touchpoints reference map ------------------------------
# white-box-begin: A9 #53 doclint
grep -q "hv-map-cap-check\|hv-map-index" "$REPO/hv-work/SKILL.md" || { echo "FAIL: hv-work has no map touchpoint"; exit 1; }
grep -q "hv-map-cap-check\|hv-map-index" "$REPO/hv-debug/SKILL.md" || { echo "FAIL: hv-debug has no map touchpoint"; exit 1; }
grep -q "post-cycle map\|hv-map-index" "$REPO/hv-go/SKILL.md" || { echo "FAIL: hv-go has no map touchpoint"; exit 1; }
echo "ok skill touchpoints (work/debug/go)"
# white-box-end

# --- status/next/resume reference hv-stale-summary ---------------
# Note: hv-status and hv-resume were merged into hv-next (F26).
# hv-next now uses bin/hv-stale-summary as a single wrapper (F48).
# white-box-begin: A9 #53 doclint
grep -q "hv-stale-summary" "$REPO/hv-next/SKILL.md"        || { echo "FAIL: hv-next missing stale-summary call"; exit 1; }
grep -q "Subsystem:" "$REPO/hv-capture/SKILL.md"           || { echo "FAIL: hv-capture missing Subsystem field"; exit 1; }
echo "ok status/next/resume/capture touchpoints"
# white-box-end

# --- end-to-end: scaffold + after-work bump + consolidate prep ----
TMP3=$(mktemp -d)
trap 'rm -rf "$TMP3" "$TMP" "$TMP2"' EXIT
(
  cd "$TMP3" && git init -q
  git config user.email test@example.com
  git config user.name Test
  "$HV_BIN" init >/dev/null
  : > CLAUDE.md
  cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into BACKLOG.md
touched: 2026-05-09
created: 2026-05-09
---

## Purpose
Capture flow.

## Entry points
- scripts/bootstrap:1 — broken ref (file does not exist in fixture)
EOF
  cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Captures items into BACKLOG.md  # near-duplicate summary
touched: 2025-12-01
created: 2025-12-01
---

## Purpose
Work flow.
EOF
  hvj map index >/dev/null

  python3 - <<'PY'
from pathlib import Path
p = Path(".hv/map/capture.md")
text = p.read_text().replace("touched: 2026-05-09", "touched: 2026-05-10")
p.write_text(text)
PY
  grep -q "touched: 2026-05-10" .hv/map/capture.md || { echo "FAIL: after-work bump"; exit 1; }

  out="$(HV_TEST_TODAY=2026-05-10 hvj backlog stale --kind map --days 30 | jget data.entries)"
  grep -q '"name":"work"' <<<"$out" || { echo "FAIL: work should be stale at days=30"; exit 1; }

  count=$(hvj map stats | jget data.count)
  [ "$count" = "2" ] || { echo "FAIL: stats count $count != 2"; exit 1; }

  hvj map index >/dev/null
  sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  hvj map index >/dev/null
  sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  [ "$sha1" = "$sha2" ] || { echo "FAIL: integration idempotence"; exit 1; }
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$TMP2" "$TMP3"
echo "ok end-to-end map flow"

# --- parse_todo_fields handles Subsystem ---------------------------
# white-box-begin: go-unit A4 #48
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
# white-box-end

echo "B28: /hv-brainstorm --auto-loop dispatch chain"

# (a) /hv-brainstorm SKILL.md exposes --auto-loop with the inline dispatch language.
# white-box-begin: A9 #53 doclint
grep -q -- '--auto-loop' "$REPO/hv-brainstorm/SKILL.md" \
  || fail "B28: hv-brainstorm/SKILL.md must document the --auto-loop flag"
grep -q '## Auto-loop mode' "$REPO/hv-brainstorm/SKILL.md" \
  || fail "B28: hv-brainstorm/SKILL.md must include the dedicated 'Auto-loop mode' section"
# white-box-end

# (b) /hv-work Step 4 carries the inline loop-mode auto-brainstorm dispatch directive.
# white-box-begin: A9 #53 doclint
grep -q '/hv-brainstorm --auto-loop' "$REPO/hv-work/SKILL.md" \
  || fail "B28: hv-work/SKILL.md must reference /hv-brainstorm --auto-loop dispatch"
grep -q 'Loop-mode auto-dispatch chain' "$REPO/hv-work/SKILL.md" \
  || fail "B28: hv-work/SKILL.md must title Step 4 chain as 'Loop-mode auto-dispatch chain'"
# white-box-end

# (c) /hv-work Step 2 carve-out for Major + Milestone-tagged items defers to Step 4 chain.
# white-box-begin: A9 #53 doclint
grep -q 'defer to Step 4' "$REPO/hv-work/SKILL.md" \
  || fail "B28: hv-work/SKILL.md Step 2 must defer Major + Milestone-tagged ambiguity to Step 4 chain"
# white-box-end

# (d) references/loop-mode-plan-dispatch.md describes the design pre-flight.
# white-box-begin: A9 #53 doclint
grep -q 'Design pre-flight' "$REPO/references/loop-mode-plan-dispatch.md" \
  || fail "B28: references/loop-mode-plan-dispatch.md must include the Design pre-flight section"

pass "B28: /hv-brainstorm --auto-loop dispatch chain is wired across SKILL.md + reference"
# white-box-end
