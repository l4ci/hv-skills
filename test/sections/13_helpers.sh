echo "hv-types.sh source contract"
# Source the file in a subshell and assert the exported env vars.
( . "$BIN/hv-types.sh"
  [ "$HV_ITEM_TYPES" = "BFT" ] || { echo "HV_ITEM_TYPES=$HV_ITEM_TYPES"; exit 1; }
  [ "$HV_OPEN_SECTIONS" = "Bugs|Features|Tasks" ] || { echo "HV_OPEN_SECTIONS=$HV_OPEN_SECTIONS"; exit 1; }
) || fail "hv-types.sh did not export expected values"
pass "hv-types.sh exports HV_ITEM_TYPES=BFT and HV_OPEN_SECTIONS=Bugs|Features|Tasks"

echo "## hv-base-branch + hv-worktree-clear + hv-managed-block + hv-fm-list (refactor)"

# 1. hv-base-branch
BB_TMP="$(mktemp -d)"
(
  cd "$BB_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  OUT=$("$BIN/hv-base-branch")
  [ "$OUT" = "main" ] || { echo "FAIL hv-base-branch: expected 'main', got '$OUT'"; exit 1; }
)
rm -rf "$BB_TMP"
pass "hv-base-branch resolves 'main' in a fresh git repo"

# 1b. hv-base-branch respects git.baseBranch from config
BB2_TMP="$(mktemp -d)"
(
  cd "$BB2_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  git checkout -q -b develop
  echo dev > dev.txt && git add dev.txt && git commit -q -m "dev"
  git checkout -q main
  mkdir -p .hv
  printf '{"git":{"baseBranch":"develop"}}\n' > .hv/config.json
  OUT=$("$BIN/hv-base-branch")
  [ "$OUT" = "develop" ] || { echo "FAIL hv-base-branch config override: expected 'develop', got '$OUT'"; exit 1; }
)
rm -rf "$BB2_TMP"
pass "hv-base-branch respects git.baseBranch config override"

# 2. hv-worktree-clear
WC_TMP="$(mktemp -d)"
(
  cd "$WC_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  "$BIN/hv-worktree-clear" nonexistent-branch
  git checkout -q -b feat-x
  echo wip > wip.txt && git add wip.txt && git commit -q -m "wip"
  git checkout -q main
  WT_PATH="$WC_TMP/wt-feat-x"
  git worktree add "$WT_PATH" feat-x -q
  "$BIN/hv-worktree-clear" feat-x
  git worktree list | grep -q "$WT_PATH" && { echo "FAIL: worktree still present"; exit 1; }
  true
)
rm -rf "$WC_TMP"
pass "hv-worktree-clear silently exits on missing branch; removes non-main worktree"

# 3. hv-managed-block knowledge (flat-list mode)
MB_TMP="$(mktemp -d)"
(
  cd "$MB_TMP"
  mkdir -p .hv
  git init -q && git config user.email t@t && git config user.name t
  OUT=$("$BIN/hv-managed-block" knowledge)
  [ "$OUT" = "created" ] || { echo "FAIL: expected 'created', got '$OUT'"; exit 1; }
  grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || { echo "FAIL: marker missing"; exit 1; }
  grep -q "no topics yet" CLAUDE.md || { echo "FAIL: empty msg missing"; exit 1; }

  mkdir -p .hv
  printf '# Knowledge\n\n## Build\n- details\n\n## Testing\n- more\n' > .hv/KNOWLEDGE.md
  OUT=$("$BIN/hv-managed-block" knowledge)
  [ "$OUT" = "updated" ] || { echo "FAIL: expected 'updated', got '$OUT'"; exit 1; }
  grep -q "^- Build" CLAUDE.md || { echo "FAIL: Build topic missing"; exit 1; }
  grep -q "^- Testing" CLAUDE.md || { echo "FAIL: Testing topic missing"; exit 1; }

  printf '# Preamble\n\n<!-- hv:knowledge:start -->\n## Project Knowledge\n- OldTopic\n<!-- hv:knowledge:end -->\n\n# Postamble\n' > CLAUDE.md
  "$BIN/hv-managed-block" knowledge >/dev/null
  grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || { echo "FAIL: legacy markers not migrated"; exit 1; }
  grep -q "hv:knowledge:start" CLAUDE.md && { echo "FAIL: legacy colon markers still present"; exit 1; }
  grep -q "^# Preamble" CLAUDE.md || { echo "FAIL: preamble lost"; exit 1; }
)
rm -rf "$MB_TMP"
pass "hv-managed-block knowledge: creates, updates, and migrates legacy markers"

# 4. hv-managed-block decisions --body-stdin
BS_TMP="$(mktemp -d)"
(
  cd "$BS_TMP"
  mkdir -p .hv
  CUSTOM_BODY="## Project Decisions

Custom intro.

- Topic A"
  OUT=$(printf '%s' "$CUSTOM_BODY" | "$BIN/hv-managed-block" decisions --body-stdin)
  [ "$OUT" = "created" ] || { echo "FAIL: expected 'created', got '$OUT'"; exit 1; }
  grep -q "<!-- hv-decisions-start -->" CLAUDE.md || { echo "FAIL: start marker missing"; exit 1; }
  grep -q "<!-- hv-decisions-end -->" CLAUDE.md || { echo "FAIL: end marker missing"; exit 1; }
  grep -q "Topic A" CLAUDE.md || { echo "FAIL: body content missing"; exit 1; }
)
rm -rf "$BS_TMP"
pass "hv-managed-block decisions --body-stdin writes stdin body wrapped in markers"

# 5. hv-fm-list
FM_TMP="$(mktemp -d)"
(
  mkdir -p "$FM_TMP/docs"
  printf -- '---\nid: X01\ntitle: Alpha\nstatus: active\n---\nBody here.\n' > "$FM_TMP/docs/X01.md"
  printf 'No frontmatter here.\n' > "$FM_TMP/docs/X02.md"
  OUT=$("$BIN/hv-fm-list" "$FM_TMP/docs" id title status)
  echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data) == 1, f'expected 1, got {len(data)}: {data}'
assert data[0]['id'] == 'X01', f'id: {data[0][\"id\"]}'
assert data[0]['title'] == 'Alpha', f'title: {data[0][\"title\"]}'
assert data[0]['status'] == 'active', f'status: {data[0][\"status\"]}'
assert '_path' in data[0], '_path missing'
" || { echo "FAIL: fm-list output wrong"; exit 1; }
)
rm -rf "$FM_TMP"
pass "hv-fm-list extracts FM fields, skips files without frontmatter, includes _path"

echo "hv-vision-index heals archived Status line"
# Seed MILESTONES.md with a stale archived line; frontmatter says planned.
# hv-vision-index must overwrite the archived line with planned.
HEAL_TMP="$(mktemp -d)"
(
  cd "$HEAL_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  mkdir -p .hv/milestones
  printf -- '---\nid: M99\ntitle: Foo\nstatus: planned\ndepends: []\n---\nBody.\n' > .hv/milestones/M99.md
  printf '# MILESTONES\n\n## Active milestones\n\n_(none)_\n\n## Milestones\n\n### M99 — Foo\n\n**Status:** archived\n' > .hv/MILESTONES.md
  touch CLAUDE.md
  git add . && git commit -q -m "seed"
  "$BIN/hv-vision-index"
  python3 -c "
import re, sys
ms = open('.hv/MILESTONES.md').read()
m = re.search(r'### M99 — Foo\n\n\*\*Status:\*\* (\w+)', ms)
if not (m and m.group(1) == 'planned'):
    print('heal failed; Status line:', m.group(0) if m else 'not found', file=sys.stderr)
    sys.exit(1)
" || { echo "FAIL: hv-vision-index did not heal archived -> planned"; exit 1; }
)
rm -rf "$HEAL_TMP"
pass "hv-vision-index heals stale 'archived' Status line to match frontmatter"

## hv-fm-list (CRLF tolerance)
CRLF_TMP="$(mktemp -d)"
(
  mkdir -p "$CRLF_TMP/ms"
  python3 -c "
from pathlib import Path
Path('$CRLF_TMP/ms/M01.md').write_bytes(
  b'---\r\nid: M01\r\ntitle: CRLF Milestone\r\nstatus: planned\r\n---\r\nBody.\r\n'
)
"
  OUT=$("$BIN/hv-fm-list" "$CRLF_TMP/ms" id title)
  echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data) == 1, f'file skipped (CRLF not tolerated): {data}'
assert data[0]['id'] == 'M01', f'id wrong: {data[0][\"id\"]}'
assert data[0]['title'] == 'CRLF Milestone', f'title wrong: {data[0][\"title\"]}'
" || { echo "FAIL: hv-fm-list skipped CRLF file or extracted garbled values"; exit 1; }
)
rm -rf "$CRLF_TMP"
pass "hv-fm-list parses frontmatter with CRLF line endings"

echo "## hvlib.py (find_section, section, load_json, dump_json_atomic, update_json)"

# 1. find_section finds known section
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import find_section
content = '## A\nbody-a\n\n## B\nbody-b\n'
span = find_section(content, 'A')
assert span is not None, 'find_section returned None'
assert content[span[0]:span[1]].strip() == 'body-a', f'got: {content[span[0]:span[1]]!r}'
" || fail "find_section did not locate known section body"
pass "find_section returns correct (start, end) for known section"

# 2. section returns empty string for missing heading
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import section
result = section('foo', 'Bar')
assert result == '', f'expected empty string, got {result!r}'
" || fail "section did not return '' for missing heading"
pass "section returns '' for missing heading"

# 3. load_json returns default on corrupt file
HVLIB_CORRUPT="$(mktemp)"
printf 'not-json' > "$HVLIB_CORRUPT"
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import load_json
result = load_json('$HVLIB_CORRUPT', {'x': 1})
assert result == {'x': 1}, f'expected default, got {result!r}'
" || fail "load_json did not return default on corrupt file"
rm -f "$HVLIB_CORRUPT"
pass "load_json returns default on corrupt file"

# 4. dump_json_atomic writes pretty JSON with trailing newline; no .tmp leftover
HVLIB_ATOMIC="$(mktemp -d)"
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import dump_json_atomic
import os
path = '$HVLIB_ATOMIC/out.json'
dump_json_atomic(path, {'k': 'v'})
content = open(path).read()
assert content == '{' + chr(10) + '  \"k\": \"v\"' + chr(10) + '}' + chr(10), f'got: {content!r}'
assert not os.path.exists(path + '.tmp'), '.tmp file was not cleaned up'
" || fail "dump_json_atomic did not write expected content or left .tmp"
rm -rf "$HVLIB_ATOMIC"
pass "dump_json_atomic writes indent=2 JSON with trailing newline; no .tmp leftover"

# 5. write_text_atomic writes text and cleans up .tmp
HVLIB_TXT="$(mktemp -d)"
python3 -c "
import sys, os; sys.path.insert(0, '$REPO/bin')
from hvlib import write_text_atomic
path = '$HVLIB_TXT/out.md'
write_text_atomic(path, '# Header\n')
content = open(path).read()
assert content == '# Header' + chr(10), f'got: {content!r}'
assert not os.path.exists(path + '.tmp'), '.tmp file was not cleaned up'
" || fail "write_text_atomic did not write expected content or left .tmp"
rm -rf "$HVLIB_TXT"
pass "write_text_atomic writes text atomically; no .tmp leftover"

# 6. update_json mutates and atomically writes
HVLIB_UPDATE="$(mktemp -d)"
python3 -c "
import sys, json; sys.path.insert(0, '$REPO/bin')
from hvlib import dump_json_atomic, update_json
path = '$HVLIB_UPDATE/data.json'
dump_json_atomic(path, {'n': 1})
update_json(path, {}, lambda data: data.update({'n': 2}) or None)
result = json.loads(open(path).read())
assert result == {'n': 2}, f'expected n=2, got {result!r}'
" || fail "update_json did not mutate and write correctly"
rm -rf "$HVLIB_UPDATE"
pass "update_json mutates in place and atomically writes result"

# 7. find_origin_bullet returns origin bullet, ignores Related: references
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import find_origin_bullet
corpus = '- **[F80] [Minor] Refers to B70.** Something. Related: [B70]\n- ~~**[B70] [P1] Real bug.** Description.~~ Done 2026-04-10 [\`abc1234\`]\n'
result = find_origin_bullet(corpus, 'B70')
assert result is not None, 'find_origin_bullet returned None for known ID'
line, title = result
assert title == 'Real bug', f'expected title \"Real bug\", got {title!r}'
assert 'Done' not in line, f'Done suffix not stripped: {line!r}'
assert '~~' not in line, f'strikethrough not unwrapped: {line!r}'
" || fail "find_origin_bullet did not return correct origin bullet"
pass "find_origin_bullet picks origin bullet over Related-link reference"

# 8. parse_todo_fields is order-agnostic
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import parse_todo_fields
# Order: Detail, Related, Milestone
r = parse_todo_fields('Body. Detail: alpha. Related: [F02]. Milestone: M01')
assert r['detail'] == 'alpha.', f'detail wrong: {r}'
assert r['related'] == '[F02].', f'related wrong: {r}'
assert r['milestone'] == 'M01', f'milestone wrong: {r}'
# Order: Milestone, Related, Detail (reversed)
r = parse_todo_fields('Body. Milestone: M01 Related: [F02] Detail: alpha')
assert r['detail'] == 'alpha', f'detail wrong reversed: {r}'
assert r['related'] == '[F02]', f'related wrong reversed: {r}'
assert r['milestone'] == 'M01', f'milestone wrong reversed: {r}'
" || fail "parse_todo_fields not order-agnostic"
pass "parse_todo_fields extracts Detail/Related/Milestone in any order"

echo "## hv-find-milestone-for-items"
FM4I_TMP="$(mktemp -d)"
(
  cd "$FM4I_TMP"
  mkdir -p .hv
  cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B70] [P1] Single-tag bug.** Desc. Milestone: M01

## Features
- **[F70] [Minor] Multi-tag feature.** Desc. Milestone: M02, M10
- **[F71] [Cosmetic] Untagged feature.** Just a tweak.

## Tasks
- **[T70] Plain task tagged M01.** Body. Milestone: M01

## Completed
- ~~**[F99] [Minor] Should not surface.** Desc. Milestone: M99~~ Done 2026-05-01 [`abc1234`]
EOF

  # 1. Unknown IDs → silent, exit 0
  OUT=$("$BIN/hv-find-milestone-for-items" ZZ99) || fail "exit non-zero on unknown ID"
  [ -z "$OUT" ] || fail "unknown ID produced output: '$OUT'"

  # 2. Single tag
  OUT=$("$BIN/hv-find-milestone-for-items" B70)
  [ "$OUT" = "M01" ] || fail "single-tag wrong: '$OUT'"

  # 3. Multi-tag
  OUT=$("$BIN/hv-find-milestone-for-items" F70)
  echo "$OUT" | grep -qx "M02" || fail "multi-tag missing M02: '$OUT'"
  echo "$OUT" | grep -qx "M10" || fail "multi-tag missing M10: '$OUT'"

  # 4. Dedup across input IDs sharing M01
  OUT=$("$BIN/hv-find-milestone-for-items" B70 T70)
  [ "$(echo "$OUT" | wc -l)" -eq 1 ] || fail "dedup failed: '$OUT'"
  [ "$OUT" = "M01" ] || fail "dedup picked wrong value: '$OUT'"

  # 5. Completed items don't surface
  OUT=$("$BIN/hv-find-milestone-for-items" F99)
  [ -z "$OUT" ] || fail "completed item leaked milestone: '$OUT'"

  # 6. Untagged item is silent
  OUT=$("$BIN/hv-find-milestone-for-items" F71)
  [ -z "$OUT" ] || fail "untagged item leaked: '$OUT'"

  # 7. Numeric sort: M01 < M02 < M10
  OUT=$("$BIN/hv-find-milestone-for-items" B70 F70 T70)
  EXPECTED=$(printf 'M01\nM02\nM10\n')
  [ "$OUT" = "$EXPECTED" ] || fail "sort wrong: got '$OUT', want '$EXPECTED'"

  # 8. No args → exit 1 with usage
  if "$BIN/hv-find-milestone-for-items" 2>/dev/null; then
    fail "no-args case exited 0"
  fi
)
rm -rf "$FM4I_TMP"
pass "hv-find-milestone-for-items: lookup semantics, dedup, sort, open-sections only"

