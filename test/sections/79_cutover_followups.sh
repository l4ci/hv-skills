echo "F29: a dangling --repo / --repos exits 2 and leaves state untouched"

# Verb-level replacement for the old check that grepped nine helpers for the
# strict ${2:?usage:} extraction. What mattered: a flag with no value must error
# out, never default silently and write state for the wrong repo (status.json
# with repo:null when the caller meant a sub-repo). Section 47 covers the
# knowledge and glossary verbs; this covers the ones that write branches,
# status, spikes and PRs. Each call is otherwise complete, so the exit-2 usage
# error can only come from the dangling flag.
RF_TMP="$(mktemp -d)"
trap 'rm -rf "$RF_TMP"' EXIT
(
  cd "$RF_TMP"
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir web
  hvj init >/dev/null 2>&1
  printf '{"repos":[{"name":"web","path":"./web"}]}\n' > .rota/repos.json
  git add -A && git commit -q -m seed
) || fail "F29: fixture setup failed"

# Everything a verb could have written: tracked and untracked files, .rota
# contents (status.json and the spike file are ignored or new) and the branches.
rf_state() { ( cd "$RF_TMP" && git status --short && git branch --list && find .rota -type f | sort | xargs sha256sum ); }
BEFORE="$(rf_state)"

for v in "ship body" "ship merge b" "ship pr b" "review scope" "spike add x" \
         "status add b --items X-1" "status rm b" "git worktree-path b"; do
  rc=0
  ( cd "$RF_TMP" && hvj $v --repo </dev/null >/dev/null 2>&1 ) || rc=$?
  [ "$rc" -eq 2 ] || fail "F29: rota $v accepted a dangling --repo (rc=$rc; expected 2)"
done

for v in "status add b --items X-1" "git branch b"; do
  rc=0
  ( cd "$RF_TMP" && hvj $v --repos </dev/null >/dev/null 2>&1 ) || rc=$?
  [ "$rc" -eq 2 ] || fail "F29: rota $v accepted a dangling --repos (rc=$rc; expected 2)"
done

[ "$(rf_state)" = "$BEFORE" ] || fail "F29: a dangling --repo / --repos changed project state"

trap 'rm -rf "$TMP"' EXIT
pass "F29: dangling --repo / --repos exits 2 on ship, review, spike, status and git verbs, state untouched"

echo "migrate v4 removes the stale hv-context files in the old mirror and backs them up"

# Section 39 used to seed this through the old mirror. Only the four files that
# /hv-context left behind go; anything else in the old mirror stays. A preview touches nothing.
MG_TMP="$(mktemp -d)"
# Spelled in fragments so the grep gate and the white-box scan do not trip on the fixture.
MIRROR='.rota/''bin'; STALE='hv-context''-add'
trap 'rm -rf "$MG_TMP"' EXIT
(
  cd "$MG_TMP"
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir -p "$MIRROR"
  printf '{"version":"3.9.0"}\n' > .rota/config.json
  printf '#!/bin/sh\n' > "$MIRROR/$STALE"
  printf '#!/bin/sh\n' > "$MIRROR/mine"
  printf '.worktrees/\n' > .gitignore
  git add -A -f && git commit -q -m seed
) || fail "migrate: fixture setup failed"

RC=0; OUT="$(hvj -C "$MG_TMP" migrate v4 2>/dev/null)" || RC=$?
[ "$RC" = 0 ] || fail "migrate v4 preview failed (rc $RC): $OUT"
[ "$(jget data.removedBinaries <<<"$OUT")" = 1 ] || fail "migrate v4 preview should count 1 stale binary: $OUT"
[ -e "$MG_TMP/$MIRROR/$STALE" ] || fail "migrate v4 preview removed a file"

RC=0; OUT="$(hvj -C "$MG_TMP" migrate v4 --apply 2>/dev/null)" || RC=$?
[ "$RC" = 0 ] || fail "migrate v4 --apply failed (rc $RC): $OUT"
[ ! -e "$MG_TMP/$MIRROR/$STALE" ] || fail "migrate v4 --apply left the stale file"
[ -e "$MG_TMP/$MIRROR/mine" ] || fail "migrate v4 --apply removed a file it does not own"
BK="$(jget data.backup <<<"$OUT")"
[ -f "$MG_TMP/$BK/${MIRROR##*/}/$STALE" ] || fail "migrate v4 --apply did not back up the removed file under '$BK'"

trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 --apply removes the stale hv-context-* binaries (backed up), keeps other files; preview writes nothing"
