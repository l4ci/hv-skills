echo "T118: hv-config-show reports value + source layer from one defaults table"

CS="$(mktemp -d)"
trap 'rm -rf "$CS"' EXIT
mkdir -p "$CS/.hv"
printf '{"work":{"dispatch":"tmux"},"autonomy":{"level":"auto"}}\n' > "$CS/.hv/config.json"
printf '{"autonomy":{"level":"loop"}}\n' > "$CS/.hv/config.local.json"

show() { ( cd "$CS" && "$BIN/hv-config-show" "$@" ); }

[ "$(show work.dispatch)" = 'work.dispatch = "tmux"  (source: project)' ] \
  || fail "T118: project value not reported as source project"
[ "$(show autonomy.level)" = 'autonomy.level = "loop"  (source: local)' ] \
  || fail "T118: config.local.json should win and report source local"
[ "$(show ship.secondOpinionRunner)" = 'ship.secondOpinionRunner = "subagent"  (source: default)' ] \
  || fail "T118: unset key should report the default"
[ "$(show work.accounts)" = 'work.accounts = []  (source: default)' ] \
  || fail "T118: array default not printed as JSON"
pass "T118: hv-config-show resolves local > project > default"

N="$(show | wc -l)"
[ "$N" -eq "$(PYTHONPATH="$BIN" python3 -c 'from hvlib import CONFIG_KEYS; print(len(CONFIG_KEYS))')" ] \
  || fail "T118: no-arg output should have one line per known key, got $N"
_grep_in=$(show || true)
grep -q '^work.dispatch = ' <<<"$_grep_in" || fail "T118: no-arg output missing work.dispatch"
RC=0; show no.such.key >/dev/null 2>&1 || RC=$?
[ "$RC" = "1" ] || fail "T118: unknown key should exit 1, got $RC"
pass "T118: no-arg lists every key; unknown key exits 1"

# Schema check derives from the same table: dropping one required key names it.
printf '{}\n' > "$CS/.hv/config.json"
V="$( cd "$CS" && "$BIN/hv-config-schema-check" )"
case "$V" in
  STALE:*work.dispatch*ship.secondOpinionRunner*) : ;;
  *) fail "T118: schema-check on an empty config should be STALE naming table keys, got '$V'" ;;
esac
case "$V" in *release.*|*issues.label*) fail "T118: non-required keys leaked into EXPECTED: $V" ;; esac
pass "T118: hv-config-schema-check EXPECTED derives from CONFIG_KEYS required rows"

trap 'rm -rf "$TMP"' EXIT
