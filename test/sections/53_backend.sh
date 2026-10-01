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

echo "FileBackend complete/uncomplete and file-only verbs"

TMP_CU="$(mktemp -d)"
trap 'rm -rf "$TMP_BK" "$TMP_GB" "$TMP_CU"' EXIT
(
  cd "$TMP_CU"
  git init -q && git config user.email t@t && git config user.name t
  echo a > a && git add a && git commit -qm "feat: work"
  C1="$(git log -1 --format=%h)"
  echo b >> a && git commit -qam "refactor(core): tidy"
  R1="$(git log -1 --format=%h)"
  TODAY="$(date +%Y-%m-%d)"
  mkdir -p .hv
  cat > .hv/BACKLOG.md <<MD
# Backlog

## Bugs

- **[B01] [P1] First bug.** Desc one.
- **[B02] [P0] Second bug.** Desc two.
- **[B04] [P2] No proof.** Desc.

## Features

- **[F01] [Major] Big.** Needs work.

## Tasks

## Completed

- ~~**[B03] [P1] Done thing.** old.~~ Done 2026-01-01 [\`$C1\`]
- ~~**[T02] Skipped.** x.~~ Done 2026-01-02 [\`$C1\`] (dropped: not needed)
MD
  printf '# Archive\n\n- ~~**[B05] [P2] Archived.** old.~~ Done 2025-12-01 [`%s`] (blocked: waiting)\n' "$C1" > .hv/ARCHIVE.md
  echo '{"since_refactor":{"features":3,"bugs":3}}' > .hv/counters.json
  "$BIN/hv-proof-add" B01 --check t --result PASS --evidence x --sha "$C1" >/dev/null
  "$BIN/hv-proof-add" B02 --check t --result PASS --evidence x --sha "$C1" >/dev/null
  cp .hv/BACKLOG.md orig.md; cp .hv/ARCHIVE.md orig.arch; cp .hv/counters.json orig.cnt
  eq() { [ "$2" = "$3" ] || fail "$1: expected [$2] got [$3]"; }
  cnt() { python3 -c 'import json;d=json.load(open(".hv/counters.json"))["since_refactor"];print(d["features"],d["bugs"])'; }

  # complete: proof row present, default Done line, counter bumped
  "$BIN/hv-complete" B01 "$C1"
  eq "complete line" "- ~~**[B01] [P1] First bug.** Desc one.~~ Done $TODAY [\`$C1\`]" "$(grep -F '[B01]' .hv/BACKLOG.md)"
  eq "complete counter" "3 4" "$(cnt)"
  # already completed: silent no-op, no second bump
  rc=0; out="$("$BIN/hv-complete" B01 "$C1" 2>&1)" || rc=$?
  eq "complete noop" "0:" "$rc:$out"; eq "noop counter" "3 4" "$(cnt)"
  # no proof: exit 3 with the exact message, nothing written
  cp .hv/BACKLOG.md pre.md
  rc=0; err="$("$BIN/hv-complete" B04 "$C1" 2>&1)" || rc=$?
  eq "no proof" "3:error: [B04] no proof recorded, pass --no-proof to override (hv-proof-add B04 --check <name> --result PASS --evidence <path-or-text>)" "$rc:$err"
  cmp -s .hv/BACKLOG.md pre.md || fail "no-proof close wrote BACKLOG.md"
  # --no-proof with reason and note
  "$BIN/hv-complete" B04 "$C1" --no-proof --reason blocked --note "waiting on X"
  eq "reason/note line" "- ~~**[B04] [P2] No proof.** Desc.~~ Done $TODAY [\`$C1\`] (blocked: waiting on X)" "$(grep -F '[B04]' .hv/BACKLOG.md | head -1)"
  # refactor: commit leaves counters alone
  "$BIN/hv-complete" B02 "$R1"
  eq "refactor counter" "3 5" "$(cnt)"
  # unknown ID / bad reason
  rc=0; err="$("$BIN/hv-complete" B99 "$C1" 2>&1)" || rc=$?
  eq "complete unknown" "1:error: [B99] not found" "$rc:$err"
  rc=0; err="$("$BIN/hv-complete" B01 "$C1" --reason bogus 2>&1 | head -1)" || rc=$?
  eq "complete bad reason" "error: invalid --reason 'bogus'" "$err"
  pass "hv-complete golden"

  # uncomplete: from Completed, rewinds counter; from ARCHIVE.md; refactor; active no-op
  cp orig.md .hv/BACKLOG.md; cp orig.arch .hv/ARCHIVE.md; cp orig.cnt .hv/counters.json
  "$BIN/hv-uncomplete" B03
  eq "uncomplete line" "- **[B03] [P1] Done thing.** old." "$(grep -F '[B03]' .hv/BACKLOG.md)"
  if grep -qF '~~**[B03]' .hv/BACKLOG.md; then fail "B03 Done line left in BACKLOG"; fi
  eq "uncomplete counter" "3 2" "$(cnt)"
  "$BIN/hv-uncomplete" B05
  eq "archive restore" "- **[B05] [P2] Archived.** old." "$(grep -F '[B05]' .hv/BACKLOG.md)"
  eq "archive emptied" "# Archive" "$(grep -v '^$' .hv/ARCHIVE.md)"
  eq "archive counter" "3 1" "$(cnt)"
  rc=0; err="$("$BIN/hv-uncomplete" B03 2>&1)" || rc=$?
  eq "uncomplete noop" "0:noop: [B03] already active in BACKLOG.md" "$rc:$err"
  eq "noop counter" "3 1" "$(cnt)"
  "$BIN/hv-uncomplete" T02
  eq "task restore" "- **[T02] Skipped.** x." "$(grep -F '[T02]' .hv/BACKLOG.md)"
  eq "task counter" "3 1" "$(cnt)"
  rc=0; err="$("$BIN/hv-uncomplete" B99 2>&1)" || rc=$?
  eq "uncomplete unknown" "1:error: [B99] not found in BACKLOG.md (## Completed) or .hv/ARCHIVE.md" "$rc:$err"
  pass "hv-uncomplete golden"

  # backlog.backend = issues: complete/uncomplete refuse (exit 2, nothing written)
  cp orig.md .hv/BACKLOG.md; cp orig.arch .hv/ARCHIVE.md; cp orig.cnt .hv/counters.json
  echo '{"backlog":{"backend":"issues"}}' > .hv/config.json
  for call in "hv-complete|B01|$C1" "hv-uncomplete|B03"; do
    IFS='|' read -r -a argv <<< "$call"; h="${argv[0]}"
    rc=0; err="$("$BIN/$h" "${argv[@]:1}" 2>&1)" || rc=$?
    eq "$h issues refusal" "2:error: $h: issues backend not available yet (M07-S02)" "$rc:$err"
  done
  cmp -s .hv/BACKLOG.md orig.md && cmp -s .hv/ARCHIVE.md orig.arch && cmp -s .hv/counters.json orig.cnt || fail "complete/uncomplete wrote under issues backend"
  pass "complete/uncomplete refused under issues backend, files unchanged"

  # file-only verbs refuse in issue mode, with a tracker pointer, writing nothing
  while IFS='|' read -r h args ptr; do
    # shellcheck disable=SC2086
    rc=0; err="$("$BIN/$h" $args 2>&1)" || rc=$?
    eq "$h issues refusal" "2:error: $h: not available with backlog.backend \"issues\" — $ptr" "$rc:$err"
  done <<'EOF'
hv-next-id|bugs|IDs are issue numbers; capture creates the issue
hv-rm|--force B01|close the issue instead: hv-complete <#N> --reason dropped
hv-archive-old|0|closed issues are the archive
hv-backfill-since|-|Since: anchors exist only in the file backend
hv-todo-drift|-|PRs carry "Closes #N", so the tracker closes shipped issues
EOF
  cmp -s .hv/BACKLOG.md orig.md && cmp -s .hv/ARCHIVE.md orig.arch && cmp -s .hv/counters.json orig.cnt || fail "file-only verb wrote under issues backend"
  pass "file-only verbs refuse under issues backend (exit 2, no writes)"

  # bogus backend: exit 1
  echo '{"backlog":{"backend":"bogus"}}' > .hv/config.json
  for h in hv-complete hv-uncomplete hv-next-id hv-rm hv-archive-old hv-backfill-since hv-todo-drift; do
    case "$h" in hv-complete) a="B01 $C1" ;; hv-uncomplete) a=B03 ;; hv-next-id) a=bugs ;; hv-rm) a=B01 ;; hv-archive-old) a=0 ;; *) a="" ;; esac
    # shellcheck disable=SC2086
    rc=0; err="$("$BIN/$h" $a 2>&1)" || rc=$?
    eq "$h bogus backend" "1:error: $h: invalid backlog.backend 'bogus' (expected file|issues)" "$rc:$err"
  done
  cmp -s .hv/BACKLOG.md orig.md && cmp -s .hv/counters.json orig.cnt || fail "bogus backend wrote"
  pass "bogus backlog.backend exits 1 for all seven helpers"

  # file mode: file-only verbs still work
  rm .hv/config.json
  eq "next-id file mode" "B06" "$("$BIN/hv-next-id" bugs)"
  pass "hv-next-id unchanged in file mode"
)
