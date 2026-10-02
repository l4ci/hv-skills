echo "T118: config show reports value + source layer from one defaults table"

CS="$(mktemp -d)"
trap 'rm -rf "$CS"' EXIT
mkdir -p "$CS/.hv"
printf '{"work":{"dispatch":"tmux"},"autonomy":{"level":"auto"}}\n' > "$CS/.hv/config.json"
printf '{"autonomy":{"level":"loop"}}\n' > "$CS/.hv/config.local.json"

# show [<key>…]: run in the fixture project and print the envelope.
show() { ( cd "$CS" && hvj config show "$@" ); }

OUT=$(show work.dispatch)
[ "$(echo "$OUT" | jget 'data.entries[0].value')" = "tmux" ] \
  || fail "T118: project value not reported: $OUT"
[ "$(echo "$OUT" | jget 'data.entries[0].source')" = "project" ] \
  || fail "T118: project value not reported as source project: $OUT"
OUT=$(show autonomy.level)
[ "$(echo "$OUT" | jget 'data.entries[0].value')" = "loop" ] \
  || fail "T118: config.local.json should win: $OUT"
[ "$(echo "$OUT" | jget 'data.entries[0].source')" = "local" ] \
  || fail "T118: config.local.json should report source local: $OUT"
OUT=$(show ship.secondOpinionRunner)
[ "$(echo "$OUT" | jget 'data.entries[0].value')" = "subagent" ] \
  || fail "T118: unset key should report the default: $OUT"
[ "$(echo "$OUT" | jget 'data.entries[0].source')" = "default" ] \
  || fail "T118: unset key should report source default: $OUT"
OUT=$(show work.accounts)
[ "$(echo "$OUT" | jget 'data.entries[0].value')" = "[]" ] \
  || fail "T118: array default not returned as a JSON array: $OUT"
[ "$(echo "$OUT" | jget 'data.entries[0].source')" = "default" ] \
  || fail "T118: array default should report source default: $OUT"
[ "$(echo "$OUT" | jget 'data.entries[0].key')" = "work.accounts" ] \
  || fail "T118: entry should name its key: $OUT"
pass "T118: config show resolves local > project > default"

# white-box: kept until the A3 Go unit test lands (#47), then delete
N="$( cd "$CS" && "$BIN/hv-config-show" | wc -l )"
[ "$N" -eq "$(PYTHONPATH="$BIN" python3 -c 'from hvlib import CONFIG_KEYS; print(len(CONFIG_KEYS))')" ] \
  || fail "T118: no-arg output should have one line per known key, got $N"
OUT=$(show)
N=$(echo "$OUT" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)["data"]["entries"]))')
[ "$N" -gt 1 ] || fail "T118: no-arg output should list every key, got $N"
echo "$OUT" | python3 -c '
import json, sys
keys = [e["key"] for e in json.load(sys.stdin)["data"]["entries"]]
for want in ("work.dispatch", "autonomy.level", "ship.secondOpinionRunner", "work.accounts"):
    assert want in keys, (want, keys)
' || fail "T118: no-arg output missing known keys"
RC=0; show no.such.key >/dev/null 2>&1 || RC=$?
[ "$RC" = "3" ] || fail "T118: unknown key should exit 3, got $RC"
RC=0; show work.dispatch autonomy.level >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "T118: two keys should exit 2, got $RC"
pass "T118: no-arg lists every key; unknown key exits 3; extra key exits 2"

# Schema check derives from the same table: dropping one required key names it.
printf '{}\n' > "$CS/.hv/config.json"
RC=0; V=$( cd "$CS" && hvj config check 2>/dev/null ) || RC=$?
[ "$RC" = "1" ] || fail "T118: config check on an empty config should exit 1, got $RC"
[ "$(echo "$V" | jget data.status)" = "stale" ] \
  || fail "T118: config check on an empty config should be stale: $V"
echo "$V" | python3 -c '
import json, sys
missing = json.load(sys.stdin)["data"]["missing"]
for want in ("work.dispatch", "ship.secondOpinionRunner"):
    assert want in missing, (want, missing)
for k in missing:
    assert not k.startswith("release.") and k != "issues.label", ("non-required key leaked", k)
' || fail "T118: config check missing list should name required table keys, got: $V"
pass "T118: config check names the required keys of the same table"

trap 'rm -rf "$TMP"' EXIT
rm -rf "$CS"
