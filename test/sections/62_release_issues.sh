echo "Issue mode: release gate, notes from issues, milestone close-out"

TMP_RL="$(mktemp -d)"
trap 'rm -rf "$TMP_RL"' EXIT

for prov in github gitlab; do
  P="$TMP_RL/$prov"; mkdir -p "$P/.hv"
  echo "{\"backlog\":{\"backend\":\"issues\"},\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    printf '# Project\n' > CLAUDE.md
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov $1: expected [$2] got [$3]"; }
    RC() { local rc=0; OUT="$("$@" 2>"$P/err")" || rc=$?; RCV=$rc; }
    ISSUE() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
i = adapter_for(load_config()).get(int(sys.argv[1]), comments=True)
print("|".join([i["state"], str(i["state_reason"]), ",".join(sorted(i["labels"])), ";".join(c["body"] for c in i["comments"])]))' "$1"; }
    NATIVE() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(",".join(m["state"] for m in adapter_for(load_config()).milestones("all") if m["title"].startswith(sys.argv[1] + " ")))' "$1"; }
    WRITES() { grep -cE "issue (edit|close|reopen|comment)|label (create|add)|api -X|milestone (create|edit)" "$P/log" || true; }

    "$BIN/hv-vision-add" "Launch" "Ship it" >/dev/null   # #1 tracking issue
    "$BIN/hv-vision-status" M01 active >/dev/null
    "$BIN/hv-item-create" features --title "Feat" --field Milestone=M01 >/dev/null   # F2
    "$BIN/hv-item-create" bugs --title "Bug" --field Milestone=M01 >/dev/null        # B3
    "$BIN/hv-item-create" tasks --title "Task" --field Milestone=M01 >/dev/null      # T4
    "$BIN/hv-item-create" tasks --title "Dropped" --field Milestone=M01 >/dev/null   # T5
    "$BIN/hv-item-create" tasks --title "Outside" >/dev/null                         # T6 no milestone

    # --- gate: warnings only
    RC "$BIN/hv-release-milestone-check" M01
    eq "warning-only exit" "0" "$RCV"
    eq "warning lines" "warning: #2 Feat (still open)
warning: #3 Bug (still open)
warning: #4 Task (still open)
warning: #5 Dropped (still open)" "$OUT"
    # --- gate: each blocking label
    for pair in "in-progress:in-progress" "needs-review:needs-review" "changes-requested:changes-requested"; do
      st="${pair%%:*}"
      "$BIN/hv-item-state" F2 "$st" >/dev/null
      RC "$BIN/hv-release-milestone-check" M01
      eq "$st blocks" "6" "$RCV"
      eq "$st first line" "blocked: #2 Feat [$st]" "$(printf '%s\n' "$OUT" | head -1)"
    done
    "$BIN/hv-item-state" F2 none >/dev/null
    # --- clear
    for r in "F2 done" "B3 done" "T4 done" "T5 dropped"; do
      set -- $r; "$BIN/hv-complete" "$1" --reason "$2" --no-proof >/dev/null
    done
    RC "$BIN/hv-release-milestone-check" M01
    eq "clear exit" "0" "$RCV"; eq "clear silent" "" "$OUT"
    RC "$BIN/hv-release-milestone-check" M99
    eq "unknown milestone" "1" "$RCV"
    RC "$BIN/hv-release-milestone-check"
    eq "gate usage" "1" "$RCV"

    # --- notes
    git commit -q --allow-empty -m "feat: tagged thing [F82]"
    git tag base
    git commit -q --allow-empty -m "fix: references issue #4"
    git commit -q --allow-empty -m "chore: untagged cleanup"
    git commit -q --allow-empty -m "docs: tagged [T07]"
    RC "$BIN/hv-release-notes-from-issues" M01
    eq "notes exit" "0" "$RCV"
    eq "notes buckets" "### New

- Feat (#2)

### Fixed

- Bug (#3)

### Changed

- Task (#4)" "$OUT"
    RC "$BIN/hv-release-notes-from-issues" M01 --since base
    eq "notes other" "### Other

- chore: untagged cleanup" "$(printf '%s\n' "$OUT" | sed -n '/^### Other/,$p')"
    eq "notes since keeps buckets" "### New" "$(printf '%s\n' "$OUT" | head -1)"
    RC "$BIN/hv-release-notes-from-issues" M01 --since nope
    eq "notes bad ref" "1" "$RCV"
    RC "$BIN/hv-release-notes-from-issues" M99
    eq "notes unknown milestone" "1" "$RCV"

    # --- close-out
    RC "$BIN/hv-release-close-milestone" M01 v1.2.0
    eq "close-out exit" "0" "$RCV"
    eq "close-out line" "closed-out M01 v1.2.0: 3 issues" "$OUT"
    eq "feat closed completed" "closed|completed" "$(ISSUE 2 | cut -d"|" -f1,2)"
    for n in 2 3 4; do
      case "$(ISSUE $n)" in *released*"Released in v1.2.0") ;; *) fail "$prov #$n not released: $(ISSUE $n)" ;; esac
    done
    case "$(ISSUE 5)" in *released*|*"Released in"*) fail "$prov dropped issue released" ;; esac
    case "$(ISSUE 6)" in *released*|*"Released in"*) fail "$prov outside issue released" ;; esac
    eq "native closed" "closed" "$(NATIVE M01)"
    eq "status shipped" "shipped" "$("$BIN/hv-vision-list" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')"
    w="$(WRITES)"
    RC "$BIN/hv-release-close-milestone" M01 v1.2.0
    eq "second run exit" "0" "$RCV"
    eq "second run line" "closed-out M01 v1.2.0: 3 issues" "$OUT"
    eq "second run no writes" "$w" "$(WRITES)"
    eq "one comment only" "1" "$(ISSUE 2 | awk -F'|' '{print $4}' | grep -o 'Released in' | wc -l)"
    RC "$BIN/hv-release-close-milestone" M01
    eq "close usage" "1" "$RCV"
    RC "$BIN/hv-release-close-milestone" M99 v1
    eq "close unknown milestone" "1" "$RCV"
  )
done

# --- file mode refuses
P="$TMP_RL/file"; mkdir -p "$P/.hv/milestones"
(
  cd "$P"
  git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
  echo '{}' > .hv/counters.json
  for h in "hv-release-milestone-check M01" "hv-release-notes-from-issues M01" "hv-release-close-milestone M01 v1"; do
    set -- $h; rc=0; "$BIN/$1" "${@:2}" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 2 ] || fail "file mode $1: expected exit 2 got $rc"
  done
)

trap 'rm -rf "$TMP"' EXIT
pass "release: gate (blocked/warning/clear), notes by type, close-out and idempotent re-run (github, gitlab), file mode refuses"
