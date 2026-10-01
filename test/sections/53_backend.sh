echo "backlog.backend config keys and accessors"

TMP_BK="$(mktemp -d)"
trap 'rm -rf "$TMP_BK"' EXIT
mkdir -p "$TMP_BK/proj/.hv"
(
  cd "$TMP_BK/proj"
  out="$("$BIN/hv-config-show" backlog.backend)"
  [ "$out" = 'backlog.backend = "file"  (source: default)' ] || fail "default backlog.backend: got '$out'"
  echo '{"backlog":{"backend":"issues"}}' > .hv/config.json
  out="$("$BIN/hv-config-show" backlog.backend)"
  [ "$out" = 'backlog.backend = "issues"  (source: project)' ] || fail "project backlog.backend: got '$out'"
  echo '{"backlog":{"backend":"file"}}' > .hv/config.local.json
  out="$("$BIN/hv-config-show" backlog.backend)"
  [ "$out" = 'backlog.backend = "file"  (source: local)' ] || fail "local backlog.backend: got '$out'"
  pass "hv-config-show reports backlog.backend default/project/local"

  PYTHONPATH="$BIN" python3 - <<'PY' || fail "backend accessors"
from hvlib import config_value, backlog_backend, tracker_label, BACKLOG_BACKENDS
assert BACKLOG_BACKENDS == ("file", "issues")
assert backlog_backend({}) == "file"
assert backlog_backend({"backlog": {"backend": "issues"}}) == "issues"
try:
    backlog_backend({"backlog": {"backend": "bogus"}})
    raise SystemExit("bogus backend accepted")
except ValueError:
    pass
assert tracker_label({}, "inProgress") == "in-progress"
assert tracker_label({"issues": {"label": "wip"}}, "inProgress") == "wip"
assert tracker_label({"issues": {"label": "wip", "labels": {"inProgress": "doing"}}}, "inProgress") == "doing"
assert tracker_label({"issues": {"label": "wip"}}, "needsReview") == "needs-review"
assert tracker_label({}, "types.bug") == "type:bug"
try:
    config_value({}, "nope")
    raise SystemExit("unknown key accepted")
except KeyError:
    pass
PY
  pass "backlog_backend / tracker_label / config_value behave"
)
trap 'rm -rf "$TMP"' EXIT
