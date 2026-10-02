echo ".worktrees/ — one gitignored worktree root; nothing walks into it"
# Covers #79. (a) hv-bootstrap adds `.worktrees/` to .gitignore once;
# (b) hv-worker-pool creates slots under .worktrees/ and leaves a slot that is
# registered at the old .claude/worktrees/hv-worker path where it is;
# (c) a decoy SKILL.md / CLAUDE.md under .worktrees/ is invisible to
# validate-skills and hv-migrate; (d) census: no helper or validator walks the
# project tree recursively, which is what would find a nested checkout.

TMP_WR="$(mktemp -d)"
trap 'rm -rf "$TMP_WR"' EXIT

# ── (a) hv-bootstrap ────────────────────────────────────────────────────────
mkdir -p "$TMP_WR/boot"
(
  cd "$TMP_WR/boot"
  git init -q -b main .
  "$BIN/hv-bootstrap" >/dev/null 2>&1 || exit 1
  "$BIN/hv-bootstrap" >/dev/null 2>&1 || exit 1
) || fail "hv-bootstrap failed in a fresh repo"
[ "$(grep -cxF '.worktrees/' "$TMP_WR/boot/.gitignore")" = "1" ] \
  || fail "hv-bootstrap must add .worktrees/ to .gitignore exactly once, got $(grep -cxF '.worktrees/' "$TMP_WR/boot/.gitignore")"
# An existing project that already has the whole hv block still gets the line,
# and the block is not repeated.
mkdir -p "$TMP_WR/boot2"
(
  cd "$TMP_WR/boot2"
  git init -q -b main .
  "$BIN/hv-bootstrap" >/dev/null 2>&1 || exit 1
  grep -vxF '.worktrees/' .gitignore | grep -vxF '# Worker worktrees (hv-worker-pool, parallel rounds)' > .gitignore.new && mv .gitignore.new .gitignore
  "$BIN/hv-bootstrap" >/dev/null 2>&1 || exit 1
) || fail "hv-bootstrap re-run failed"
[ "$(grep -cxF '.worktrees/' "$TMP_WR/boot2/.gitignore")" = "1" ] || fail "an upgraded project must gain .worktrees/ once"
# Every spelling git treats as the same ignore must stop a duplicate append.
for SPELL in '.worktrees' '/.worktrees' '/.worktrees/' '.worktrees/'"$(printf '\r')"; do
  mkdir -p "$TMP_WR/boot3"
  ( cd "$TMP_WR/boot3" && rm -rf .git .gitignore && git init -q -b main . && printf '%s\n' "$SPELL" > .gitignore \
      && "$BIN/hv-bootstrap" >/dev/null 2>&1 ) || fail "hv-bootstrap failed with an existing '$SPELL' line"
  tr -d '\r' < "$TMP_WR/boot3/.gitignore" | grep -qxE '/?\.worktrees/?' || fail "fixture lost its ignore line"
  [ "$(tr -d '\r' < "$TMP_WR/boot3/.gitignore" | grep -cE '^/?\.worktrees/?$')" = "1" ] \
    || fail "an existing '$SPELL' line must not be duplicated: $(cat "$TMP_WR/boot3/.gitignore")"
done
[ "$(grep -cxF '.hv/status.json' "$TMP_WR/boot2/.gitignore")" = "1" ] || fail "adding .worktrees/ must not repeat the hv block"
grep -qxF '.worktrees/' "$REPO/.gitignore" || fail "this repo's own .gitignore must list .worktrees/"
pass "hv-bootstrap adds .worktrees/ to .gitignore once, in fresh and upgraded projects"

# ── (b) pool root + legacy slots ────────────────────────────────────────────
mkdir -p "$TMP_WR/repo/.hv"
(
  cd "$TMP_WR/repo"
  git init -q -b main .
  git config user.email t@t; git config user.name t
  printf '.worktrees/\n' > .gitignore
  echo seed > seed.txt; git add seed.txt .gitignore; git commit -q -m seed
) || fail "worktrees-root fixture setup failed"
slot_wt() { python3 -c 'import json,sys; print([s for s in json.load(open(sys.argv[1]))["slots"] if s["name"]==sys.argv[2]][0]["worktree"])' "$TMP_WR/repo/.hv/workers.json" "$1"; }
( cd "$TMP_WR/repo" && "$BIN/hv-worker-pool" init --slots 1 --base main ) >/dev/null 2>&1 || fail "pool init failed"
[ "$(slot_wt w1)" = "$(cd "$TMP_WR/repo" && pwd -P)/.worktrees/w1" ] || fail "new slot must live in <root>/.worktrees/w1, got $(slot_wt w1)"
[ -z "$(git -C "$TMP_WR/repo" status --porcelain -- . ':!.hv')" ] || fail "an ignored .worktrees/ must leave the project clean"
OUT="$(cd "$TMP_WR/repo" && "$BIN/hv-worker-pool" init --slots 1 --base main 2>&1)" || fail "re-init failed"
case "$OUT" in *warning*) fail "no gitignore warning expected when .worktrees/ is ignored: $OUT" ;; esac

# A slot registered at the legacy root keeps its path; init neither errors nor duplicates.
( cd "$TMP_WR/repo" && git worktree remove --force .worktrees/w1 && git branch -D hv-worker/w1 >/dev/null \
    && mkdir -p .claude/worktrees/hv-worker && git worktree add -q -b hv-worker/w1 .claude/worktrees/hv-worker/w1 main )
python3 - "$TMP_WR/repo/.hv/workers.json" "$TMP_WR/repo/.claude/worktrees/hv-worker/w1" <<'PY'
import json, os, sys
p, wt = sys.argv[1:3]; d = json.load(open(p))
d["slots"][0]["worktree"] = os.path.realpath(wt); json.dump(d, open(p, "w"))
PY
OUT="$(cd "$TMP_WR/repo" && "$BIN/hv-worker-pool" init --slots 1 --base main 2>&1)" || fail "init must accept a legacy-path slot, got: $OUT"
case "$(slot_wt w1)" in */.claude/worktrees/hv-worker/w1) ;; *) fail "a healthy legacy slot must keep its registered path, got $(slot_wt w1)" ;; esac
[ ! -e "$TMP_WR/repo/.worktrees/w1" ] || fail "init must not create a second worktree for a legacy slot"
case "$OUT" in *"git worktree move"*) ;; *) fail "init should say how to relocate a legacy slot, got: $OUT" ;; esac
# A registry path that is another repository's worktree is refused, not adopted.
mkdir -p "$TMP_WR/other"
( cd "$TMP_WR/other" && git init -q -b main . && git config user.email t@t && git config user.name t && echo o > o && git add o && git commit -q -m o )
cp "$TMP_WR/repo/.hv/workers.json" "$TMP_WR/workers.keep"
python3 - "$TMP_WR/repo/.hv/workers.json" "$TMP_WR/other" <<'PY'
import json, os, sys
p, wt = sys.argv[1:3]; d = json.load(open(p))
d["slots"][0]["worktree"] = os.path.realpath(wt); json.dump(d, open(p, "w"))
PY
RC=0; OUT="$(cd "$TMP_WR/repo" && "$BIN/hv-worker-pool" init --slots 1 --base main 2>&1)" || RC=$?
[ "$RC" = "3" ] || fail "a slot registered at another repo's checkout must exit 3, got $RC: $OUT"
case "$OUT" in *"another repository"*) ;; *) fail "refusal must name the problem, got: $OUT" ;; esac
cp "$TMP_WR/workers.keep" "$TMP_WR/repo/.hv/workers.json"
# A legacy slot whose worktree is gone is rebuilt under the new root.
( cd "$TMP_WR/repo" && git worktree remove --force .claude/worktrees/hv-worker/w1 )
( cd "$TMP_WR/repo" && "$BIN/hv-worker-pool" init --slots 1 --base main ) >/dev/null 2>&1 || fail "init must rebuild a missing legacy slot"
[ "$(slot_wt w1)" = "$(cd "$TMP_WR/repo" && pwd -P)/.worktrees/w1" ] || fail "a rebuilt slot belongs under .worktrees/, got $(slot_wt w1)"
# Unignored root: warn, don't edit .gitignore.
: > "$TMP_WR/repo/.gitignore"; git -C "$TMP_WR/repo" commit -qam "drop ignore"
OUT="$(cd "$TMP_WR/repo" && "$BIN/hv-worker-pool" init --slots 1 --base main 2>&1)" || fail "init failed on an unignored root"
case "$OUT" in *"not gitignored"*) ;; *) fail "init must warn when .worktrees/ is not ignored, got: $OUT" ;; esac
[ ! -s "$TMP_WR/repo/.gitignore" ] || fail "init must not edit .gitignore itself"
pass "hv-worker-pool: slots go under .worktrees/; legacy slots keep their path; unignored root warns"

# ── (c) decoys under .worktrees/ are not picked up ──────────────────────────
VS="$TMP_WR/vs"
mkdir -p "$VS"
cp -R "$REPO"/hv-* "$REPO/references" "$REPO/.claude-plugin" "$REPO/CHANGELOG.md" "$VS/"
mkdir -p "$VS/test"; cp "$REPO/test/validate-skills.py" "$VS/test/"
BASE_OUT="$(cd "$VS" && python3 test/validate-skills.py 2>&1)" || fail "validate-skills fixture does not pass on its own: $BASE_OUT"
# A decoy skill that would fail every check, and a duplicate of a real one.
mkdir -p "$VS/.worktrees/x/hv-decoy" "$VS/.worktrees/x/hv-go"
printf 'no frontmatter, banner or references\n' > "$VS/.worktrees/x/hv-decoy/SKILL.md"
cp "$VS/hv-go/SKILL.md" "$VS/.worktrees/x/hv-go/SKILL.md"
DECOY_OUT="$(cd "$VS" && python3 test/validate-skills.py 2>&1)" || fail "validate-skills picked up .worktrees/: $DECOY_OUT"
[ "$BASE_OUT" = "$DECOY_OUT" ] || fail "validate-skills output changed with a decoy: '$BASE_OUT' vs '$DECOY_OUT'"

# hv-migrate scans CLAUDE.md/AGENTS.md and .hv/*. The real CLAUDE.md is the
# non-decoy twin: it must be listed, the byte-identical decoy under .worktrees/
# must not, and migrate must not have refused, or an empty scan would pass.
MG="$TMP_WR/mg"
mkdir -p "$MG/.hv/plans" "$MG/.worktrees/x/.hv/plans"
printf 'run /hv-map now\n' > "$MG/CLAUDE.md"
( cd "$MG" && git init -q -b main . && git config user.email t@t && git config user.name t && echo '{"version":"3.9.0"}' > .hv/config.json && printf '.worktrees/\n' > .gitignore && git add -A && git commit -q -m seed )
cp "$MG/CLAUDE.md" "$MG/.worktrees/x/CLAUDE.md"
cp "$MG/CLAUDE.md" "$MG/.worktrees/x/.hv/plans/p.md"
RC=0; MOUT="$(cd "$MG" && "$BIN/hv-migrate" v4 --dry-run --verbose 2>&1)" || RC=$?
case "$MOUT" in *refusing*) fail "hv-migrate refused, so the decoy check proves nothing: $MOUT" ;; esac
case "$MOUT" in *CLAUDE.md*) ;; *) fail "hv-migrate must list the real CLAUDE.md (the non-decoy twin), got: $MOUT" ;; esac
case "$MOUT" in *".worktrees"*) fail "hv-migrate listed a path under .worktrees/: $MOUT" ;; esac
pass "a decoy SKILL.md/CLAUDE.md under .worktrees/ is invisible to validate-skills and hv-migrate"

# ── (d) census: nothing walks the project tree recursively ──────────────────
# validate-skills globs `hv-*/SKILL.md` (one level) and the helpers read fixed
# .hv/ paths or one-level globs. A recursive walk of the project root would
# find nested checkouts; fail on one. No exemptions.
WALK='rglob\(|os\.walk\(|os\.scandir\(|recursive ?= ?True|glob\([^)]*\*\*|find +(\.|\./|"\$PWD"|\$PWD|"\$\(pwd\)"|\$\(pwd\))( |$)'
# The pattern must bite: each of these walks has to trip it.
for SAMPLE in 'Path(".").rglob("SKILL.md")' 'os.walk(".")' 'os.scandir(root)' 'glob.glob("**/SKILL.md", recursive=True)' \
              'glob.glob(f"{d}/**/x")' 'find . -name SKILL.md' 'find "$PWD" -type f' 'find $PWD -type f'; do
  printf '%s\n' "$SAMPLE" | grep -qE "$WALK" || fail "census pattern does not catch: $SAMPLE"
done
for SAMPLE in 'find "$root/cmd" -newer "$bin"' 'sorted(Path(".").glob("hv-*/SKILL.md"))'; do
  printf '%s\n' "$SAMPLE" | grep -qE "$WALK" && fail "census pattern flags an anchored lookup: $SAMPLE"
done
HITS="$(cd "$REPO" && grep -nE "$WALK" bin/* test/validate-skills.py 2>/dev/null || true)"
[ -z "$HITS" ] || fail "recursive tree walk found — it would pick up .worktrees/ checkouts; prune them or anchor the walk: $HITS"
pass "no bin/ helper or validator walks the project tree recursively"

trap 'rm -rf "$TMP"' EXIT
pass "worktrees-root contract"
