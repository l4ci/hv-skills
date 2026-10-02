echo "hv-migrate-issues: file backlog onto the tracker (github, gitlab)"

TMP_MI="$(mktemp -d)"
trap 'rm -rf "$TMP_MI"' EXIT

# MAKE <dir> <provider>: a file-backend project with an open backlog, artifacts and two milestones
MAKE_MI() {
  local P="$1" prov="$2"
  mkdir -p "$P/.hv/bugs" "$P/.hv/features" "$P/.hv/tasks" "$P/.hv/designs" "$P/.hv/plans" "$P/.hv/milestones"
  printf '{"issues":{"provider":"%s","retryWaitSeconds":0,"bulkPaceMs":0}}\n' "$prov" > "$P/.hv/config.json"
  cat > "$P/.hv/BACKLOG.md" <<'BL'
# TODO

## Bugs

- **[B1] [P1] Crash on save.** Saving a large file crashes. Detail: .hv/bugs/B1.md
- **[B2] [P2] Typo in help.** Fix the help text. Milestone: M01

## Features

- **[F1] [Major] Export data.** Export to CSV. Detail: .hv/features/F1.md Related: [F2], [F9], F80 Milestone: M07 Since: abc1234
- **[F2] [Minor] Load files.** Read files in. Repos: web Related: [F9]

## Tasks

- **[T1] Clean up scripts.** Remove dead scripts.

## Completed

- ~~**[F9] [Minor] Old thing.** done long ago~~ Done 2026-01-01 [`abc1234`]
BL
  printf 'Crash details.\n' > "$P/.hv/bugs/B1.md"
  printf 'Export details.\n\n## Proof\n\n- 2026-09-01 · smoke · PASS · abc1234 · all green\n' > "$P/.hv/features/F1.md"
  printf '# Design F1\n\nSee [F2] and F2 but not F22.\n' > "$P/.hv/designs/F1.md"
  printf '# Plan F1\n\nDepends on F2.\n' > "$P/.hv/plans/M07-F1.md"
  printf -- '---\nid: M07\ntitle: Tracker work\nstatus: active\ndepends: []\n---\n\n# M07 — Tracker work\n\n## Goal\n\nMove to the tracker. Needs [F1].\n' > "$P/.hv/milestones/M07.md"
  printf -- '---\nid: M01\ntitle: Old launch\nstatus: shipped\ndepends: []\n---\n\n# M01 — Old launch\n\n## Goal\n\nDone.\n' > "$P/.hv/milestones/M01.md"
  printf '# M07-S01\n\nSlice: [F1] first, then T1 of the plan.\n' > "$P/.hv/plans/M07-S01.md"
}

for prov in github gitlab; do
  P="$TMP_MI/$prov"; MAKE_MI "$P" "$prov"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov migrate $1: expected [$2] got [$3]"; }
    has() { case "$3" in *"$2"*) ;; *) fail "$prov migrate $1: [$3] lacks [$2]";; esac; }
    RC() { local rc=0; OUT="$("$@" 2>"$P/err")" || rc=$?; RCV=$rc; ERR="$(cat "$P/err")"; }
    TREE() { find .hv -type f | sort | xargs cat | md5sum | cut -c1-32; }
    CALLS() { if [ -f "$P/log" ]; then wc -l < "$P/log" | tr -d ' '; else echo 0; fi; }
    # DUMP: one line per issue: number|title|sorted labels|native milestone|state
    DUMP() { PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
for i in sorted(adapter_for(load_config()).list(state="all"), key=lambda i: i["number"]):
    print("|".join([str(i["number"]), i["title"], ",".join(sorted(i["labels"])), str(i["milestone"] or ""), i["state"]]))'; }
    # NOTES n -> comments of issue n joined by ~~
    NOTES() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print("~~".join(c["body"] for c in adapter_for(load_config()).comments(int(sys.argv[1]))))' "$1"; }
    BODY() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(adapter_for(load_config()).get(int(sys.argv[1]))["body"])' "$1"; }
    MAPQ() { python3 -c '
import json, sys
m = json.load(open(".hv/issue-map.json"))
print(eval(sys.argv[1]))' "$1"; }

    # --- usage and refusals
    RC "$BIN/hv-migrate-issues" --bogus
    eq "bad flag" "1" "$RCV"
    RC "$BIN/hv-migrate-issues" --limit x
    eq "bad limit" "1" "$RCV"
    mkdir -p "$TMP_MI/empty-$prov/.hv"; printf '{}\n' > "$TMP_MI/empty-$prov/.hv/config.json"
    RC bash -c "cd '$TMP_MI/empty-$prov' && '$BIN/hv-migrate-issues' --apply"
    eq "missing backlog exit" "1" "$RCV"; has "missing backlog msg" "BACKLOG.md" "$ERR"
    cp -r "$P" "$TMP_MI/umb-$prov"
    printf '{"repos":[{"name":"a","path":"a"}]}\n' > "$TMP_MI/umb-$prov/.hv/repos.json"; mkdir -p "$TMP_MI/umb-$prov/a"
    RC bash -c "cd '$TMP_MI/umb-$prov' && '$BIN/hv-migrate-issues' --apply"
    eq "umbrella exit" "1" "$RCV"; has "umbrella msg" "each sub-repo separately" "$ERR"

    # --- dry run: default mode, prints the plan, touches nothing
    BEFORE="$(TREE)"
    RC "$BIN/hv-migrate-issues"
    eq "dry exit" "0" "$RCV"
    has "dry milestone" "create milestone M07 (active)" "$OUT"
    has "dry issue" 'create issue F1 → feature "Export data" [type:feature, size:Major] milestone M07' "$OUT"
    has "dry bug" 'create issue B1 → bug "Crash on save" [type:bug, p1]' "$OUT"
    has "dry design" "note design on F1" "$OUT"
    has "dry proof" "note proof on F1" "$OUT"
    has "dry plan" "note plan on F1" "$OUT"
    has "dry slice" "note plan:S01 on M07" "$OUT"
    has "dry related" "rewrite Related on F1: F2 → #?" "$OUT"
    has "dry map" "would-be map" "$OUT"
    case "$OUT" in *"issue F9"*|*"create milestone M01"*) fail "$prov migrate dry: completed item / shipped milestone planned";; esac
    has "dry dropped milestone warning" "milestone M01 is not on the tracker" "$ERR"
    eq "dry makes no tracker call" "0" "$(CALLS)"
    eq "dry leaves the tree unchanged" "$BEFORE" "$(TREE)"
    [ ! -e .hv/issue-map.json ] || fail "$prov migrate dry wrote the map"
    RC "$BIN/hv-migrate-issues" --dry-run
    eq "explicit dry exit" "0" "$RCV"

    # --- apply
    RC "$BIN/hv-migrate-issues" --apply
    eq "apply exit" "0" "$RCV"
    has "apply next line" "Next: /hv-config backlog.backend=issues" "$OUT"
    eq "issue list" "1|M07 — Tracker work|milestone-tracker,status:active|M07 — Tracker work|open
2|Crash on save|p1,type:bug||open
3|Typo in help|p2,type:bug||open
4|Export data|size:Major,type:feature|M07 — Tracker work|open
5|Load files|size:Minor,type:feature||open
6|Clean up scripts|type:task||open" "$(DUMP)"
    eq "map ids" "M07:1 B1:B2 B2:B3 F1:F4 F2:F5 T1:T6" \
       "$(MAPQ '" ".join(k + ":" + str(v["id"] if k != "M07" else v["number"]) for k, v in m.items())')"
    eq "map has no completed item" "False" "$(MAPQ '"F9" in m or "M01" in m')"
    eq "map entry url" "True" "$(MAPQ 'm["F1"]["url"].endswith("/4") and m["F1"]["number"] == 4')"
    has "F1 body detail" "Export details." "$(BODY 4)"
    case "$(BODY 4)" in *"## Proof"*) fail "$prov migrate: proof section left in the body";; esac
    has "F1 fields block" "Related: [F5]" "$(BODY 4)"
    has "F2 repos field" "Repos: web" "$(BODY 5)"
    has "Since kept in fields block" "Since: abc1234" "$(BODY 4)"
    has "F1 dangling Related dropped from field" "Related: [F5]" "$(BODY 4)"
    case "$(BODY 4)" in *"Related: [F5], "*|*"[F9]"*|*"Related: [F9]"*) fail "$prov migrate: dangling Related left in F1 field: $(BODY 4)";; esac
    has "F1 unmapped listed in body" "Related before migration (not migrated): F9, F80" "$(BODY 4)"
    has "F2 unmapped listed in body" "Related before migration (not migrated): F9" "$(BODY 5)"
    case "$(BODY 5)" in *"Related:"*) fail "$prov migrate: F2 kept an all-dangling Related field: $(BODY 5)";; esac
    has "B1 body" "Crash details." "$(BODY 2)"
    N4="$(NOTES 4)"
    has "proof note" "<!-- hv:proof -->" "$N4"; has "proof rows" "smoke · PASS" "$N4"
    has "design note rewritten" "See [F5] and F5 but not F22." "$N4"
    has "plan note rewritten" "Depends on F5." "$N4"
    N1="$(NOTES 1)"
    has "slice note" "<!-- hv:plan:S01 -->" "$N1"
    has "slice bracket rewrite only" "Slice: [F4] first, then T1 of the plan." "$N1"
    has "milestone body rewritten" "Needs [F4]." "$(BODY 1)"
    has "milestone status kept" "status: active" "$(BODY 1)"
    eq "banner first line" "true" "$(_grep_in=$(head -1 .hv/BACKLOG.md || true); grep -q '^> Frozen: this backlog moved to the issue tracker on ' <<<"$_grep_in" && echo true)"
    eq "banner once" "1" "$(grep -c '^> Frozen:' .hv/BACKLOG.md)"
    grep -q 'Old thing' .hv/BACKLOG.md || fail "$prov migrate: completed item lost"
    case "$(cat .hv/config.json)" in *backend*) fail "$prov migrate: backend flipped";; esac

    # --- re-run is a no-op
    TREE_DONE="$(TREE)"; C0="$(CALLS)"
    RC "$BIN/hv-migrate-issues" --apply
    eq "rerun exit" "0" "$RCV"
    eq "rerun makes no tracker call" "$C0" "$(CALLS)"
    eq "rerun leaves the tree unchanged" "$TREE_DONE" "$(TREE)"
    eq "rerun banner once" "1" "$(grep -c '^> Frozen:' .hv/BACKLOG.md)"
    has "rerun skips" "skip F1 (already migrated as F4)" "$OUT"
  ) 2>"$TMP_MI/sub-$prov.err" || { cat "$TMP_MI/sub-$prov.err" >&2; fail "$prov migrate main flow failed"; }

  # --- rate limit mid-run, then resume without duplicates
  R="$TMP_MI/rl-$prov"; MAKE_MI "$R" "$prov"
  (
    cd "$R"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$R/db.json" FAKE_TRACKER_LOG="$R/log"
    eq() { [ "$2" = "$3" ] || fail "$prov migrate rate-limit $1: expected [$2] got [$3]"; }
    has() { case "$3" in *"$2"*) ;; *) fail "$prov migrate rate-limit $1: [$3] lacks [$2]";; esac; }
    RC() { local rc=0; OUT="$("$@" 2>"$R/err")" || rc=$?; RCV=$rc; ERR="$(cat "$R/err")"; }
    COUNT() { PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
print(len(adapter_for(load_config()).list(state="all")))'; }

    FAKE_TRACKER_FAIL="Load files" FAKE_TRACKER_FAIL_MSG="secondary rate limit" RC "$BIN/hv-migrate-issues" --apply
    eq "stop exit" "4" "$RCV"
    has "stop report" "re-run to continue" "$OUT"
    eq "map saved" "M07 B1 B2 F1" "$(python3 -c 'import json;print(" ".join(json.load(open(".hv/issue-map.json"))))')"
    eq "created so far" "4" "$(COUNT)"
    [ "$(grep -c '^> Frozen:' .hv/BACKLOG.md || true)" = "0" ] || fail "$prov migrate rate-limit: froze an incomplete migration"
    RC "$BIN/hv-migrate-issues" --apply
    eq "resume exit" "0" "$RCV"
    eq "no duplicates" "6" "$(COUNT)"
    eq "resume map" "M07 B1 B2 F1 F2 T1" "$(python3 -c 'import json;print(" ".join(json.load(open(".hv/issue-map.json"))))')"
    has "resume Related rewritten" "Related: [F5]" "$(PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
print(adapter_for(load_config()).get(4)["body"])')"
    eq "resume banner" "1" "$(grep -c '^> Frozen:' .hv/BACKLOG.md)"
  ) 2>"$TMP_MI/rl-$prov.err" || { cat "$TMP_MI/rl-$prov.err" >&2; fail "$prov migrate rate-limit flow failed"; }

  # --- a plain tracker failure stops with exit 1 and keeps the map
  E="$TMP_MI/er-$prov"; MAKE_MI "$E" "$prov"
  (
    cd "$E"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$E/db.json" FAKE_TRACKER_LOG="$E/log"
    rc=0; FAKE_TRACKER_FAIL="Load files" "$BIN/hv-migrate-issues" --apply >/dev/null 2>&1 || rc=$?
    [ "$rc" = "1" ] || fail "$prov migrate tracker failure: expected exit 1 got $rc"
    [ -f .hv/issue-map.json ] || fail "$prov migrate tracker failure: map not saved"
  ) || fail "$prov migrate tracker failure flow failed"

  # --- --limit: create N items per run; notes wait until everything exists
  L="$TMP_MI/lim-$prov"; MAKE_MI "$L" "$prov"
  (
    cd "$L"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$L/db.json" FAKE_TRACKER_LOG="$L/log"
    eq() { [ "$2" = "$3" ] || fail "$prov migrate limit $1: expected [$2] got [$3]"; }
    has() { case "$3" in *"$2"*) ;; *) fail "$prov migrate limit $1: [$3] lacks [$2]";; esac; }
    KEYS() { python3 -c 'import json;print(" ".join(json.load(open(".hv/issue-map.json"))))'; }
    OUT="$("$BIN/hv-migrate-issues" --apply --limit 2 2>/dev/null)"
    eq "limit keys" "M07 B1 B2" "$(KEYS)"
    has "limit message" "re-run to continue" "$OUT"
    [ "$(grep -c '^> Frozen:' .hv/BACKLOG.md || true)" = "0" ] || fail "$prov migrate limit: froze early"
    "$BIN/hv-migrate-issues" --apply --limit 2 >/dev/null 2>&1
    eq "limit second run" "M07 B1 B2 F1 F2" "$(KEYS)"
    "$BIN/hv-migrate-issues" --apply --limit 2 >/dev/null 2>&1
    eq "limit third run" "M07 B1 B2 F1 F2 T1" "$(KEYS)"
    eq "limit finished: banner" "1" "$(grep -c '^> Frozen:' .hv/BACKLOG.md)"
    has "limit finished: notes" "hv:design" "$(PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
print(" ".join(c["body"] for c in adapter_for(load_config()).comments(4)))')"
  ) 2>"$TMP_MI/lim-$prov.err" || { cat "$TMP_MI/lim-$prov.err" >&2; fail "$prov migrate limit flow failed"; }
done

trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate-issues: dry run, apply, map, rewrites, banner, no-op re-run, rate-limit resume, limit (github, gitlab)"
