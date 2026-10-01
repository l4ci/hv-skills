echo "Issue mode: marker notes, item comments, proof, adapter lifecycle calls"

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
    # BODIES: every comment body of issue $1 as one marker line per comment (first line only)
    MARKERS() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print("|".join(c["body"].split("\n")[0] for c in adapter_for(load_config()).comments(int(sys.argv[1]))))' "$1"; }
    ERR() { local rc=0; ERRMSG="$("$@" 2>&1 >/dev/null)" || rc=$?; ERRRC=$rc; }

    T1="$("$BIN/hv-item-create" tasks --title "First")"
    T2="$("$BIN/hv-item-create" tasks --title "Second")"
    eq "ids" "T1 T2" "$T1 $T2"

    # --- note put / get / idempotence / rm
    eq "show absent" "" "$("$BIN/hv-item-note" T1 --kind design --show)"
    printf 'line one\nline two\n' > "$P/n.md"
    "$BIN/hv-item-note" T1 --kind design --body-file "$P/n.md"
    eq "marker" "<!-- hv:design -->" "$(MARKERS 1)"
    eq "show" "$(printf 'line one\nline two')" "$("$BIN/hv-item-note" T1 --kind design --show)"
    : > "$P/log"
    "$BIN/hv-item-note" T1 --kind design --body-file "$P/n.md"
    eq "idempotent put writes nothing" "0" "$(WRITES)"
    printf 'changed\n' | "$BIN/hv-item-note" T1 --kind design --body-file -
    eq "edited in place" "<!-- hv:design -->" "$(MARKERS 1)"
    eq "show after edit" "changed" "$("$BIN/hv-item-note" '#1' --kind design --show)"
    "$BIN/hv-item-note" T1 --kind plan --body-file "$P/n.md"
    eq "kinds independent" "<!-- hv:design -->|<!-- hv:plan -->" "$(MARKERS 1)"
    "$BIN/hv-item-note" T1 --kind design --rm
    "$BIN/hv-item-note" T1 --kind design --rm
    eq "rm leaves other kind" "<!-- hv:plan -->" "$(MARKERS 1)"
    "$BIN/hv-item-note" T1 --kind plan --rm
    eq "all removed" "" "$(MARKERS 1)"

    # --- split into parts and shrink back
    export HV_NOTE_LIMIT=200
    python3 -c 'print("\n".join("line %02d of the long note body" % i for i in range(15)))' > "$P/big.md"
    "$BIN/hv-item-note" T1 --kind plan --body-file "$P/big.md"
    eq "three parts" "<!-- hv:plan 1/3 -->|<!-- hv:plan 2/3 -->|<!-- hv:plan 3/3 -->" "$(MARKERS 1)"
    eq "parts round-trip" "$(cat "$P/big.md")" "$("$BIN/hv-item-note" T1 --kind plan --show)"
    : > "$P/log"
    "$BIN/hv-item-note" T1 --kind plan --body-file "$P/big.md"
    eq "idempotent split put" "0" "$(WRITES)"
    "$BIN/hv-item-note" T1 --kind plan --body-file "$P/n.md"
    eq "shrink deletes surplus parts" "<!-- hv:plan -->" "$(MARKERS 1)"
    "$BIN/hv-item-note" T1 --kind plan --body-file "$P/big.md"
    eq "grow again" "<!-- hv:plan 1/3 -->|<!-- hv:plan 2/3 -->|<!-- hv:plan 3/3 -->" "$(MARKERS 1)"
    unset HV_NOTE_LIMIT
    "$BIN/hv-item-note" T1 --kind plan --body-file "$P/n.md"
    eq "single again" "<!-- hv:plan -->" "$(MARKERS 1)"
    "$BIN/hv-item-note" T1 --kind plan --rm

    ERR "$BIN/hv-item-note" T1 --kind bogus --show
    eq "bad kind" "1" "$ERRRC"
    ERR "$BIN/hv-item-note" T1 --kind plan
    eq "no action" "1" "$ERRRC"
    ERR "$BIN/hv-item-note" T99 --kind plan --show
    eq "unknown item" "1" "$ERRRC"

    # --- comments
    printf 'Which db?\nSecond line\n' | "$BIN/hv-item-comment" T1 --kind question --body-file - >/dev/null
    printf 'Postgres\n' > "$P/a.md"
    id="$("$BIN/hv-item-comment" T1 --kind answer --body-file "$P/a.md")"
    case "$id" in ''|*[!0-9]*) fail "$prov comment id not numeric: $id" ;; esac
    eq "comment markers" "<!-- hv:comment question -->|<!-- hv:comment answer -->" "$(MARKERS 1)"
    ERR "$BIN/hv-item-comment" T1 --kind bogus --body-file "$P/a.md"
    eq "comment bad kind" "1" "$ERRRC"

    # --- proof round trip
    eq "no proof" "0" "$("$BIN/hv-proof-show" T1 --count)"
    "$BIN/hv-proof-add" T1 --check smoke --result PASS --evidence "all green" --sha abc1234
    "$BIN/hv-proof-add" T1 --check lint --result FAIL --evidence "2 errors" --sha abc1234
    : > "$P/log"
    "$BIN/hv-proof-add" T1 --check smoke --result PASS --evidence "all green" --sha abc1234
    eq "proof idempotent" "0" "$(WRITES)"
    eq "proof count" "2" "$("$BIN/hv-proof-show" T1 --count)"
    d="$(date +%Y-%m-%d)"
    eq "proof rows" "$(printf -- '- %s · smoke · PASS · abc1234 · all green\n- %s · lint · FAIL · abc1234 · 2 errors' "$d" "$d")" "$("$BIN/hv-proof-show" '#1')"
    eq "proof note shape" "$(printf '## Proof\n\n- %s · smoke · PASS · abc1234 · all green\n- %s · lint · FAIL · abc1234 · 2 errors' "$d" "$d")" "$("$BIN/hv-item-note" T1 --kind proof --show)"
    eq "proof is a marker note" "<!-- hv:comment question -->|<!-- hv:comment answer -->|<!-- hv:proof -->" "$(MARKERS 1)"
    ERR "$BIN/hv-proof-add" T99 --check c --result PASS --evidence e
    eq "proof unknown item" "1" "$ERRRC"

    # --- hv-complete gate sees issue-mode proof (close itself lands in M07-S03 T2)
    ERR "$BIN/hv-complete" T1 abc1234
    eq "proven item passes the gate, then backend unavailable" "2" "$ERRRC"
    ERR "$BIN/hv-complete" T2 abc1234
    eq "unproven item stops at the gate" "3" "$ERRRC"

    # --- adapter lifecycle calls
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
    pass "$prov: marker notes, split/shrink, comments, proof and adapter lifecycle calls"
  )
done

# File mode: comment_add appends a Log row; proof/note behaviour unchanged
TMP_INF="$(mktemp -d)"
trap 'rm -rf "$TMP_IN" "$TMP_INF"' EXIT
mkdir -p "$TMP_INF/.hv"
(
  cd "$TMP_INF"
  git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
  printf '# Backlog\n\n## Bugs\n\n- **[B01] [P1] Crash.** Desc.\n\n## Features\n\n## Tasks\n\n## Completed\n' > .hv/BACKLOG.md
  printf 'Which db?\nsecond line\n' | "$BIN/hv-item-comment" B01 --kind question --body-file -
  printf 'Postgres\n' | "$BIN/hv-item-comment" B01 --kind answer --body-file -
  d="$(date +%Y-%m-%d)"
  exp="$(printf '# B01: Crash\n\n> Related TODO entry: `[B01]` in `.hv/BACKLOG.md`\n\n## Log\n\n- %s · question · Which db?\n  second line\n- %s · answer · Postgres\n' "$d" "$d")"
  [ "$(cat .hv/bugs/B01.md)" = "$exp" ] || fail "file-mode Log rows: $(cat .hv/bugs/B01.md)"
  "$BIN/hv-proof-add" B01 --check smoke --result PASS --evidence ok --sha abc1234
  [ "$("$BIN/hv-proof-show" B01 --count)" = 1 ] || fail "file-mode proof count"
  rc=0; "$BIN/hv-item-note" B01 --kind design --show 2>/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "file-mode hv-item-note exit: $rc"
  rc=0; "$BIN/hv-item-comment" B99 --kind answer --body-file - </dev/null 2>/dev/null || rc=$?
  [ "$rc" = 1 ] || fail "empty/unknown comment exit: $rc"
)
trap 'rm -rf "$TMP"' EXIT
pass "file backend: comment_add writes ## Log rows, hv-item-note refuses (exit 2), proof unchanged"
