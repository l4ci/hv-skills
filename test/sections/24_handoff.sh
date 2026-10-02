echo "status handoff lookup verb"

# Scratch tmpdir for this section — sibling to runner's $TMP to keep state clean.
HANDOFF_TMP="$(mktemp -d)"
trap 'rm -rf "$HANDOFF_TMP"' EXIT
(
  cd "$HANDOFF_TMP"
  mkdir -p .hv/handoff web api
  # --repo needs registered sub-repos.
  echo '{"repos":[{"name":"web","path":"./web"},{"name":"api","path":"./api"}]}' > .hv/repos.json

  # handoff <expected path|null> <expected exists> <args…>: one lookup, both fields checked.
  handoff() {
    local want_path="$1" want_exists="$2" label="$3"; shift 3
    local out
    out="$(hvj status handoff "$@")" || { echo "FAIL: $label: exit $?"; exit 1; }
    [ "$(echo "$out" | jget data.path)" = "$want_path" ] \
      || { echo "FAIL: $label path (want $want_path, got: $out)"; exit 1; }
    [ "$(echo "$out" | jget data.exists)" = "$want_exists" ] \
      || { echo "FAIL: $label exists (want $want_exists, got: $out)"; exit 1; }
  }

  # --- Read mode: no handoff present → path null, exists false ---
  handoff null false "empty when no handoff" "hv/feature-x"

  # --- Read mode: flat handoff present → flat path ---
  mkdir -p .hv/handoff/hv
  echo dummy > .hv/handoff/hv/feature-x.md
  handoff .hv/handoff/hv/feature-x.md true "flat read" "hv/feature-x"

  # --- Read mode with --repo: prefer @repo form when it exists ---
  echo umbrella > .hv/handoff/hv/feature-x@web.md
  handoff .hv/handoff/hv/feature-x@web.md true "umbrella-keyed read" --repo web "hv/feature-x"

  # --- Read mode with --repo: fall back to flat when @repo absent ---
  rm -f .hv/handoff/hv/feature-x@web.md
  handoff .hv/handoff/hv/feature-x.md true "fallback to flat" --repo web "hv/feature-x"

  # --- Read mode with --repo: nothing exists for either form ---
  rm -f .hv/handoff/hv/feature-x.md
  handoff null false "empty when neither form exists" --repo web "hv/feature-x"

  # --- Canonical mode: path emission, no probing ---
  handoff .hv/handoff/hv/feature-y.md false "canonical flat" --canonical "hv/feature-y"
  handoff .hv/handoff/hv/feature-y@api.md false "canonical umbrella-keyed" --canonical --repo api "hv/feature-y"

  # --- Canonical mode: exists reports the file even though the path is not probed ---
  echo dummy > .hv/handoff/hv/feature-y.md
  handoff .hv/handoff/hv/feature-y.md true "canonical flat, file present" --canonical "hv/feature-y"

  # --- Missing branch arg → exit 2 (usage) ---
  rc=0; "$HV_BIN" status handoff >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: missing branch should exit 2, got $rc"; exit 1; }

  # --- Unknown flag → exit 2 ---
  rc=0; "$HV_BIN" status handoff --bogus "hv/x" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: unknown flag should exit 2, got $rc"; exit 1; }

  # --- Unregistered --repo → exit 3 (resolution) ---
  rc=0; "$HV_BIN" status handoff --repo nonexistent "hv/x" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] || { echo "FAIL: unregistered --repo should exit 3, got $rc"; exit 1; }
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$HANDOFF_TMP"
pass "status handoff lookup + canonical modes, umbrella fallback, error cases"

# white-box-begin: A9 #53 doclint
echo "hv-next/SKILL.md references hv-resolve-handoff"
grep -q "hv-resolve-handoff" "$REPO/hv-next/SKILL.md" || fail "hv-next/SKILL.md missing hv-resolve-handoff call"
pass "hv-next/SKILL.md uses hv-resolve-handoff"
# white-box-end
