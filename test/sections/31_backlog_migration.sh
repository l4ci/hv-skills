echo "hv-bootstrap BACKLOG.md migration (F71/T1)"

# Self-contained: each subtest uses its own BOOT_DIR so state doesn't bleed.
BOOT_DIR="$TMP/boot-test-31"

# Local trap pattern (F38/F62 convention): save runner's EXIT trap, restore after.
trap 'rm -rf "$BOOT_DIR"; trap '"'"'rm -rf "$TMP"'"'"' EXIT' EXIT

# ── (a) Fresh init seeds BACKLOG.md, not TODO.md ─────────────────────────────
mkdir -p "$BOOT_DIR"
( cd "$BOOT_DIR" && "$BIN/hv-bootstrap" )
[ -f "$BOOT_DIR/.hv/BACKLOG.md" ] || fail "hv-bootstrap did not seed BACKLOG.md on fresh init"
! [ -f "$BOOT_DIR/.hv/TODO.md" ] || fail "hv-bootstrap seeded legacy TODO.md on fresh init"
pass "hv-bootstrap seeds BACKLOG.md on fresh init"

# ── (b) Legacy auto-rename ────────────────────────────────────────────────────
rm -rf "$BOOT_DIR"
mkdir -p "$BOOT_DIR/.hv"
echo "# TODO" > "$BOOT_DIR/.hv/TODO.md"
( cd "$BOOT_DIR" && "$BIN/hv-bootstrap" )
[ -f "$BOOT_DIR/.hv/BACKLOG.md" ] || fail "hv-bootstrap did not rename TODO.md → BACKLOG.md"
! [ -f "$BOOT_DIR/.hv/TODO.md" ] || fail "hv-bootstrap left legacy TODO.md after rename"
grep -q "^# TODO$" "$BOOT_DIR/.hv/BACKLOG.md" || fail "content was not preserved after rename"

# Idempotency: second run must exit 0 and preserve the file.
( cd "$BOOT_DIR" && "$BIN/hv-bootstrap" )
[ -f "$BOOT_DIR/.hv/BACKLOG.md" ] || fail "BACKLOG.md missing after idempotent second run"
pass "hv-bootstrap renames legacy TODO.md → BACKLOG.md, idempotent"

# ── (c) Reader contract — load_backlog_corpus reads BACKLOG.md only ──
# The legacy TODO.md fallback was removed in v4.1 (F71 self-flagged it for
# removal once the rename shipped in v4.0). Preflight gates on BACKLOG.md
# presence — the fallback was unreachable in practice. Reader test now
# verifies the corpus reflects what's at BACKLOG.md, not the legacy path.
rm -rf "$BOOT_DIR"
mkdir -p "$BOOT_DIR/.hv"
cat > "$BOOT_DIR/.hv/BACKLOG.md" <<'EOF'
# BACKLOG

## Bugs

- **[B99] [P1] Reader-contract test bug.** Body.
EOF
PYTHONPATH="$BIN" python3 -c "
from hvlib import load_backlog_corpus
corpus = load_backlog_corpus('$BOOT_DIR')
assert 'B99' in corpus, f'load_backlog_corpus did not include BACKLOG.md content; corpus={corpus!r}'
" || fail "load_backlog_corpus did not read BACKLOG.md"
pass "load_backlog_corpus reads BACKLOG.md (legacy TODO.md fallback removed in v4.1)"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BOOT_DIR"
trap 'rm -rf "$TMP"' EXIT
