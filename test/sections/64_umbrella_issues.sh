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

  # --- milestone ops are deferred to T2
  RC "$BIN/hv-vision-list"
  eq "milestones unavailable exit" "2" "$RCV"
) 2>"$TMP_UI/subshell.err" || { cat "$TMP_UI/subshell.err" >&2; fail "umbrella issue mode section failed"; }
rm -rf "$TMP_UI"
trap 'rm -rf "$TMP"' EXIT
pass "umbrella issue mode: per-repo stores, merged backlog, refs, claim, complete, capture routing"
