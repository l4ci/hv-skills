echo "hv-config-set resolve helper"

CFG_TMP=$(mktemp -d)
trap 'rm -rf "$CFG_TMP"' EXIT
(
  cd "$CFG_TMP"
  mkdir -p .hv

  # --- Fresh config: top-level scalar (boolean JSON value) ---
  echo '{}' > .hv/config.json
  "$BIN/hv-config-set" ship.review true || { echo "FAIL: simple set"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d == {'ship':{'review':True}}, d" || { echo "FAIL: ship.review true"; exit 1; }

  # --- Nested dotted path (creates intermediate dicts) ---
  "$BIN/hv-config-set" models.orchestrator opus || { echo "FAIL: nested set"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['models']['orchestrator']=='opus', d" || { echo "FAIL: nested models.orchestrator"; exit 1; }

  # --- Idempotency: set same value twice, result unchanged ---
  before=$(cat .hv/config.json)
  "$BIN/hv-config-set" models.orchestrator opus || { echo "FAIL: re-set"; exit 1; }
  after=$(cat .hv/config.json)
  [ "$before" = "$after" ] || { echo "FAIL: idempotent re-set changed file"; exit 1; }

  # --- Preserves other keys ---
  "$BIN/hv-config-set" learn.verify true || { echo "FAIL: add new section"; exit 1; }
  python3 -c "
import json
d = json.load(open('.hv/config.json'))
assert d['ship']['review'] is True, d
assert d['models']['orchestrator'] == 'opus', d
assert d['learn']['verify'] is True, d
" || { echo "FAIL: preservation"; exit 1; }

  # --- JSON value types: number, false, string ---
  "$BIN/hv-config-set" counters.bugs 42 || { echo "FAIL: number"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['counters']['bugs'] == 42 and isinstance(d['counters']['bugs'], int)" || { echo "FAIL: int parsing"; exit 1; }

  "$BIN/hv-config-set" ship.review false || { echo "FAIL: false"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['ship']['review'] is False" || { echo "FAIL: false parsing"; exit 1; }

  # --- Bare identifier falls back to string ---
  "$BIN/hv-config-set" autonomy.level loop || { echo "FAIL: string fallback"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['autonomy']['level'] == 'loop'" || { echo "FAIL: string-loop"; exit 1; }

  # --- Top-level key (no nesting) ---
  "$BIN/hv-config-set" version 17 || { echo "FAIL: top-level"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['version'] == 17" || { echo "FAIL: top-level scalar"; exit 1; }

  # --- Bad inputs ---
  if "$BIN/hv-config-set" 2>/dev/null; then
    echo "FAIL: missing args should exit 1"; exit 1
  fi
  if "$BIN/hv-config-set" "" "x" 2>/dev/null; then
    echo "FAIL: empty key should exit 1"; exit 1
  fi
  if "$BIN/hv-config-set" ".foo" "x" 2>/dev/null; then
    echo "FAIL: leading dot should exit 1"; exit 1
  fi
  if "$BIN/hv-config-set" "foo." "x" 2>/dev/null; then
    echo "FAIL: trailing dot should exit 1"; exit 1
  fi

  # --- Missing config.json: helper creates it ---
  rm -f .hv/config.json
  "$BIN/hv-config-set" autonomy.level loop || { echo "FAIL: missing file"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d == {'autonomy':{'level':'loop'}}" || { echo "FAIL: missing file content"; exit 1; }
) || fail "hv-config-set assertions"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$CFG_TMP"
pass "hv-config-set top-level / nested / idempotent / typed values / preservation / errors / autocreate"

echo "hv-ship (Docs Mode) / hv-config / hv-init reference hv-config-set"
grep -q "hv-config-set" "$REPO/hv-ship/SKILL.md"   || fail "hv-ship Docs Mode missing hv-config-set call"
grep -q "hv-config-set" "$REPO/hv-config/SKILL.md" || fail "hv-config missing hv-config-set call"
grep -q "hv-config-set" "$REPO/hv-init/SKILL.md"   || fail "hv-init missing hv-config-set call"
pass "hv-ship Docs Mode, hv-config, hv-init all reference the new helper"

echo "F09: hv-ship --docs manual entry routes to after-work flow with gate bypass"
grep -E '\| Manual invoke.*after-work.*manual mode' "$REPO/hv-ship/SKILL.md" >/dev/null \
  || fail "F09: hv-ship Docs Mode Modes row for manual invocation doesn't reflect after-work in manual mode"
grep -q "Route to the After-work sub-flow" "$REPO/hv-ship/SKILL.md" \
  || fail "F09: hv-ship Docs Mode Step D1 'Already true' branch doesn't route to after-work sub-flow"
grep -q "Manual entry bypasses the gate" "$REPO/hv-ship/SKILL.md" \
  || fail "F09: hv-ship Docs Mode Step D-A1 missing manual-entry bypass clause"
# Old no-op text must not survive
if grep -q "Re-running .*hv-docs.* manually has no further effect" "$REPO/hv-ship/SKILL.md"; then
  fail "F09: stale 'no further effect' no-op text still present in hv-ship/SKILL.md Docs Mode"
fi
pass "F09: hv-ship --docs manual entry routes to after-work flow with gate bypass"

echo "hv-config positional-args invocation shapes"
grep -q '## Step 1.5 — Parse Positional Arguments' "$REPO/hv-config/SKILL.md" || fail "hv-config missing Step 1.5"
grep -qE 'work\.isolation=worktree|<key>=<value>' "$REPO/hv-config/SKILL.md" || fail "hv-config Step 1.5 missing positional-args syntax doc"
grep -q 'models.orchestrator' "$REPO/hv-config/SKILL.md" || fail "hv-config Step 1.5 missing canonical key list"
# Each canonical key should appear in Step 1.5's enumeration (12 base + the models pair = 14 keys)
for key in models.orchestrator models.worker work.isolation work.mergeStrategy ship.review learn.verify refactor.confirmBeforeExecute debug.competingHypotheses autonomy.level docs.path docs.autoCreate docs.afterWork git.baseBranch umbrella.enabled; do
  grep -q "\`$key\`" "$REPO/hv-config/SKILL.md" || fail "hv-config Step 1.5 missing key: $key"
done
pass "hv-config Step 1.5 documents all 14 canonical keys with positional-args syntax"

echo "hv-config positional-args mentioned in docs + README"
grep -q 'positional' "$REPO/docs/reference/config-options.md" || fail "config-options.md missing positional-args mention"
grep -q 'positional\|<key>=<value>' "$REPO/docs/usage/configuration.md" || fail "configuration.md missing positional-args mention"
grep -q '/hv-config <key>' "$REPO/README.md" || fail "README.md missing /hv-config <key> shortcut"
pass "hv-config positional-args documented in docs + README"
