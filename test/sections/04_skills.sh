echo "hv-skills-index"
# Fresh CLAUDE.md — first run should create the block.
rm -f CLAUDE.md
"$BIN/hv-skills-index" >/dev/null
grep -q "<!-- hv-skills-start -->" CLAUDE.md || fail "hv-skills-index didn't write start marker"
grep -q "<!-- hv-skills-end -->" CLAUDE.md || fail "hv-skills-index didn't write end marker"
grep -q "Capture & pick" CLAUDE.md || fail "hv-skills body missing canonical sections"
grep -q "hv-knowledge-query" CLAUDE.md || fail "hv-skills body missing consult-points"
pass "hv-skills-index creates managed block with canonical body"

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
"$BIN/hv-skills-index" >/dev/null
[ "$(grep -c '<!-- hv-skills-start -->' CLAUDE.md)" = "1" ] || fail "hv-skills-index duplicated start marker"
grep -q "stale body" CLAUDE.md && fail "hv-skills-index didn't replace stale body"
grep -q "Some pre-existing content" CLAUDE.md || fail "hv-skills-index clobbered pre-block content"
grep -q "Trailing content that must survive" CLAUDE.md || fail "hv-skills-index clobbered post-block content"
grep -q "Capture & pick" CLAUDE.md || fail "hv-skills-index didn't write fresh body on update"
pass "hv-skills-index updates in place and preserves unrelated content"

