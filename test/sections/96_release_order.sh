echo "release order: tag first, one release finished from the workflow's draft, branch last (F4, #74)"
# Real hv, a local bare origin that reads as github, and a scripted gh: it logs
# its argv and answers `release view` from the state in $RO/state.
RO="$(mktemp -d)"
mkdir -p "$RO/bin"
cat > "$RO/bin/gh" <<'GH'
#!/bin/sh
echo "$*" >> "$RO_LOG"
if [ "$1 $2" = "release view" ]; then
  case $(cat "$RO_STATE") in
    none) echo "release not found" >&2; exit 1 ;;
    empty) echo '{"isDraft":true,"assets":[]}' ;;
    partial) echo '{"isDraft":true,"assets":[{"name":"hv_linux_amd64"}]}' ;;
    ready) echo '{"isDraft":true,"assets":[{"name":"hv_linux_amd64"},{"name":"checksums.txt"}]}' ;;
  esac
  exit 0
fi
echo "https://github.com/fake/repo/releases/tag/$3"
GH
chmod +x "$RO/bin/gh"
export RO_LOG="$RO/log" RO_STATE="$RO/state"

P="$RO/proj"
mkdir -p "$P/.hv"
printf '{"backlog":{"backend":"file"}}\n' > "$P/.hv/config.json"
( cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && printf '.hv/gate-audit.jsonl\n.hv/**/*.lock\n' > .gitignore && echo seed > seed.txt \
  && printf 'version: 2\n' > .goreleaser.yaml \
  && git add seed.txt .gitignore .hv/config.json .goreleaser.yaml && git commit -q -m seed \
  && git init -q --bare github.com/fake/repo.git && printf 'github.com/\n' >> .git/info/exclude \
  && git remote add origin github.com/fake/repo.git && git tag -a v1.0.0 -m v1.0.0 )
RHAS() { [ -n "$(git -C "$P" ls-remote "$1" origin "$2")" ]; }
GATE="--confirm --confirm-note ok"

RC=0; ( cd "$P" && PATH="$RO/bin:$PATH" hvj release push 1.0.0 --branch-only $GATE >/dev/null 2>&1 ) || RC=$?
[ "$RC" = 3 ] || fail "--branch-only before the tag is on origin should exit 3, got $RC"
RHAS --heads main && fail "the branch reached origin before the tag"
RC=0; ( cd "$P" && hvj release push 1.0.0 --tag-only --branch-only $GATE >/dev/null 2>&1 ) || RC=$?
[ "$RC" = 2 ] || fail "--tag-only with --branch-only should exit 2, got $RC"

OUT=$(cd "$P" && hvj release push 1.0.0 --tag-only $GATE) || fail "tag-only push: $OUT"
[ "$(echo "$OUT" | jget data.scope)" = tag ] || fail "tag-only scope: $OUT"
RHAS --tags refs/tags/v1.0.0 || fail "tag-only did not push the tag"
RHAS --heads main && fail "tag-only pushed the branch"
pass "the tag goes first; the branch cannot lead it"

rpub() { ( cd "$P" && PATH="$RO/bin:$PATH" hvj release publish 1.0.0 --title T --body-file - $GATE <<<"notes" ); }
for STATE in none empty partial; do
  echo "$STATE" > "$RO_STATE"; : > "$RO_LOG"
  RC=0; OUT=$(rpub 2>/dev/null) || RC=$?
  [ "$RC" = 3 ] || fail "publish with state '$STATE' should exit 3, got $RC: $OUT"
  grep -q 'release create\|release edit' "$RO_LOG" && fail "publish with state '$STATE' wrote a release: $(cat "$RO_LOG")"
done
pass "publish waits for the workflow: no release, an empty draft or a draft without checksums.txt exit 3"

echo ready > "$RO_STATE"; : > "$RO_LOG"
OUT=$(rpub) || fail "publish of a ready draft: $OUT"
grep -q '^release edit v1.0.0 --title T --notes-file .* --draft=false$' "$RO_LOG" || fail "expected one release edit: $(cat "$RO_LOG")"
grep -q 'release create' "$RO_LOG" && fail "a second release was created: $(cat "$RO_LOG")"
pass "publish finishes the workflow's draft and creates no second release"

OUT=$(cd "$P" && hvj release push 1.0.0 --branch-only $GATE) || fail "branch-only push: $OUT"
[ "$(echo "$OUT" | jget data.scope)" = branch ] || fail "branch-only scope: $OUT"
RHAS --heads main || fail "branch-only did not push the branch"
pass "the branch follows once the release is out"
rm -rf "${RO:?}/proj" "${RO:?}/bin"
