echo "hv-resolve-handoff lookup helper"

# Scratch tmpdir for this section — sibling to runner's $TMP to keep state clean.
HANDOFF_TMP="$(mktemp -d)"
trap 'rm -rf "$HANDOFF_TMP"' EXIT
(
  cd "$HANDOFF_TMP"
  mkdir -p .hv/handoff

  # --- Read mode: no handoff present → empty stdout, exit 0 ---
  out="$("$BIN/hv-resolve-handoff" "hv/feature-x")"
  [ -z "$out" ] || { echo "FAIL: empty stdout expected when no handoff (got: $out)"; exit 1; }

  # --- Read mode: flat handoff present → prints flat path ---
  mkdir -p .hv/handoff/hv
  echo dummy > .hv/handoff/hv/feature-x.md
  out="$("$BIN/hv-resolve-handoff" "hv/feature-x")"
  [ "$out" = ".hv/handoff/hv/feature-x.md" ] || { echo "FAIL: flat read (got: $out)"; exit 1; }

  # --- Read mode with --repo: prefer @repo form when it exists ---
  echo umbrella > .hv/handoff/hv/feature-x@web.md
  out="$("$BIN/hv-resolve-handoff" --repo web "hv/feature-x")"
  [ "$out" = ".hv/handoff/hv/feature-x@web.md" ] || { echo "FAIL: umbrella-keyed read (got: $out)"; exit 1; }

  # --- Read mode with --repo: fall back to flat when @repo absent ---
  rm -f .hv/handoff/hv/feature-x@web.md
  out="$("$BIN/hv-resolve-handoff" --repo web "hv/feature-x")"
  [ "$out" = ".hv/handoff/hv/feature-x.md" ] || { echo "FAIL: fallback to flat (got: $out)"; exit 1; }

  # --- Read mode with --repo: nothing exists for either form ---
  rm -f .hv/handoff/hv/feature-x.md
  out="$("$BIN/hv-resolve-handoff" --repo web "hv/feature-x")"
  [ -z "$out" ] || { echo "FAIL: empty when neither form exists (got: $out)"; exit 1; }

  # --- Write mode: canonical path emission, no probing ---
  out="$("$BIN/hv-resolve-handoff" --write "hv/feature-y")"
  [ "$out" = ".hv/handoff/hv/feature-y.md" ] || { echo "FAIL: write flat (got: $out)"; exit 1; }
  out="$("$BIN/hv-resolve-handoff" --write --repo api "hv/feature-y")"
  [ "$out" = ".hv/handoff/hv/feature-y@api.md" ] || { echo "FAIL: write umbrella-keyed (got: $out)"; exit 1; }

  # --- Missing branch arg → exit 1 with usage ---
  if "$BIN/hv-resolve-handoff" >/dev/null 2>&1; then
    echo "FAIL: missing branch should exit 1"
    exit 1
  fi

  # --- Unknown flag → exit 1 ---
  if "$BIN/hv-resolve-handoff" --bogus "hv/x" >/dev/null 2>&1; then
    echo "FAIL: unknown flag should exit 1"
    exit 1
  fi
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$HANDOFF_TMP"
pass "hv-resolve-handoff lookup + write modes, umbrella fallback, error cases"

echo "hv-next/SKILL.md references hv-resolve-handoff"
grep -q "hv-resolve-handoff" "$REPO/hv-next/SKILL.md" || fail "hv-next/SKILL.md missing hv-resolve-handoff call"
pass "hv-next/SKILL.md uses hv-resolve-handoff"
