echo "F24 hv-preamble.sh — single-line preamble source"

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

# Walk-up path: source from a sub-cwd that lacks .hv/. hv_self_locate must
# walk up via hv-walk-up and cd back to the umbrella root.
mkdir -p "$TMP/walkup-sub"
(
  cd "$TMP/walkup-sub"
  before_pwd="$(pwd -P)"
  # shellcheck source=/dev/null
  . "$TMP/.hv/bin/hv-preamble.sh"
  [ "$(pwd -P)" = "$TMP" ] || { echo "FAIL: walk-up didn't cd to umbrella; pwd=$(pwd -P) expected=$TMP"; exit 1; }
  [ "$HV_ORIG_PWD" = "$before_pwd" ] || { echo "FAIL: HV_ORIG_PWD didn't capture pre-cd cwd: '$HV_ORIG_PWD' vs '$before_pwd'"; exit 1; }
  [ -f "$HERE/hv-self-locate.sh" ] || { echo "FAIL: HERE does not point at bin/: '$HERE'"; exit 1; }
)
rm -rf "$TMP/walkup-sub"
pass "hv-preamble.sh walk-up — cd's to umbrella root, HV_ORIG_PWD captures pre-cd cwd"

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
