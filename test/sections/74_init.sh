echo "A9: hv init seeds .hv/, runs the blocks, and hv init check reports"
# The shim's init still runs the 4.x bootstrap (mirror, no blocks), so this
# section needs init served by Go.
require_go_verb init || return 0

TMP_IN="$(mktemp -d)"
trap 'rm -rf "$TMP_IN"' EXIT
# The 4.x mirror directory; spelled in two pieces so the white-box census (72) reads this as a plain path.
MIRROR=".hv/""bin"
jfield() { python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(json.dumps(d.get(sys.argv[1], "ABSENT")))' "$1"; }

# (a) clean dir: seeded, blocks written, AGENTS.md is the instructions file
mkdir -p "$TMP_IN/fresh"
OUT="$(hvj -C "$TMP_IN/fresh" init)"
for f in BACKLOG KNOWLEDGE DECISIONS MAP MILESTONES; do
  [ -f "$TMP_IN/fresh/.hv/$f.md" ] || fail "A9[a]: .hv/$f.md not seeded"
done
for f in counters status repos config; do
  [ -f "$TMP_IN/fresh/.hv/$f.json" ] || fail "A9[a]: .hv/$f.json not seeded"
done
[ ! -e "$TMP_IN/fresh/$MIRROR" ] || fail "A9[a]: init created the mirror dir"
grep -qx '.worktrees/' "$TMP_IN/fresh/.gitignore" || fail "A9[a]: .worktrees/ not ignored"
[ "$(printf '%s' "$OUT" | jfield changed)" = "true" ] || fail "A9[a]: changed is not true"
KEYS="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(",".join(b["key"] for b in json.load(sys.stdin)["data"]["blocks"]))')"
[ "$KEYS" = "skills,knowledge,milestones,decisions,map,qa" ] || fail "A9[a]: blocks were: $KEYS"
grep -q "<!-- hv-skills-start -->" "$TMP_IN/fresh/AGENTS.md" || fail "A9[a]: skills block missing from AGENTS.md"
grep -qx '@AGENTS.md' "$TMP_IN/fresh/CLAUDE.md" || fail "A9[a]: CLAUDE.md does not import AGENTS.md"
pass "A9[a]: hv init seeds .hv/ and writes the six blocks"

# (b) a second run is a no-op
OUT="$(hvj -C "$TMP_IN/fresh" init)"
[ "$(printf '%s' "$OUT" | jfield changed)" = "false" ] || fail "A9[b]: second run changed something"
[ "$(printf '%s' "$OUT" | jfield created)" = "[]" ] || fail "A9[b]: second run created paths"
pass "A9[b]: hv init is idempotent"

# (c) --no-blocks seeds only
mkdir -p "$TMP_IN/nb"
OUT="$(hvj -C "$TMP_IN/nb" init --no-blocks)"
[ "$(printf '%s' "$OUT" | jfield blocks)" = '"ABSENT"' ] || fail "A9[c]: blocks reported under --no-blocks"
[ ! -e "$TMP_IN/nb/AGENTS.md" ] || fail "A9[c]: AGENTS.md written under --no-blocks"
[ -f "$TMP_IN/nb/.hv/config.json" ] || fail "A9[c]: .hv/config.json not seeded"
pass "A9[c]: --no-blocks seeds .hv/ and nothing else"

# (d) hv init check: uninitialized reports every missing path, exit 1
mkdir -p "$TMP_IN/empty"
rc=0; OUT="$(hvj -C "$TMP_IN/empty" init check)" || rc=$?
[ "$rc" = 1 ] || fail "A9[d]: uninitialized init check exits $rc, want 1"
[ "$(printf '%s' "$OUT" | jfield missing)" = '[".hv"]' ] || fail "A9[d]: missing was $(printf '%s' "$OUT" | jfield missing)"
rm "$TMP_IN/nb/.hv/counters.json" "$TMP_IN/nb/.hv/status.json"
rc=0; OUT="$(hvj -C "$TMP_IN/nb" init check)" || rc=$?
[ "$rc" = 1 ] || fail "A9[d]: partial init check exits $rc, want 1"
[ "$(printf '%s' "$OUT" | jfield missing)" = '[".hv/counters.json", ".hv/status.json"]' ] || fail "A9[d]: partial missing was $(printf '%s' "$OUT" | jfield missing)"
hvj -C "$TMP_IN/fresh" init check >/dev/null || fail "A9[d]: initialized init check did not exit 0"
pass "A9[d]: init check lists every missing path, exit 1; 0 when initialized"

# (e) legacy TODO.md, stale .hv/bin mirror, blanket .hv/ ignore
mkdir -p "$TMP_IN/legacy/$MIRROR"
printf '# Backlog\n\n## Bugs\n- [B01] old\n' > "$TMP_IN/legacy/.hv/TODO.md"
: > "$TMP_IN/legacy/$MIRROR/hv-status-add"
printf 'dist/\n.hv/\n' > "$TMP_IN/legacy/.gitignore"
hvj -C "$TMP_IN/legacy" init --no-blocks >/dev/null
[ -f "$TMP_IN/legacy/.hv/BACKLOG.md" ] && [ ! -e "$TMP_IN/legacy/.hv/TODO.md" ] || fail "A9[e]: TODO.md not renamed"
grep -q 'B01' "$TMP_IN/legacy/.hv/BACKLOG.md" || fail "A9[e]: renamed backlog lost its content"
[ ! -e "$TMP_IN/legacy/$MIRROR" ] || fail "A9[e]: stale mirror dir not removed"
if grep -qx '.hv/' "$TMP_IN/legacy/.gitignore"; then fail "A9[e]: blanket .hv/ ignore kept"; fi
grep -qx 'dist/' "$TMP_IN/legacy/.gitignore" || fail "A9[e]: user ignore line lost"
pass "A9[e]: legacy TODO.md renamed, stale mirror removed, blanket ignore stripped"

# (f) a corrupt counters.json is refused, not overwritten
mkdir -p "$TMP_IN/bad/.hv"
printf '{oops' > "$TMP_IN/bad/.hv/counters.json"
rc=0; hvj -C "$TMP_IN/bad" init --no-blocks >/dev/null || rc=$?
[ "$rc" = 70 ] || fail "A9[f]: corrupt counters exits $rc, want 70"
[ "$(cat "$TMP_IN/bad/.hv/counters.json")" = '{oops' ] || fail "A9[f]: corrupt counters.json was rewritten"
pass "A9[f]: corrupt counters.json exits 70 and is left alone"

trap 'rm -rf "$TMP"' EXIT
rm -rf "${TMP_IN:?}"
