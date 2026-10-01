echo "hv-pr: GitHub PR / GitLab MR, --closes lines"

TMP_PR="$(mktemp -d)"
trap 'rm -rf "$TMP_PR"' EXIT

# PRBODY <db>: body of the newest stored PR/MR
PRBODY() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["prs"][-1]["body"], end="")' "$1"; }
PRFIELD() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["prs"][-1][sys.argv[2]], end="")' "$1" "$2"; }

for prov in github gitlab; do
  for mode in file issues; do
    P="$TMP_PR/$prov-$mode"; mkdir -p "$P"
    git init -q --bare "$P/origin.git"
    git clone -q "$P/origin.git" "$P/work" 2>/dev/null; mkdir -p "$P/work/.hv"
    printf '{"backlog":{"backend":"%s"},"issues":{"provider":"%s","retryWaitSeconds":0}}\n' \
      "$([ "$mode" = issues ] && echo issues || echo file)" "$prov" > "$P/work/.hv/config.json"
    (
      cd "$P/work"
      git config user.email t@t; git config user.name t
      git checkout -q -b main && git commit -q --allow-empty -m seed && git push -q origin main
      git checkout -q -b feat/x && git commit -q --allow-empty -m work
      export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
      DB="$P/db.json"
      if [ "$mode" = issues ]; then
        "$BIN/hv-item-create" features --title "One" >/dev/null   # F1
        "$BIN/hv-item-create" bugs --title "Two" --tag P1 >/dev/null  # B2
      fi
      url="$(printf 'Summary line' | "$BIN/hv-pr" --closes F1,2 feat/x "My title" 2>/dev/null | tail -n 1)"
      if [ "$prov" = github ]; then
        want_n=$([ "$mode" = issues ] && echo 3 || echo 1)
        [ "$url" = "https://github.com/fake/repo/pull/$want_n" ] || fail "$prov/$mode: url [$url]"
      else
        [ "$url" = "https://gitlab.com/fake/repo/-/merge_requests/1" ] || fail "$prov/$mode: url [$url]"
        [ "$(PRFIELD "$DB" head)" = feat/x ] && [ "$(PRFIELD "$DB" base)" = main ] || fail "$prov/$mode: MR branches"
        grep -q -- '--source-branch feat/x --target-branch main --yes' "$P/log" || fail "$prov/$mode: glab argv"
      fi
      [ "$(PRFIELD "$DB" title)" = "My title" ] || fail "$prov/$mode: title"
      git -C "$P/origin.git" rev-parse --verify -q refs/heads/feat/x >/dev/null || fail "$prov/$mode: branch not pushed"
      if [ "$mode" = issues ]; then
        want="$(printf 'Summary line\n\nCloses #1\nCloses #2')"
      else
        want="Summary line"
      fi
      [ "$(PRBODY "$DB")" = "$want" ] || fail "$prov/$mode: body [$(PRBODY "$DB")]"
    )
    pass "hv-pr $prov / $mode mode"
  done
done

# a --closes item that does not exist fails before anything is pushed
P="$TMP_PR/github-issues"
(
  cd "$P/work"
  git checkout -q -b feat/y && git commit -q --allow-empty -m more
  export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json"
  rc=0; err="$(printf b | "$BIN/hv-pr" --closes F99 feat/y T 2>&1)" || rc=$?
  [ "$rc" = 1 ] || fail "unknown --closes should exit 1 (got $rc)"
  case "$err" in *"F99"*) ;; *) fail "error should name F99: $err" ;; esac
  git -C "$P/origin.git" rev-parse --verify -q refs/heads/feat/y >/dev/null && fail "nothing should be pushed on a bad --closes" || true
)
pass "hv-pr rejects an unknown --closes item before pushing"

trap 'rm -rf "$TMP"' EXIT
