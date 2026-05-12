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

# ── (c) Reader fallback — load_backlog_corpus reads legacy TODO.md when BACKLOG.md absent ──
rm -rf "$BOOT_DIR"
mkdir -p "$BOOT_DIR/.hv"
cat > "$BOOT_DIR/.hv/TODO.md" <<'EOF'
# TODO

## Bugs

- **[B99] [P1] Legacy test bug.** Body.
EOF
PYTHONPATH="$BIN" python3 -c "
from hvlib import load_backlog_corpus
corpus = load_backlog_corpus('$BOOT_DIR')
assert 'B99' in corpus, f'load_backlog_corpus did not include legacy TODO.md content; corpus={corpus!r}'
" || fail "load_backlog_corpus did not read legacy TODO.md when BACKLOG.md absent"
pass "load_backlog_corpus reads legacy TODO.md when BACKLOG.md absent"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BOOT_DIR"
trap 'rm -rf "$TMP"' EXIT
