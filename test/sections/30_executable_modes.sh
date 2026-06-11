echo "F66 — bin/ executables tracked at mode 100755 in git index"

# Walk every file in $REPO/bin/ whose on-disk executable bit is set, and
# assert git tracks it at mode 100755 (executable). The recurring trap:
# core.fileMode=false in dev configs means `chmod +x file` on disk does
# NOT propagate to git's tracked mode — files land in the index at 100644.
# Pair every new executable with `git update-index --chmod=+x <file>` so
# the tracked mode is 100755.
#
# Skip non-executable files in bin/ (e.g., hvlib.py is a library, 100644
# is correct). The check is: "anything executable on disk must be
# executable in git", not "everything in bin/ is executable".

cd "$REPO"

violations=""
for f in bin/hv-*; do
  [ -f "$f" ] || continue
  # Only check files that are executable on disk — libraries (.py, .sh
  # sourced helpers) stay 100644.
  [ -x "$f" ] || continue
  mode=$(git ls-tree HEAD -- "$f" 2>/dev/null | awk '{print $1}')
  if [ "$mode" != "100755" ]; then
    violations="${violations}${f} (git mode: ${mode:-untracked})\n"
  fi
done

if [ -n "$violations" ]; then
  printf 'F66 — these executables are not tracked at 100755:\n%b' "$violations" >&2
  fail "F66 — some bin/ executables track at wrong mode in git index"
fi

pass "F66 — all bin/ executables track at mode 100755 in git index"
