echo "F24 hv-preamble.sh — single-line preamble source"

# white-box-begin: A9 #53 keep
# Install canonical helpers at .hv/bin/ so walk-up from BASH_SOURCE lands
# on the test umbrella's .hv/, not the dev tree's.
mkdir -p .hv/bin
install_helpers

# Sanity — the new helper landed via the canonical mirror.
[ -f .hv/bin/hv-preamble.sh ] || fail "F24: bin/hv-preamble.sh missing from installed helpers"
pass "hv-preamble.sh installs under .hv/bin/ via canonical mirror"

# Fast-path: cwd already contains .hv/. Sourcing hv-preamble.sh must
# preserve cwd, export HERE pointing at bin/, and capture HV_ORIG_PWD.
(
  cd "$TMP"
  before_pwd="$(pwd -P)"
  # shellcheck source=/dev/null
  . .hv/bin/hv-preamble.sh
  [ "$(pwd -P)" = "$before_pwd" ] || { echo "FAIL: fast-path cd'd away from cwd ($(pwd -P) vs $before_pwd)"; exit 1; }
  [ -n "$HERE" ] && [ -d "$HERE" ] || { echo "FAIL: HERE unset or not a dir: '$HERE'"; exit 1; }
  [ -f "$HERE/hv-self-locate.sh" ] || { echo "FAIL: HERE does not point at bin/: '$HERE'"; exit 1; }
  [ "$HV_ORIG_PWD" = "$before_pwd" ] || { echo "FAIL: HV_ORIG_PWD mismatch: '$HV_ORIG_PWD' vs '$before_pwd'"; exit 1; }
)
pass "hv-preamble.sh fast-path — cwd preserved, HERE and HV_ORIG_PWD exported"

# Walk-up path: a verb run from a sub-cwd that lacks .hv/ must resolve the
# enclosing project's .hv/, not the cwd's and not the dev tree's.
WALKUP_TMP="$(mktemp -d)"
trap 'rm -rf "$WALKUP_TMP"' EXIT
mkdir -p "$WALKUP_TMP/.hv" "$WALKUP_TMP/walkup-sub/deep"
printf '{"work":{"dispatch":"tmux"}}\n' > "$WALKUP_TMP/.hv/config.json"
for d in "$WALKUP_TMP" "$WALKUP_TMP/walkup-sub" "$WALKUP_TMP/walkup-sub/deep"; do
  OUT=$(cd "$d" && hvj config show work.dispatch) || fail "walk-up: config show failed from $d: $OUT"
  [ "$(echo "$OUT" | jget 'data.entries[0].value')" = "tmux" ] \
    || fail "walk-up: config show from $d did not resolve the project .hv/: $OUT"
  [ "$(echo "$OUT" | jget 'data.entries[0].source')" = "project" ] \
    || fail "walk-up: config show from $d did not read the project config: $OUT"
done
[ ! -d "$WALKUP_TMP/walkup-sub/.hv" ] || fail "walk-up: a verb created .hv/ in the sub-cwd"
# -C acts as if started in that directory, with the same walk-up.
OUT=$(hvj -C "$WALKUP_TMP/walkup-sub/deep" config show work.dispatch) || fail "walk-up: -C failed: $OUT"
[ "$(echo "$OUT" | jget 'data.entries[0].source')" = "project" ] || fail "walk-up: -C did not walk up: $OUT"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$WALKUP_TMP"
pass "verbs walk up from a sub-cwd to the project's .hv/ (also with -C)"

# hv-self-locate.sh stays a pure library — sourcing it alone must NOT
# auto-invoke hv_self_locate (preserves the "sourceable files define,
# don't run" convention that hv-preamble.sh is the explicit exception to).
(
  cd "$TMP"
  before_pwd="$(pwd -P)"
  # Clear HV_ORIG_PWD so we can detect whether sourcing alone sets it.
  unset HV_ORIG_PWD
  # shellcheck source=/dev/null
  . .hv/bin/hv-self-locate.sh
  [ "${HV_ORIG_PWD-unset}" = "unset" ] || { echo "FAIL: hv-self-locate.sh auto-invoked on source (HV_ORIG_PWD=$HV_ORIG_PWD)"; exit 1; }
  [ "$(pwd -P)" = "$before_pwd" ] || { echo "FAIL: hv-self-locate.sh cd'd on source"; exit 1; }
  # Calling the function explicitly must still work.
  hv_self_locate
  [ -n "${HV_ORIG_PWD-}" ] || { echo "FAIL: hv_self_locate didn't set HV_ORIG_PWD when called explicitly"; exit 1; }
)
pass "hv-self-locate.sh stays library-shaped — no auto-invocation on source"

rm -rf .hv/bin
# white-box-end
