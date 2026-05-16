echo "F22 /hv-init mirror — strips stale helpers before copy"

# Builds a fixture .hv/bin/ that holds stale helpers (simulating a v3 → v4
# update), then runs the canonical /hv-init Step 2 mirror block and asserts
# the stale binaries are gone while every canonical helper landed and is
# executable.
#
# The mirror block under test is the exact sequence from hv-init/SKILL.md
# Step 2 — kept in sync via the section header below. If SKILL.md changes
# the block, mirror the change here and bump the comment.
#
# Source-of-truth block (mirrors hv-init/SKILL.md Step 2):
#   find .hv/bin/ -maxdepth 1 \( -name 'hv-*' -o -name 'hvlib.py' \) -type f -delete
#   cp "$SRC"/hv-* "$SRC"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*

TMP_MIRROR="$(mktemp -d)"
trap 'rm -rf "$TMP_MIRROR"' EXIT
cd "$TMP_MIRROR"
git init -q
git config user.email t@t
git config user.name t
mkdir -p .hv/bin

# Stage stale helpers: a renamed-away `hv-context-add` (F18 cut), a
# renamed-away `hvlib.py` (just to prove the filter catches it), and an
# unrelated user-dropped binary that the mirror should still strip.
echo '#!/bin/sh' > .hv/bin/hv-context-add
echo '#!/bin/sh' > .hv/bin/hv-stale-helper
echo '# old hvlib' > .hv/bin/hvlib.py
chmod +x .hv/bin/hv-context-add .hv/bin/hv-stale-helper
# Also stage a subdirectory and a non-hv- file the mirror MUST leave alone.
mkdir -p .hv/bin/__pycache__
touch .hv/bin/__pycache__/marker
echo "not a helper" > .hv/bin/README.txt

# Run the canonical mirror block — SRC mirrors how SKILL.md sets it from
# the resolved plugin root; in the smoke we point at the repo's canonical
# bin/ via $BIN.
SRC="$BIN"
find .hv/bin/ -maxdepth 1 \( -name 'hv-*' -o -name 'hvlib.py' \) -type f -delete
cp "$SRC"/hv-* "$SRC"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*

# Assert: stale helpers stripped.
[ ! -f .hv/bin/hv-context-add ] || fail "stale hv-context-add not removed by mirror"
[ ! -f .hv/bin/hv-stale-helper ] || fail "stale hv-stale-helper not removed by mirror"
pass "F22 mirror — stale hv-* helpers stripped before copy"

# Assert: stale hvlib.py replaced (must exist post-cp, and not match the old marker).
[ -f .hv/bin/hvlib.py ] || fail "hvlib.py missing after mirror"
grep -q '# old hvlib' .hv/bin/hvlib.py && fail "stale hvlib.py was not replaced by canonical copy"
pass "F22 mirror — stale hvlib.py replaced by canonical copy"

# Assert: canonical helpers landed and are executable.
[ -x .hv/bin/hv-bootstrap ] || fail "canonical hv-bootstrap missing or not executable post-mirror"
[ -x .hv/bin/hv-backlog ] || fail "canonical hv-backlog missing or not executable post-mirror"
[ -x .hv/bin/hv-knowledge-query ] || fail "canonical hv-knowledge-query missing or not executable post-mirror"
pass "F22 mirror — canonical helpers landed executable"

# Assert: non-hv- file untouched (user/runtime artifacts outside the mirror filter survive).
[ -f .hv/bin/README.txt ] || fail "non-hv- README.txt was stripped by mirror (filter too broad)"
pass "F22 mirror — non-hv- files outside filter survive"

# Assert: subdirectory survives (find -maxdepth 1 -type f scopes to files only).
[ -d .hv/bin/__pycache__ ] || fail "__pycache__ subdirectory removed by mirror (filter must be -type f)"
[ -f .hv/bin/__pycache__/marker ] || fail "__pycache__ contents removed by mirror"
pass "F22 mirror — subdirectories outside filter survive"

# Assert: re-running the mirror is idempotent — no error, no churn.
find .hv/bin/ -maxdepth 1 \( -name 'hv-*' -o -name 'hvlib.py' \) -type f -delete
cp "$SRC"/hv-* "$SRC"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
[ -x .hv/bin/hv-bootstrap ] || fail "idempotent re-mirror dropped canonical helpers"
pass "F22 mirror — idempotent re-run leaves canonical bin/ intact"

cd "$TMP"
trap 'rm -rf "$TMP"' EXIT
