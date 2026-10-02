echo "Issue mode: claim lock, readiness check, state labels"

TMP_CL="$(mktemp -d)"
trap 'rm -rf "$TMP_CL"' EXIT

for prov in github gitlab; do
  P="$TMP_CL/$prov"; mkdir -p "$P/.hv"
  echo "{\"backlog\":{\"backend\":\"issues\"},\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov claim $1: expected [$2] got [$3]"; }
    ERR() { local rc=0; ERRMSG="$("$@" 2>&1 >/dev/null)" || rc=$?; ERRRC=$rc; }
    WRITES() { grep -c 'issue \(edit\|update\)\|api -X' "$P/log" || true; }
    LABELS() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(",".join(sorted(adapter_for(load_config()).get(int(sys.argv[1]))["labels"])))' "$1"; }
    # MARKERS <n>: first line of every comment, joined by |
    MARKERS() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print("|".join(c["body"].split("\n")[0] for c in adapter_for(load_config()).comments(int(sys.argv[1]))))' "$1"; }
    ASSIGNEES() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(len(adapter_for(load_config()).get(int(sys.argv[1]))["assignees"]))' "$1"; }

    "$BIN/hv-item-create" tasks --title "Race" >/dev/null   # T1
    "$BIN/hv-item-create" tasks --title "Other" >/dev/null  # T2

    # --- two claims race: A wins, B loses and releases
    eq "claim A" "claimed T1 as ann/t1" "$("$BIN/hv-item-claim" T1 --as ann/t1)"
    eq "A labels" "in-progress,type:task" "$(LABELS 1)"
    eq "A assigned" 1 "$(ASSIGNEES 1)"
    eq "A marker" "<!-- hv:claim ann/t1 -->" "$(MARKERS 1)"
    ERR "$BIN/hv-item-claim" '#1' --as bob
    eq "B loses" "5:error: hv-item-claim: T1 is claimed by ann/t1" "$ERRRC:$ERRMSG"
    eq "B posted claim then release" "<!-- hv:claim ann/t1 -->|<!-- hv:claim bob -->|<!-- hv:release bob -->" "$(MARKERS 1)"
    eq "loser leaves labels" "in-progress,type:task" "$(LABELS 1)"
    : > "$P/log"
    eq "A re-claim" "claimed T1 as ann/t1" "$("$BIN/hv-item-claim" T1 --as ann/t1)"
    eq "A re-claim posts nothing" "<!-- hv:claim ann/t1 -->|<!-- hv:claim bob -->|<!-- hv:release bob -->" "$(MARKERS 1)"
    eq "A re-claim writes nothing" 0 "$(WRITES)"

    # --- release then B claims
    "$BIN/hv-item-release" T1 --as bob   # no open claim by bob: no-op
    eq "release no-op" "<!-- hv:claim ann/t1 -->|<!-- hv:claim bob -->|<!-- hv:release bob -->" "$(MARKERS 1)"
    "$BIN/hv-item-release" T1 --as ann/t1
    eq "A released" "type:task" "$(LABELS 1)"
    eq "release marker" "<!-- hv:claim ann/t1 -->|<!-- hv:claim bob -->|<!-- hv:release bob -->|<!-- hv:release ann/t1 -->" "$(MARKERS 1)"
    eq "B claims after release" "claimed T1 as bob" "$("$BIN/hv-item-claim" T1 --as bob)"
    eq "B labels" "in-progress,type:task" "$(LABELS 1)"
    ERR "$BIN/hv-item-claim" T1 --as ann/t1
    eq "A now loses" "5:error: hv-item-claim: T1 is claimed by bob" "$ERRRC:$ERRMSG"

    # --- claim clears review states
    "$BIN/hv-item-release" T1 --as bob
    "$BIN/hv-item-state" T1 changes-requested
    eq "state cr" "changes-requested,type:task" "$(LABELS 1)"
    "$BIN/hv-item-claim" T1 --as ann/t1 >/dev/null
    eq "claim swaps state" "in-progress,type:task" "$(LABELS 1)"

    # --- hv-item-show reads state, claim, assignee and comments back, writing nothing
    printf 'Which db?\nsecond line\n' | "$BIN/hv-item-comment" T1 --kind question --body-file - >/dev/null
    : > "$P/log"
    "$BIN/hv-item-show" T1 > "$P/show"
    eq "show writes nothing" 0 "$(WRITES)"
    eq "show head" "$(printf '[T1] Race\ntype: task\nstatus: open\nstate: in-progress\nclaimed by: ann/t1')" "$(sed -n 1,5p "$P/show")"
    eq "show assignee" "assignee: fake-user" "$(sed -n 6p "$P/show")"
    eq "show tail" "$(printf 'milestone: none\nnotes: none\ncomments: 1')" "$(sed -n 7,9p "$P/show")"
    eq "show comment row" "- fake-user · question · Which db?" "$(sed -n 10p "$P/show")"
    eq "show comment continuation" "  second line" "$(sed -n 11p "$P/show")"
    eq "list kind filter" "" "$("$BIN/hv-item-comment" T1 --list --kind answer)"
    eq "list matches show" "$(sed -n '10,$p' "$P/show")" "$("$BIN/hv-item-comment" T1 --list --kind question)"
    "$BIN/hv-item-release" T1 --as ann/t1
    eq "show after release" "$(printf 'state: none\nclaimed by: none')" "$("$BIN/hv-item-show" T1 | sed -n '4,5p')"
    "$BIN/hv-item-claim" T1 --as ann/t1 >/dev/null
    ERR "$BIN/hv-item-show" T99; eq "show unknown" "1" "$ERRRC"
    ERR "$BIN/hv-item-comment" T1 --list --kind bogus; eq "list bad kind" "1" "$ERRRC"
    ERR "$BIN/hv-item-comment" T1 --list --body-file x; eq "list with body" "1" "$ERRRC"

    # --- errors
    ERR "$BIN/hv-item-claim" T99 --as ann; eq "claim unknown" "1:error: hv-item-claim: [T99] not found in the issue tracker" "$ERRRC:$ERRMSG"
    ERR "$BIN/hv-item-claim" T1; eq "claim no --as" 1 "$ERRRC"
    ERR "$BIN/hv-item-release" T1 --as "a b"; eq "release bad id" 1 "$ERRRC"
    ERR "$BIN/hv-item-state" T1 bogus; eq "state bad" 1 "$ERRRC"
    "$BIN/hv-tracker-call" -- issue close 2 </dev/null >/dev/null 2>&1 || true
    pass "$prov: claim race, re-claim, release, re-claim by the other, error paths"

    # --- state machine keeps one state label
    eq "state to needs-review" "" "$("$BIN/hv-item-state" T1 needs-review)"
    eq "nr" "needs-review,type:task" "$(LABELS 1)"
    : > "$P/log"
    "$BIN/hv-item-state" T1 needs-review
    eq "state no-op writes nothing" 0 "$(WRITES)"
    : > "$P/log"
    "$BIN/hv-item-state" T1 in-progress
    eq "one edit per transition" 1 "$(WRITES)"
    eq "ip" "in-progress,type:task" "$(LABELS 1)"
    "$BIN/hv-item-state" T1 changes-requested
    eq "cr" "changes-requested,type:task" "$(LABELS 1)"
    "$BIN/hv-item-state" T1 none
    eq "none" "type:task" "$(LABELS 1)"
    "$BIN/hv-item-state" T1 none
    ERR "$BIN/hv-item-state" T99 none; eq "state unknown" 1 "$ERRRC"
    pass "$prov: hv-item-state keeps exactly one state label"

    # --- readiness
    for t in bare accept box plan; do "$BIN/hv-item-create" tasks --title "Ready $t" >/dev/null; done  # T3..T6
    printf 'Intro\n\n## Acceptance criteria\n\n- it works\n' > "$P/a.md"
    printf 'Intro\n\n- [ ] first\n- [x] second\n' > "$P/c.md"
    "$BIN/hv-item-create" tasks --title "Ready accept body" --body-file "$P/a.md" >/dev/null   # T7
    "$BIN/hv-item-create" tasks --title "Ready box body" --body-file "$P/c.md" >/dev/null      # T8
    printf '## Plan\n\n1. do it\n' | "$BIN/hv-item-note" T6 --kind plan --body-file -
    both="$(printf 'no acceptance criteria in the issue body\nno design or plan note')"
    ERR "$BIN/hv-item-ready" T3; eq "bare rc" 1 "$ERRRC"
    eq "bare reasons" "$both" "$("$BIN/hv-item-ready" T3 2>&1 || true)"
    eq "accept heading" "0:" "$(rc=0; out="$("$BIN/hv-item-ready" T7 2>&1)" || rc=$?; echo "$rc:$out")"
    eq "checkbox" "0:" "$(rc=0; out="$("$BIN/hv-item-ready" T8 2>&1)" || rc=$?; echo "$rc:$out")"
    eq "plan note" "0:" "$(rc=0; out="$("$BIN/hv-item-ready" '#6' 2>&1)" || rc=$?; echo "$rc:$out")"
    "$BIN/hv-item-note" T3 --kind design --body-file "$P/a.md"
    eq "design note" "0:" "$(rc=0; out="$("$BIN/hv-item-ready" T3 2>&1)" || rc=$?; echo "$rc:$out")"
    ERR "$BIN/hv-item-ready" T99; eq "ready unknown" "1:error: hv-item-ready: [T99] not found in the issue tracker" "$ERRRC:$ERRMSG"
    pass "$prov: hv-item-ready reasons for bare, acceptance heading, checkbox, design/plan note"
  )
done

# --- file mode: claim/release/state are silent no-ops, ready reads the detail file and designs/plans
TMP_CLF="$(mktemp -d)"
trap 'rm -rf "$TMP_CL" "$TMP_CLF"' EXIT
mkdir -p "$TMP_CLF/.hv/tasks" "$TMP_CLF/.hv/designs" "$TMP_CLF/.hv/plans"
(
  cd "$TMP_CLF"
  git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
  printf '# Backlog\n\n## Bugs\n\n## Features\n\n## Tasks\n\n- **[T01] Bare.** x.\n- **[T02] Accept.** x.\n- **[T03] Boxes.** x.\n- **[T04] Designed.** x.\n- **[T05] Planned.** x.\n\n## Completed\n' > .hv/BACKLOG.md
  printf '## Acceptance\n\n- works\n' > .hv/tasks/T02.md
  printf -- '- [ ] one\n' > .hv/tasks/T03.md
  printf 'design\n' > .hv/designs/T04.md
  printf 'plan\n' > .hv/plans/M01-T05.md
  cp .hv/BACKLOG.md before.md
  fe() { [ "$2" = "$3" ] || fail "file-mode claim $1: expected [$2] got [$3]"; }
  out="$("$BIN/hv-item-claim" T01 --as ann 2>&1)"; fe "claim silent" "" "$out"
  "$BIN/hv-item-claim" T01 --as bob; "$BIN/hv-item-release" T01 --as ann; "$BIN/hv-item-state" T01 needs-review
  cmp -s before.md .hv/BACKLOG.md || fail "file-mode claim/release/state wrote BACKLOG.md"
  both="$(printf 'no acceptance criteria in the issue body\nno design or plan note')"
  rc=0; out="$("$BIN/hv-item-ready" T01 2>&1)" || rc=$?; fe "bare" "1:$both" "$rc:$out"
  for id in T02 T03 T04 T05; do
    rc=0; out="$("$BIN/hv-item-ready" $id 2>&1)" || rc=$?; fe "ready $id" "0:" "$rc:$out"
  done
  rc=0; out="$("$BIN/hv-item-ready" T99 2>&1)" || rc=$?; fe "unknown" "1:error: hv-item-ready: [T99] not found in BACKLOG.md or ARCHIVE.md" "$rc:$out"
)
trap 'rm -rf "$TMP"' EXIT
pass "file backend: claim/release/state are silent no-ops, hv-item-ready reads detail file, designs and plans"
