echo "E2: Agent Skills frontmatter lint, hv init --codex, Codex discovery (#69)"
# test/validate-skills.py checks every SKILL.md against the Agent Skills spec;
# `hv init --codex` symlinks the skills into .agents/skills; Codex lists them.
VALIDATE="$TESTDIR/validate-skills.py"
SPEC_TMP="$(mktemp -d)"
trap 'rm -rf "$SPEC_TMP"' EXIT
SK='SKILL''.md'

# A fixture repo with one skill whose frontmatter the caller supplies.
sp_fixture() {
  local d="$1"
  mkdir -p "$d/hv-a" "$d/references" "$d/.claude-plugin"
  printf -- '---\n%b---\n\nbody\n' "$2" > "$d/hv-a/$SK"
  printf '{"version": "1.0.0"}\n' > "$d/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## v1.0.0\n' > "$d/CHANGELOG.md"
}
# sp_run <dir> [pending] prints the validator output and returns its exit code.
sp_run() { ( cd "$1" && HV_DOCLINT_PROSE=off HV_SPEC_PENDING="${2:-}" python3 "$VALIDATE" 2>&1 ); }

# (a) a compliant skill passes, optional spec keys included
sp_fixture "$SPEC_TMP/ok" 'name: hv-a\ndescription: Does a thing.\nlicense: MIT\ncompatibility: needs hv\nmetadata:\n  owner: l4ci\nallowed-tools: Bash\n'
OUT="$(sp_run "$SPEC_TMP/ok")" || fail "E2[a]: lint flagged a compliant skill: $OUT"
sp_fixture "$SPEC_TMP/folded" 'name: hv-a\ndescription: >\n  Folded text\n  over lines.\n'
OUT="$(sp_run "$SPEC_TMP/folded")" || fail "E2[a]: lint flagged a folded description: $OUT"
pass "E2[a]: a compliant skill passes, optional spec keys and folded descriptions included"

# (b) each rule fails, and the message names the file and the rule
LONG="$(python3 -c 'print("x" * 1025)')"
n=0
while IFS='|' read -r want fm; do
  n=$((n + 1)); F="$SPEC_TMP/bad$n"; sp_fixture "$F" "$fm"
  RC=0; OUT="$(sp_run "$F")" || RC=$?
  [ "$RC" = 1 ] || fail "E2[b]: lint passed '$want' (rc $RC): $OUT"
  grep -qF "hv-a/$SK" <<<"$OUT" || fail "E2[b]: lint did not name the file for '$want': $OUT"
  grep -qF "$want" <<<"$OUT" || fail "E2[b]: lint did not report '$want': $OUT"
done <<EOF
must equal the directory|name: hv-b\ndescription: ok\n
lowercase letters, digits|name: Hv-a\ndescription: ok\n
lowercase letters, digits|name: hv--a\ndescription: ok\n
the spec allows 1024|name: hv-a\ndescription: $LONG\n
not in the Agent Skills spec|name: hv-a\ndescription: ok\nuser-invocable: true\n
missing required key 'description'|name: hv-a\n
missing required key 'name'|description: ok\n
EOF
pass "E2[b]: a wrong name, a long description, an unknown key and a missing key each fail"

# (c) the transitional sets excuse what is listed, and only that
sp_fixture "$SPEC_TMP/pend" 'name: hv-a\ndescription: ok\nuser-invocable: true\n'
OUT="$(sp_run "$SPEC_TMP/pend" "user-invocable")" || fail "E2[c]: a pending key was flagged: $OUT"
sp_fixture "$SPEC_TMP/clean" 'name: hv-a\ndescription: ok\n'
RC=0; OUT="$(sp_run "$SPEC_TMP/clean" "user-invocable")" || RC=$?
[ "$RC" = 1 ] && grep -qF "uses 'user-invocable' any more" <<<"$OUT" || fail "E2[c]: an unused pending key passed (rc $RC): $OUT"
sp_fixture "$SPEC_TMP/plong" "name: hv-a\ndescription: $LONG\n"
OUT="$(sp_run "$SPEC_TMP/plong" "hv-a/$SK")" || fail "E2[c]: a pending long description was flagged: $OUT"
RC=0; OUT="$(sp_run "$SPEC_TMP/ok" "hv-a/$SK")" || RC=$?
[ "$RC" = 1 ] && grep -qF "remove it from PENDING_LONG" <<<"$OUT" || fail "E2[c]: an unused PENDING_LONG entry passed (rc $RC): $OUT"
pass "E2[c]: pending entries excuse only what they name, and a stale entry fails"

# (d) hv init --codex links every skill, ignores the links, and is a no-op twice
SKILLS="$SPEC_TMP/hv-skills"
mkdir -p "$SKILLS/hv-one" "$SKILLS/hv-two" "$SKILLS/references" "$SKILLS/notes"
for s in hv-one hv-two; do printf -- '---\nname: %s\ndescription: t\n---\n' "$s" > "$SKILLS/$s/$SK"; done
mkdir -p "$SPEC_TMP/proj"
OUT="$(hvj -C "$SPEC_TMP/proj" init --no-blocks)"
[ ! -e "$SPEC_TMP/proj/.agents" ] || fail "E2[d]: plain init created .agents"
OUT="$(hvj -C "$SPEC_TMP/proj" init --no-blocks --codex --skills-dir "$SKILLS")"
for s in hv-one hv-two; do
  [ -L "$SPEC_TMP/proj/.agents/skills/$s" ] || fail "E2[d]: $s is not a symlink"
  [ "$(readlink "$SPEC_TMP/proj/.agents/skills/$s")" = "$SKILLS/$s" ] || fail "E2[d]: $s links to the wrong target"
done
[ ! -e "$SPEC_TMP/proj/.agents/skills/notes" ] || fail "E2[d]: a non-skill directory was linked"
[ "$(printf '%s' "$OUT" | jget data.codex.links[0].status)" = "created" ] || fail "E2[d]: first link status: $OUT"
grep -qx '.agents/skills/hv-\*' "$SPEC_TMP/proj/.gitignore" || fail "E2[d]: links not gitignored"
OUT="$(hvj -C "$SPEC_TMP/proj" init --no-blocks --codex --skills-dir "$SKILLS")"
[ "$(printf '%s' "$OUT" | jget data.changed)" = "false" ] || fail "E2[d]: second run changed something: $OUT"
[ "$(printf '%s' "$OUT" | jget data.codex.links[0].status)" = "unchanged" ] || fail "E2[d]: second run status: $OUT"
[ "$(grep -c '^\.agents/skills/hv-\*$' "$SPEC_TMP/proj/.gitignore")" = 1 ] || fail "E2[d]: gitignore line repeated"
pass "E2[d]: hv init --codex symlinks each skill, gitignores the links and is idempotent"

# (e) it never overwrites, and refuses a bad root or a stray flag before writing
mkdir -p "$SPEC_TMP/keep/.agents/skills/hv-one"
OUT="$(hvj -C "$SPEC_TMP/keep" init --no-blocks --codex --skills-dir "$SKILLS")"
[ ! -L "$SPEC_TMP/keep/.agents/skills/hv-one" ] || fail "E2[e]: an existing directory was replaced"
[ "$(printf '%s' "$OUT" | jget data.codex.links[0].status)" = "skipped" ] || fail "E2[e]: skipped status: $OUT"
mkdir -p "$SPEC_TMP/empty-root" "$SPEC_TMP/nope"
RC=0; hvj -C "$SPEC_TMP/nope" init --codex --skills-dir "$SPEC_TMP/empty-root" >/dev/null 2>&1 || RC=$?
[ "$RC" = 3 ] || fail "E2[e]: a root without skills exited $RC, want 3"
[ ! -e "$SPEC_TMP/nope/.hv" ] && [ ! -e "$SPEC_TMP/nope/.agents" ] || fail "E2[e]: exit 3 left files behind"
RC=0; hvj -C "$SPEC_TMP/nope" init --skills-dir "$SKILLS" >/dev/null 2>&1 || RC=$?
[ "$RC" = 2 ] || fail "E2[e]: --skills-dir without --codex exited $RC, want 2"
pass "E2[e]: existing paths are skipped; a bad root exits 3 and a stray flag exits 2, both before writing"

# (f) Codex lists the linked skills. The probe renders the model-visible input
# with `codex debug prompt-input`: no model session, no login used beyond what
# Codex reads at start, nothing written to the project. It runs against the
# caller's own ~/.codex (CODEX_HOME unset) and skips when codex is missing or
# is not a version this probe was checked against (E1, #68, owns the real pin).
CODEX_PROBED="0.159."
if ! command -v codex >/dev/null 2>&1; then
  echo "  SKIP E2[f]: codex is not installed"
elif ! grep -q "^codex-cli ${CODEX_PROBED//./\\.}" <<<"$(codex --version 2>&1)"; then
  echo "  SKIP E2[f]: codex $(codex --version 2>&1) is outside ${CODEX_PROBED}x"
else
  git -C "$SPEC_TMP/proj" init -q
  # Codex (node) leaves a compile cache in TMPDIR; keep it inside this section's tree.
  mkdir -p "$SPEC_TMP/codex-tmp"
  OUT="$(cd "$SPEC_TMP/proj" && TMPDIR="$SPEC_TMP/codex-tmp" timeout 60 codex debug prompt-input hi 2>&1)" || fail "E2[f]: codex debug prompt-input failed: $OUT"
  for s in hv-one hv-two; do
    grep -qE "(^|[^a-z-])(hv-skills:)?$s: " <<<"$OUT" || fail "E2[f]: Codex did not list $s"
  done
  pass "E2[f]: Codex ${CODEX_PROBED}x lists both skills from .agents/skills"
fi

trap 'rm -rf "$TMP"' EXIT
rm -rf "$SPEC_TMP"
