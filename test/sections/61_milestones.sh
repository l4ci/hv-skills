echo "Issue mode: native milestones, tracking issues, vision helpers, slice plan notes"

TMP_MS="$(mktemp -d)"
trap 'rm -rf "$TMP_MS"' EXIT

for prov in github gitlab; do
  P="$TMP_MS/$prov"; mkdir -p "$P/.hv"
  echo "{\"backlog\":{\"backend\":\"issues\"},\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    printf '# Project\n' > CLAUDE.md
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov $1: expected [$2] got [$3]"; }
    ERR() { local rc=0; ERRMSG="$("$@" 2>&1 >/dev/null)" || rc=$?; ERRRC=$rc; }
    # ISSUE n -> state|reason|sorted labels|native milestone
    ISSUE() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
i = adapter_for(load_config()).get(int(sys.argv[1]))
print("|".join([i["state"], str(i["state_reason"]), ",".join(sorted(i["labels"])), str(i["milestone"])]))' "$1"; }
    # NATIVE MNN -> state of the native milestone whose title starts with MNN
    NATIVE() { PYTHONPATH="$BIN" python3 -c '
import sys
from hvlib import adapter_for, load_config
print(",".join(m["state"] for m in adapter_for(load_config()).milestones("all") if m["title"].startswith(sys.argv[1] + " ")))' "$1"; }
    # SUMMARY -> id:status:ready:depends per milestone
    SUMMARY() { "$BIN/hv-vision-list" 2>/dev/null | python3 -c '
import json, sys
print(" ".join("%s:%s:%s:%s" % (m["id"], m["status"], str(m["ready"]).lower(), "+".join(m["depends"])) for m in json.load(sys.stdin)))'; }

    # --- ID minting, add, list shape
    eq "empty list" "[]" "$("$BIN/hv-vision-list")"
    eq "first id" "M01" "$("$BIN/hv-vision-add" "Alpha" "First summary")"
    eq "second id" "M02" "$("$BIN/hv-vision-add" "Beta" "Second summary" "M01")"
    eq "list shape" "M01:planned:true: M02:planned:false:M01" "$(SUMMARY)"
    eq "list keys" "id,title,status,depends,ready" "$("$BIN/hv-vision-list" | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)[0]))')"
    eq "list titles" "Alpha|Beta" "$("$BIN/hv-vision-list" | python3 -c 'import json,sys; print("|".join(m["title"] for m in json.load(sys.stdin)))')"
    eq "tracking issue" "open|None|milestone-tracker,status:planned|M01 — Alpha" "$(ISSUE 1)"
    eq "tracking issue with deps" "open|None|milestone-tracker,status:planned|M02 — Beta" "$(ISSUE 2)"
    eq "native open" "open" "$(NATIVE M01)"
    PYTHONPATH="$BIN" python3 - <<'PY' || fail "$prov native milestone fields"
from hvlib import adapter_for, load_config
a = adapter_for(load_config())
ms = {m["title"]: m for m in a.milestones("all")}
assert ms["M01 — Alpha"]["description"] == "First summary", ms
assert isinstance(ms["M01 — Alpha"]["number"], int)
body = a.get(2)["body"]
assert body.startswith("---\nid: M02\ntitle: Beta\nstatus: planned\ndepends: [M01]\n"), body
assert "\n# M02 — Beta\n\n## Goal\n\nSecond summary\n" in body, body
assert body.endswith("<!-- hv:fields\nDepends: M01\n-->"), body
assert a.get(1)["body"].count("hv:fields") == 0
PY

    # gaps and closed milestones count toward the next ID
    PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import adapter_for, load_config
a = adapter_for(load_config())
a.create_milestone("M05 — gap", "")
n = a.create_milestone("M09 — closed holder", "")
a.edit_milestone(n, state="closed")
assert {m["title"]: m["state"] for m in a.milestones("all")}["M09 — closed holder"] == "closed"
assert [m["title"] for m in a.milestones("all")][-1] == "M09 — closed holder"
a.edit_milestone(n, description="renamed")
assert [m for m in a.milestones("all") if m["number"] == n][0]["description"] == "renamed"
PY
    eq "id after gap and closed max" "M10" "$("$BIN/hv-vision-add" "Tenth" "Skips ahead")"
    ERR "$BIN/hv-next-id" milestones
    eq "hv-next-id still refuses" "2" "$ERRRC"

    # --- status transitions
    "$BIN/hv-vision-status" M01 active >/dev/null
    eq "active labels" "open|None|milestone-tracker,status:active|M01 — Alpha" "$(ISSUE 1)"
    eq "active listed" "M01" "$("$BIN/hv-vision-active")"
    eq "frontmatter synced" "status: active" "$("$BIN/hv-vision-show" M01 | sed -n 4p)"
    "$BIN/hv-vision-status" M01 shipped >/dev/null
    eq "shipped closes completed" "closed|completed|milestone-tracker,status:shipped|M01 — Alpha" "$(ISSUE 1)"
    eq "shipped closes native milestone" "closed" "$(NATIVE M01)"
    eq "shipped frontmatter" "status: shipped" "$("$BIN/hv-vision-show" M01 | sed -n 4p)"
    case "$(SUMMARY)" in "M01:shipped:true: M02:planned:true:M01 "*) ;; *) fail "$prov ready after ship: $(SUMMARY)" ;; esac
    "$BIN/hv-vision-status" M02 archived >/dev/null
    eq "archived closes not planned" "closed|not_planned" "$(ISSUE 2 | cut -d'|' -f1,2)"
    eq "archived closes native milestone" "closed" "$(NATIVE M02)"
    "$BIN/hv-vision-status" M02 planned >/dev/null
    eq "planned reopens" "open|None|milestone-tracker,status:planned|M02 — Beta" "$(ISSUE 2)"
    eq "planned reopens native milestone" "open" "$(NATIVE M02)"
    "$BIN/hv-vision-status" M02 shipped >/dev/null
    eq "archived -> planned -> shipped reads completed" "closed|completed|milestone-tracker,status:shipped|M02 — Beta" "$(ISSUE 2)"
    "$BIN/hv-vision-status" M02 active >/dev/null
    "$BIN/hv-vision-status" M01 active >/dev/null
    eq "shipped -> active reopens issue" "open|None|milestone-tracker,status:active|M01 — Alpha" "$(ISSUE 1)"
    eq "shipped -> active reopens milestone" "open" "$(NATIVE M01)"
    "$BIN/hv-vision-status" M01 shipped >/dev/null
    STATE_CALLS() { grep -cE 'issue (close|reopen)' "$P/log" || true; }
    before="$(STATE_CALLS)"; state="$(ISSUE 1)"
    "$BIN/hv-vision-status" M01 shipped >/dev/null
    eq "re-status keeps state" "$state" "$(ISSUE 1)"
    eq "re-status adds no close/reopen" "$before" "$(STATE_CALLS)"
    ERR "$BIN/hv-vision-status" M99 active
    eq "status unknown id" "1" "$ERRRC"
    ERR "$BIN/hv-vision-status" M01 bogus
    eq "status bad value" "1" "$ERRRC"

    # --- show / put round trip
    "$BIN/hv-vision-show" M02 > "$P/m02.md"
    eq "show starts with frontmatter" "---" "$(head -1 "$P/m02.md")"
    case "$(cat "$P/m02.md")" in *'hv:fields'*) fail "$prov show leaks the fields block" ;; esac
    printf '\n## Extra section\n\nLonger plan text.\n' >> "$P/m02.md"
    sed -i 's/^depends: .*/depends: [M01, M05]/' "$P/m02.md"
    "$BIN/hv-vision-put" M02 --body-file "$P/m02.md"
    eq "put round trip" "$(cat "$P/m02.md" | sed 's/^status: .*/status: active/')" "$("$BIN/hv-vision-show" M02)"
    eq "put updates depends" "M02:active:false:M01+M05" "$(SUMMARY | tr ' ' '\n' | grep '^M02')"
    sed -i 's/^status: .*/status: shipped/' "$P/m02.md"
    "$BIN/hv-vision-put" M02 --body-file - < "$P/m02.md"
    eq "put keeps status label authoritative" "status: active" "$("$BIN/hv-vision-show" M02 | sed -n 4p)"
    ERR "$BIN/hv-vision-put" M02 --body-file "$P/missing.md"
    eq "put unreadable body" "1" "$ERRRC"
    sed 's/^id: M02/id: M03/' "$P/m02.md" > "$P/bad.md"
    ERR "$BIN/hv-vision-put" M02 --body-file "$P/bad.md"
    eq "put id mismatch" "1" "$ERRRC"
    printf 'no frontmatter\n' > "$P/nofm.md"
    ERR "$BIN/hv-vision-put" M02 --body-file "$P/nofm.md"
    eq "put without frontmatter" "1" "$ERRRC"
    sed 's/^id: M02/id: M77/' "$P/m02.md" > "$P/m77.md"
    ERR "$BIN/hv-vision-put" M77 --body-file "$P/m77.md"
    eq "put unknown milestone" "1" "$ERRRC"
    ERR "$BIN/hv-vision-show" M77
    eq "show unknown milestone" "1" "$ERRRC"
    ERR "$BIN/hv-vision-put" M02
    eq "put usage" "1" "$ERRRC"

    # --- plan:SNN notes on the tracking issue (backend level)
    PYTHONPATH="$BIN" python3 - <<'PY' || fail "$prov slice notes"
from hvlib import get_backend, adapter_for, load_config
b = get_backend()
n = str(b.tracker_issue("M02")["number"])
assert b.note_get(n, "plan:S01") is None and b.slice_units("M02") == []
b.note_put(n, "plan:S01", "slice one\nline two")
b.note_put(n, "plan:S02", "slice two")
b.note_put(n, "plan", "plain plan note")
assert b.note_get(n, "plan:S01") == "slice one\nline two"
assert b.note_get(n, "plan") == "plain plan note"
assert b.slice_units("M02") == ["S01", "S02"]
marks = [c["body"].split("\n")[0] for c in adapter_for(load_config()).comments(int(n))]
assert marks == ["<!-- hv:plan:S01 -->", "<!-- hv:plan:S02 -->", "<!-- hv:plan -->"], marks
assert b.note_put(n, "plan:S01", "slice one\nline two") is False
assert b.note_rm(n, "plan:S01") and b.note_rm(n, "plan:S01") is False
assert b.slice_units("M02") == ["S02"] and b.note_get(n, "plan") == "plain plan note"
b.note_rm(n, "plan:S02"); b.note_rm(n, "plan")
try:
    b.note_put(n, "plan:x1", "bad"); raise SystemExit("bad slice kind accepted")
except ValueError:
    pass
PY

    # --- duplicate tracking issues: lowest open wins, stderr warning
    PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
a = adapter_for(load_config())
a.ensure_labels(["milestone-tracker"])
a.create("M02 — duplicate", "---\nid: M02\n---\n", ["milestone-tracker"])'
    "$BIN/hv-vision-list" > /dev/null 2> "$P/dup.err"
    case "$(cat "$P/dup.err")" in *"M02"*"#2"*"#"*"using #2"*) ;; *) fail "$prov duplicate warning: $(cat "$P/dup.err")" ;; esac
    eq "duplicate leaves winner" "M02:active:false:M01+M05" "$(SUMMARY | tr ' ' '\n' | grep '^M02')"
  )
done

# --- helper round trip with its own project: add -> put -> active -> index -> slice plans -> shipped
for prov in github gitlab; do
  P="$TMP_MS/rt-$prov"; mkdir -p "$P/.hv"
  echo "{\"backlog\":{\"backend\":\"issues\"},\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    printf '# Project\n\nIntro.\n' > CLAUDE.md
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    eq() { [ "$2" = "$3" ] || fail "$prov $1: expected [$2] got [$3]"; }
    ERR() { local rc=0; ERRMSG="$("$@" 2>&1 >/dev/null)" || rc=$?; ERRRC=$rc; }
    HAS() { grep -qF -- "$2" "$1" || fail "$prov $3: [$2] not in $1: $(cat "$1")"; }
    NOT() { if grep -qF -- "$2" "$1"; then fail "$prov $3: [$2] unexpectedly in $1"; fi; }

    eq "add" "M01" "$("$BIN/hv-vision-add" "Launch" "Ship the thing")"
    eq "add dep" "M02" "$("$BIN/hv-vision-add" "Scale" "Grow it" "M01")"
    [ ! -e .hv/milestones ] || fail "$prov issue mode wrote .hv/milestones"
    "$BIN/hv-vision-show" M01 | sed 's/_(define what shipped looks like)_/Users can sign up./' > body.md
    "$BIN/hv-vision-put" M01 --body-file body.md
    HAS <("$BIN/hv-vision-show" M01) "Users can sign up." "put body"
    "$BIN/hv-vision-status" M01 active >/dev/null
    HAS .hv/MILESTONES.md "- M01 — Launch" "active list"
    NOT .hv/MILESTONES.md "M02 —" "planned milestone not in the active list"
    HAS .hv/MILESTONES.md "# Milestones" "seeded H1"
    HAS .hv/MILESTONES.md "_(no vision yet" "seeded vision paragraph"
    HAS .hv/MILESTONES.md "## Milestones" "seeded milestones heading"
    HAS CLAUDE.md "- **M01** — Launch (depends: —)" "CLAUDE.md block"
    HAS CLAUDE.md "the tracking issues" "CLAUDE.md issue-mode pointer"
    HAS CLAUDE.md "Intro." "CLAUDE.md prose kept"
    NOT .hv/MILESTONES.md "### M01" "no per-milestone overview section"
    "$BIN/hv-vision-index" >/dev/null
    eq "index idempotent" "1" "$(grep -c 'hv-vision-start' CLAUDE.md)"
    "$BIN/hv-vision-status" M02 active >/dev/null
    HAS CLAUDE.md "- **M02** — Scale (depends: M01) ⚠ blocked" "blocked flag"
    eq "active ids" "M01 M02" "$("$BIN/hv-vision-active" | tr '\n' ' ' | sed 's/ $//')"
    eq "empty-active lists milestones without items" "M01 M02" "$("$BIN/hv-vision-empty-active" | tr '\n' ' ' | sed 's/ $//')"
    "$BIN/hv-item-create" tasks --title "In M01" --field Milestone=M01 > /dev/null
    eq "empty-active skips milestones with items" "M02" "$("$BIN/hv-vision-empty-active")"

    PYTHONPATH="$BIN" python3 -c '
from hvlib import adapter_for, load_config
a = adapter_for(load_config())
a.ensure_labels(["milestone-tracker"])
a.create("M1x stuff", "", ["milestone-tracker"])'
    case "$("$BIN/hv-vision-list" | python3 -c 'import json,sys; print(" ".join(m["id"] for m in json.load(sys.stdin)))')" in "M01 M02") ;; *) fail "$prov M1x title not ignored" ;; esac

    # slice plans
    eq "slice 1" "M01-S01" "$("$BIN/hv-plan-add" M01 slice "First slice")"
    eq "slice 2" "M01-S02" "$("$BIN/hv-plan-add" M01 slice "Second slice")"
    HAS <("$BIN/hv-plan-show" M01-S01) "# M01-S01 — First slice" "slice show"
    HAS <("$BIN/hv-plan-show" M01-S01) "unitKind: slice" "slice frontmatter"
    eq "slice design pointer" "M01-S03" "$("$BIN/hv-plan-add" --design .hv/designs/F07.md M01 slice "Designed")"
    HAS <("$BIN/hv-plan-show" M01-S03) "design: note:F07:design" "slice design pointer"
    ERR "$BIN/hv-plan-add" --design .hv/designs/M01.md M01 slice "Bad design"
    eq "slice design needs an item id" "1" "$ERRRC"
    "$BIN/hv-plan-rm" M01-S03
    [ ! -e .hv/plans/M01-S01.md ] || fail "$prov slice plan written as a file"
    ERR "$BIN/hv-plan-add" M01 S01 "dup"
    eq "slice duplicate" "1" "$ERRRC"
    ERR "$BIN/hv-plan-add" M09 slice "no tracker"
    eq "slice on unknown milestone" "1" "$ERRRC"
    "$BIN/hv-plan-show" M01-S01 | sed 's/^status: planned/status: active/' > plan.md
    "$BIN/hv-plan-put" M01-S01 --body-file plan.md
    eq "slice put/show" "$(cat plan.md)" "$("$BIN/hv-plan-show" M01-S01)"
    ERR "$BIN/hv-plan-put" M01-S07 --body-file plan.md
    eq "slice put missing" "1" "$ERRRC"
    "$BIN/hv-plan-list" 2> plan-list.err > plan-list.json
    HAS plan-list.err "item plans live on their issues" "plan-list note"
    eq "plan-list" "M01-S01:slice:active:First slice M01-S02:slice:planned:Second slice" "$(python3 -c '
import json
print(" ".join("%s:%s:%s:%s" % (p["key"], p["unitKind"], p["status"], p["title"]) for p in json.load(open("plan-list.json"))))')"
    eq "plan-list keys" "key,milestone,unit,unitKind,title,status,created,repo" "$(python3 -c 'import json; print(",".join(json.load(open("plan-list.json"))[0]))')"
    eq "plan-list filter other milestone" "[]" "$("$BIN/hv-plan-list" M02 2>/dev/null)"
    eq "plan-list filter" "2" "$("$BIN/hv-plan-list" M01 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
    "$BIN/hv-plan-rm" M01-S02
    ERR "$BIN/hv-plan-show" M01-S02
    eq "slice rm" "1" "$ERRRC"
    ERR "$BIN/hv-plan-rm" M01-S02
    eq "slice rm twice" "1" "$ERRRC"
    eq "slice re-mint" "M01-S02" "$("$BIN/hv-plan-add" M01 slice "Again")"

    # ship
    "$BIN/hv-vision-status" M01 shipped >/dev/null
    "$BIN/hv-vision-status" M02 shipped >/dev/null
    HAS .hv/MILESTONES.md "_(none active" "active list emptied"
    HAS CLAUDE.md "all shipped or archived" "CLAUDE.md after ship"
    eq "nothing active" "" "$("$BIN/hv-vision-active")"
  )
done

# --- file mode: hv-vision-put
P="$TMP_MS/file"; mkdir -p "$P/.hv/milestones"
(
  cd "$P"
  git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
  echo '{}' > .hv/counters.json
  eq() { [ "$2" = "$3" ] || fail "file mode $1: expected [$2] got [$3]"; }
  ERR() { local rc=0; ERRMSG="$("$@" 2>&1 >/dev/null)" || rc=$?; ERRRC=$rc; }
  eq "add" "M01" "$("$BIN/hv-vision-add" "Local" "On disk")"
  sed 's/^title: Local/title: Local renamed/' .hv/milestones/M01.md > "$P/new.md"
  "$BIN/hv-vision-put" M01 --body-file "$P/new.md"
  eq "put writes the file" "$(cat "$P/new.md")" "$(cat .hv/milestones/M01.md)"
  printf -- '---\nid: M01\ntitle: Via stdin\nstatus: planned\n---\n# body\n' | "$BIN/hv-vision-put" M01 --body-file -
  eq "put from stdin" "title: Via stdin" "$(sed -n 3p .hv/milestones/M01.md)"
  cp .hv/milestones/M01.md before.md
  printf -- '---\nid: M02\ntitle: x\n---\n' > wrong.md
  ERR "$BIN/hv-vision-put" M01 --body-file wrong.md
  eq "id mismatch" "1" "$ERRRC"
  printf 'no frontmatter\n' > nofm.md
  ERR "$BIN/hv-vision-put" M01 --body-file nofm.md
  eq "no frontmatter" "1" "$ERRRC"
  eq "refused put leaves the file" "$(cat before.md)" "$(cat .hv/milestones/M01.md)"
  printf -- '---\nid: M09\n---\n' > m09.md
  ERR "$BIN/hv-vision-put" M09 --body-file m09.md
  eq "unknown milestone" "1" "$ERRRC"
  [ ! -e .hv/milestones/M09.md ] || fail "file mode put created M09"
  ERR "$BIN/hv-vision-put" notanid --body-file m09.md
  eq "bad id" "1" "$ERRRC"
  ERR "$BIN/hv-vision-put" M01 --body-file "$P/nope.md"
  eq "unreadable body" "1" "$ERRRC"
  ERR "$BIN/hv-vision-put" M01
  eq "usage" "1" "$ERRRC"
)

trap 'rm -rf "$TMP"' EXIT
pass "milestones: native milestone + tracking issue, status transitions, vision and slice-plan helpers (github, gitlab), vision-put (file)"
