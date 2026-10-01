echo "F84: managed blocks target AGENTS.md when present, else CLAUDE.md"

TMP_AG="$(mktemp -d)"
trap 'rm -rf "$TMP_AG"' EXIT
mkdir -p "$TMP_AG/.hv"
printf '# Knowledge\n\n## Architecture\n- x\n' > "$TMP_AG/.hv/KNOWLEDGE.md"
run_ag() { ( cd "$TMP_AG" && "$BIN/$1" "${@:2}" ); }

# (a) no AGENTS.md -> CLAUDE.md, exactly as before
printf 'vision body\n' | run_ag hv-managed-block vision --body-stdin >/dev/null
run_ag hv-managed-block knowledge >/dev/null
grep -q "<!-- hv-vision-start -->" "$TMP_AG/CLAUDE.md" || fail "F84[a]: vision block missing from CLAUDE.md"
grep -q "^- Architecture" "$TMP_AG/CLAUDE.md" || fail "F84[a]: knowledge block missing from CLAUDE.md"
[ ! -e "$TMP_AG/AGENTS.md" ] || fail "F84[a]: AGENTS.md must not be created"
pass "F84[a]: no AGENTS.md -> blocks land in CLAUDE.md"

# (b) AGENTS.md present -> blocks land there, CLAUDE.md untouched
printf '# Agents\n' > "$TMP_AG/AGENTS.md"
cp "$TMP_AG/CLAUDE.md" "$TMP_AG/CLAUDE.before"
printf 'vision body\n' | run_ag hv-managed-block vision --body-stdin >/dev/null
run_ag hv-managed-block knowledge >/dev/null
grep -q "<!-- hv-vision-start -->" "$TMP_AG/AGENTS.md" || fail "F84[b]: vision block missing from AGENTS.md"
grep -q "^- Architecture" "$TMP_AG/AGENTS.md" || fail "F84[b]: knowledge block missing from AGENTS.md"
cmp -s "$TMP_AG/CLAUDE.md" "$TMP_AG/CLAUDE.before" || fail "F84[b]: CLAUDE.md must be untouched"
pass "F84[b]: AGENTS.md present -> blocks land in AGENTS.md, CLAUDE.md untouched"

# (c) sub-repo scope resolves per sub-repo dir
mkdir -p "$TMP_AG/web"
printf '{"repos":[{"name":"web","path":"./web"}]}' > "$TMP_AG/.hv/repos.json"
printf '# web agents\n' > "$TMP_AG/web/AGENTS.md"
run_ag hv-managed-block knowledge --repo web >/dev/null
grep -q "<!-- hv-knowledge-start -->" "$TMP_AG/web/AGENTS.md" || fail "F84[c]: sub-repo block missing from web/AGENTS.md"
[ ! -e "$TMP_AG/web/CLAUDE.md" ] || fail "F84[c]: web/CLAUDE.md must not be created"
pass "F84[c]: sub-repo scope honours the sub-repo's AGENTS.md"

trap 'rm -rf "$TMP"' EXIT
rm -rf "$TMP_AG"
