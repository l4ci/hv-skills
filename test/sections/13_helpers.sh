# white-box-begin: go-unit A3 #47
echo "hv-types.sh source contract"
# Source the file in a subshell and assert the exported env vars.
( . "$BIN/hv-types.sh"
  [ "$HV_ITEM_TYPES" = "BFT" ] || { echo "HV_ITEM_TYPES=$HV_ITEM_TYPES"; exit 1; }
  [ "$HV_OPEN_SECTIONS" = "Bugs|Features|Tasks" ] || { echo "HV_OPEN_SECTIONS=$HV_OPEN_SECTIONS"; exit 1; }
) || fail "hv-types.sh did not export expected values"
pass "hv-types.sh exports HV_ITEM_TYPES=BFT and HV_OPEN_SECTIONS=Bugs|Features|Tasks"
# white-box-end

# white-box-begin: go-unit A3 #47
echo "hv-types.sh <-> hvlib_types registry parity"
# Both sides parse the same HV_TYPE_REGISTRY line in bin/hv-types.sh — bash
# via the sourcing loop, python via hvlib_types' regex parser. This pins the
# residual duality: any divergence between the two parsers fails here, not
# in some downstream helper. The subshell scopes the sourced env vars; the
# python child inherits them via export and compares against the constants.
( . "$BIN/hv-types.sh"
  PYTHONPATH="$BIN" python3 - <<'PY'
import os
import sys
import hvlib_types as t

PAIRS = [
    ("HV_ITEM_TYPES", t.ITEM_TYPES),
    ("HV_OPEN_SECTIONS", "|".join(t.OPEN_SECTIONS)),
    ("HV_COUNTABLE_TYPES", t.COUNTABLE_TYPES),
    ("HV_PLANNABLE_TYPES", t.PLANNABLE_TYPES),
]
diverged = False
for env_name, py_val in PAIRS:
    env_val = os.environ.get(env_name)
    if env_val != py_val:
        print(f"{env_name}: bash={env_val!r} python={py_val!r}", file=sys.stderr)
        diverged = True
if diverged:
    sys.exit(1)
PY
) || fail "bash hv-types.sh and python hvlib_types diverge on HV_TYPE_REGISTRY"
pass "hv-types.sh env exports match hvlib_types constants (registry parity)"
# white-box-end

echo "## git base + hv-worktree-clear + block + hv-fm-list (refactor)"

# 1. git base
BB_TMP="$(mktemp -d)"
(
  cd "$BB_TMP"
  mkdir -p .hv
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  OUT=$(hvj git base) || { echo "FAIL git base: exit non-zero: $OUT"; exit 1; }
  [ "$(jget data.base <<<"$OUT")" = "main" ] || { echo "FAIL git base: expected 'main', got '$OUT'"; exit 1; }
)
rm -rf "$BB_TMP"
pass "git base resolves 'main' in a fresh git repo"

# 1b. git base respects git.baseBranch from config
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
  OUT=$(hvj git base) || { echo "FAIL git base config override: exit non-zero: $OUT"; exit 1; }
  [ "$(jget data.base <<<"$OUT")" = "develop" ] || { echo "FAIL git base config override: expected 'develop', got '$OUT'"; exit 1; }
)
rm -rf "$BB2_TMP"
pass "git base respects git.baseBranch config override"

# 2. hv-worktree-clear
# white-box-begin: go-unit A8 #52
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
  if git worktree list | grep "$WT_PATH" >/dev/null; then echo "FAIL: worktree still present"; exit 1; fi
  true
)
rm -rf "$WC_TMP"
pass "hv-worktree-clear silently exits on missing branch; removes non-main worktree"
# white-box-end

# 3. block knowledge (flat-list mode)
MB_TMP="$(mktemp -d)"
(
  cd "$MB_TMP"
  mkdir -p .hv
  git init -q && git config user.email t@t && git config user.name t
  OUT=$(hvj block knowledge) || { echo "FAIL: block knowledge exit non-zero: $OUT"; exit 1; }
  [ "$(jget data.status <<<"$OUT")" = "created" ] || { echo "FAIL: expected 'created', got '$OUT'"; exit 1; }
  [ "$(jget data.changed <<<"$OUT")" = "true" ] || { echo "FAIL: expected changed true: $OUT"; exit 1; }
  grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || { echo "FAIL: marker missing"; exit 1; }
  grep -q "no topics yet" CLAUDE.md || { echo "FAIL: empty msg missing"; exit 1; }

  mkdir -p .hv
  printf '# Knowledge\n\n## Build\n- details\n\n## Testing\n- more\n' > .hv/KNOWLEDGE.md
  OUT=$(hvj block knowledge) || { echo "FAIL: block knowledge exit non-zero: $OUT"; exit 1; }
  [ "$(jget data.status <<<"$OUT")" = "updated" ] || { echo "FAIL: expected 'updated', got '$OUT'"; exit 1; }
  grep -q "^- Build" CLAUDE.md || { echo "FAIL: Build topic missing"; exit 1; }
  grep -q "^- Testing" CLAUDE.md || { echo "FAIL: Testing topic missing"; exit 1; }

  printf '# Preamble\n\n<!-- hv:knowledge:start -->\n## Project Knowledge\n- OldTopic\n<!-- hv:knowledge:end -->\n\n# Postamble\n' > CLAUDE.md
  hvj block knowledge >/dev/null
  grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || { echo "FAIL: legacy markers not migrated"; exit 1; }
  grep -q "hv:knowledge:start" CLAUDE.md && { echo "FAIL: legacy colon markers still present"; exit 1; }
  grep -q "^# Preamble" CLAUDE.md || { echo "FAIL: preamble lost"; exit 1; }
)
rm -rf "$MB_TMP"
pass "block knowledge: creates, updates, and migrates legacy markers"

# 4. block decisions --body-file -
BS_TMP="$(mktemp -d)"
(
  cd "$BS_TMP"
  mkdir -p .hv
  CUSTOM_BODY="## Project Decisions

Custom intro.

- Topic A"
  OUT=$(printf '%s' "$CUSTOM_BODY" | hvj block decisions --body-file -) || { echo "FAIL: block decisions exit non-zero: $OUT"; exit 1; }
  [ "$(jget data.status <<<"$OUT")" = "created" ] || { echo "FAIL: expected 'created', got '$OUT'"; exit 1; }
  grep -q "<!-- hv-decisions-start -->" CLAUDE.md || { echo "FAIL: start marker missing"; exit 1; }
  grep -q "<!-- hv-decisions-end -->" CLAUDE.md || { echo "FAIL: end marker missing"; exit 1; }
  grep -q "Topic A" CLAUDE.md || { echo "FAIL: body content missing"; exit 1; }
)
rm -rf "$BS_TMP"
pass "block decisions --body-file - writes stdin body wrapped in markers"

# white-box-begin: go-unit A3 #47
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
# white-box-end

echo "milestone index heals archived Status line"
# Seed MILESTONES.md with a stale archived line; frontmatter says planned.
# milestone index must overwrite the archived line with planned.
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
  hvj milestone index >/dev/null || { echo "FAIL: milestone index exit non-zero"; exit 1; }
  python3 -c "
import re, sys
ms = open('.hv/MILESTONES.md').read()
m = re.search(r'### M99 — Foo\n\n\*\*Status:\*\* (\w+)', ms)
if not (m and m.group(1) == 'planned'):
    print('heal failed; Status line:', m.group(0) if m else 'not found', file=sys.stderr)
    sys.exit(1)
" || { echo "FAIL: milestone index did not heal archived -> planned"; exit 1; }
)
rm -rf "$HEAL_TMP"
pass "milestone index heals stale 'archived' Status line to match frontmatter"

# white-box-begin: go-unit A3 #47
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
# white-box-end

echo "## fsio and section helpers (find_section, section, load_json, dump_json_atomic, update_json)"

# white-box-begin: go-unit A3 #47
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
# white-box-end

# white-box-begin: go-unit A3 #47
# 2. section returns empty string for missing heading
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import section
result = section('foo', 'Bar')
assert result == '', f'expected empty string, got {result!r}'
" || fail "section did not return '' for missing heading"
pass "section returns '' for missing heading"
# white-box-end

# white-box-begin: go-unit A3 #47
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
# white-box-end

# white-box-begin: go-unit A3 #47
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
# white-box-end

# white-box-begin: go-unit A3 #47
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
# white-box-end

# white-box-begin: go-unit A3 #47
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
# white-box-end

# white-box-begin: go-unit A4 #48
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
# white-box-end

# white-box-begin: go-unit A4 #48
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
# white-box-end

echo "## backlog milestones"
FM4I_TMP="$(mktemp -d)"
(
  cd "$FM4I_TMP"
  mkdir -p .hv
  cat > .hv/BACKLOG.md <<'EOF'
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
  OUT=$(hvj backlog milestones ZZ99) || fail "exit non-zero on unknown ID"
  [ "$(jget data.milestones <<<"$OUT")" = "[]" ] || fail "unknown ID produced output: '$OUT'"

  # 2. Single tag
  OUT=$(hvj backlog milestones B70) || fail "single-tag lookup failed"
  [ "$(jget data.milestones <<<"$OUT")" = '["M01"]' ] || fail "single-tag wrong: '$OUT'"

  # 3. Multi-tag
  OUT=$(hvj backlog milestones F70) || fail "multi-tag lookup failed"
  [ "$(jget data.milestones <<<"$OUT")" = '["M02","M10"]' ] || fail "multi-tag wrong: '$OUT'"

  # 4. Dedup across input IDs sharing M01
  OUT=$(hvj backlog milestones B70 T70) || fail "dedup lookup failed"
  [ "$(jget data.milestones <<<"$OUT")" = '["M01"]' ] || fail "dedup wrong: '$OUT'"

  # 5. Completed items don't surface
  OUT=$(hvj backlog milestones F99) || fail "completed lookup failed"
  [ "$(jget data.milestones <<<"$OUT")" = "[]" ] || fail "completed item leaked milestone: '$OUT'"

  # 6. Untagged item is silent
  OUT=$(hvj backlog milestones F71) || fail "untagged lookup failed"
  [ "$(jget data.milestones <<<"$OUT")" = "[]" ] || fail "untagged item leaked: '$OUT'"

  # 7. Numeric sort: M01 < M02 < M10
  OUT=$(hvj backlog milestones B70 F70 T70) || fail "sort lookup failed"
  [ "$(jget data.milestones <<<"$OUT")" = '["M01","M02","M10"]' ] || fail "sort wrong: '$OUT'"

  # 8. No args → exit 2 (usage)
  rc=0; hvj backlog milestones >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || fail "no-args case: expected exit 2, got $rc"
)
rm -rf "$FM4I_TMP"
pass "backlog milestones: lookup semantics, dedup, sort, open-sections only"

echo "## plan rename-check"
PRC_TMP="$(mktemp -d)"
(
  cd "$PRC_TMP"
  mkdir -p .hv
  git init -q
  git config user.email t@t && git config user.name t

  # 1. No args → exit 2 (usage)
  rc=0; hvj plan rename-check >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || fail "no-args case: expected exit 2, got $rc"

  # 2. Single-file match
  printf 'line one referencing OLDNAME\n' > foo.txt
  git add foo.txt && git commit -q -m seed
  OUT=$(hvj plan rename-check OLDNAME) || fail "single-file lookup failed"
  [ "$(jget data.files <<<"$OUT")" = '["foo.txt"]' ] || fail "single-file match wrong: '$OUT'"

  # 3. Multi-file match
  printf 'also has OLDNAME here\n' > bar.md
  printf 'unrelated content\n' > baz.txt
  git add bar.md baz.txt && git commit -q -m "add more"
  OUT=$(hvj plan rename-check OLDNAME) || fail "multi-file lookup failed"
  FILES=$(jget data.files <<<"$OUT")
  grep -q '"foo.txt"' <<<"$FILES" || fail "multi-file missing foo.txt: '$OUT'"
  grep -q '"bar.md"' <<<"$FILES" || fail "multi-file missing bar.md: '$OUT'"
  if grep -q '"baz.txt"' <<<"$FILES"; then fail "matched unrelated baz.txt: '$OUT'"; fi

  # 4. No matches → empty list, exit 0
  OUT=$(hvj plan rename-check NEVER_REFERENCED) || fail "no-match exit non-zero"
  [ "$(jget data.files <<<"$OUT")" = "[]" ] || fail "no-match produced output: '$OUT'"

  # 5. Scope pathspec after --
  OUT=$(hvj plan rename-check OLDNAME -- '*.md') || fail "scope lookup failed"
  [ "$(jget data.files <<<"$OUT")" = '["bar.md"]' ] || fail "scope filter wrong: '$OUT'"
)
rm -rf "$PRC_TMP"

# 6. Outside any git repo
PRC_NON="$(mktemp -d)"
(
  cd "$PRC_NON"
  OUT=$(hvj plan rename-check ANYTHING) || fail "non-repo exit non-zero"
  [ "$(jget data.files <<<"$OUT")" = "[]" ] || fail "non-repo produced output: '$OUT'"
)
rm -rf "$PRC_NON"
pass "plan rename-check: lookup semantics, multi-file, scope filter, non-repo silence"

echo "## knowledge add"
KM_TMP="$(mktemp -d)"
(
  cd "$KM_TMP"
  mkdir -p .hv
  cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Existing Topic

- **Older rule** — body of the older rule. <!-- 2026-04-01 -->
- legacy bullet without a title <!-- 2026-03-15 -->
EOF

  # 1. Missing args → exit 2
  rc=0; hvj knowledge add >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || fail "no-args: expected exit 2, got $rc"
  rc=0; hvj knowledge add --topic "Existing Topic" --body-file - <<<"x" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || fail "missing --title: expected exit 2, got $rc"

  # 2. Missing topic → exit 3
  rc=0; hvj knowledge add --topic "Nonexistent" --title "X" --body-file - <<<"body" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "3" ] || fail "missing topic: expected exit 3, got $rc"

  # 3. Successful insert prepends bullet at top of topic
  OUT=$(hvj knowledge add --topic "Existing Topic" --title "Fresh insight" --date 2026-05-11 --body-file - <<<"Fresh insight body.") || fail "insert failed: $OUT"
  [ "$(jget data.changed <<<"$OUT")" = "true" ] || fail "insert: expected changed true: $OUT"
  grep -q "^- \*\*Fresh insight\*\* — Fresh insight body\. <!-- 2026-05-11 -->" .hv/KNOWLEDGE.md || fail "insert wrong format"
  # The new bullet must come BEFORE 'Older rule'
  python3 -c "
import sys
content = open('.hv/KNOWLEDGE.md').read()
fresh_idx = content.index('**Fresh insight**')
older_idx = content.index('**Older rule**')
assert fresh_idx < older_idx, f'Fresh insight ({fresh_idx}) should come before Older rule ({older_idx})'
" || fail "ordering wrong: Fresh insight should be above Older rule"
  # Legacy bullet preserved
  grep -q "^- legacy bullet without a title <!-- 2026-03-15 -->" .hv/KNOWLEDGE.md || fail "legacy bullet lost"

  # 4. Idempotent: calling with the same title is a no-op
  COUNT_BEFORE=$(grep -c "^\- \*\*Fresh insight\*\*" .hv/KNOWLEDGE.md)
  OUT=$(hvj knowledge add --topic "Existing Topic" --title "fresh insight" --date 2026-05-11 --body-file - <<<"Different body, same title.") || fail "dedup call failed: $OUT"
  [ "$(jget data.changed <<<"$OUT")" = "false" ] || fail "dedup: expected changed false: $OUT"
  COUNT_AFTER=$(grep -c "^\- \*\*Fresh insight\*\*" .hv/KNOWLEDGE.md)
  [ "$COUNT_BEFORE" = "$COUNT_AFTER" ] || fail "dedup failed: title repeated (count went from $COUNT_BEFORE to $COUNT_AFTER)"

  # 5. --body-file <path> alternative (the old inline --body flag is gone)
  printf 'Body passed from a file.\n' > body.txt
  hvj knowledge add --topic "Existing Topic" --title "Body via file" --body-file body.txt --date 2026-05-11 >/dev/null || fail "--body-file path add failed"
  grep -q "^- \*\*Body via file\*\* — Body passed from a file\. <!-- 2026-05-11 -->" .hv/KNOWLEDGE.md || fail "--body-file path wrong"
)
rm -rf "$KM_TMP"
pass "knowledge add: argv, missing topic, insert-at-top, idempotent dedup, --body-file path"

echo "## knowledge amend"
KA_TMP="$(mktemp -d)"
(
  cd "$KA_TMP"
  mkdir -p .hv
  cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Topic A

- **First rule** — body with unique fragment ALPHA. <!-- 2026-04-01 -->
- **Second rule** — body with unique fragment BETA. <!-- 2026-04-02 -->

## Topic B

- **Third rule** — body with fragment GAMMA. <!-- 2026-04-03 -->
EOF

  # 1. Missing args → exit 2
  rc=0; hvj knowledge amend >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || fail "no-args: expected exit 2, got $rc"

  # 2. Missing topic → exit 3
  rc=0; hvj knowledge amend --topic "Nonexistent" --fragment "X" --mode append --body-file - <<<"Y" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "3" ] || fail "missing topic: expected exit 3, got $rc"

  # 3. No matching fragment → exit 3
  rc=0; hvj knowledge amend --topic "Topic A" --fragment "NOTHING" --mode append --body-file - <<<"X" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "3" ] || fail "missing fragment: expected exit 3, got $rc"

  # 4. Successful append after the trailing date comment
  OUT=$(hvj knowledge amend --topic "Topic A" --fragment "ALPHA" --mode append --body-file - <<<"Upstream: hv-skills#42") || fail "append failed: $OUT"
  [ "$(jget data.changed <<<"$OUT")" = "true" ] || fail "append: expected changed true: $OUT"
  grep -q "^- \*\*First rule\*\* — body with unique fragment ALPHA\. <!-- 2026-04-01 --> Upstream: hv-skills#42$" .hv/KNOWLEDGE.md || fail "append wrong (Topic A First rule)"

  # 5. Other bullets and topics untouched
  grep -q "^- \*\*Second rule\*\* — body with unique fragment BETA\. <!-- 2026-04-02 -->$" .hv/KNOWLEDGE.md || fail "Second rule changed unexpectedly"
  grep -q "^- \*\*Third rule\*\* — body with fragment GAMMA\. <!-- 2026-04-03 -->$" .hv/KNOWLEDGE.md || fail "Topic B Third rule changed unexpectedly"

  # 6. Fragment must be within the named topic (Topic B has GAMMA, calling with Topic A should miss)
  rc=0; hvj knowledge amend --topic "Topic A" --fragment "GAMMA" --mode append --body-file - <<<"WRONG" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "3" ] || fail "fragment leaked across topics (Topic A should not match GAMMA from Topic B): exit $rc"
)
rm -rf "$KA_TMP"
pass "knowledge amend: argv, missing topic, missing fragment, scoped append, other-bullet preservation"
