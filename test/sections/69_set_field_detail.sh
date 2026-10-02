echo "hv-todo-set-field: detail"

TMP_SD="$(mktemp -d)"
trap 'rm -rf "$TMP_SD"' EXIT
mkdir -p "$TMP_SD/.hv/features"
printf '# F10\n' > "$TMP_SD/.hv/features/F10.md"
printf '# F11\n' > "$TMP_SD/.hv/features/F11.md"
cat > "$TMP_SD/.hv/BACKLOG.md" <<'BL'
# TODO

## Features
- **[F10] [Major] With fields.** Summary. Related: [F11] Since: abc1234
- **[F12] [Minor] Bare.** Summary only.

## Completed
BL
SD() ( cd "$TMP_SD" && "$BIN/hv-todo-set-field" "$@" )
LINE() { grep -F "[$1]" "$TMP_SD/.hv/BACKLOG.md"; }

SD F10 detail .hv/features/F10.md
[ "$(LINE F10)" = '- **[F10] [Major] With fields.** Summary. Detail: `.hv/features/F10.md` Related: [F11] Since: abc1234' ] \
  || fail "detail[set]: not inserted before Related: $(LINE F10)"
SD F12 detail .hv/features/F10.md
[ "$(LINE F12)" = '- **[F12] [Minor] Bare.** Summary only. Detail: `.hv/features/F10.md`' ] \
  || fail "detail[set]: not appended on a bare bullet: $(LINE F12)"
pass "detail[set]: backticked path, before the other fields (or at the end)"

SD F10 detail .hv/features/F11.md
[ "$(LINE F10)" = '- **[F10] [Major] With fields.** Summary. Detail: `.hv/features/F11.md` Related: [F11] Since: abc1234' ] \
  || fail "detail[replace]: $(LINE F10)"
BEFORE="$(md5sum "$TMP_SD/.hv/BACKLOG.md")"
SD F10 detail .hv/features/F11.md || fail "detail[idempotent]: errored"
SD F10 detail '`.hv/features/F11.md`' || fail "detail[idempotent]: backticked input errored"
[ "$BEFORE" = "$(md5sum "$TMP_SD/.hv/BACKLOG.md")" ] || fail "detail[idempotent]: file rewritten"
pass "detail[replace]: replaced in place; same value (bare or backticked) is a no-op"

SD F10 detail ""
[ "$(LINE F10)" = '- **[F10] [Major] With fields.** Summary. Related: [F11] Since: abc1234' ] \
  || fail "detail[clear]: $(LINE F10)"
SD F12 detail ""
[ "$(LINE F12)" = '- **[F12] [Minor] Bare.** Summary only.' ] || fail "detail[clear]: $(LINE F12)"
pass "detail[clear]: empty value drops the pointer, neighbours intact"

BEFORE="$(md5sum "$TMP_SD/.hv/BACKLOG.md")"
rc=0; err="$(SD F10 detail .hv/features/F99.md 2>&1)" || rc=$?
[ "$rc" = 1 ] || fail "detail[missing]: expected exit 1, got $rc"
[ "$err" = "error: detail file .hv/features/F99.md does not exist" ] || fail "detail[missing]: message: $err"
[ "$BEFORE" = "$(md5sum "$TMP_SD/.hv/BACKLOG.md")" ] || fail "detail[missing]: file changed"
pass "detail[missing]: nonexistent file refused, backlog untouched"

# the parsed field round-trips (value keeps its backticks, like capture's entries)
SD F10 detail .hv/features/F10.md
[ "$(cd "$TMP_SD" && "$BIN/hv-todo-field" F10 detail)" = '`.hv/features/F10.md`' ] \
  || fail "detail[parse]: hv-todo-field does not read it back"
pass "detail[parse]: hv-todo-field reads the pointer back"

trap 'rm -rf "$TMP"' EXIT
rm -rf "$TMP_SD"
