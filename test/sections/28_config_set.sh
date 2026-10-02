echo "config set"

CFG_TMP=$(mktemp -d)
trap 'rm -rf "$CFG_TMP"' EXIT
(
  cd "$CFG_TMP"
  mkdir -p .hv

  # --- Fresh config: nested key, boolean JSON value ---
  echo '{}' > .hv/config.json
  OUT=$(hvj config set ship.review true) || { echo "FAIL: simple set"; exit 1; }
  [ "$(echo "$OUT" | jget data.changed)" = "true" ] || { echo "FAIL: first set should report changed: $OUT"; exit 1; }
  [ "$(echo "$OUT" | jget data.value)" = "true" ] || { echo "FAIL: set should echo the stored value: $OUT"; exit 1; }
  echo "$OUT" | jget data.previous >/dev/null && { echo "FAIL: previous must be absent for an unset key: $OUT"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d == {'ship':{'review':True}}, d" || { echo "FAIL: ship.review true"; exit 1; }

  # --- Nested dotted path (creates intermediate dicts) ---
  hvj config set models.orchestrator opus >/dev/null || { echo "FAIL: nested set"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['models']['orchestrator']=='opus', d" || { echo "FAIL: nested models.orchestrator"; exit 1; }

  # --- Idempotency: set same value twice, file unchanged, changed false ---
  before=$(cat .hv/config.json)
  OUT=$(hvj config set models.orchestrator opus) || { echo "FAIL: re-set"; exit 1; }
  after=$(cat .hv/config.json)
  [ "$before" = "$after" ] || { echo "FAIL: idempotent re-set changed file"; exit 1; }
  [ "$(echo "$OUT" | jget data.changed)" = "false" ] || { echo "FAIL: idempotent re-set should report changed false: $OUT"; exit 1; }
  [ "$(echo "$OUT" | jget data.previous)" = "opus" ] || { echo "FAIL: re-set should report previous: $OUT"; exit 1; }

  # --- Preserves other keys ---
  hvj config set learn.verify true >/dev/null || { echo "FAIL: add new section"; exit 1; }
  python3 -c "
import json
d = json.load(open('.hv/config.json'))
assert d['ship']['review'] is True, d
assert d['models']['orchestrator'] == 'opus', d
assert d['learn']['verify'] is True, d
" || { echo "FAIL: preservation"; exit 1; }

  # --- JSON value types: number, false, array, string ---
  hvj config set work.workerSlots 42 >/dev/null || { echo "FAIL: number"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['work']['workerSlots'] == 42 and isinstance(d['work']['workerSlots'], int)" || { echo "FAIL: int parsing"; exit 1; }

  OUT=$(hvj config set ship.review false) || { echo "FAIL: false"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['ship']['review'] is False" || { echo "FAIL: false parsing"; exit 1; }
  [ "$(echo "$OUT" | jget data.previous)" = "true" ] || { echo "FAIL: false should report previous true: $OUT"; exit 1; }

  hvj config set work.accounts '["a","b"]' >/dev/null || { echo "FAIL: array"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['work']['accounts'] == ['a','b'], d" || { echo "FAIL: array parsing"; exit 1; }

  # --- Bare identifier falls back to string ---
  hvj config set autonomy.level loop >/dev/null || { echo "FAIL: string fallback"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['autonomy']['level'] == 'loop'" || { echo "FAIL: string-loop"; exit 1; }

  # --- A string that looks like JSON needs shell quoting to stay a string ---
  hvj config set work.workerCommand '"true"' >/dev/null || { echo "FAIL: quoted string"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['work']['workerCommand'] == 'true', d" || { echo "FAIL: quoted string value"; exit 1; }

  # --- Empty string is a valid value ---
  hvj config set work.workerCommand '' >/dev/null || { echo "FAIL: empty value"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d['work']['workerCommand'] == '', d" || { echo "FAIL: empty value stored"; exit 1; }

  # --- Bad inputs exit 2 and leave the file alone ---
  before=$(cat .hv/config.json)
  rc=0; "$HV_BIN" config set >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: missing args should exit 2, got $rc"; exit 1; }
  rc=0; "$HV_BIN" config set ship.review >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: missing value should exit 2, got $rc"; exit 1; }
  rc=0; "$HV_BIN" config set "" "x" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: empty key should exit 2, got $rc"; exit 1; }
  rc=0; "$HV_BIN" config set ".foo" "x" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: leading dot should exit 2, got $rc"; exit 1; }
  rc=0; "$HV_BIN" config set "foo." "x" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: trailing dot should exit 2, got $rc"; exit 1; }
  # A key outside the schema is rejected (maintainer decision; old accepted any key).
  rc=0; "$HV_BIN" config set version 17 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: key outside the schema should exit 2, got $rc"; exit 1; }
  rc=0; "$HV_BIN" config set no.such.key 1 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: unknown dotted key should exit 2, got $rc"; exit 1; }
  [ "$before" = "$(cat .hv/config.json)" ] || { echo "FAIL: rejected sets changed the file"; exit 1; }

  # --- Missing config.json: verb creates it ---
  rm -f .hv/config.json
  hvj config set autonomy.level loop >/dev/null || { echo "FAIL: missing file"; exit 1; }
  python3 -c "import json; d=json.load(open('.hv/config.json')); assert d == {'autonomy':{'level':'loop'}}" || { echo "FAIL: missing file content"; exit 1; }

  # --- A config that is not a JSON object is an internal error (70), file untouched ---
  echo '[1]' > .hv/config.json
  rc=0; "$HV_BIN" config set autonomy.level loop >/dev/null 2>&1 || rc=$?
  [ "$rc" = 70 ] || { echo "FAIL: non-object config should exit 70, got $rc"; exit 1; }
  [ "$(cat .hv/config.json)" = "[1]" ] || { echo "FAIL: non-object config was rewritten"; exit 1; }
) || fail "config set assertions"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$CFG_TMP"
pass "config set nested / idempotent / typed values / preservation / errors / autocreate"

echo "hv-ship (Docs Mode) / hv-config / hv-init reference hv-config-set"
# white-box-begin: A9 #53 doclint
grep -q "hv-config-set" "$REPO/hv-ship/SKILL.md"   || fail "hv-ship Docs Mode missing hv-config-set call"
grep -q "hv-config-set" "$REPO/hv-config/SKILL.md" || fail "hv-config missing hv-config-set call"
grep -q "hv-config-set" "$REPO/hv-init/SKILL.md"   || fail "hv-init missing hv-config-set call"
pass "hv-ship Docs Mode, hv-config, hv-init all reference the new helper"
# white-box-end

echo "F09: hv-ship --docs manual entry routes to after-work flow with gate bypass"
# white-box-begin: A9 #53 doclint
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
# white-box-end

echo "hv-config positional-args invocation shapes"
# white-box-begin: A9 #53 doclint
grep -q '## Step 1.5 — Parse Positional Arguments' "$REPO/hv-config/SKILL.md" || fail "hv-config missing Step 1.5"
grep -qE 'work\.isolation=worktree|<key>=<value>' "$REPO/hv-config/SKILL.md" || fail "hv-config Step 1.5 missing positional-args syntax doc"
grep -q 'models.orchestrator' "$REPO/hv-config/SKILL.md" || fail "hv-config Step 1.5 missing canonical key list"
# Each canonical key should appear in Step 1.5's enumeration (12 base + the models pair = 14 keys)
for key in models.orchestrator models.worker work.isolation work.mergeStrategy ship.review learn.verify refactor.confirmBeforeExecute debug.competingHypotheses autonomy.level docs.path docs.autoCreate docs.afterWork git.baseBranch umbrella.enabled; do
  grep -q "\`$key\`" "$REPO/hv-config/SKILL.md" || fail "hv-config Step 1.5 missing key: $key"
done
pass "hv-config Step 1.5 documents all 14 canonical keys with positional-args syntax"
# white-box-end

echo "F78: work.dispatch / workerSlots / workerCommand are registered everywhere"
# A config key that is only half-registered fails silently: hv-config rejects it
# as unknown, or /hv-init never backfills it on an upgrade. Pin the skill and doc sites.
# (The CONFIG_KEYS table row is also covered by `config show` / `config check` below.)
# white-box-begin: A9 #53 keep
for key in work.dispatch work.workerSlots work.workerCommand; do
  grep -q "\`$key\`" "$REPO/hv-config/SKILL.md" \
    || fail "F78: hv-config Step 1.5 valid-key list missing $key"
  grep -q "$key" "$REPO/hv-init/SKILL.md" \
    || fail "F78: hv-init does not seed $key"
  grep -q "$key" "$REPO/docs/reference/config-options.md" \
    || fail "F78: config-options.md does not document $key"
done
grep -q '("work.dispatch", "subagent", True)' "$REPO/bin/hvlib_config.py" \
  || fail "F78: hvlib_config CONFIG_KEYS missing work.dispatch"
grep -q 'work.dispatch.*subagent.*tmux\|`work.dispatch` accepts' "$REPO/hv-config/SKILL.md" \
  || fail "F78: hv-config validation rules do not constrain work.dispatch to its enum"
grep -q 'work.dispatch' "$REPO/docs/usage/configuration.md" \
  || fail "F78: usage/configuration.md does not explain work.dispatch"
pass "F78: work.dispatch + workerSlots + workerCommand registered in the skill and doc sites"
# white-box-end

echo "F78: config check reports the new keys stale on an older config"
CFG_F78="$(mktemp -d)"
trap 'rm -rf "$CFG_F78"' EXIT
mkdir -p "$CFG_F78/.hv"
python3 - "$CFG_F78/.hv/config.json" <<'PYEOF'
import json, sys
# A pre-F78 config: complete for its era, missing only the new work.* keys.
json.dump({
    "models": {"orchestrator": "opus", "worker": "sonnet"},
    "work": {"isolation": "branch", "mergeStrategy": "direct"},
    "refactor": {"confirmBeforeExecute": True, "verifyCommands": []},
    "learn": {"verify": True, "promoteThreshold": 3},
    "ship": {"review": True, "secondOpinion": False, "qa": False},
    "qa": {"gate": "advisory", "afterWork": False},
    "autonomy": {"level": "off"},
    "debug": {"competingHypotheses": False},
    "docs": {"path": "docs", "autoCreate": False, "afterWork": False},
    "git": {"baseBranch": ""},
    "umbrella": {"enabled": False},
    "issues": {"providers": {"github": True, "gitlab": True}},
    "hvSkills": {"version": "4.5.0"},
}, open(sys.argv[1], "w"))
PYEOF
rc=0; VERDICT=$( cd "$CFG_F78" && hvj config check 2>/dev/null ) || rc=$?
[ "$rc" = 1 ] || fail "F78: config check on a pre-F78 config should exit 1, got $rc"
[ "$(echo "$VERDICT" | jget data.status)" = "stale" ] \
  || fail "F78: expected stale on a pre-F78 config, got '$VERDICT'"
echo "$VERDICT" | python3 -c '
import json, sys
missing = json.load(sys.stdin)["data"]["missing"]
for want in ("work.dispatch", "work.workerSlots"):
    assert want in missing, (want, missing)
' || fail "F78: stale verdict omits work.dispatch or work.workerSlots: '$VERDICT'"
# A fully populated config is up to date and exits 0.
python3 - "$CFG_F78/.hv/config.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p))
cfg["work"].update({"dispatch": "subagent", "workerSlots": 3, "workerCommand": "",
                    "accounts": [], "operatorCommand": ""})
cfg["ship"]["secondOpinionRunner"] = "subagent"
json.dump(cfg, open(p, "w"))
PYEOF
rc=0; VERDICT=$( cd "$CFG_F78" && hvj config check 2>/dev/null ) || rc=$?
[ "$rc" = 0 ] || fail "F78: config check on a complete config should exit 0, got $rc: $VERDICT"
[ "$(echo "$VERDICT" | jget data.upToDate)" = "true" ] || fail "F78: expected upToDate: $VERDICT"
# No config.json at all is fresh, and a broken one is corrupt; both exit 1.
rm "$CFG_F78/.hv/config.json"
rc=0; VERDICT=$( cd "$CFG_F78" && hvj config check 2>/dev/null ) || rc=$?
[ "$rc" = 1 ] && [ "$(echo "$VERDICT" | jget data.status)" = "fresh" ] \
  || fail "F78: a missing config should be fresh (exit 1), got $rc: $VERDICT"
echo '{not json' > "$CFG_F78/.hv/config.json"
rc=0; VERDICT=$( cd "$CFG_F78" && hvj config check 2>/dev/null ) || rc=$?
[ "$rc" = 1 ] && [ "$(echo "$VERDICT" | jget data.status)" = "corrupt" ] \
  || fail "F78: an unparseable config should be corrupt (exit 1), got $rc: $VERDICT"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$CFG_F78"
pass "F78: pre-F78 configs report stale so /hv-init backfills the new keys"

echo "hv-config positional-args mentioned in docs + README"
# white-box-begin: A9 #53 doclint
grep -q 'positional' "$REPO/docs/reference/config-options.md" || fail "config-options.md missing positional-args mention"
grep -q 'positional\|<key>=<value>' "$REPO/docs/usage/configuration.md" || fail "configuration.md missing positional-args mention"
grep -q '/hv-config <key>' "$REPO/README.md" || fail "README.md missing /hv-config <key> shortcut"
pass "hv-config positional-args documented in docs + README"
# white-box-end
