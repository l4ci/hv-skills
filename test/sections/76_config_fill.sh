echo "config fill: missing required keys get schema defaults (A9 G1, G7)"

# config fill has no old helper, so the plain shim answers 71 (no adapter).
# The section needs the Go binary: HV_BIN=test/hv-hybrid or the binary itself.
CF="$(mktemp -d)"
trap 'rm -rf "$CF"' EXIT
mkdir -p "$CF/.hv"
RC=0; ( cd "$CF" && hvj config fill >/dev/null 2>&1 ) || RC=$?
if [ "$RC" = "71" ]; then
  printf '  \033[33mSKIP\033[0m config fill is not served by %s (needs the Go binary)\n' "$HV_BIN"
else
  [ "$RC" = "0" ] || fail "config fill on a project without config.json should exit 0, got $RC"
  [ "$( cd "$CF" && hvj config check | jget data.status )" = "upToDate" ] \
    || fail "config check after fill on a fresh project should be upToDate"

  # The hv init seed (issues-only keys, schema order) filled out stays in schema order.
  printf '{\n  "issues": {\n    "providers": {\n      "github": true,\n      "gitlab": true\n    },\n    "label": "in-progress",\n    "autoCreateLabel": true,\n    "filterMineOnly": false\n  }\n}\n' > "$CF/.hv/config.json"
  OUT=$( cd "$CF" && hvj config fill )
  [ "$(echo "$OUT" | jget data.changed)" = "true" ] || fail "fill on the seed should report changed: $OUT"
  [ "$(echo "$OUT" | jget 'data.filled[0]')" = "models.orchestrator" ] \
    || fail "filled should list keys in schema order: $OUT"
  python3 - "$CF/.hv/config.json" <<'PY' || fail "filled seed is not in schema order"
import json, sys
cfg = json.load(open(sys.argv[1]))
want = ["models", "work", "refactor", "learn", "ship", "qa", "autonomy", "debug", "docs", "git", "umbrella", "issues", "hvSkills"]
assert list(cfg) == want, list(cfg)
assert list(cfg["issues"]) == ["providers", "label", "autoCreateLabel", "filterMineOnly"], list(cfg["issues"])
assert cfg["work"]["isolation"] == "branch" and cfg["work"]["accounts"] == [], cfg["work"]
PY
  pass "config fill completes a fresh and a seeded config in schema order"

  # Present values are kept, a second fill writes nothing.
  ( cd "$CF" && "$HV_BIN" config set models.worker haiku >/dev/null )
  BEFORE="$(cat "$CF/.hv/config.json")"
  OUT=$( cd "$CF" && hvj config fill )
  [ "$(echo "$OUT" | jget data.changed)" = "false" ] || fail "second fill should not change anything: $OUT"
  [ "$(echo "$OUT" | jget data.filled)" = "[]" ] || fail "second fill should fill nothing: $OUT"
  [ "$(cat "$CF/.hv/config.json")" = "$BEFORE" ] || fail "second fill rewrote config.json"

  # A corrupt file is refused (70) and left as it was.
  printf '{oops\n' > "$CF/.hv/config.json"
  RC=0; ( cd "$CF" && hvj config fill >/dev/null 2>&1 ) || RC=$?
  [ "$RC" = "70" ] || fail "fill on a corrupt config should exit 70, got $RC"
  [ "$(cat "$CF/.hv/config.json")" = "{oops" ] || fail "fill touched a corrupt config"
  pass "config fill keeps present keys, is idempotent and refuses a corrupt file"
fi

trap 'rm -rf "$TMP"' EXIT
rm -rf "$CF"
