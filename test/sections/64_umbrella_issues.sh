echo "Umbrella issue mode: per-sub-repo trackers"

TMP_UI="$(mktemp -d)"
trap 'rm -rf "$TMP_UI"' EXIT

U="$TMP_UI/umb"; mkdir -p "$U/.hv" "$TMP_UI/db"
echo '{"backlog":{"backend":"issues"},"issues":{"retryWaitSeconds":0}}' > "$U/.hv/config.json"
echo '{"repos":[{"name":"ghrepo","path":"ghrepo"},{"name":"glrepo","path":"glrepo"}]}' > "$U/.hv/repos.json"
for pair in "ghrepo:https://github.com/o/ghrepo.git" "glrepo:https://gitlab.com/o/glrepo.git"; do
  r="${pair%%:*}"; mkdir -p "$U/$r"
  (cd "$U/$r" && git init -q && git config user.email t@t && git config user.name t \
    && git commit -q --allow-empty -m seed && git remote add origin "${pair#*:}")
done
(
  cd "$U"
  export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB_DIR="$TMP_UI/db" FAKE_TRACKER_LOG="$TMP_UI/log"
  unset FAKE_TRACKER_DB
  eq() { [ "$2" = "$3" ] || fail "umbrella issues $1: expected [$2] got [$3]"; }
  RC() { local rc=0; OUT="$("$@" 2>"$TMP_UI/err")" || rc=$?; RCV=$rc; ERR="$(cat "$TMP_UI/err")"; }
  has() { case "$3" in *"$2"*) ;; *) fail "umbrella issues $1: [$3] lacks [$2]";; esac; }

  # --- capture routing (colliding numbers: both repos start at #1)
  RC "$BIN/hv-item-create" features --title "Gh feat" --field Repos=ghrepo
  eq "create field exit" "0" "$RCV"; eq "create field id" "ghrepo:F1" "$OUT"
  RC "$BIN/hv-item-create" tasks --title "Gh task" --field Repos=ghrepo
  eq "gh T2" "ghrepo:T2" "$OUT"
  RC "$BIN/hv-item-create" features --title "Gl feat" --field Repos=glrepo
  eq "gl F1" "glrepo:F1" "$OUT"
  RC "$BIN/hv-item-create" bugs --tag P1 --title "Gl bug" --field Repos=glrepo
  eq "gl B2" "glrepo:B2" "$OUT"
  RC bash -c "cd '$U/glrepo' && '$BIN/hv-item-create' tasks --title 'Gl cwd task'"
  eq "create cwd exit" "0" "$RCV"; eq "create cwd id" "glrepo:T3" "$OUT"
  RC "$BIN/hv-item-create" tasks --title "Nowhere"
  eq "create missing repo exit" "1" "$RCV"; has "missing repo msg" "Repos=<name>" "$ERR"
  RC "$BIN/hv-item-create" tasks --title "Both" --field Repos=ghrepo,glrepo
  eq "create multi-repo exit" "1" "$RCV"; has "multi-repo msg" "one item per repo" "$ERR"
  RC "$BIN/hv-item-create" tasks --title "Bad" --field Repos=nope
  eq "create unknown repo exit" "1" "$RCV"
  # each item went to its own tracker
  eq "gh store" "2" "$(python3 -c "import json;print(len(json.load(open('$TMP_UI/db/ghrepo.json'))['issues']))")"
  eq "gl store" "3" "$(python3 -c "import json;print(len(json.load(open('$TMP_UI/db/glrepo.json'))['issues']))")"
  grep -q "^gh " "$TMP_UI/log" && grep -q "^glab " "$TMP_UI/log" 2>/dev/null || true

  # --- merged backlog
  RC "$BIN/hv-backlog"
  eq "backlog exit" "0" "$RCV$ERR"
  has "backlog gh feat" "Gh feat" "$OUT"; has "backlog gl feat" "Gl feat" "$OUT"
  has "backlog gl bug" "Gl bug" "$OUT"; has "backlog gl cwd task" "Gl cwd task" "$OUT"
  eq "Repos field gh" "ghrepo" "$("$BIN/hv-todo-field" ghrepo:F1 repos)"
  eq "Repos field gl" "glrepo" "$("$BIN/hv-todo-field" glrepo:F1 repos)"

  # --- refs: qualified
  eq "qualified colon" "Gl feat" "$("$BIN/hv-todo-field" glrepo:F1 title)"
  eq "qualified hash" "Gh feat" "$("$BIN/hv-todo-field" ghrepo#1 title)"
  # bare: unique (type letter or number exists once), ambiguous
  eq "bare unique T2" "Gh task" "$("$BIN/hv-todo-field" T2 title)"
  eq "bare unique B2" "Gl bug" "$("$BIN/hv-todo-field" B2 title)"
  eq "bare unique T3" "Gl cwd task" "$("$BIN/hv-todo-field" '#3' title)"
  RC "$BIN/hv-todo-field" F1 title
  eq "bare ambiguous exit" "1" "$RCV"
  has "ambiguous lists ghrepo" "ghrepo:F1" "$ERR"; has "ambiguous lists glrepo" "glrepo:F1" "$ERR"
  RC "$BIN/hv-todo-field" '#2' title
  eq "bare #2 ambiguous" "1" "$RCV"
  RC "$BIN/hv-todo-field" F99 title
  eq "unknown exit" "1" "$RCV"
  RC "$BIN/hv-todo-field" nope:F1 title
  eq "unknown repo prefix" "1" "$RCV"

  # --- hv-item-claim
  RC "$BIN/hv-item-claim" F1 --as w1
  eq "claim ambiguous exit" "1" "$RCV"; has "claim ambiguous msg" "ghrepo:F1" "$ERR"
  RC "$BIN/hv-item-claim" glrepo:F1 --as w1
  eq "claim qualified exit" "0" "$RCV"; eq "claim qualified out" "claimed glrepo:F1 as w1" "$OUT"
  RC "$BIN/hv-item-claim" B2 --as w2
  eq "claim bare unique" "claimed B2 as w2" "$OUT"
  RC "$BIN/hv-item-claim" glrepo:F1 --as w3
  eq "claim lost exit" "5" "$RCV"
  has "claim only in gl store" "in-progress" "$(cat "$TMP_UI/db/glrepo.json")"
  case "$(cat "$TMP_UI/db/ghrepo.json")" in *in-progress*) fail "umbrella issues: claim leaked into ghrepo";; esac

  # --- hv-complete
  RC "$BIN/hv-complete" F1 abc1234 --reason done --no-proof
  eq "complete ambiguous exit" "1" "$RCV"; has "complete ambiguous msg" "glrepo:F1" "$ERR"
  RC "$BIN/hv-complete" ghrepo:F1 abc1234 --reason done --no-proof
  eq "complete qualified exit" "0" "$RCV"
  RC "$BIN/hv-complete" T2 abc1234 --reason done --no-proof
  eq "complete bare unique exit" "0" "$RCV"
  eq "gh F1 closed" "closed" "$(python3 -c "
import json;d=json.load(open('$TMP_UI/db/ghrepo.json'))
print([i['state'] for i in d['issues'] if i['number']==1][0])")"
  eq "gl F1 still open" "open" "$(python3 -c "
import json;d=json.load(open('$TMP_UI/db/glrepo.json'))
print([i['state'] for i in d['issues'] if i['number']==1][0])")"
  RC "$BIN/hv-backlog"
  case "$OUT" in *"Gh feat"*) fail "umbrella issues: closed ghrepo F1 still listed open";; esac
  has "open gl feat kept" "Gl feat" "$OUT"

  # --- hv-backlog: qualified ID cells (plain IDs collide across sub-repos)
  RC "$BIN/hv-backlog"
  has "backlog qualified glrepo F1" "| glrepo:F1 |" "$OUT"
  has "backlog qualified glrepo B2" "| glrepo:B2 |" "$OUT"
  has "backlog qualified glrepo T3" "| glrepo:T3 |" "$OUT"

  # --- milestones: ID minted over native milestones of ALL sub-repos, tracking issue on the home repo
  NATIVE() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(",".join(m["title"] + ":" + m["state"] for m in adapter_for(load_config(), cwd=sys.argv[1]).milestones("all")))' "$U/$1"; }
  (cd "$U/glrepo" && glab api -X POST projects/:id/milestones -f title="M04 — Legacy" -f description= >/dev/null)
  RC "$BIN/hv-vision-add" "Alpha" "First"
  eq "vision-add mints over all repos" "M05" "$OUT"
  RC "$BIN/hv-vision-add" "Beta" "Second" M05
  eq "vision-add second" "M06" "$OUT"
  eq "home native milestones" "M05 — Alpha:open,M06 — Beta:open" "$(NATIVE ghrepo)"
  eq "other repo untouched" "M04 — Legacy:open" "$(NATIVE glrepo)"
  RC "$BIN/hv-vision-list"
  eq "vision-list exit" "0" "$RCV"
  eq "vision-list ids" "M05,M06" "$(python3 -c 'import json,sys;print(",".join(m["id"]+"" for m in json.loads(sys.argv[1])))' "$OUT")"
  has "vision-show" "id: M05" "$("$BIN/hv-vision-show" M05)"

  # --- assigning an item creates the sub-repo native milestone once
  RC "$BIN/hv-todo-set-field" glrepo:F1 milestone M05
  eq "assign exit" "0" "$RCV"
  eq "gl milestone created" "M04 — Legacy:open,M05 — Alpha:open" "$(NATIVE glrepo)"
  RC "$BIN/hv-todo-set-field" glrepo:B2 milestone M05
  eq "second assign exit" "0" "$RCV"
  eq "gl milestone reused" "M04 — Legacy:open,M05 — Alpha:open" "$(NATIVE glrepo)"
  RC "$BIN/hv-item-create" features --title "Gh ms feat" --field Repos=ghrepo --field Milestone=M05
  eq "capture with milestone" "0" "$RCV"; GHMS="${OUT#ghrepo:}"
  eq "home milestone not duplicated" "M05 — Alpha:open,M06 — Beta:open" "$(NATIVE ghrepo)"
  RC "$BIN/hv-todo-set-field" glrepo:T3 milestone M99
  eq "unknown milestone exit" "1" "$RCV"

  # --- status aggregation
  eq "status planned" "planned" "$(python3 -c 'import json,sys;print([m["status"] for m in json.loads(sys.argv[1]) if m["id"]=="M05"][0])' "$("$BIN/hv-vision-list")")"
  RC "$BIN/hv-vision-status" M05 shipped
  eq "status shipped exit" "0" "$RCV"
  eq "shipped closes every repo" "M05 — Alpha:closed,M06 — Beta:open|M04 — Legacy:open,M05 — Alpha:closed" "$(NATIVE ghrepo)|$(NATIVE glrepo)"
  LSTAT() { python3 -c 'import json,sys;print([m["status"] for m in json.loads(sys.argv[1]) if m["id"]=="M05"][0])' "$("$BIN/hv-vision-list")"; }
  eq "list shipped" "shipped" "$(LSTAT)"
  (cd "$U/glrepo" && glab api -X PUT "projects/:id/milestones/$(PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
print([m["number"] for m in adapter_for(load_config(), cwd=".").milestones("all") if m["title"].startswith("M05")][0])')" -f state_event=activate >/dev/null)
  eq "list active while a repo is open" "active" "$(LSTAT)"
  RC "$BIN/hv-vision-status" M05 planned
  eq "planned reopens all" "M05 — Alpha:open|M05 — Alpha:open" "$(NATIVE ghrepo | tr ',' '\n' | grep M05)|$(NATIVE glrepo | tr ',' '\n' | grep M05)"
  eq "list planned" "planned" "$(LSTAT)"

  # --- release per sub-repo
  RC "$BIN/hv-release-milestone-check" M05
  eq "gate without --repo exit" "1" "$RCV"; has "gate without --repo msg" "--repo" "$ERR"
  RC "$BIN/hv-release-notes-from-issues" M05
  eq "notes without --repo exit" "1" "$RCV"
  RC "$BIN/hv-release-close-milestone" M05 v1.0.0
  eq "close without --repo exit" "1" "$RCV"
  RC "$BIN/hv-release-milestone-check" M05 --repo glrepo
  eq "gate glrepo blocked (B2 in progress)" "6" "$RCV"; has "gate lists B2" "[in-progress]" "$OUT"
  RC "$BIN/hv-release-milestone-check" M05 --repo nope
  eq "gate unknown repo exit" "1" "$RCV"
  RC "$BIN/hv-complete" glrepo:F1 aaa1111 --reason done --no-proof;  eq "complete gl F1" "0" "$RCV"
  RC "$BIN/hv-complete" glrepo:B2 bbb2222 --reason done --no-proof;  eq "complete gl B2" "0" "$RCV"
  RC "$BIN/hv-complete" "ghrepo:$GHMS" ccc3333 --reason done --no-proof; eq "complete gh ms feat" "0" "$RCV"
  RC "$BIN/hv-release-notes-from-issues" M05 --repo glrepo
  has "gl notes new" "Gl feat" "$OUT"; has "gl notes fixed" "Gl bug" "$OUT"
  case "$OUT" in *"Gh ms feat"*) fail "umbrella issues: ghrepo item in glrepo notes";; esac
  RC "$BIN/hv-release-close-milestone" M05 v1.0.0 --repo glrepo
  eq "close glrepo exit" "0" "$RCV"; eq "close glrepo out" "closed-out M05 v1.0.0: 2 issues" "$OUT"
  eq "gl native closed" "closed" "$(NATIVE glrepo | tr ',' '\n' | grep M05 | sed 's/.*://')"
  eq "tracking issue still open after one repo" "planned" "$(LSTAT)"
  RC "$BIN/hv-release-close-milestone" M05 v1.0.0 --repo glrepo
  eq "close idempotent" "0" "$RCV"
  RC "$BIN/hv-release-close-milestone" M05 v1.0.0 --repo ghrepo
  eq "close ghrepo exit" "0" "$RCV"; eq "close ghrepo out" "closed-out M05 v1.0.0: 1 issues" "$OUT"
  eq "list shipped after both" "shipped" "$(LSTAT)"

  # --- review queue + PRs across both repos
  RC "$BIN/hv-item-create" tasks --title "Gh review" --field Repos=ghrepo; GHQ="${OUT#ghrepo:}"
  RC "$BIN/hv-item-create" tasks --title "Gl review" --field Repos=glrepo; GLQ="${OUT#glrepo:}"
  "$BIN/hv-item-state" "ghrepo:$GHQ" needs-review; "$BIN/hv-item-state" "glrepo:$GLQ" needs-review
  (cd "$U/ghrepo" && gh pr create --title "gh pr" --body "Closes #${GHQ#T}" --base main --head feat/gh >/dev/null)
  (cd "$U/glrepo" && glab mr create --title "gl mr" --description "Closes #${GLQ#T}" --source-branch feat/gl --target-branch main --yes >/dev/null)
  RC "$BIN/hv-review-queue"
  eq "queue exit" "0" "$RCV"
  eq "queue repos" "ghrepo:$GHQ,glrepo:$GLQ" "$(python3 -c 'import json,sys;print(",".join(x["id"] for x in json.loads(sys.argv[1])))' "$OUT")"
  eq "queue repo field + prs" "ghrepo:1,glrepo:1" "$(python3 -c 'import json,sys;print(",".join("%s:%d" % (x["repo"], len(x["prs"])) for x in json.loads(sys.argv[1])))' "$OUT")"
  RC "$BIN/hv-pr-merge" 1
  eq "pr-merge without --repo exit" "1" "$RCV"
  "$BIN/hv-proof-add" "glrepo:$GLQ" --check unit --result PASS --evidence ok --sha abc1234 >/dev/null
  PRN="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])[1]["prs"][0]["number"])' "$("$BIN/hv-review-queue")")"
  RC "$BIN/hv-pr-merge" "$PRN" --repo glrepo
  eq "pr-merge glrepo exit" "0" "$RCV"; has "pr-merge closed qualified" "closed glrepo:$GLQ" "$OUT"
  eq "gh queue entry remains" "ghrepo:$GHQ" "$(python3 -c 'import json,sys;print(",".join(x["id"] for x in json.loads(sys.argv[1])))' "$("$BIN/hv-review-queue")")"
  # hv-pr --repo --closes resolves the bare ID inside that sub-repo and pushes there
  git init -q --bare "$TMP_UI/gh-origin.git"
  git -C "$U/ghrepo" config "url.$TMP_UI/gh-origin.git.pushInsteadOf" "https://github.com/o/ghrepo.git"
  git -C "$U/ghrepo" checkout -q -b feat/pr2
  RC bash -c "printf 'Body' | '$BIN/hv-pr' --repo ghrepo --closes $GHQ feat/pr2 'Via hv-pr'"
  eq "hv-pr --repo exit" "0" "$RCV"
  has "hv-pr --repo body" "Closes #${GHQ#T}" "$(python3 -c "import json;print(json.load(open('$TMP_UI/db/ghrepo.json'))['prs'][-1]['body'])")"
  git -C "$U/ghrepo" checkout -q master 2>/dev/null || git -C "$U/ghrepo" checkout -q main 2>/dev/null || true
) 2>"$TMP_UI/subshell.err" || { cat "$TMP_UI/subshell.err" >&2; fail "umbrella issue mode section failed"; }
rm -rf "$TMP_UI"
trap 'rm -rf "$TMP"' EXIT
pass "umbrella issue mode: per-repo stores, merged backlog, refs, claim, complete, capture routing, milestones, release, review queue"
