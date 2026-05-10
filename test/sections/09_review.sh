echo "hv-review-scaffolding — flags scaffolding patterns in diff"
SCAF_TMP="$(mktemp -d)"
trap 'rm -rf "$SCAF_TMP"' EXIT
(
  cd "$SCAF_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  mkdir -p .hv/bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  # Seed main with a benign file
  echo "ok" > a.txt
  git add a.txt && git commit -q -m "init"
  git checkout -q -b feat
  # Add a file with scaffolding text and a clean line
  cat > b.sh <<'EOF'
#!/usr/bin/env bash
# Umbrella behavior is added in Task 7 — for now --repo is parsed but ignored
set -e
echo "real work"
EOF
  git add b.sh && git commit -q -m "feat: add b.sh"

  OUT=$(.hv/bin/hv-review-scaffolding main feat)
  echo "$OUT" | grep -q "b.sh:.*Task 7" || fail "scaffolding scan missed 'Task 7' in b.sh: $OUT"

  # Add a clean-only commit; helper output should still surface the existing match
  echo "more" >> a.txt && git add a.txt && git commit -q -m "feat: tweak a"
  OUT2=$(.hv/bin/hv-review-scaffolding main feat)
  echo "$OUT2" | grep -q "Task 7" || fail "scaffolding scan lost match after benign commit: $OUT2"

  # Empty diff (current branch == base) → empty output, exit 0
  git checkout -q main
  set +e
  OUT3=$(.hv/bin/hv-review-scaffolding main main)
  RC=$?
  set -e
  [ $RC -eq 0 ] || fail "empty-diff scan should exit 0, got $RC"
  [ -z "$OUT3" ] || fail "empty-diff scan should produce empty output, got: $OUT3"

  pass "hv-review-scaffolding flags scaffolding + handles empty diff"
)
trap 'rm -rf "$TMP"' EXIT
