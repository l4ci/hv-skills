echo "Issue mode: review queue, hv-pr-merge, adapter PR ops"

TMP_RQ="$(mktemp -d)"
trap 'rm -rf "$TMP_RQ"' EXIT

for prov in github gitlab; do
  P="$TMP_RQ/$prov"; mkdir -p "$P"
  git init -q --bare "$P/origin.git"
  git clone -q "$P/origin.git" "$P/work" 2>/dev/null; mkdir -p "$P/work/.hv"
  printf '{"backlog":{"backend":"issues"},"issues":{"provider":"%s","retryWaitSeconds":0}}\n' "$prov" > "$P/work/.hv/config.json"
  (
    cd "$P/work"
    git config user.email t@t; git config user.name t
    git checkout -q -b main && git commit -q --allow-empty -m seed && git push -q origin main
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    DB="$P/db.json"
    eq() { [ "$2" = "$3" ] || fail "$prov $1: expected [$2] got [$3]"; }
    # PY <expr over d (the db)>: evaluate against the fake store
    DBQ() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$DB" "$1"; }
    QUEUE() { "$BIN/hv-review-queue" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
    prnum() { sed 's:.*/::' <<<"$1"; }
    pr_open() { # <branch> <body> [target-base]: commit on a branch, push it, open a PR/MR by hand
      git checkout -q -b "$1" main; git commit -q --allow-empty -m "work $1"; git push -q origin "$1"
      if [ "$prov" = github ]; then gh pr create --title "PR $1" --body "$2" --base "${3:-main}" --head "$1"
      else glab mr create --title "PR $1" --description "$2" --source-branch "$1" --target-branch "${3:-main}" --yes; fi
    }

    for t in One Two Three Four Five; do "$BIN/hv-item-create" features --title "$t" >/dev/null; done  # F1..F5
    for id in F1 F2 F3 F4; do "$BIN/hv-item-state" $id needs-review; done
    for id in F1 F2; do "$BIN/hv-proof-add" $id --check unit --result PASS --evidence ok --sha abc1234; done

    # PR A via hv-pr --closes (base main); B and C base dev (host does not auto-close); D "Closes #40" must not link F4
    git checkout -q -b feat/a; git commit -q --allow-empty -m a
    A="$(prnum "$(printf 'Summary' | "$BIN/hv-pr" --closes F1 feat/a "PR a" 2>/dev/null | tail -n 1)")"
    git checkout -q main
    B="$(prnum "$(pr_open feat/b 'Resolves: #2' dev)")"
    git checkout -q main
    C="$(prnum "$(pr_open feat/c 'Fixes #3' dev)")"
    git checkout -q main
    D="$(prnum "$(pr_open feat/d 'Closes #40')")"
    git checkout -q main

    # --- queue listing
    eq "queue ids" "[F1, F2, F3, F4]" "$(QUEUE '[x["id"] for x in d]' | sed "s/'//g")"
    eq "queue prs" "[[$A], [$B], [$C], []]" "$(QUEUE '[[p["number"] for p in x["prs"]] for x in d]')"
    eq "queue fields" "True" "$(QUEUE 'd[0]["title"]=="One" and d[0]["number"]==1 and d[0]["prs"][0]["branch"]=="feat/a" and d[0]["prs"][0]["url"].endswith("/'$A'") and "Closes #1" in d[0]["prs"][0]["body"]')"
    pass "$prov: review queue lists needs-review items with closing-keyword PRs"

    # --- keyword variants (adapter regex)
    eq "keywords" "[1, 2, 3, 4, 40]" "$(PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
a = adapter_for(load_config())
print(a.closed_numbers("closes #1\nFIXED: #2, resolve   #3 and Resolved #4; prefixes #9 unclosed #8 closes #40"))')"
    eq "implements" "$([ $prov = gitlab ] && echo "[7]" || echo "[]")" "$(PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
print(adapter_for(load_config()).closed_numbers("Implements #7"))')"
    eq "prs_closing" "[$A]" "$(PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
print([p["number"] for p in adapter_for(load_config()).prs_closing(1)])')"
    pass "$prov: closing keyword matching"

    # --- checkout, comment, state
    git checkout -q main
    PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
a = adapter_for(load_config()); a.pr_checkout(sys.argv[1]); a.pr_comment(sys.argv[1], "looks good\nsecond line")' "$A"
    eq "checkout" "feat/a" "$(git rev-parse --abbrev-ref HEAD)"
    eq "pr comment" "True" "$(DBQ '[p for p in d["prs"] if p["number"]==int("'$A'")][0]["comments"]==["looks good\nsecond line"]' )"
    eq "pr_state open" "open" "$(PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(adapter_for(load_config()).pr_state(sys.argv[1]))' "$A")"
    git checkout -q main

    # --- merge A: host auto-closes (base main)
    out="$("$BIN/hv-pr-merge" "$A")"
    case "$out" in "merged $A as "*) ;; *) fail "$prov: merge output [$out]" ;; esac
    grep -q '^closed F1$' <<<"$out" || fail "$prov: closed line [$out]"
    eq "A state" "closed" "$(DBQ '[i for i in d["issues"] if i["number"]==1][0]["state"]')"
    eq "A labels cleared" "[]" "$(DBQ '[l for l in [i for i in d["issues"] if i["number"]==1][0]["labels"] if "review" in l or "progress" in l]')"
    eq "A pr state" "merged" "$(DBQ '[p for p in d["prs"] if p["number"]==int("'$A'")][0]["state"]')"
    pass "$prov: merge into main closes the issue"

    # --- merge B: base is dev, host does not close, fallback closes via complete
    out="$("$BIN/hv-pr-merge" "$B")"
    grep -q '^closed F2$' <<<"$out" || fail "$prov: fallback closed line [$out]"
    eq "B state" "closed" "$(DBQ '[i for i in d["issues"] if i["number"]==2][0]["state"]')"
    eq "B done comment" "True" "$(DBQ 'any(c["body"].startswith("Done in `") for c in [i for i in d["issues"] if i["number"]==2][0]["comments"])')"
    eq "B labels cleared" "[]" "$(DBQ '[l for l in [i for i in d["issues"] if i["number"]==2][0]["labels"] if "review" in l]')"
    pass "$prov: merge into a non-default base falls back to complete"

    # --- merge C: unproven → not merged (checked before merging, so a default-branch
    # merge can't let the host close it), exit 5
    rc=0; out="$("$BIN/hv-pr-merge" "$C" 2>"$P/err")" || rc=$?
    eq "C exit" 5 "$rc"
    eq "C not merged" "" "$out"
    if grep -q "pr merge $C\|mr merge $C" "$FAKE_TRACKER_LOG" 2>/dev/null; then fail "$prov: unproven PR $C was merged"; fi
    grep -q 'unproven F3' "$P/err" || fail "$prov: unproven stderr [$(cat "$P/err")]"
    eq "C open" "open" "$(DBQ '[i for i in d["issues"] if i["number"]==3][0]["state"]')"
    eq "C labels" "['changes-requested']" "$(DBQ '[i for i in d["issues"] if i["number"]==3][0]["labels"][-1:]')"
    eq "C no needs-review" "False" "$(DBQ '"needs-review" in [i for i in d["issues"] if i["number"]==3][0]["labels"]')"
    eq "C feedback" "True" "$(DBQ 'any("hv:comment feedback" in c["body"] and "no proof recorded" in c["body"] for c in [i for i in d["issues"] if i["number"]==3][0]["comments"])')"
    pass "$prov: unproven item blocks the merge, stays open, changes-requested, exit 5"

    # --- queue after merges: only F4 (open PR D does not link it)
    eq "queue after" "[F4]" "$(QUEUE '[x["id"] for x in d]' | sed "s/'//g")"
    eq "queue after prs" "[[]]" "$(QUEUE '[[p["number"] for p in x["prs"]] for x in d]')"

    # --- errors
    rc=0; "$BIN/hv-pr-merge" 9999 2>"$P/err" >/dev/null || rc=$?
    eq "unknown pr exit" 1 "$rc"
    rc=0; "$BIN/hv-pr-merge" x 2>/dev/null >&2 || rc=$?
    eq "bad pr arg" 1 "$rc"
    rc=0; FAKE_TRACKER_FAIL="list" "$BIN/hv-review-queue" 2>/dev/null >&2 || rc=$?
    eq "queue tracker failure" 1 "$rc"
    pass "$prov: error exits"
  )
done

# --- file mode
F="$TMP_RQ/file"; mkdir -p "$F/.hv"
echo '{"backlog":{"backend":"file"}}' > "$F/.hv/config.json"
(
  cd "$F"; git init -q
  rc=0; out="$("$BIN/hv-review-queue" 2>"$F/err")" || rc=$?
  [ "$rc" = 0 ] && [ "$out" = "[]" ] && grep -q "hv-review-queue: file backend has no review queue" "$F/err" || fail "file-mode queue: rc=$rc out=[$out]"
  rc=0; "$BIN/hv-pr-merge" 1 2>"$F/err" || rc=$?
  [ "$rc" = 2 ] && grep -q 'use hv-merge' "$F/err" || fail "file-mode merge: rc=$rc [$(cat "$F/err")]"
)
pass "file mode: empty queue, hv-pr-merge refused"

trap 'rm -rf "$TMP"' EXIT
