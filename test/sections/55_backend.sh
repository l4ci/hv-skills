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

  # backlog.backend = issues: write helpers refuse (exit 2), BACKLOG.md untouched
  echo '{"backlog":{"backend":"issues"}}' > .hv/config.json
  want="error: HELPER: issues backend not available yet (M07-S02 T4)"
  for call in "hv-append|## Bugs|- **[B10] x.**" "hv-todo-set-field|B01|milestone|M09"; do
    IFS='|' read -r -a argv <<< "$call"
    h="${argv[0]}"
    rc=0; err="$("$BIN/$h" "${argv[@]:1}" 2>&1)" || rc=$?
    eq "$h issues refusal" "2:${want/HELPER/$h}" "$rc:$err"
    cmp -s .hv/BACKLOG.md "$TMP_GB/orig.md" || fail "$h wrote BACKLOG.md under issues backend"
  done
  pass "issues backend refused by hv-append / hv-todo-set-field (exit 2, file unchanged)"

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
    eq "$h issues refusal" "2:error: $h: issues backend not available yet (M07-S03)" "$rc:$err"
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

echo "IssueBackend: reads served from the tracker"

TMP_IB="$(mktemp -d)"
trap 'rm -rf "$TMP_BK" "$TMP_GB" "$TMP_CU" "$TMP_IB"' EXIT

# Pure helpers: item refs and the fields block.
PYTHONPATH="$BIN" python3 - <<'PY' || fail "item ref / fields block helpers"
from hvlib import resolve_item_ref, parse_fields_block, render_fields_block
assert resolve_item_ref("#42") == (42, None)
assert resolve_item_ref("42") == (42, None)
assert resolve_item_ref("F42") == (42, "F")
assert resolve_item_ref("b07") == (7, "B")
for bad in ("", "x", "Q9", "#", "F", "4 2"):
    try:
        resolve_item_ref(bad)
        raise AssertionError(bad)
    except ValueError:
        pass
f = {"Related": "F12, B03", "Repos": "web"}
body = render_fields_block("Some text\n\nmore", f)
assert body == "Some text\n\nmore\n\n<!-- hv:fields\nRelated: F12, B03\nRepos: web\n-->", repr(body)
assert parse_fields_block(body) == ("Some text\n\nmore", f)
assert render_fields_block("t", {}) == "t" and render_fields_block("t", {"Repos": " "}) == "t"
assert parse_fields_block("no block") == ("no block", {})
assert parse_fields_block(render_fields_block("", f)) == ("", f)
assert render_fields_block("", f).startswith("<!-- hv:fields")
assert parse_fields_block("a\r\n<!-- hv:fields\r\nRepos: web\r\n-->\r\n") == ("a", {"Repos": "web"})
PY
pass "resolve_item_ref and fields block round-trip"

for prov in github gitlab; do
  P="$TMP_IB/$prov"; mkdir -p "$P/.hv"
  echo "{\"backlog\":{\"backend\":\"issues\"},\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov issue mode $1: expected [$2] got [$3]"; }
    TC() { "$BIN/hv-tracker-call" -- "$@" </dev/null >/dev/null; }
    FB="$(printf 'Adds the thing.\n\nSecond paragraph.\n\n<!-- hv:fields\nRelated: F3, B1\nRepos: web\n-->')"
    if [ "$prov" = github ]; then
      TC api repos/fake/repo/milestones -f "title=M07 — Issue backend"
      for l in type:bug type:feature type:task p1 size:Major milestone-tracker; do TC label create "$l"; done
      IC() { TC issue create --title "$1" --body "$2" ${3:+--label "$3"} ${4:+--milestone "$4"}; }
      CLOSE_DONE() { TC issue close "$1"; }
      CLOSE_DROP() { TC issue close "$1" --reason "not planned"; }
    else
      TC api projects/:id/milestones -f "title=M07 — Issue backend"
      IC() { TC issue create --title "$1" --description "$2" ${3:+--label "$3"} ${4:+--milestone "$4"} -y; }
      CLOSE_DONE() { TC issue close "$1"; }
      CLOSE_DROP() { TC issue close "$1"; TC issue update "$1" --label not-planned; }
    fi
    IC "Crash on start" "Crashes when config is missing." "type:bug,p1"
    IC "Big feature" "$FB" "type:feature,size:Major" "M07 — Issue backend"
    IC "Other feature" "" "type:feature"
    IC "Chore" "do the \`thing\`" ""
    IC "M07 tracking" "tracker" "milestone-tracker"
    IC "Old bug" "fixed long ago" "type:bug"
    IC "Dropped task" "never mind" "type:task"
    CLOSE_DONE 6
    sleep 1
    CLOSE_DROP 7

    # rendering
    md="$(PYTHONPATH="$BIN" python3 -c 'from hvlib import get_backend; print(get_backend().backlog_markdown(), end="")')"
    exp="# Backlog

## Bugs

- **[B1] [P1] Crash on start.** Crashes when config is missing.

## Features

- **[F2] [Major] Big feature.** Adds the thing. Milestone: M07 Related: [F3], [B1] Repos: web
- **[F3] Other feature.**

## Tasks

- **[T4] Chore.** do the \`thing\`

## Completed
"
    case "$md" in "$exp"*) ;; *) fail "$prov rendering head: got
$md";; esac
    comp="$(printf '%s\n' "$md" | sed -n '/^## Completed/,$p' | tail -n +3)"
    n=0; while IFS= read -r line; do n=$((n+1)); done <<< "$comp"
    eq "completed count" 2 "$n"
    case "$(printf '%s\n' "$comp" | sed -n 1p)" in
      '- ~~**[T7] Dropped task.** never mind~~ Done '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' [`#7`] (dropped)') ;;
      *) fail "$prov completed dropped line: $(printf '%s\n' "$comp" | sed -n 1p)" ;;
    esac
    case "$(printf '%s\n' "$comp" | sed -n 2p)" in
      '- ~~**[B6] Old bug.** fixed long ago~~ Done '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' [`#6`]') ;;
      *) fail "$prov completed line: $(printf '%s\n' "$comp" | sed -n 2p)" ;;
    esac
    case "$md" in *"[T5]"*|*"M07 tracking"*) fail "$prov milestone-tracker issue rendered";; esac
    pass "$prov: backlog_markdown shape, tags, fields, completed, tracker issue excluded"
    PYTHONPATH="$BIN" python3 - <<'PY' || fail "$prov closed_limit / truncation"
from hvlib import get_backend
b = get_backend()
assert "Done" not in b.backlog_markdown(closed_limit=0)
assert b.backlog_markdown(closed_limit=1).count("~~**[") == 1
c, secs = b.list_open()
assert [n for n, _ in secs] == ["Bugs", "Features", "Tasks"] and "Done" not in c
PY
    BIG="$(python3 -c 'print("word " * 80)')"
    IC "Long one" "$BIG" "type:task"
    long="$(PYTHONPATH="$BIN" python3 -c 'from hvlib import get_backend; print(get_backend().backlog_markdown(closed_limit=0))' | grep -F '[T8]')"
    [ "${#long}" -lt 260 ] && case "$long" in *"…"*) ;; *) fail "$prov truncation: $long";; esac

    # hv-backlog
    out="$("$BIN/hv-backlog")"
    case "$out" in *"| B1 | P1 | Crash on start |  |"*) ;; *) fail "$prov hv-backlog bug row: $out";; esac
    case "$out" in *"| F2 | Major | Big feature | [F3], [B1] | M07 |"*) ;; *) fail "$prov hv-backlog feature row: $out";; esac
    case "$out" in *"| F3 | "*"Other feature"*) ;; *) fail "$prov hv-backlog F3: $out";; esac
    case "$out" in *"| T4 | Chore |"*) ;; *) fail "$prov hv-backlog task: $out";; esac
    case "$out" in *"Old bug"*|*"tracking"*) fail "$prov hv-backlog shows closed/tracker: $out";; esac
    pass "$prov: hv-backlog renders tracker items"

    # hv-todo-field across ID spellings
    for ref in F2 '#2' 2; do
      eq "title $ref" "Big feature" "$("$BIN/hv-todo-field" "$ref" title)"
      eq "milestone $ref" "M07" "$("$BIN/hv-todo-field" "$ref" milestone)"
    done
    eq "related" "[F3], [B1]" "$("$BIN/hv-todo-field" F2 related)"
    eq "repos" "web" "$("$BIN/hv-todo-field" F2 repos)"
    eq "subsystem" "" "$("$BIN/hv-todo-field" F2 subsystem)"
    eq "since" "" "$("$BIN/hv-todo-field" F2 since)"
    eq "reason open" "" "$("$BIN/hv-todo-field" F2 reason)"
    eq "reason done" "done" "$("$BIN/hv-todo-field" B6 reason)"
    eq "reason dropped" "dropped" "$("$BIN/hv-todo-field" '#7' reason)"
    eq "note" "" "$("$BIN/hv-todo-field" F2 note)"
    case "$("$BIN/hv-todo-field" F2 detail)" in http*/2) ;; *) fail "$prov detail is not the issue URL";; esac
    dump="$("$BIN/hv-todo-field" --dump '#2')"
    DUMP="$dump" python3 - <<'PY' || fail "$prov --dump"
import json, os
d = json.loads(os.environ["DUMP"])
assert list(d) == ["title","detail","related","milestone","repos","subsystem","since","reason","note"], list(d)
assert d["title"] == "Big feature" and d["related"] == "[F3], [B1]" and d["milestone"] == "M07", d
assert d["repos"] == "web" and d["detail"].endswith("/2"), d
PY
    for bad in B2 T2 B99 9999 F5; do
      rc=0; err="$("$BIN/hv-todo-field" "$bad" title 2>&1)" || rc=$?
      eq "unknown $bad" "1:error: [$bad] not found in the issue tracker" "$rc:$err"
    done
    pass "$prov: hv-todo-field resolves F2/#2/2, rejects type mismatch and tracker issues"

    # hv-summary, milestone readers
    sum="$("$BIN/hv-summary")"
    case "$sum" in "Backlog: 1 bug, 2 features, 2 tasks"*) ;; *) fail "$prov hv-summary: $sum";; esac
    case "$sum" in *"Recent: [T7] on "*"(dropped), [B6] on "*) ;; *) fail "$prov hv-summary recent: $sum";; esac
    eq "todo-by-milestone" "F2" "$("$BIN/hv-todo-by-milestone" M07)"
    eq "todo-by-milestone none" "" "$("$BIN/hv-todo-by-milestone" M08)"
    eq "find-milestone" "M07" "$("$BIN/hv-find-milestone-for-items" B1 F2 '#3')"
    eq "find-milestone none" "" "$("$BIN/hv-find-milestone-for-items" B1 T4)"
    pass "$prov: hv-summary / hv-todo-by-milestone / hv-find-milestone-for-items"

    # hv-uncertain: F2 is Major with a prose-only body (no code span)
    rc=0; out="$("$BIN/hv-uncertain" F2 2>&1)" || rc=$?
    eq "uncertain F2" "0:no concrete identifiers (unknown surface)" "$rc:$out"
    rc=0; out="$("$BIN/hv-uncertain" '#2' 2>&1)" || rc=$?
    eq "uncertain #2" "0:no concrete identifiers (unknown surface)" "$rc:$out"
    rc=0; out="$("$BIN/hv-uncertain" B1 2>&1)" || rc=$?
    eq "uncertain non-major" "1:" "$rc:$out"
    rc=0; out="$("$BIN/hv-uncertain" B2 2>&1)" || rc=$?
    eq "uncertain unknown" "2:error: item B2 not found in BACKLOG.md" "$rc:$out"
    pass "$prov: hv-uncertain reads the issue body as the detail text"

    # tracker failure: error line, exit 1
    for call in "hv-backlog" "hv-summary" "hv-todo-by-milestone M07" "hv-find-milestone-for-items F2" "hv-uncertain F2"; do
      h="${call%% *}"
      # shellcheck disable=SC2086
      rc=0; err="$(FAKE_TRACKER_FAIL=list "$BIN/$h" ${call#"$h"} 2>&1 >/dev/null)" || rc=$?
      eq "$h list failure rc" 1 "$rc"
      case "$err" in "error: $h: "*) ;; *) fail "$prov $h failure message: $err";; esac
    done
    rc=0; err="$(FAKE_TRACKER_FAIL=view "$BIN/hv-todo-field" F2 title 2>&1)" || rc=$?
    eq "todo-field view failure" 1 "$rc"; case "$err" in "error: hv-todo-field: "*) ;; *) fail "$prov todo-field failure: $err";; esac
    pass "$prov: tracker failures surface as 'error: <helper>: ...' exit 1"

    # write verbs stay refused
    rc=0; "$BIN/hv-append" "## Bugs" '- **[B10] x.**' >/dev/null 2>&1 || rc=$?; eq "append refused" 2 "$rc"
    rc=0; "$BIN/hv-complete" B1 abc1234 >/dev/null 2>&1 || rc=$?; eq "complete refused" 2 "$rc"
    pass "$prov: hv-append / hv-complete still refused in issue mode"
  )
done
trap 'rm -rf "$TMP"' EXIT
