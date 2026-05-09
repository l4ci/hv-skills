# Context-scaling map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an AI-facing project map (`.hv/MAP.md` + `.hv/map/<subsystem>.md`) plus shared hygiene (staleness flags, soft caps, `/hv-map` consolidation) that keeps growing projects legible without bloating the always-on context.

**Architecture:** Mirrors the existing KNOWLEDGE pattern exactly. Topic-indexed detail files + a managed CLAUDE.md block + on-demand query helpers. Updates ride along with `/hv-work` cycles (no hooks, no schedulers). Hygiene is shared with KNOWLEDGE/TODO via a single `hv-staleness` helper.

**Tech Stack:** Bash + Python 3 (stdlib only) heredocs, mirroring `bin/hv-knowledge-*` style. Tests in `test/smoke.sh` (single end-to-end script). Skills are markdown under `hv-*/SKILL.md`.

**Spec:** `docs/superpowers/specs/2026-05-09-context-scaling-map-design.md`

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `bin/hv-map-query` | Read `.hv/map/<name>.md` body for AI on demand. |
| `bin/hv-map-stats` | JSON: counts, sizes, last-touched, broken `file:line` per subsystem. |
| `bin/hv-map-index` | Regenerate the managed `## Project Map` block in CLAUDE.md from frontmatter `summary:` lines. |
| `bin/hv-staleness` | Scan MAP / KNOWLEDGE / TODO timestamps; print stale candidates. Used by status/next/resume. |
| `hv-map/SKILL.md` | New skill with three modes: first-run, after-work, consolidate. |

**Modified files:**

| Path | Change |
|---|---|
| `bin/hvlib.py` | Add `parse_frontmatter(text)` and `iter_map_entries(map_dir)` helpers. |
| `bin/hv-bootstrap` | Seed `.hv/MAP.md`, `.hv/map/` directory. |
| `hv-init/SKILL.md` | Mention MAP scaffold; run `hv-map-index` after bootstrap. |
| `hv-work/SKILL.md` | Soft-cap warning at start; `/hv-map after-work` post-cycle (alongside existing `/hv-learn`/`/hv-docs` calls). |
| `hv-debug/SKILL.md` | `/hv-map after-work` post-cycle. |
| `hv-go/SKILL.md` | `/hv-map after-work` post-cycle. |
| `hv-status/SKILL.md` | Print `Stale candidates:` line via `hv-staleness`. |
| `hv-next/SKILL.md` | Same. |
| `hv-resume/SKILL.md` | Same. |
| `hv-capture/SKILL.md` | Optional `Subsystem:` inference (suggest, never block). |
| `test/smoke.sh` | Six new cases (init, first-run, after-work, soft-cap, staleness, consolidate). |

**Convention recap (so later tasks can reference it):**

Detail file frontmatter:
```yaml
---
subsystem: capture
summary: Captures bugs/features/tasks into TODO.md without executing
touched: 2026-05-09
created: 2026-03-12
related-topics: [Skill Authoring, Build & Tooling]
related-items: [F12, B08]
---
```

Managed CLAUDE.md block (target output):
```markdown
<!-- hv-map-start -->
## Project Map

Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). Pull with `.hv/bin/hv-map-query <name>`.

- **capture** — Captures bugs/features/tasks into TODO.md without executing
- **plan** — Implementation plans before execution
<!-- hv-map-end -->
```

---

## Task 1: Add frontmatter parsing to hvlib.py

**Files:**
- Modify: `bin/hvlib.py`
- Test: `test/smoke.sh` (append cases at end)

- [ ] **Step 1: Append a smoke-test case for `parse_frontmatter` and `iter_map_entries`**

Edit `test/smoke.sh` — append before the final summary line. The cases create a synthetic `.hv/map/` and shell out to a `python3 -c` snippet that imports the helpers and prints results.

```bash
# --- hvlib: parse_frontmatter & iter_map_entries -------------------
mkdir -p .hv/map
cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into TODO.md
touched: 2026-05-09
related-topics: [Skill Authoring]
---

## Purpose
One paragraph.
EOF
cat > .hv/map/plan.md <<'EOF'
---
subsystem: plan
summary: Plans before execution
touched: 2026-04-01
---
body
EOF
# malformed: no frontmatter
echo "no frontmatter here" > .hv/map/broken.md

PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import parse_frontmatter, iter_map_entries
fm, body = parse_frontmatter(open(".hv/map/capture.md").read())
assert fm["subsystem"] == "capture", fm
assert fm["summary"] == "Captures items into TODO.md", fm
assert "## Purpose" in body, body
assert fm["related-topics"] == ["Skill Authoring"], fm

# malformed body: empty frontmatter dict, full content as body
fm2, body2 = parse_frontmatter(open(".hv/map/broken.md").read())
assert fm2 == {}, fm2
assert body2.strip() == "no frontmatter here", body2

entries = list(iter_map_entries(".hv/map"))
names = sorted(e[0] for e in entries)
assert names == ["capture", "plan"], names  # malformed file is skipped
PY
echo "ok hvlib parse_frontmatter / iter_map_entries"
```

- [ ] **Step 2: Run smoke to verify the new case fails**

Run: `bash test/smoke.sh`
Expected: FAIL with `ImportError: cannot import name 'parse_frontmatter' from 'hvlib'` (or similar).

- [ ] **Step 3: Implement `parse_frontmatter` and `iter_map_entries` in `bin/hvlib.py`**

Append to `bin/hvlib.py`:

```python
def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Parse a YAML-ish frontmatter block delimited by `---` lines.

    Supports a flat key/value subset only:
      - `key: value`
      - `key: [a, b, c]` (inline list)
    Returns ({}, original_text) when no frontmatter is present or it is
    malformed. Never raises.
    """
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return {}, text
    # Find closing ---
    rest = text.split("\n", 1)[1] if "\n" in text else ""
    end = re.search(r"^---\s*$", rest, re.MULTILINE)
    if not end:
        return {}, text
    block = rest[: end.start()]
    body = rest[end.end():].lstrip("\n")
    fm: dict = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            fm[key] = [v.strip() for v in inner.split(",") if v.strip()] if inner else []
        else:
            fm[key] = value
    return fm, body


def iter_map_entries(map_dir):
    """Yield (subsystem, frontmatter_dict, body, path) for each *.md file
    in `map_dir` whose frontmatter has a `subsystem:` key. Files without
    valid frontmatter are skipped silently. Sorted by subsystem name.
    """
    p = Path(map_dir)
    if not p.is_dir():
        return
    entries = []
    for md in sorted(p.glob("*.md")):
        try:
            text = md.read_text()
        except OSError:
            continue
        fm, body = parse_frontmatter(text)
        name = fm.get("subsystem")
        if not name:
            continue
        entries.append((name, fm, body, md))
    entries.sort(key=lambda e: e[0])
    for entry in entries:
        yield entry
```

- [ ] **Step 4: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok hvlib parse_frontmatter / iter_map_entries` printed.

- [ ] **Step 5: Commit**

```bash
git add bin/hvlib.py test/smoke.sh
git commit -m "feat: parse_frontmatter + iter_map_entries in hvlib"
```

---

## Task 2: Implement `bin/hv-map-query`

**Files:**
- Create: `bin/hv-map-query`
- Test: `test/smoke.sh` (append)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`:

```bash
# --- hv-map-query --------------------------------------------------
out="$("$BIN/hv-map-query" capture)"
[[ "$out" == *"## Purpose"* ]] || { echo "FAIL: hv-map-query body missing"; exit 1; }
out="$("$BIN/hv-map-query" capture plan)"
[[ "$out" == *"## Purpose"* && "$out" == *"body"* ]] || { echo "FAIL: hv-map-query multi"; exit 1; }
out="$("$BIN/hv-map-query" nonexistent)"
[[ -z "$out" ]] || { echo "FAIL: hv-map-query missing should be empty, got: $out"; exit 1; }
echo "ok hv-map-query"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL with `hv-map-query: command not found` or similar.

- [ ] **Step 3: Implement `bin/hv-map-query`**

Create `bin/hv-map-query`:

```bash
#!/usr/bin/env bash
# Print the body (minus frontmatter) of named subsystem files in .hv/map/.
# Usage: hv-map-query <subsystem>...
#   stdout: matching bodies, separated by blank line, in argument order
#   exit:   0 always (missing subsystems are silent)
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: hv-map-query <subsystem>..." >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/hv-self-locate.sh"
hv_self_locate
PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" python3 - "$@" <<'PY'
import sys
from pathlib import Path
from hvlib import parse_frontmatter

first = True
for name in sys.argv[1:]:
    path = Path(".hv/map") / f"{name}.md"
    if not path.exists():
        continue
    _, body = parse_frontmatter(path.read_text())
    body = body.rstrip("\n")
    if not body:
        continue
    if not first:
        print()
    print(body)
    first = False
PY
```

Then mark executable: `chmod +x bin/hv-map-query`.

- [ ] **Step 4: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok hv-map-query` printed.

- [ ] **Step 5: Commit**

```bash
git add bin/hv-map-query test/smoke.sh
git commit -m "feat: hv-map-query helper for on-demand subsystem reads"
```

---

## Task 3: Implement `bin/hv-map-stats`

**Files:**
- Create: `bin/hv-map-stats`
- Test: `test/smoke.sh` (append)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`:

```bash
# --- hv-map-stats --------------------------------------------------
# Add an entry-point referencing this very file to test the file:line check
mkdir -p src
echo "line1" > src/sample.txt
echo "line2" >> src/sample.txt
cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Orchestrator-driven execution
touched: 2026-05-09
---

## Entry points
- src/sample.txt:2 — second line
- src/missing.txt:42 — broken ref
EOF
out="$("$BIN/hv-map-stats")"
echo "$out" | grep -q '"name": "capture"' || { echo "FAIL: stats missing capture"; exit 1; }
echo "$out" | grep -q '"broken_refs"' || { echo "FAIL: stats missing broken_refs"; exit 1; }
# work has 1 broken ref out of 2 entry points
echo "$out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
work = next(s for s in data["subsystems"] if s["name"] == "work")
assert work["broken_refs"] == 1, work
assert work["entry_points"] == 2, work
'
echo "ok hv-map-stats"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL — helper not found.

- [ ] **Step 3: Implement `bin/hv-map-stats`**

Create `bin/hv-map-stats`:

```bash
#!/usr/bin/env bash
# Print per-subsystem stats from .hv/map/ as JSON.
# Usage: hv-map-stats
# Output: {"subsystems": [{"name": "...", "bytes": N, "touched": "YYYY-MM-DD",
#                         "entry_points": N, "broken_refs": N}, ...]}
# Silent-empty {"subsystems": []} when .hv/map/ is missing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/hv-self-locate.sh"
hv_self_locate
PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import json
import re
import subprocess
from pathlib import Path
from hvlib import iter_map_entries, section

map_dir = Path(".hv/map")
if not map_dir.is_dir():
    print(json.dumps({"subsystems": []}, indent=2))
    raise SystemExit(0)

ENTRY_RE = re.compile(r"^- ([^:\s]+):(\d+)\b", re.MULTILINE)


def git_mtime(path: Path) -> str | None:
    try:
        out = subprocess.check_output(
            ["git", "log", "-1", "--format=%cs", "--", str(path)],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return out or None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


subsystems = []
for name, fm, body, path in iter_map_entries(str(map_dir)):
    nbytes = path.stat().st_size
    touched = fm.get("touched") or git_mtime(path) or ""
    ep_block = section(body, "Entry points")
    refs = ENTRY_RE.findall(ep_block)
    broken = 0
    for file_ref, lineno in refs:
        p = Path(file_ref)
        if not p.exists():
            broken += 1
            continue
        try:
            n = int(lineno)
            line_count = sum(1 for _ in p.open())
            if n < 1 or n > line_count:
                broken += 1
        except (OSError, ValueError):
            broken += 1
    subsystems.append({
        "name": name,
        "bytes": nbytes,
        "touched": touched,
        "entry_points": len(refs),
        "broken_refs": broken,
    })

print(json.dumps({"subsystems": subsystems}, indent=2))
PY
```

`chmod +x bin/hv-map-stats`.

- [ ] **Step 4: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok hv-map-stats`.

- [ ] **Step 5: Commit**

```bash
git add bin/hv-map-stats test/smoke.sh
git commit -m "feat: hv-map-stats with broken file:line detection"
```

---

## Task 4: Implement `bin/hv-map-index`

**Files:**
- Create: `bin/hv-map-index`
- Test: `test/smoke.sh` (append)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`:

```bash
# --- hv-map-index --------------------------------------------------
[ -f CLAUDE.md ] || : > CLAUDE.md
"$BIN/hv-map-index" >/dev/null
grep -q '<!-- hv-map-start -->' CLAUDE.md || { echo "FAIL: map block not in CLAUDE.md"; exit 1; }
grep -q '## Project Map' CLAUDE.md || { echo "FAIL: heading missing"; exit 1; }
grep -q '\*\*capture\*\* — Captures items into TODO.md' CLAUDE.md || { echo "FAIL: capture summary missing"; exit 1; }
# Idempotence
sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
"$BIN/hv-map-index" >/dev/null
sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
[ "$sha1" = "$sha2" ] || { echo "FAIL: hv-map-index not idempotent"; exit 1; }
# Empty case: hide the block when .hv/map/ has no valid entries
mv .hv/map .hv/map.bak
mkdir .hv/map
"$BIN/hv-map-index" >/dev/null
grep -q '_(no subsystems yet' CLAUDE.md || { echo "FAIL: empty placeholder missing"; exit 1; }
mv .hv/map .hv/map.empty
mv .hv/map.bak .hv/map
echo "ok hv-map-index"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL — helper not found.

- [ ] **Step 3: Implement `bin/hv-map-index`**

Create `bin/hv-map-index`:

```bash
#!/usr/bin/env bash
# Regenerate the managed <!-- hv-map-start --> block in CLAUDE.md from
# the frontmatter `summary:` of every .hv/map/<name>.md.
# Usage: hv-map-index
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/hv-self-locate.sh"
hv_self_locate

BODY=$(PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
from pathlib import Path
from hvlib import iter_map_entries

heading = "## Project Map"
intro = (
    "Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). "
    "Pull with `.hv/bin/hv-map-query <name>`."
)

entries = list(iter_map_entries(".hv/map"))
if entries:
    bullets = "\n".join(
        f"- **{name}** — {fm.get('summary', '').strip() or '(no summary)'}"
        for name, fm, _body, _path in entries
    )
else:
    bullets = "- _(no subsystems yet — run `/hv-map first-run` to scaffold)_"

print(f"{heading}\n\n{intro}\n\n{bullets}\n")
PY
)
printf '%s' "$BODY" | "$HERE/hv-managed-block" map --body-stdin
```

`chmod +x bin/hv-map-index`.

- [ ] **Step 4: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok hv-map-index`.

- [ ] **Step 5: Commit**

```bash
git add bin/hv-map-index test/smoke.sh
git commit -m "feat: hv-map-index regenerates ## Project Map block in CLAUDE.md"
```

---

## Task 5: Implement `bin/hv-staleness`

**Files:**
- Create: `bin/hv-staleness`
- Test: `test/smoke.sh` (append)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`:

```bash
# --- hv-staleness --------------------------------------------------
# Capture (touched 2026-04-01) is older than 30 days from "today=2026-05-09";
# work is touched 2026-05-09 and should not be flagged at days=30.
out="$("$BIN/hv-staleness" map --days 30 --today 2026-05-09)"
echo "$out" | grep -q '^plan ' || { echo "FAIL: plan should be stale"; exit 1; }
echo "$out" | grep -q '^work ' && { echo "FAIL: work should NOT be stale"; exit 1; }
# days=0 lists all
out="$("$BIN/hv-staleness" map --days 0 --today 2026-05-09)"
[ "$(echo "$out" | wc -l)" -ge 2 ] || { echo "FAIL: days=0 should list all"; exit 1; }
# Knowledge: KNOWLEDGE.md exists from bootstrap-style fixture; should not error
"$BIN/hv-staleness" knowledge --days 0 >/dev/null
echo "ok hv-staleness"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL — helper not found.

- [ ] **Step 3: Implement `bin/hv-staleness`**

Create `bin/hv-staleness`:

```bash
#!/usr/bin/env bash
# List stale entries across MAP / KNOWLEDGE / TODO based on a days threshold.
# Usage: hv-staleness <kind> [--days N] [--today YYYY-MM-DD]
#   kind:    map | knowledge | todo
#   --days:  threshold; entries strictly older than N days are listed (default 90)
#   --today: override today (test hook); defaults to today's date
#   stdout:  one line per stale entry: "<name> <YYYY-MM-DD>"
#   exit:    0 always
set -euo pipefail
KIND="${1:?usage: hv-staleness <kind> [--days N] [--today YYYY-MM-DD]}"
shift
DAYS=90
TODAY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --today) TODAY="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/hv-self-locate.sh"
hv_self_locate

PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" python3 - "$KIND" "$DAYS" "$TODAY" <<'PY'
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path
from hvlib import iter_map_entries, iter_topics

kind, days_s, today_s = sys.argv[1], sys.argv[2], sys.argv[3]
days = int(days_s)
today = dt.date.fromisoformat(today_s) if today_s else dt.date.today()


def parse_date(s: str) -> dt.date | None:
    try:
        return dt.date.fromisoformat(s.strip())
    except (ValueError, AttributeError):
        return None


def git_mtime(path: Path) -> dt.date | None:
    try:
        out = subprocess.check_output(
            ["git", "log", "-1", "--format=%cs", "--", str(path)],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return parse_date(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def is_stale(d: dt.date | None) -> bool:
    if d is None:
        return False
    return (today - d).days > days


def emit(name: str, d: dt.date | None) -> None:
    print(f"{name} {d.isoformat() if d else 'unknown'}")


if kind == "map":
    for name, fm, _body, path in iter_map_entries(".hv/map"):
        d = parse_date(fm.get("touched", "")) or git_mtime(path)
        if is_stale(d):
            emit(name, d)
elif kind == "knowledge":
    p = Path(".hv/KNOWLEDGE.md")
    if not p.exists():
        sys.exit(0)
    # KNOWLEDGE has no per-topic timestamps yet; fall back to file mtime.
    d = git_mtime(p)
    if is_stale(d):
        for topic, _body in iter_topics(p.read_text()):
            emit(topic, d)
elif kind == "todo":
    p = Path(".hv/TODO.md")
    if not p.exists():
        sys.exit(0)
    # Match open bullets like "- [B07] Title (...) Captured: 2026-02-01"
    captured_re = re.compile(r"^- \[([A-Z]\d+)\].*?Captured:\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE)
    for m in captured_re.finditer(p.read_text()):
        d = parse_date(m.group(2))
        if is_stale(d):
            emit(m.group(1), d)
else:
    print(f"unknown kind: {kind}", file=sys.stderr)
    sys.exit(1)
PY
```

`chmod +x bin/hv-staleness`.

- [ ] **Step 4: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok hv-staleness`.

- [ ] **Step 5: Commit**

```bash
git add bin/hv-staleness test/smoke.sh
git commit -m "feat: hv-staleness flags old entries across MAP/KNOWLEDGE/TODO"
```

---

## Task 6: Seed `.hv/MAP.md` and `.hv/map/` in bootstrap and `/hv-init`

**Files:**
- Modify: `bin/hv-bootstrap`
- Modify: `hv-init/SKILL.md`
- Test: `test/smoke.sh` (append)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`:

```bash
# --- hv-bootstrap seeds map ---------------------------------------
TMP2=$(mktemp -d)
trap 'rm -rf "$TMP2"' EXIT
(
  cd "$TMP2"
  git init -q
  "$BIN/hv-bootstrap" >/dev/null
  [ -d .hv/map ] || { echo "FAIL: .hv/map not created"; exit 1; }
  [ -f .hv/MAP.md ] || { echo "FAIL: .hv/MAP.md not seeded"; exit 1; }
  grep -q "Project map" .hv/MAP.md || { echo "FAIL: .hv/MAP.md content missing"; exit 1; }
)
echo "ok hv-bootstrap seeds map"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL — `.hv/map` not created.

- [ ] **Step 3: Modify `bin/hv-bootstrap` to seed MAP**

Edit `bin/hv-bootstrap`. The first `mkdir -p` line includes the `.hv/` subdirs — add `map` to it. Then add an `[ -f "$HV/MAP.md" ] || cat >` block alongside the existing KNOWLEDGE/DECISIONS/MILESTONES blocks:

Change:
```bash
mkdir -p "$HV"/{bugs,features,tasks,milestones,plans,spikes,bin}
```
to:
```bash
mkdir -p "$HV"/{bugs,features,tasks,milestones,plans,spikes,map,bin}
```

Then append, after the existing DECISIONS block (and before whatever follows):
```bash
[ -f "$HV/MAP.md" ] || cat > "$HV/MAP.md" <<'EOF'
# Project map

AI-facing index of subsystems. Detail files live in `.hv/map/<name>.md` and are loaded on demand via `.hv/bin/hv-map-query <name>`. The thin always-on summary in `CLAUDE.md` is regenerated by `.hv/bin/hv-map-index`.

Use `/hv-map` to scaffold (`first-run`), update touched subsystems (`after-work`), or consolidate dormant entries (`consolidate`).
EOF
```

- [ ] **Step 4: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok hv-bootstrap seeds map`.

- [ ] **Step 5: Update `hv-init/SKILL.md` to mention MAP and run `hv-map-index`**

Edit `hv-init/SKILL.md`:
- In the description of what `/hv-init` creates, add a line for MAP next to the existing KNOWLEDGE / DECISIONS / MILESTONES mentions.
- After the bootstrap step that already runs `hv-knowledge-index` and `hv-decisions-index`, add a parallel `hv-map-index` invocation so the empty-state CLAUDE.md block lands on first init.

Read the existing file before editing — match its style; add one bullet and one command line. Do not rewrite unrelated parts.

- [ ] **Step 6: Commit**

```bash
git add bin/hv-bootstrap hv-init/SKILL.md test/smoke.sh
git commit -m "feat: /hv-init seeds .hv/MAP.md, .hv/map/, and ## Project Map block"
```

---

## Task 7: Create `/hv-map` skill (first-run, after-work, consolidate)

**Files:**
- Create: `hv-map/SKILL.md`
- Test: none (skill is markdown, exercised by smoke at Task 10)

- [ ] **Step 1: Read an existing 3-mode skill for style reference**

Run: `cat hv-docs/SKILL.md | head -120`
Expected: shows the frontmatter shape (`name`, `description`) and how three modes are documented.

- [ ] **Step 2: Write `hv-map/SKILL.md`**

Create the file with this content:

```markdown
---
name: hv-map
description: Maintain the project map of subsystems under .hv/map/. Modes — first-run (scaffold), after-work (update touched subsystems), consolidate (merge stale/duplicate entries). Auto-invoked post-cycle by /hv-work, /hv-debug, /hv-go; run manually for first-run and consolidation.
---

# /hv-map — project map orchestrator

Subsystems are AI-curated narratives describing one coherent area of the project. The system has three layers (see spec `docs/superpowers/specs/2026-05-09-context-scaling-map-design.md`):

1. **Map artifacts** — `.hv/MAP.md` + `.hv/map/<name>.md` detail files with frontmatter (`subsystem`, `summary`, `touched`, `created`, `related-topics`, `related-items`).
2. **Always-on index** — `## Project Map` managed block in CLAUDE.md, regenerated by `bin/hv-map-index`.
3. **Hygiene** — staleness flags via `hv-staleness`, soft-cap warnings, manual consolidation.

## Modes

### Mode: first-run

Run when `.hv/map/` is empty.

1. Inspect: directory structure (`ls -d */`), top-level commands (`bin/hv-*` and skill folders `hv-*/`), KNOWLEDGE topics (`hv-knowledge-query` over each topic name listed in `## Project Knowledge` of CLAUDE.md), recent commits (`git log --oneline -50`).
2. Propose 3–10 candidate subsystems with one-line summaries. Show them to the user; do not write yet.
3. On confirmation, create `.hv/map/<name>.md` for each, with frontmatter (`subsystem`, `summary`, `created` = today, `touched` = today) and the five body sections (Purpose, Entry points, Key files / dirs, Conventions specific here, Notes / gotchas) — populated from what was inspected. Leave any unknown section as a single placeholder line so future cycles fill it in.
4. Run `bin/hv-map-index` to regenerate the CLAUDE.md block.
5. Commit: `chore: scaffold project map (.hv/map/, ## Project Map block)`.

### Mode: after-work

Auto-invoked at the end of `/hv-work`, `/hv-debug`, `/hv-go` when the cycle's plan touched files belonging to one or more subsystems.

1. Determine touched subsystems. Match changed files (from the cycle's commits) against each subsystem's `Key files / dirs` and `Entry points`. If no existing subsystem fits and the project is under the soft cap (default 20 subsystems), ask the user whether to propose a new subsystem; default to "yes" with an inferred name.
2. For each touched subsystem: bump `touched:` to today; refresh `summary:` if the cycle's intent changed it; add new entry points where helpful; do not rewrite untouched sections.
3. Run `bin/hv-map-index`.
4. Stage the `.hv/map/<name>.md` updates as part of the cycle's final commit (do not create a separate commit — ride along with the work).

### Mode: consolidate

Run on demand when the user asks ("consolidate the map", "clean up subsystems", or after a soft-cap warning).

1. Read `bin/hv-map-stats` to find: stale entries (via `bin/hv-staleness map --days 90`), near-duplicates (any two summaries with cosine-similarity-by-shared-words ≥ 0.6 — fall back to substring overlap if too coarse), entries with high `broken_refs`.
2. Propose, in order: merges (two subsystems → one, with a chosen target name), archives (rename to `.hv/map/_archive/<name>-YYYY-MM-DD.md`), and entry-point fixes.
3. Show the proposed changes; never auto-apply. On confirmation, perform them, run `bin/hv-map-index`, and commit: `chore: consolidate project map (<short reason>)`.
4. Apply the same review to KNOWLEDGE topics and TODO items: print suggestions ("topic X has 1 bullet from 8 months ago — fold into Y?", "TODO Z idle 90+ days — archive?"). Suggest only; do not edit those files in this skill.

## Soft caps

Default thresholds (override in `.hv/config.json`):

```json
{
  "map": {
    "softcap_subsystems": 20,
    "stale_days": 90
  }
}
```

When `bin/hv-map-stats` reports more subsystems than `softcap_subsystems`, `/hv-work`, `/hv-debug`, `/hv-go` print a one-line warning at start: `note: project map has N subsystems (cap N); consider /hv-map consolidate`. Never blocks.

## Failure modes

- Missing/corrupted detail file: helpers skip silently with stderr warning. Re-create or fix manually; the file lives in `.hv/map/`.
- Frontmatter `touched:` missing: hygiene falls back to git mtime.
- New subsystem proposal during `after-work` declined by user: cycle commits without the map update; the area stays uncovered until next time.
```

- [ ] **Step 3: Verify the file parses as a skill (frontmatter present, name matches dir)**

Run: `head -5 hv-map/SKILL.md`
Expected: shows `---`, `name: hv-map`, `description: ...`, `---`.

- [ ] **Step 4: Commit**

```bash
git add hv-map/SKILL.md
git commit -m "feat: /hv-map skill (first-run, after-work, consolidate)"
```

---

## Task 8: Wire `/hv-work`, `/hv-debug`, `/hv-go` to the map

**Files:**
- Modify: `hv-work/SKILL.md`
- Modify: `hv-debug/SKILL.md`
- Modify: `hv-go/SKILL.md`
- Test: `test/smoke.sh` (append — assertion-free check that the skills mention `hv-map-stats` / `/hv-map`)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`. The smoke runs in a tmpdir without the source skill files, so we check the source repo's files via `$REPO`:

```bash
# --- skill touchpoints reference map ------------------------------
grep -q "hv-map-stats\|hv-map after-work" "$REPO/hv-work/SKILL.md" || { echo "FAIL: hv-work has no map touchpoint"; exit 1; }
grep -q "hv-map after-work" "$REPO/hv-debug/SKILL.md" || { echo "FAIL: hv-debug has no map after-work"; exit 1; }
grep -q "hv-map after-work" "$REPO/hv-go/SKILL.md" || { echo "FAIL: hv-go has no map after-work"; exit 1; }
echo "ok skill touchpoints (work/debug/go)"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL on the first grep.

- [ ] **Step 3: Edit `hv-work/SKILL.md`**

Add two pieces:

(a) Near the start-of-cycle section (where soft-cap warnings would fit, alongside any existing preflight): add a paragraph and command:

```markdown
**Soft-cap check (start of cycle):** If `.hv/bin/hv-map-stats | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["subsystems"]))'` exceeds the configured `map.softcap_subsystems` (default 20), print a one-line note: `note: project map has N subsystems (cap N); consider /hv-map consolidate`. Never block.
```

(b) Near the end-of-cycle section (alongside the existing `/hv-learn` and `/hv-docs` calls): add a parallel bullet:

```markdown
- **Update project map.** Invoke `/hv-map after-work` for any subsystem whose Key files / dirs or Entry points overlap the files touched in this cycle. The map updates are staged as part of the cycle's final commit, not a separate commit.
```

- [ ] **Step 4: Edit `hv-debug/SKILL.md`**

Add an end-of-cycle bullet (in the same structural location as the existing `/hv-learn` nudge):

```markdown
- **Update project map.** Invoke `/hv-map after-work` if the fix touched files belonging to a known subsystem.
```

- [ ] **Step 5: Edit `hv-go/SKILL.md`**

Add the same bullet in the same place:

```markdown
- **Update project map.** Invoke `/hv-map after-work` if the change touched files belonging to a known subsystem.
```

- [ ] **Step 6: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok skill touchpoints (work/debug/go)`.

- [ ] **Step 7: Commit**

```bash
git add hv-work/SKILL.md hv-debug/SKILL.md hv-go/SKILL.md test/smoke.sh
git commit -m "feat: /hv-work, /hv-debug, /hv-go invoke /hv-map after-work"
```

---

## Task 9: Surface `Stale candidates:` in status/next/resume + Subsystem hint in capture

**Files:**
- Modify: `hv-status/SKILL.md`
- Modify: `hv-next/SKILL.md`
- Modify: `hv-resume/SKILL.md`
- Modify: `hv-capture/SKILL.md`
- Test: `test/smoke.sh` (append — grep checks)

- [ ] **Step 1: Append smoke case**

Append to `test/smoke.sh`:

```bash
# --- status/next/resume reference hv-staleness --------------------
grep -q "hv-staleness" "$REPO/hv-status/SKILL.md" || { echo "FAIL: hv-status missing staleness"; exit 1; }
grep -q "hv-staleness" "$REPO/hv-next/SKILL.md"   || { echo "FAIL: hv-next missing staleness"; exit 1; }
grep -q "hv-staleness" "$REPO/hv-resume/SKILL.md" || { echo "FAIL: hv-resume missing staleness"; exit 1; }
grep -q "Subsystem:" "$REPO/hv-capture/SKILL.md"  || { echo "FAIL: hv-capture missing Subsystem field"; exit 1; }
echo "ok status/next/resume/capture touchpoints"
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `bash test/smoke.sh`
Expected: FAIL on the first grep.

- [ ] **Step 3: Edit `hv-status/SKILL.md`**

In the section that emits the compact overview, add a final one-line item:

```markdown
- **Stale candidates** — print one line per kind summarising counts:
  `stale: map=$(.hv/bin/hv-staleness map --days 90 | wc -l), knowledge=N, todo=N`
  Suppress kinds with zero results. Never blocks.
```

- [ ] **Step 4: Edit `hv-next/SKILL.md`**

In the section that prints the backlog summary, add the same one-line item before the "next pick" suggestion. Use the same `hv-staleness` invocation. The line is informational; it does not change which item is recommended.

- [ ] **Step 5: Edit `hv-resume/SKILL.md`**

In the reorientation summary (alongside active streams + recent commits + backlog counts), add the same one-line item.

- [ ] **Step 6: Edit `hv-capture/SKILL.md`**

In the captured-row format, add an optional `Subsystem:` field next to the existing `Milestone:` field. The skill should:
- Infer it from filenames in the user's text (e.g. mentions of `hv-work`, `bin/hv-staleness` → propose `work` / subsystem named after closest map entry).
- If a guess is available, append `Subsystem: <name>` to the captured row.
- Never block capture for a missing `Subsystem:`.

Example captured row before:
```
- [B07] Title (Pri:P1, Size:S, Files:bin/hv-x) Captured: 2026-05-09
```
After:
```
- [B07] Title (Pri:P1, Size:S, Files:bin/hv-x, Subsystem:work) Captured: 2026-05-09
```

- [ ] **Step 7: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: PASS, `ok status/next/resume/capture touchpoints`.

- [ ] **Step 8: Commit**

```bash
git add hv-status/SKILL.md hv-next/SKILL.md hv-resume/SKILL.md hv-capture/SKILL.md test/smoke.sh
git commit -m "feat: surface stale candidates and Subsystem: capture hint"
```

---

## Task 10: End-to-end smoke for `/hv-map first-run` and consolidate proposals

**Files:**
- Modify: `test/smoke.sh` (append final integration case)

This task asserts the *helper-level* end-to-end behaviour the `/hv-map` skill relies on. It does not invoke the skill directly (skills are markdown, not executables) — it simulates the steps.

- [ ] **Step 1: Append the integration case**

Append to `test/smoke.sh`:

```bash
# --- end-to-end: scaffold + after-work bump + consolidate prep ----
TMP3=$(mktemp -d)
trap 'rm -rf "$TMP3" "$TMP" "$TMP2"' EXIT
(
  cd "$TMP3"
  git init -q
  git config user.email test@example.com
  git config user.name Test
  "$BIN/hv-bootstrap" >/dev/null
  : > CLAUDE.md
  # First-run-style scaffold: write two subsystems
  cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into TODO.md
touched: 2026-05-09
created: 2026-05-09
---

## Purpose
Capture flow.

## Entry points
- bin/hv-bootstrap:1 — file exists in this fixture
EOF
  cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Captures items into TODO.md  # near-duplicate summary
touched: 2025-12-01
created: 2025-12-01
---

## Purpose
Work flow.
EOF
  "$BIN/hv-map-index" >/dev/null

  # /hv-map after-work simulation: bump touched on capture
  python3 - <<'PY'
from pathlib import Path
p = Path(".hv/map/capture.md")
text = p.read_text().replace("touched: 2026-05-09", "touched: 2026-05-10")
p.write_text(text)
PY
  grep -q "touched: 2026-05-10" .hv/map/capture.md || { echo "FAIL: after-work bump"; exit 1; }

  # consolidate-input: stale subsystem visible
  out="$("$BIN/hv-staleness" map --days 30 --today 2026-05-10)"
  echo "$out" | grep -q "^work " || { echo "FAIL: work should be stale at days=30"; exit 1; }

  # stats sees both
  count=$("$BIN/hv-map-stats" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["subsystems"]))')
  [ "$count" = "2" ] || { echo "FAIL: stats count $count != 2"; exit 1; }

  # idempotent index regeneration
  "$BIN/hv-map-index" >/dev/null
  sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  "$BIN/hv-map-index" >/dev/null
  sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  [ "$sha1" = "$sha2" ] || { echo "FAIL: integration idempotence"; exit 1; }
)
echo "ok end-to-end map flow"
```

- [ ] **Step 2: Run smoke to verify it passes**

Run: `bash test/smoke.sh`
Expected: All cases pass, including `ok end-to-end map flow`. Existing pre-map cases must still pass.

- [ ] **Step 3: Update README and docs**

The user feedback memory says docs/ + README.md must be updated in-cycle. Add:

(a) `README.md` — under whatever existing section lists `/hv-*` commands, add `/hv-map` with one-line description.

(b) `docs/` — find the user-facing skill reference (likely `docs/skills/` or `docs/commands/`). Add a page or section for `/hv-map` covering: what it is, the three modes, when it auto-runs, how to consolidate.

If the docs structure is unclear, run `ls docs/` and pick the closest existing page to extend; do not invent a new directory.

- [ ] **Step 4: Commit**

```bash
git add test/smoke.sh README.md docs/
git commit -m "test: end-to-end smoke for project map flow + docs update"
```

---

## Self-Review Notes

**Spec coverage:**
- §"Three coordinated layers" → Tasks 1–5 (helpers), Task 6 (init seeding), Task 7 (skill).
- §"Detail file shape" → Convention recap above; Task 1 parser; Task 7 first-run scaffold.
- §"New helpers" → Tasks 2–5.
- §"New skill /hv-map" → Task 7.
- §"Touchpoints in existing skills" → Tasks 6 (init), 8 (work/debug/go), 9 (status/next/resume/capture).
- §"Always-on context impact" → Task 4 (CLAUDE.md block via `--body-stdin`).
- §"Lifecycle of a waypoint" → covered by the soft-cap + after-work + consolidate paths in Tasks 7–9.
- §"Failure modes & mitigations" → handled in helpers (Tasks 2–5: silent skip, git-mtime fallback, broken-ref detection) and skill (Task 7: missing-frontmatter + declined-proposal paths).
- §"Testing strategy" → Tasks 1–10 each include smoke cases; Task 10 covers the end-to-end + idempotence + staleness path.
- §"Open questions" defaults — soft-cap 20, stale-days 90 — are baked into Task 7 (config keys) and Task 5 (default flag).

**Type/method consistency check:**
- `parse_frontmatter` returns `(dict, str)` everywhere it's referenced.
- `iter_map_entries` yields `(name, fm, body, path)` 4-tuples — used consistently in Tasks 3, 4, 5.
- Helpers all named `hv-map-*` (no `hv_map_*` mix).
- Frontmatter keys: `subsystem`, `summary`, `touched`, `created`, `related-topics`, `related-items` — same in spec, scaffold (Task 7), and parser tests (Task 1).
- CLAUDE.md block markers `<!-- hv-map-start -->` / `<!-- hv-map-end -->` — same in Task 4 helper, Task 4 smoke, and `hv-managed-block` (which already pattern-matches on the key).
