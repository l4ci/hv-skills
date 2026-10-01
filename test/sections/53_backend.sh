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

echo "FileBackend: create/read helpers byte-identical"

TMP_GB="$(mktemp -d)"
trap 'rm -rf "$TMP_BK" "$TMP_GB"' EXIT
mkdir -p "$TMP_GB/.hv"
(
  cd "$TMP_GB"
  git init -q && git config user.email t@t && git config user.name t
  cat > .hv/BACKLOG.md <<'MD'
# Backlog

## Bugs

- **[B01] [P1] First bug.** Desc one. Related: [F01] Milestone: M01 Since: abc1234
- **[B02] [P0] Second bug.** Desc two. Since: abc1234

## Features

- **[F01] [Major] Big feature.** Needs work. Related: [B01] Milestone: M01, M02 Repos: api, web Subsystem: core Since: abc1234
- **[F02] [Minor] Small feature.** No fields.

## Tasks

- **[T01] Chore.** Do it. Related: [F01]

## Completed

- ~~**[B03] [P1] Done thing.** old desc. Milestone: M01 Since: abc1234~~ Done 2026-01-01 [`abc1234`]
- ~~**[T02] Skipped.** x.~~ Done 2026-01-02 [`def5678`] (dropped: not needed)
MD
  printf '# Archive\n\n- ~~**[B05] [P2] Archived.** old. Related: [B01]~~ Done 2025-12-01 [`1111111`] (blocked: waiting)\n' > .hv/ARCHIVE.md
  echo '{"active":[{"items":["B02"],"branch":"fix/b02","startedAt":"2026-01-01T00:00:00Z"}]}' > .hv/status.json
  git add -A && git commit -qm seed
  cp .hv/BACKLOG.md "$TMP_GB/orig.md"

  eq() { # label, expected, actual
    [ "$2" = "$3" ] || fail "golden $1: expected '$2' got '$3'"
  }

  # hv-todo-field
  eq "field title" "First bug" "$("$BIN/hv-todo-field" B01 title)"
  eq "field milestone" "M01, M02" "$("$BIN/hv-todo-field" F01 milestone)"
  eq "field reason" "dropped" "$("$BIN/hv-todo-field" T02 reason)"
  eq "field note archived" "waiting" "$("$BIN/hv-todo-field" B05 note)"
  eq "field empty" "" "$("$BIN/hv-todo-field" T01 milestone)"
  eq "dump" '{"title": "Big feature", "detail": "", "related": "[B01]", "milestone": "M01, M02", "repos": "api, web", "subsystem": "core", "since": "abc1234", "reason": "", "note": ""}' "$("$BIN/hv-todo-field" --dump F01)"
  eq "dump done" '{"title": "Done thing", "detail": "", "related": "", "milestone": "M01", "repos": "", "subsystem": "", "since": "abc1234", "reason": "done", "note": ""}' "$("$BIN/hv-todo-field" --dump B03)"
  rc=0; err="$("$BIN/hv-todo-field" B99 title 2>&1)" || rc=$?
  eq "field unknown" "1:error: [B99] not found in BACKLOG.md or ARCHIVE.md" "$rc:$err"
  rc=0; err="$("$BIN/hv-todo-field" B01 bogus 2>&1)" || rc=$?
  eq "field bad" "1:error: bogus is not a valid field; pick one of title/detail/related/milestone/repos/subsystem/since/reason/note" "$rc:$err"
  pass "hv-todo-field golden"

  # hv-todo-set-field
  "$BIN/hv-todo-set-field" F02 milestone M03
  eq "set-field line" '- **[F02] [Minor] Small feature.** No fields. Milestone: M03' "$(grep -F '[F02]' .hv/BACKLOG.md)"
  "$BIN/hv-todo-set-field" F02 milestone ""
  eq "set-field clear" '- **[F02] [Minor] Small feature.** No fields.' "$(grep -F '[F02]' .hv/BACKLOG.md)"
  cmp -s .hv/BACKLOG.md "$TMP_GB/orig.md" || fail "set-field round trip changed BACKLOG.md"
  rc=0; err="$("$BIN/hv-todo-set-field" B99 milestone M1 2>&1)" || rc=$?
  eq "set-field unknown" "1:error: [B99] has no open bullet in .hv/BACKLOG.md (unknown, completed, or archived)" "$rc:$err"
  rc=0; err="$("$BIN/hv-todo-set-field" B01 title X 2>&1)" || rc=$?
  eq "set-field bad field" "1:error: title is not a settable field; pick one of milestone/related/repos/subsystem" "$rc:$err"
  rc=0; err="$("$BIN/hv-todo-set-field" B01 2>&1)" || rc=$?
  eq "set-field usage" "2:usage: hv-todo-set-field <ID> <field> <value>" "$rc:$err"
  pass "hv-todo-set-field golden"

  # hv-append (Since: stamped from HEAD when absent)
  head="$(git rev-parse --short HEAD)"
  "$BIN/hv-append" "## Bugs" '- **[B09] [P2] New.** d.'
  eq "append stamp" "- **[B09] [P2] New.** d. Since: $head" "$(grep -F '[B09]' .hv/BACKLOG.md)"
  "$BIN/hv-append" "Tasks" '- **[T09] t.** d. Since: zzz9999'
  eq "append keeps Since" '- **[T09] t.** d. Since: zzz9999' "$(grep -F '[T09]' .hv/BACKLOG.md)"
  eq "append placement" "$(printf '%s\n%s' '- **[B02] [P0] Second bug.** Desc two. Since: abc1234' "- **[B09] [P2] New.** d. Since: $head")" "$(grep -A1 -F '[B02]' .hv/BACKLOG.md)"
  rc=0; err="$("$BIN/hv-append" "## Nope" '- **[B10] x**' 2>&1)" || rc=$?
  eq "append missing section" "1:error: section '## Nope' not found" "$rc:$err"
  cp "$TMP_GB/orig.md" .hv/BACKLOG.md
  pass "hv-append golden"

  # hv-backlog
  exp_all='### In Progress

| ID | Title | Branch | Started |
|----|-------|--------|---------|
| B02 | [P0] Second bug | fix/b02 | 2026-01-01 |

### Bugs

| ID | Prio | Title | Related | Milestone |
|----|----|----|----|----|
| B01 | P1 | First bug | [F01] | M01 |

### Features

| ID | Size | Title | Related | Milestone |
|----|----|----|----|----|
| F02 | Minor | Small feature |  |  |
| F01 | Major | Big feature | [B01] | M01, M02 |

### Tasks

| ID | Title | Related |
|----|----|----|
| T01 | Chore | [F01] |

### Clusters

- [B01] First bug, [F01] Big feature, [T01] Chore'
  eq "backlog all" "$exp_all" "$("$BIN/hv-backlog")"
  eq "backlog grep keeps In Progress" "### In Progress

| ID | Title | Branch | Started |
|----|-------|--------|---------|
| B02 | [P0] Second bug | fix/b02 | 2026-01-01 |" "$("$BIN/hv-backlog" --grep zzzznomatch)"
  rc=0; err="$("$BIN/hv-backlog" --bogus 2>&1)" || rc=$?
  eq "backlog bad arg" "1:error: unknown argument: --bogus" "$rc:$err"
  pass "hv-backlog golden"

  # backlog.backend = issues: every helper refuses, exit 2, BACKLOG.md untouched
  echo '{"backlog":{"backend":"issues"}}' > .hv/config.json
  want="error: HELPER: issues backend not available yet (M07-S02)"
  for call in "hv-append|## Bugs|- **[B10] x.**" "hv-todo-field|B01|title" "hv-todo-set-field|B01|milestone|M09" "hv-backlog"; do
    IFS='|' read -r -a argv <<< "$call"
    h="${argv[0]}"
    rc=0; err="$("$BIN/$h" "${argv[@]:1}" 2>&1)" || rc=$?
    eq "$h issues refusal" "2:${want/HELPER/$h}" "$rc:$err"
    cmp -s .hv/BACKLOG.md "$TMP_GB/orig.md" || fail "$h wrote BACKLOG.md under issues backend"
  done
  pass "issues backend refused by all four helpers (exit 2, file unchanged)"

  # bogus backend: exit 1
  echo '{"backlog":{"backend":"bogus"}}' > .hv/config.json
  for call in "hv-append|## Bugs|- **[B10] x.**" "hv-todo-field|B01|title" "hv-todo-set-field|B01|milestone|M09" "hv-backlog"; do
    IFS='|' read -r -a argv <<< "$call"
    h="${argv[0]}"
    rc=0; err="$("$BIN/$h" "${argv[@]:1}" 2>&1)" || rc=$?
    eq "$h bogus backend" "1:error: $h: invalid backlog.backend 'bogus' (expected file|issues)" "$rc:$err"
  done
  cmp -s .hv/BACKLOG.md "$TMP_GB/orig.md" || fail "bogus backend wrote BACKLOG.md"
  pass "bogus backlog.backend exits 1"
)
