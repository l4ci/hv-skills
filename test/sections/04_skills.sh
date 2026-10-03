echo "block skills"
# Fresh CLAUDE.md — first run should create the block.
rm -f CLAUDE.md
"$HV_BIN" block skills >/dev/null
grep -q "<!-- hv-skills-start -->" CLAUDE.md || fail "block skills didn't write start marker"
grep -q "<!-- hv-skills-end -->" CLAUDE.md || fail "block skills didn't write end marker"
grep -q "Capture & pick" CLAUDE.md || fail "hv-skills body missing canonical sections"
grep -q "hv knowledge query" CLAUDE.md || fail "hv-skills body missing consult-points"
pass "block skills creates managed block with canonical body"

# Second run on existing CLAUDE.md with prior content — must update in place,
# not duplicate, and must preserve unrelated content above and below.
cat > CLAUDE.md <<'EOF'
# Project notes

Some pre-existing content.

<!-- hv-skills-start -->
## hv-skills

stale body — should be replaced.
<!-- hv-skills-end -->

Trailing content that must survive.
EOF
"$HV_BIN" block skills >/dev/null
[ "$(grep -c '<!-- hv-skills-start -->' CLAUDE.md)" = "1" ] || fail "block skills duplicated start marker"
grep -q "stale body" CLAUDE.md && fail "block skills didn't replace stale body"
grep -q "Some pre-existing content" CLAUDE.md || fail "block skills clobbered pre-block content"
grep -q "Trailing content that must survive" CLAUDE.md || fail "block skills clobbered post-block content"
grep -q "Capture & pick" CLAUDE.md || fail "block skills didn't write fresh body on update"
pass "block skills updates in place and preserves unrelated content"

