echo "Issue mode: marker notes, item comments, proof, tracker lifecycle calls"

TMP_IN="$(mktemp -d)"
trap 'rm -rf "$TMP_IN"' EXIT

for prov in github gitlab; do
  P="$TMP_IN/$prov"; mkdir -p "$P/.hv"
  echo "{\"backlog\":{\"backend\":\"issues\"},\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov $1: expected [$2] got [$3]"; }
    WRITES() { grep -c 'api -X \(POST\|PATCH\|PUT\|DELETE\)' "$P/log" || true; }
    # The fake tracker's store is the tracker's own state: no verb exposes raw comment markers.
    # MARKERS <n>: first line of every comment of issue <n>, joined by |
    MARKERS() { python3 -c '
import json, sys
issue = next(i for i in json.load(open(sys.argv[2]))["issues"] if i["number"] == int(sys.argv[1]))
print("|".join(c["body"].split("\n")[0] for c in issue["comments"]))' "$1" "$P/db.json"; }
    # TRACKER_OF <id>: number of the tracking issue titled "<id> — …"
    TRACKER_OF() { python3 -c '
import json, sys
print(next(i["number"] for i in json.load(open(sys.argv[2]))["issues"] if i["title"].startswith(sys.argv[1] + " ")))' "$1" "$P/db.json"; }
    # RC <cmd…>: the command's exit code
    RC() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

    T1="$(hvj item create --kind tasks --title "First" | jget data.id)"
    T2="$(hvj item create --kind tasks --title "Second" | jget data.id)"
    eq "ids" "1 2" "$T1 $T2"

    # --- note put / get / idempotence / rm
    OUT="$(hvj item note show T1 --kind design)"
    eq "show absent" "false|" "$(jget data.exists <<<"$OUT")|$(jget data.body <<<"$OUT")"
    printf 'line one\nline two\n' > "$P/n.md"
    hvj item note add T1 --kind design --body-file "$P/n.md" >/dev/null
    eq "marker" "<!-- hv:design -->" "$(MARKERS 1)"
    eq "show" "$(printf 'line one\nline two')" "$(hvj item note show T1 --kind design | jget data.body)"
    : > "$P/log"
    hvj item note add T1 --kind design --body-file "$P/n.md" >/dev/null
    eq "idempotent put writes nothing" "0" "$(WRITES)"
    printf 'changed\n' | hvj item note add T1 --kind design --body-file - >/dev/null
    eq "edited in place" "<!-- hv:design -->" "$(MARKERS 1)"
    eq "show after edit" "changed" "$(hvj item note show '#1' --kind design | jget data.body)"
    hvj item note add T1 --kind plan --body-file "$P/n.md" >/dev/null
    eq "kinds independent" "<!-- hv:design -->|<!-- hv:plan -->" "$(MARKERS 1)"
    hvj item note rm T1 --kind design >/dev/null
    hvj item note rm T1 --kind design >/dev/null
    eq "rm leaves other kind" "<!-- hv:plan -->" "$(MARKERS 1)"
    hvj item note rm T1 --kind plan >/dev/null
    eq "all removed" "" "$(MARKERS 1)"

    # --- split into parts and shrink back
    export HV_NOTE_LIMIT=200
    python3 -c 'print("\n".join("line %02d of the long note body" % i for i in range(15)))' > "$P/big.md"
    hvj item note add T1 --kind plan --body-file "$P/big.md" >/dev/null
    eq "three parts" "<!-- hv:plan 1/3 -->|<!-- hv:plan 2/3 -->|<!-- hv:plan 3/3 -->" "$(MARKERS 1)"
    eq "parts round-trip" "$(cat "$P/big.md")" "$(hvj item note show T1 --kind plan | jget data.body)"
    : > "$P/log"
    hvj item note add T1 --kind plan --body-file "$P/big.md" >/dev/null
    eq "idempotent split put" "0" "$(WRITES)"
    hvj item note add T1 --kind plan --body-file "$P/n.md" >/dev/null
    eq "shrink deletes surplus parts" "<!-- hv:plan -->" "$(MARKERS 1)"
    hvj item note add T1 --kind plan --body-file "$P/big.md" >/dev/null
    eq "grow again" "<!-- hv:plan 1/3 -->|<!-- hv:plan 2/3 -->|<!-- hv:plan 3/3 -->" "$(MARKERS 1)"
    unset HV_NOTE_LIMIT
    hvj item note add T1 --kind plan --body-file "$P/n.md" >/dev/null
    eq "single again" "<!-- hv:plan -->" "$(MARKERS 1)"
    hvj item note rm T1 --kind plan >/dev/null

    eq "bad kind" "2" "$(RC hvj item note show T1 --kind bogus)"
    eq "note add needs a body" "2" "$(RC hvj item note add T1 --kind plan)"
    eq "unknown item" "3" "$(RC hvj item note show T99 --kind plan)"

    # --- comments
    OUT="$(printf 'Which db?\nSecond line\n' | hvj item comment add T1 --kind question --body-file -)"
    eq "comment add changed" "true" "$(jget data.changed <<<"$OUT")"
    printf 'Postgres\n' > "$P/a.md"
    id="$(hvj item comment add T1 --kind answer --body-file "$P/a.md" | jget data.commentId)"
    case "$id" in ''|*[!0-9]*) fail "$prov comment id not numeric: $id" ;; esac
    eq "comment markers" "<!-- hv:comment question -->|<!-- hv:comment answer -->" "$(MARKERS 1)"
    eq "comment bad kind" "2" "$(RC hvj item comment add T1 --kind bogus --body-file "$P/a.md")"

    # --- proof round trip
    eq "no proof" "0" "$(hvj proof show T1 | jget data.count)"
    hvj proof add T1 --check smoke --result PASS --evidence "all green" --sha abc1234 >/dev/null
    hvj proof add T1 --check lint --result FAIL --evidence "2 errors" --sha abc1234 >/dev/null
    : > "$P/log"
    OUT="$(hvj proof add T1 --check smoke --result PASS --evidence "all green" --sha abc1234)"
    eq "proof idempotent" "0|false" "$(WRITES)|$(jget data.changed <<<"$OUT")"
    eq "proof count" "2" "$(hvj proof show T1 | jget data.count)"
    d="$(date +%Y-%m-%d)"
    OUT="$(hvj proof show '#1')"
    eq "proof rows" "$d|smoke|PASS|abc1234|all green;$d|lint|FAIL|abc1234|2 errors" "$(python3 -c '
import json, sys
rows = json.load(sys.stdin)["data"]["rows"]
print(";".join("|".join(r[k] for k in ("date", "check", "result", "sha", "evidence")) for r in rows))' <<<"$OUT")"
    eq "proof note shape" "$(printf '## Proof\n\n- %s · smoke · PASS · abc1234 · all green\n- %s · lint · FAIL · abc1234 · 2 errors' "$d" "$d")" "$(hvj item note show T1 --kind proof | jget data.body)"
    eq "proof is a marker note" "<!-- hv:comment question -->|<!-- hv:comment answer -->|<!-- hv:proof -->" "$(MARKERS 1)"
    eq "proof unknown item" "3" "$(RC hvj proof add T99 --check c --result PASS --evidence e)"
    eq "proof show unknown item" "3" "$(RC hvj proof show T99)"

    # --- item complete gate sees issue-mode proof
    eq "unproven item stops at the gate" "4" "$(RC hvj item complete T2 --commit abc1234)"
    eq "proven item passes the gate and closes" "0" "$(RC hvj item complete T1 --commit abc1234)"
    hvj item reopen T1 >/dev/null

    # --- adapter lifecycle calls
    # white-box: kept until the A8 Go unit test lands (#52), then delete
    PYTHONPATH="$BIN" python3 - "$prov" <<'PY' || fail "$prov adapter lifecycle"
import sys
from hvlib import adapter_for, load_config, TrackerError
a = adapter_for(load_config())
assert a.comments(2) == []
c1 = a.add_comment(2, "first\nmulti-line\n\nbody")
c2 = a.add_comment(2, "second")
cs = a.comments(2)
assert [c["id"] for c in cs] == [c1, c2] and cs[0]["body"] == "first\nmulti-line\n\nbody" and cs[0]["author"], cs
a.edit_comment(2, c1, "edited")
assert a.comments(2)[0]["body"] == "edited"
a.delete_comment(2, c2)
assert [c["id"] for c in a.comments(2)] == [c1]
try:
    a.delete_comment(2, 9999)
    raise SystemExit("delete of unknown comment accepted")
except TrackerError:
    pass
a.add_labels(2, ["in-progress", "blocked"])
assert sorted(a.get(2)["labels"]) == ["blocked", "in-progress", "type:task"], a.get(2)["labels"]
a.add_labels(2, ["in-progress"])
a.remove_labels(2, ["blocked"])
assert sorted(a.get(2)["labels"]) == ["in-progress", "type:task"]
a.remove_labels(2, [])
a.assign_self(2)
a.assign_self(2)
assert len(a.get(2)["assignees"]) == 1 and a.get(2)["assignees"][0], a.get(2)["assignees"]
a.close(2, "completed", comment="Done in abc")
i = a.get(2)
assert i["state"] == "closed" and i["state_reason"] == "completed", i
assert a.comments(2)[-1]["body"] == "Done in abc"
a.reopen(2)
assert a.get(2)["state"] == "open" and a.get(2)["state_reason"] is None
a.close(2, "not_planned")
i = a.get(2)
assert i["state"] == "closed" and i["state_reason"] == "not_planned", i
a.reopen(2)
PY

    # --- item designs and plans as notes (design/plan add/show/rm/put, list verbs)
    F1="F$(hvj item create --kind features --title "Big" | jget data.id)"
    eq "feature ref" "F3" "$F1"
    OUT="$(hvj design add "$F1" --title "Big design")"
    eq "design add" "3|F|true" "$(jget data.id <<<"$OUT")|$(jget data.type <<<"$OUT")|$(jget data.changed <<<"$OUT")"
    eq "design marker" "<!-- hv:design -->" "$(MARKERS 3)"
    OUT="$("$HV_BIN" design show "$F1")"
    grep "^# $F1 — Big design" >/dev/null <<<"$OUT" || fail "$prov design show stub"
    grep "^status: draft" >/dev/null <<<"$OUT" || fail "$prov design show frontmatter"
    OUT="$(RC hvj design add "$F1" --title "again")"
    eq "design add twice refused" "4" "$OUT"
    eq "design add leaves one note" "<!-- hv:design -->" "$(MARKERS 3)"
    printf '%s\n' '---' "id: $F1" 'title: Big design' 'status: final' '---' '' 'new text' > "$P/d.md"
    hvj design put "$F1" --body-file "$P/d.md" >/dev/null
    eq "design put shows" "$(cat "$P/d.md")" "$("$HV_BIN" design show "$F1")"
    : > "$P/log"
    OUT="$(cat "$P/d.md" | hvj design put "$F1" --body-file -)"
    eq "design put idempotent" "0|false" "$(WRITES)|$(jget data.changed <<<"$OUT")"
    eq "design put needs existing" "3" "$(RC hvj design put T1 --body-file "$P/d.md")"
    eq "design put did not create" "false" "$(hvj item note show T1 --kind design | jget data.exists)"
    eq "design put unreadable body" "2" "$(RC hvj design put "$F1" --body-file "$P/nope.md")"
    eq "design put needs body" "2" "$(RC hvj design put "$F1")"
    eq "design show missing exit" "3" "$(RC hvj design show T1)"
    rc=0; OUT="$(hvj design list 2>/dev/null)" || rc=$?
    eq "design list unsupported exit" "1|backend" "$rc|$(jget data.blockedBy <<<"$OUT")"

    # item plan with a --design pointer -> note:design; no plan file written
    MID="$(hvj milestone add --title "Seven" --summary "Tracking issue" | jget data.id)"
    TRK="$(TRACKER_OF "$MID")"
    eq "plan add" "$MID-$F1" "$(hvj plan add "$MID-$F1" --title "Big plan" --design "$F1" | jget data.key)"
    [ ! -e ".hv/plans/$MID-$F1.md" ] || fail "$prov item plan wrote a file"
    eq "plan marker" "<!-- hv:design -->|<!-- hv:plan -->" "$(MARKERS 3)"
    OUT="$("$HV_BIN" plan show "$MID-$F1")"
    grep "^design: note:design$" >/dev/null <<<"$OUT" || fail "$prov plan show design pointer"
    grep "^key: $MID-$F1$" >/dev/null <<<"$OUT" || fail "$prov plan show key"
    eq "plan add twice refused" "4" "$(RC hvj plan add "$MID-$F1" --title "again")"
    printf 'plan body\n' > "$P/p.md"
    hvj plan put "$MID-$F1" --body-file "$P/p.md" >/dev/null
    eq "plan put shows" "plan body" "$("$HV_BIN" plan show "$MID-$F1")"
    eq "plan put needs existing" "3" "$(RC hvj plan put "$MID-T1" --body-file "$P/p.md")"
    eq "plan show missing exit" "3" "$(RC hvj plan show "$MID-T1")"
    # slice plans are plan:S<NN> notes on the milestone's tracking issue (see 61_milestones.sh)
    eq "slice plan add" "$MID-S01" "$(hvj plan add --milestone "$MID" --slice --title "A slice" | jget data.key)"
    [ ! -e ".hv/plans/$MID-S01.md" ] || fail "$prov slice plan wrote a file"
    eq "slice plan marker" "<!-- hv:plan:S01 -->" "$(MARKERS "$TRK")"
    "$HV_BIN" plan show "$MID-S01" | grep "^key: $MID-S01$" >/dev/null || fail "$prov slice plan show"
    rc=0; OUT="$(hvj plan list 2>/dev/null)" || rc=$?
    eq "plan list ok" "0" "$rc"
    [ -n "$(jget 'warnings[0]' <<<"$OUT")" ] || fail "$prov plan list should warn that item plans live on their issues: $OUT"
    eq "plan list lists slice plans only" "$MID-S01" "$(python3 -c 'import json,sys;print(" ".join(p["key"] for p in json.load(sys.stdin)["data"]["plans"]))' <<<"$OUT")"
    printf 'slice body\n' | hvj plan put "$MID-S01" --body-file - >/dev/null
    eq "slice plan put stores the note" "slice body" "$("$HV_BIN" plan show "$MID-S01")"
    eq "slice plan makes no item note" "<!-- hv:design -->|<!-- hv:plan -->" "$(MARKERS 3)"
    hvj plan rm "$MID-S01" >/dev/null
    eq "slice plan rm" "" "$(MARKERS "$TRK")"
    hvj plan rm "$MID-$F1" >/dev/null
    eq "plan rm leaves design" "<!-- hv:design -->" "$(MARKERS 3)"
    eq "plan rm twice" "3" "$(RC hvj plan rm "$MID-$F1")"
    hvj design rm "$F1" >/dev/null
    eq "design rm" "" "$(MARKERS 3)"
    eq "design rm twice" "3" "$(RC hvj design rm "$F1")"
    pass "$prov: marker notes, split/shrink, comments, proof and tracker lifecycle calls"
  )
done

# File mode: comment add appends a Log row; proof/note behaviour unchanged
TMP_INF="$(mktemp -d)"
trap 'rm -rf "$TMP_IN" "$TMP_INF"' EXIT
mkdir -p "$TMP_INF/.hv"
(
  cd "$TMP_INF"
  git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
  printf '# Backlog\n\n## Bugs\n\n- **[B01] [P1] Crash.** Desc.\n\n## Features\n\n## Tasks\n\n## Completed\n' > .hv/BACKLOG.md
  printf 'Which db?\nsecond line\n' | hvj item comment add B01 --kind question --body-file - >/dev/null
  printf 'Postgres\n' | hvj item comment add B01 --kind answer --body-file - >/dev/null
  d="$(date +%Y-%m-%d)"
  exp="$(printf '# B01: Crash\n\n> Related TODO entry: `[B01]` in `.hv/BACKLOG.md`\n\n## Log\n\n- %s · question · Which db?\n  second line\n- %s · answer · Postgres\n' "$d" "$d")"
  [ "$(cat .hv/bugs/B01.md)" = "$exp" ] || fail "file-mode Log rows: $(cat .hv/bugs/B01.md)"
  OUT="$(hvj item comment list B01)" || fail "file-mode comment list failed"
  [ "$(jget data.comments[0].who <<<"$OUT")|$(jget data.comments[0].kind <<<"$OUT")|$(jget data.comments[0].text <<<"$OUT")" = "$d|question|$(printf 'Which db?\nsecond line')" ] \
    || fail "file-mode comment list row 0: $OUT"
  [ "$(jget data.comments[1].kind <<<"$OUT")|$(jget data.comments[1].text <<<"$OUT")" = "answer|Postgres" ] || fail "file-mode comment list row 1: $OUT"
  OUT="$(hvj item comment list B01 --kind answer)" || fail "file-mode comment list --kind failed"
  [ "$(jget data.comments[0].who <<<"$OUT")|$(jget data.comments[0].text <<<"$OUT")" = "$d|Postgres" ] || fail "file-mode comment list --kind: $OUT"
  [ "$(jget data.comments[1] <<<"$OUT" 2>/dev/null || true)" = "" ] || fail "file-mode comment list --kind should hold one row: $OUT"
  rc=0; hvj item show B01 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 1 ] || fail "file-mode item show exit: $rc"
  rc=0; hvj item comment list B99 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] || fail "file-mode comment list unknown item exit: $rc"
  hvj proof add B01 --check smoke --result PASS --evidence ok --sha abc1234 >/dev/null
  [ "$(hvj proof show B01 | jget data.count)" = 1 ] || fail "file-mode proof count"
  rc=0; hvj item note show B01 --kind design >/dev/null 2>&1 || rc=$?
  [ "$rc" = 1 ] || fail "file-mode item note show exit: $rc"
  rc=0; hvj item comment add B99 --kind answer --body-file - </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "empty comment exit: $rc"
  rc=0; printf 'x\n' | hvj item comment add B99 --kind answer --body-file - >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] || fail "unknown item comment exit: $rc"
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$TMP_IN" "$TMP_INF"
pass "file backend: comment add writes ## Log rows, item note show refuses (exit 1), proof unchanged"

# File mode: design/plan put overwrite an existing file, refuse a missing one
TMP_INP="$(mktemp -d)"
trap 'rm -rf "$TMP_IN" "$TMP_INP"' EXIT
mkdir -p "$TMP_INP/.hv"
(
  cd "$TMP_INP"
  git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
  rc=0; printf 'x\n' | hvj design put F01 --body-file - >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] || fail "file-mode design put on missing file: $rc"
  [ ! -e .hv/designs/F01.md ] || fail "file-mode design put created a file"
  hvj design add F01 --title "T" >/dev/null
  printf 'new design\n' | hvj design put F01 --body-file - >/dev/null
  [ "$(cat .hv/designs/F01.md)" = "new design" ] || fail "file-mode design put content"
  printf 'from file\n' > body.txt; mkdir sub; cd sub
  hvj design put F01 --body-file ../body.txt >/dev/null
  [ "$(cat ../.hv/designs/F01.md)" = "from file" ] || fail "file-mode design put relative body"
  cd ..
  rc=0; printf 'x\n' | hvj plan put M01-F01 --body-file - >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] || fail "file-mode plan put on missing file: $rc"
  hvj plan add M01-F01 --title "T" >/dev/null
  hvj plan add --milestone M01 --slice --title "S" >/dev/null
  printf 'new plan\n' | hvj plan put M01-F01 --body-file - >/dev/null
  [ "$(cat .hv/plans/M01-F01.md)" = "new plan" ] || fail "file-mode plan put content"
  printf 'new slice\n' | hvj plan put M01-S01 --body-file - >/dev/null
  [ "$(cat .hv/plans/M01-S01.md)" = "new slice" ] || fail "file-mode slice plan put content"
  rc=0; hvj plan put bogus --body-file body.txt >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "plan put bad key: $rc"
  rc=0; hvj design put ../x --body-file body.txt >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "design put bad id: $rc"
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$TMP_INP"
pass "file backend: design/plan put overwrite existing files and refuse missing ones"
