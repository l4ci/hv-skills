echo "T103 --repo flag guard — bare trailing --repo exits with usage error"

# All 7 knowledge/glossary helpers MUST refuse bare trailing --repo (i.e.
# --repo with no value) and emit a usage line. Pre-T103 the three glossary
# helpers silently set REPO_FLAG="", which auto-resolved to umbrella and
# masked the user's intent. After T103 every helper uses the canonical
# ${2:?$USAGE} guard.
#
# Single-repo callers never pass --repo, so output for valid invocations
# is byte-identical — this section only covers the guard.

for h in hv-knowledge-merge hv-knowledge-tier hv-knowledge-amend \
         hv-knowledge-query hv-glossary-write hv-glossary-read \
         hv-glossary-import; do
  out="$( cd "$TMP" && "$BIN/$h" --repo 2>&1 )" || rc=$? && rc=${rc:-0}
  [ "$rc" -ne 0 ] || fail "T103: $h accepted bare trailing --repo (rc=0; expected non-zero)"
  echo "$out" | grep -q "usage:" || fail "T103: $h did not emit usage line on bare --repo (got: $out)"
  unset rc
done

pass "T103 — all 7 helpers reject bare trailing --repo with usage line"
