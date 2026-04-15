---
name: hv:init
description: Initialize the .hv/ folder structure with TODO.md, counters.json, config.json, status.json, and CLI helpers. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

# hv:init — Initialize Project Backlog

Set up the `.hv/` folder with data files and CLI helpers for a project.

## Step 1 — Run Init

Run this script in the project root:

```bash
set -euo pipefail
HV=".hv"

# ── directories ──
mkdir -p "$HV"/{bugs,features,tasks,bin}

# ── data files (never overwrite) ──
[ -f "$HV/TODO.md" ] || cat > "$HV/TODO.md" <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF

[ -f "$HV/counters.json" ] || echo '{"bugs":0,"features":0,"tasks":0}' > "$HV/counters.json"

[ -f "$HV/config.json" ] || cat > "$HV/config.json" <<'CONF'
{
  "models": {
    "orchestrator": "opus",
    "worker": "sonnet"
  },
  "work": {
    "isolation": "branch",
    "mergeStrategy": "direct"
  },
  "refactor": {
    "confirmBeforeExecute": true
  }
}
CONF

[ -f "$HV/status.json" ] || echo '{"active":[]}' > "$HV/status.json"

# ── helper scripts (always refresh) ──

cat > "$HV/bin/hv-next-id" <<'SCRIPT'
#!/usr/bin/env bash
# Increment counter and return zero-padded ID.
# Usage: hv-next-id <bugs|features|tasks>
set -euo pipefail
TYPE="${1:?usage: hv-next-id <bugs|features|tasks>}"
case "$TYPE" in
  bugs) P=B ;; features) P=F ;; tasks) P=T ;;
  *) echo "error: unknown type '$TYPE'" >&2; exit 1 ;;
esac
python3 -c "
import json
p='.hv/counters.json'
d=json.load(open(p))
d['$TYPE']=d.get('$TYPE',0)+1
json.dump(d,open(p,'w'))
print(f'$P{d[\"$TYPE\"]:02d}')
"
SCRIPT

cat > "$HV/bin/hv-append" <<'SCRIPT'
#!/usr/bin/env bash
# Append entry to a section in .hv/TODO.md.
# Usage: hv-append "## Bugs" "- **[B07] [P1] Title.** Desc."
set -euo pipefail
SECTION="${1:?usage: hv-append <section> <entry>}"
ENTRY="${2:?usage: hv-append <section> <entry>}"
python3 - "$SECTION" "$ENTRY" <<'PY'
import sys
sec, entry, path = sys.argv[1], sys.argv[2], ".hv/TODO.md"
with open(path) as f: content = f.read()
marker = sec + "\n"
idx = content.find(marker)
if idx == -1:
    print(f"error: section '{sec}' not found", file=sys.stderr); sys.exit(1)
after = idx + len(marker)
nxt = content.find("\n## ", after)
if nxt == -1:
    content = content.rstrip("\n") + "\n" + entry + "\n"
else:
    before = content[:nxt].rstrip("\n")
    content = before + "\n" + entry + "\n" + content[nxt:]
with open(path, "w") as f: f.write(content)
PY
SCRIPT

cat > "$HV/bin/hv-complete" <<'SCRIPT'
#!/usr/bin/env bash
# Move item to ## Completed with strikethrough and metadata.
# Usage: hv-complete <ID> [commit-hash]
set -euo pipefail
ID="${1:?usage: hv-complete <ID> [commit-hash]}"
HASH="${2:-$(git log --oneline -1 --format='%h' 2>/dev/null || echo unknown)}"
DATE=$(date +%Y-%m-%d)
python3 - "$ID" "$HASH" "$DATE" <<'PY'
import re, sys
id_s, hash_s, date_s = sys.argv[1], sys.argv[2], sys.argv[3]
path = ".hv/TODO.md"
with open(path) as f: content = f.read()
pat = re.compile(r"^- \*\*\[" + re.escape(id_s) + r"\].*$", re.MULTILINE)
m = pat.search(content)
if not m:
    print(f"error: [{id_s}] not found", file=sys.stderr); sys.exit(1)
line = m.group(0)
content = content[:m.start()] + content[m.end()+1:]
done = f"- ~~{line[2:]}~~ Done {date_s} [`{hash_s}`]"
ci = content.find("## Completed")
if ci == -1:
    content = content.rstrip("\n") + "\n\n## Completed\n\n" + done + "\n"
else:
    after = ci + len("## Completed\n")
    nxt = content.find("\n## ", after)
    if nxt == -1:
        content = content.rstrip("\n") + "\n" + done + "\n"
    else:
        content = content[:nxt].rstrip("\n") + "\n" + done + "\n" + content[nxt:]
with open(path, "w") as f: f.write(content)
PY
SCRIPT

chmod +x "$HV"/bin/hv-*

# ── .gitignore ──
if [ -f .gitignore ]; then
  grep -qxF '.hv/' .gitignore 2>/dev/null || printf '\n# ── hv backlog ──\n.hv/\n' >> .gitignore
else
  printf '# ── hv backlog ──\n.hv/\n' > .gitignore
fi

echo "initialized"
```

## Step 2 — Confirm

If the output says "initialized", tell the user:

```
Initialized .hv/ backlog:
  .hv/TODO.md         — bugs, features, tasks
  .hv/counters.json   — auto-increment IDs
  .hv/config.json     — model, isolation, and merge settings
  .hv/status.json     — active work stream tracking
  .hv/bin/             — CLI helpers (hv-next-id, hv-append, hv-complete)
  .hv/bugs/            — overflow detail files for bug reports
  .hv/features/        — overflow detail files for feature specs
  .hv/tasks/           — overflow detail files for task descriptions
  .gitignore           — .hv/ excluded

Use /hv:capture to add bugs, features, or tasks.
Use /hv:next to see what to work on.
Edit .hv/config.json to change models, isolation, or merge strategy.
```

If `.hv/TODO.md` already existed, tell the user it was already initialized and that helper scripts were refreshed.

## Config Reference

- `models.orchestrator` — model for planning, exploration, design, and verification (`"opus"`, `"sonnet"`, `"haiku"`)
- `models.worker` — model for implementation subagents
- `work.isolation` — `"branch"` (default) or `"worktree"` (isolated directory under `.claude/worktrees/`)
- `work.mergeStrategy` — `"direct"` (default, merge to main) or `"pr"` (push and create GitHub PR)
- `refactor.confirmBeforeExecute` — `true` (default, pause for approval) or `false` (full autonomy)
