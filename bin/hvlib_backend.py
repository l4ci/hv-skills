"""Backlog backend seam: FileBackend owns the create/read verbs on .hv/BACKLOG.md.

Helpers (hv-append, hv-todo-field, hv-todo-set-field, hv-backlog) call
get_backend() and keep argv parsing, printing and exit codes to themselves;
the methods here take and return data. backlog.backend = "issues" selects
IssueBackend: reads come from the tracker as BACKLOG.md-shaped markdown
(backlog_markdown), so readers keep their parsers; lifecycle verbs (complete, claim, notes)
close, label and comment on the issues.

Imports sibling hvlib_* modules by direct path, never through the hvlib shim.
"""
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

from hvlib_io import load_config, write_text_atomic, update_json, locked
from hvlib_config import backlog_backend, tracker_label, config_value
from hvlib_section import BACKLOG_FILE, find_section, append_to_section, iter_open_sections, load_backlog_corpus
from hvlib_bullet import (
    find_origin_bullet, parse_todo_fields, parse_done_line, set_todo_field, format_done_line,
    _TODO_FIELD_NAMES, _SETTABLE_FIELDS, _CREATE_FIELDS,
)
from hvlib_paths import detail_dir_for_id, section_name_for_dir
from hvlib_tracker import adapter_for, TrackerError
from hvlib_types import COUNTABLE_TYPES, ITEM_TYPES


class BackendUnavailable(Exception):
    """The configured backend cannot serve this call."""


class ProofMissing(Exception):
    """A `done` close with no proof row recorded (hv-complete exits 3)."""


_REFACTOR_SUBJECT = re.compile(r"^refactor(\(.+?\))?!?:")


_KIND_PREFIX = {"bugs": "B", "features": "F", "tasks": "T"}
_KIND_TAGS = {"bugs": ("P0", "P1", "P2", "P3"), "features": ("Major", "Minor", "Cosmetic"), "tasks": ()}


def _check_create(kind, title, tag, fields):
    """Shared capture validation. Returns (clean title, tag, {Name: value}) or raises ValueError."""
    if kind not in _KIND_PREFIX:
        raise ValueError(f"unknown kind '{kind}' (expected bugs|features|tasks)")
    title = _one_line(title)
    if not title:
        raise ValueError("--title is required")
    tag = tag or ""
    if tag and tag not in _KIND_TAGS[kind]:
        allowed = "/".join(_KIND_TAGS[kind])
        raise ValueError(f"invalid tag '{tag}' for {kind}" + (f" (expected {allowed})" if allowed else " (tasks take no tag)"))
    clean = {}
    for name, value in (fields or {}).items():
        if name not in _CREATE_FIELDS:
            raise ValueError(f"'{name}' is not a settable field (expected {'|'.join(_CREATE_FIELDS)})")
        if not str(value).strip():
            raise ValueError(f"field {name} needs a non-empty value")
        clean[name] = _one_line(str(value))
    return title, tag, clean


def _proof_gate(item_id, reason, proof_show):
    """ProofMissing for a `done` close with no proof row (hv-proof-show --count)."""
    if reason == "done" and proof_show:
        n = subprocess.run([proof_show, item_id, "--count"],
                           capture_output=True, text=True).stdout.strip()
        if n in ("", "0"):
            raise ProofMissing(
                f"[{item_id}] no proof recorded, pass --no-proof to override "
                f"(hv-proof-add {item_id} --check <name> --result PASS --evidence <path-or-text>)")


class FileBackend:
    """Backlog verbs backed by .hv/BACKLOG.md (+ ARCHIVE.md for reads)."""

    path = Path(".hv") / BACKLOG_FILE

    def append(self, section, line):
        """Append `line` at the end of `section` ("## Bugs" or "Bugs").

        Raises FileNotFoundError when BACKLOG.md is missing, LookupError when
        the section is absent.
        """
        name = section[3:] if section.startswith("## ") else section
        # Capture anchor: stamp `Since: <short HEAD>` on bullets that lack it
        # (hv-todo-drift ignores commits older than capture), when HEAD exists.
        if line.startswith("- ") and "Since:" not in line:
            head = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                  capture_output=True, text=True)
            if head.returncode == 0 and head.stdout.strip():
                line = f"{line} Since: {head.stdout.strip()}"
        content = open(self.path).read()
        span = find_section(content, name)
        if span is None:
            raise LookupError(f"section '{section}' not found")
        _start, end = span
        tail = "\n" + content[end:] if content[end:] else ""
        content = content[:end].rstrip("\n") + "\n" + line + "\n" + tail
        write_text_atomic(self.path, content)

    def next_id(self, kind):
        """Bump counters.json and return the new zero-padded ID (`B07`).

        `kind` is bugs|features|tasks|milestones. The counter never lags the
        highest ID already in BACKLOG.md / ARCHIVE.md.
        """
        prefix = {**_KIND_PREFIX, "milestones": "M"}[kind]
        pat = re.compile(rf"\[{prefix}(\d+)\]")
        highest = 0
        for fname in (".hv/BACKLOG.md", ".hv/ARCHIVE.md"):
            p = Path(fname)
            if p.exists():
                for m in pat.finditer(p.read_text()):
                    highest = max(highest, int(m.group(1)))
        result = []

        def mutator(d):
            nxt = max(d.get(kind, 0), highest) + 1
            d[kind] = nxt
            result.append(nxt)

        update_json(Path(".hv/counters.json"), {}, mutator)
        return f"{prefix}{result[0]:02d}"

    def create(self, kind, title, tag="", desc="", fields=None, body=None):
        """Capture one item: mint the ID, append the bullet (Since stamped by
        append), write `body` to .hv/<kind>/<ID>.md (`{ID}` tokens replaced).

        `body` is bytes or None. Returns the ID. ValueError on bad input,
        FileNotFoundError / LookupError as append().
        """
        title, tag, fields = _check_create(kind, title, tag, fields)
        if not self.path.exists():
            raise FileNotFoundError(str(self.path))
        item_id = self.next_id(kind)
        parts = [f"- **[{item_id}] " + (f"[{tag}] " if tag else "")
                 + title + ("" if title[-1] in ".!?" else ".") + "**"]
        if (desc or "").strip():
            parts.append(desc.strip())
        if body is not None:
            parts.append(f"Detail: `.hv/{kind}/{item_id}.md`")
        parts += [f"{k}: {v}" for k, v in fields.items()]
        self.append(section_name_for_dir(kind), " ".join(parts))
        if body is not None:
            detail = Path(f".hv/{kind}/{item_id}.md")
            detail.parent.mkdir(parents=True, exist_ok=True)
            detail.write_bytes(body.replace(b"{ID}", item_id.encode()))
        return item_id

    def fields(self, item_id):
        """Every known field of the item's bullet (open or archived), plus
        `title`, `reason` and `note`. None when the ID is unknown."""
        corpus = load_backlog_corpus(".")
        result = find_origin_bullet(corpus, item_id)
        if result is None:
            return None
        line, title = result
        fields = parse_todo_fields(line)
        # Closure reason/note live on the Done marker, which find_origin_bullet strips.
        m = re.search(rf"^- ~~\*\*\[{re.escape(item_id)}\].*$", corpus, re.MULTILINE)
        done = parse_done_line(m.group(0)) if m else None
        fields["reason"] = done["reason"] if done else ""
        fields["note"] = done["note"] if done else ""
        fields["title"] = title
        return fields

    def set_field(self, item_id, field, value):
        """Set/replace/clear a trailing field on the open bullet of `item_id`.

        Returns True when the file changed, False for an idempotent no-op.
        Raises FileNotFoundError (no BACKLOG.md), LookupError (no open
        bullet), ValueError (field not settable).
        """
        if not self.path.exists():
            raise FileNotFoundError(str(self.path))
        content = self.path.read_text()
        # Open bullet only: `- **[ID] ...`. Done lines start `- ~~**[` and won't match.
        m = re.search(rf"^- \*\*\[{re.escape(item_id)}\].*$", content, re.MULTILINE)
        if not m:
            raise LookupError(
                f"[{item_id}] has no open bullet in .hv/{BACKLOG_FILE} "
                f"(unknown, completed, or archived)"
            )
        raw_line = m.group(0)
        new_line = set_todo_field(raw_line, field, value)
        if new_line == raw_line:
            return False
        write_text_atomic(self.path, content[: m.start()] + new_line + content[m.end():])
        return True

    def complete(self, item_id, hash_s, date_s, reason="done", note="", proof_show=None):
        """Move the open bullet of `item_id` to ## Completed with a Done marker.

        Returns True when moved, False for the idempotent already-completed
        no-op. Raises LookupError (unknown ID) and ProofMissing (a `done`
        close with no proof row; only checked when `proof_show`, the path of
        hv-proof-show, is given). Bumps counters.json#since_refactor unless
        the commit subject is a `refactor:` form.
        """
        content = self.path.read_text()
        active = re.compile(r"^- \*\*\[" + re.escape(item_id) + r"\].*$", re.MULTILINE)
        completed = re.compile(
            r"^- ~~\*\*\[" + re.escape(item_id) + r"\].*~~\s+Done\s+\d{4}-\d{2}-\d{2}", re.MULTILINE)
        m = active.search(content)
        if not m:
            if completed.search(content):
                return False
            raise LookupError(f"[{item_id}] not found")

        # Proof gate: only on the active->completed transition, only for `done`.
        _proof_gate(item_id, reason, proof_show)

        line = m.group(0)
        content = content[:m.start()] + content[m.end() + 1:]
        done = format_done_line(line, date_s, hash_s, reason, note)
        span = find_section(content, "Completed")
        if span is None:
            content = content.rstrip("\n") + "\n\n## Completed\n\n" + done + "\n"
        else:
            _start, end = span
            content = content[:end].rstrip("\n") + "\n" + done + "\n" + content[end:]
        write_text_atomic(self.path, content)

        # Refactor commits don't count toward refactor pressure; non-countable
        # types (Tasks) carry no counter. counters.json keys are detail-dir names.
        kind_key = detail_dir_for_id(item_id) if item_id[:1] in COUNTABLE_TYPES else None
        if kind_key:
            subj = subprocess.run(["git", "log", "-1", "--format=%s", hash_s],
                                  capture_output=True, text=True)
            if not (subj.returncode == 0 and _REFACTOR_SUBJECT.match(subj.stdout)):
                def bump(d):
                    sr = d.setdefault("since_refactor", {"features": 0, "bugs": 0})
                    sr[kind_key] = sr.get(kind_key, 0) + 1
                update_json(".hv/counters.json", {}, bump)
        return True

    def uncomplete(self, item_id):
        """Restore the Done line of `item_id` (BACKLOG ## Completed first, then
        ARCHIVE.md) to its active type section.

        Returns "restored", or "active" for the idempotent already-active no-op.
        Raises FileNotFoundError (no BACKLOG.md), LookupError (not found in
        either file), ValueError (unsupported ID prefix). Rewinds
        counters.json#since_refactor unless the original commit was a refactor.
        """
        backlog_path = self.path
        archive_path = Path(".hv") / "ARCHIVE.md"
        if not backlog_path.exists():
            raise FileNotFoundError(str(backlog_path))
        content = backlog_path.read_text()

        completed_span = find_section(content, "Completed")
        active_re = re.compile(r"^- \*\*\[" + re.escape(item_id) + r"\]", re.MULTILINE)
        for m in active_re.finditer(content):
            if completed_span is None or not (completed_span[0] <= m.start() < completed_span[1]):
                return "active"

        def find_done_in(text, id_target):
            """(line, line_start, line_end_excl_newline) or None."""
            pos = 0
            for raw in text.split("\n"):
                parsed = parse_done_line(raw)
                if parsed and parsed["id"] == id_target:
                    return (raw, pos, pos + len(raw))
                pos += len(raw) + 1
            return None

        source = None        # "backlog" | "archive"
        done_parsed = None
        if completed_span is not None:
            start, end = completed_span
            hit = find_done_in(content[start:end], item_id)
            if hit:
                line, lstart, lend = hit
                done_parsed = parse_done_line(line)
                abs_start, abs_end = start + lstart, start + lend
                if content[abs_end:].startswith("\n"):
                    abs_end += 1
                content = content[:abs_start] + content[abs_end:]
                source = "backlog"

        archive_content = None
        if source is None and archive_path.exists():
            archive_content = archive_path.read_text()
            hit = find_done_in(archive_content, item_id)
            if hit:
                line, lstart, lend = hit
                done_parsed = parse_done_line(line)
                cut_end = lend + 1 if archive_content[lend:].startswith("\n") else lend
                archive_content = archive_content[:lstart] + archive_content[cut_end:]
                source = "archive"

        if source is None:
            raise LookupError(
                f"[{item_id}] not found in BACKLOG.md (## Completed) or .hv/ARCHIVE.md")

        active_line = "- " + done_parsed["inner"]

        dir_name = detail_dir_for_id(item_id)
        target = section_name_for_dir(dir_name)
        if target == "Unknown":
            raise ValueError(f"[{item_id}] has unsupported prefix (expected B/F/T)")

        span = find_section(content, target)
        if span is None:
            comp = find_section(content, "Completed")
            block = f"## {target}\n{active_line}\n\n"
            if comp is None:
                content = content.rstrip("\n") + "\n\n" + block
            else:
                # comp[0] is just after the heading; walk back to its start.
                h_idx = content.rfind("## Completed", 0, comp[0])
                content = content[:h_idx] + block + content[h_idx:]
        else:
            s, e = span
            body = content[s:e]
            if any(ln.startswith("- ") for ln in body.splitlines()):
                new_body = body.rstrip("\n") + "\n" + active_line + "\n\n"
            else:
                new_body = "\n" + active_line + "\n\n"
            content = content[:s] + new_body + content[e:]

        write_text_atomic(backlog_path, content)
        if source == "archive":
            write_text_atomic(archive_path, archive_content)

        # Mirror complete()'s bump in reverse; skip tasks and refactor commits,
        # and skip silently when git can't resolve the hash.
        kind_key = dir_name if dir_name != "tasks" else None
        if kind_key:
            subj = subprocess.run(["git", "log", "-1", "--format=%s", done_parsed["hash"]],
                                  capture_output=True, text=True)
            if subj.returncode == 0 and not _REFACTOR_SUBJECT.match(subj.stdout):
                def dec(d):
                    sr = d.setdefault("since_refactor", {"features": 0, "bugs": 0})
                    sr[kind_key] = max(0, sr.get(kind_key, 0) - 1)
                update_json(".hv/counters.json", {}, dec)
        return "restored"

    def list_open(self):
        """(content, [(section_name, body), ...]) for the open sections, or
        None when BACKLOG.md does not exist."""
        if not self.path.exists():
            return None
        content = self.path.read_text()
        return content, list(iter_open_sections(content))

    def backlog_markdown(self, closed_limit=None):
        """BACKLOG.md verbatim (closed_limit is ignored), None when missing."""
        if not self.path.exists():
            return None
        return self.path.read_text()

    def canonical_id(self, ref):
        """File IDs are already canonical."""
        return ref

    def detail_text(self, item_id):
        """Content of the item's detail file, None when absent or unreadable."""
        d = detail_dir_for_id(item_id)
        if not d:
            return None
        path = Path(f".hv/{d}/{item_id}.md")
        if not path.exists():
            return None
        try:
            return path.read_text()
        except OSError:
            return None

    backlog_name = "BACKLOG.md"

    def claim(self, item_id, claim_id):
        """No-op: status.json is the file-mode lock."""
        return True, claim_id

    def release(self, item_id, claim_id):
        return False

    def set_state(self, item_id, state):
        return False

    def ready_reasons(self, item_id):
        """Same rule as IssueBackend over the detail file, .hv/designs/<ID>.md
        and .hv/plans/*-<ID>.md. LookupError for an unknown ID."""
        if find_origin_bullet(load_backlog_corpus("."), item_id) is None:
            raise LookupError(f"[{item_id}] not found in BACKLOG.md or ARCHIVE.md")
        note = Path(".hv/designs", f"{item_id}.md").exists() or any(Path(".hv/plans").glob(f"*-{item_id}.md"))
        return _ready_reasons(_has_criteria(self.detail_text(item_id)), note)

    def note_get(self, item_id, kind):
        raise BackendUnavailable(_FILE_NOTE_MSG.get(kind, _FILE_NOTE_MSG['design']))

    note_put = note_rm = note_get

    def comment_add(self, item_id, kind, text):
        """Append `- <date> · <kind> · <first line>` (continuation lines indented
        two spaces) under `## Log` in the item's detail file, creating the file
        like hv-proof-add when missing. LookupError for an unknown ID."""
        if kind not in COMMENT_KINDS:
            raise ValueError(f"comment kind must be one of {'/'.join(COMMENT_KINDS)}")
        d = detail_dir_for_id(item_id)
        if not d:
            raise LookupError(f"[{item_id}] has no detail directory (expected B/F/T prefix)")
        found = find_origin_bullet(load_backlog_corpus("."), item_id)
        if found is None:
            raise LookupError(f"[{item_id}] not found in BACKLOG.md or ARCHIVE.md")
        lines = (text or "").replace("\r\n", "\n").strip("\n").split("\n")
        row = f"- {date.today().isoformat()} \u00b7 {kind} \u00b7 {lines[0].strip()}\n" + "".join(
            f"  {l}\n" if l.strip() else "\n" for l in lines[1:])
        path = Path(f".hv/{d}/{item_id}.md")
        path.parent.mkdir(parents=True, exist_ok=True)
        with locked(path):
            content = path.read_text() if path.exists() else (
                f"# {item_id}: {found[1] or item_id}\n\n> Related TODO entry: `[{item_id}]` in `.hv/BACKLOG.md`\n")
            if find_section(content, "Log") is not None:
                new = append_to_section(content.rstrip("\n") + "\n", "Log", row)
            else:
                new = content.rstrip("\n") + f"\n\n## Log\n\n{row}"
            write_text_atomic(path, new)


# --- issue backend ---------------------------------------------------------

NOTE_KINDS = ("proof", "design", "plan")
COMMENT_KINDS = ("question", "answer", "decision", "feedback")
NOTE_LIMIT = 60000  # chars per marker comment (GitHub caps a comment at 65,536)
_FILE_NOTE_MSG = {
    "proof": "file backend keeps proof in the detail file's ## Proof section (hv-proof-add)",
    "design": "file backend keeps designs/plans in .hv/designs and .hv/plans",
    "plan": "file backend keeps designs/plans in .hv/designs and .hv/plans",
}
_MARKER_RE = re.compile(r"^<!-- hv:(proof|design|plan)(?: (\d+)/(\d+))? -->(?:\n|\Z)")


def _note_limit():
    """NOTE_LIMIT, overridable through HV_NOTE_LIMIT (tests lower it)."""
    try:
        return max(80, int(os.environ.get("HV_NOTE_LIMIT", NOTE_LIMIT)))
    except ValueError:
        return NOTE_LIMIT


def _note_norm(text):
    return (text or "").replace("\r\n", "\n").rstrip("\n")


def _note_parts(kind, text):
    """Comment bodies for `text`: one `<!-- hv:kind -->` comment, or numbered
    `<!-- hv:kind i/n -->` parts split on line boundaries (a line longer than
    a part is cut). Every part but the last ends in a newline, so concatenating
    the parts after the marker lines restores the text."""
    text = _note_norm(text)
    limit = _note_limit()
    single = f"<!-- hv:{kind} -->\n"
    if len(single) + len(text) <= limit:
        return [single + text]
    budget = limit - len(f"<!-- hv:{kind} 99/99 -->\n")
    chunks, cur = [], ""
    for line in text.splitlines(keepends=True):
        while len(line) > budget:
            if cur:
                chunks.append(cur)
                cur = ""
            chunks.append(line[:budget])
            line = line[budget:]
        if len(cur) + len(line) > budget:
            chunks.append(cur)
            cur = ""
        cur += line
    chunks.append(cur)
    # A trailing newline can only sit at a part's end if more text follows.
    n = len(chunks)
    return [f"<!-- hv:{kind} {i}/{n} -->\n{c}" for i, c in enumerate(chunks, 1)]


_FIELDS_OPEN = "<!-- hv:fields"
_FIELDS_RE = re.compile(r"\n*<!-- hv:fields\n(?P<body>.*?)\n?-->[ \t]*\n*\Z", re.DOTALL)
_FIELD_LINE_RE = re.compile(r"^([A-Za-z]+):[ \t]*(.*?)[ \t]*$")
# Fields that live in the body block: everything except what the tracker or git supplies.
_BLOCK_FIELDS = tuple(n for n in _TODO_FIELD_NAMES if n not in ("Milestone", "Since", "Detail"))
_ITEM_REF_RE = re.compile(rf"^(?:#(?P<n1>\d+)|(?P<t>[{ITEM_TYPES}])?(?P<n2>\d+))$", re.IGNORECASE)
_SECTION_FOR_LETTER = {"B": "Bugs", "F": "Features", "T": "Tasks"}
_NOT_FOUND_RE = re.compile(r"not found|could not resolve|404", re.IGNORECASE)


def resolve_item_ref(ref):
    """`#42`, `42` or `F42` -> (42, None) / (42, "F"). ValueError when malformed."""
    m = _ITEM_REF_RE.match(str(ref).strip())
    if not m:
        raise ValueError(f"not an item reference: {ref!r}")
    n = int(m.group("n1") or m.group("n2"))
    t = m.group("t")
    return n, (t.upper() if t else None)


def parse_fields_block(body):
    """(text_without_block, {Name: value}) for an issue body.

    The block is a trailing `<!-- hv:fields` ... `-->` comment, one `Name: value`
    per line. No block -> (body, {}).
    """
    body = (body or "").replace("\r\n", "\n")
    m = _FIELDS_RE.search(body)
    if not m:
        return body, {}
    fields = {}
    for line in m.group("body").split("\n"):
        fm = _FIELD_LINE_RE.match(line)
        if fm and fm.group(2):
            fields[fm.group(1)] = fm.group(2)
    return body[:m.start()], fields


def render_fields_block(text, fields):
    """Inverse of parse_fields_block: append the block to `text` (no block when
    `fields` has no non-empty values). Round-trips exactly for text without
    trailing newlines."""
    text = (text or "").rstrip("\n")
    lines = [f"{k}: {_one_line(str(v))}" for k, v in fields.items() if _one_line(str(v))]
    if not lines:
        return text
    block = _FIELDS_OPEN + "\n" + "\n".join(lines) + "\n-->"
    return f"{text}\n\n{block}" if text else block


def tracker_exit_code(err):
    """Exit code for a TrackerError: 3 unavailable and 4 rate-limited pass
    through, everything else is 1."""
    return err.code if err.code in (3, 4) else 1


def _bracket_ids(value):
    """`F12, B03` -> `[F12], [B03]` so Related matches the file grammar."""
    return re.sub(rf"(?<![\[\w])([{ITEM_TYPES}]\d+)(?![\]\w])", r"[\1]", value)


def _one_line(s):
    return re.sub(r"\s+", " ", s or "").strip()


class IssueBackend:
    """Backlog served from the issue tracker (reads, capture, field writes)."""

    def __init__(self, cfg=None):
        self.cfg = load_config() if cfg is None else cfg
        self._adapter = None

    @property
    def adapter(self):
        if self._adapter is None:
            self._adapter = adapter_for(self.cfg)
        return self._adapter

    # -- classification ----------------------------------------------------

    def _letter(self, issue):
        labels = issue["labels"]
        for letter, role in (("B", "types.bug"), ("F", "types.feature"), ("T", "types.task")):
            if tracker_label(self.cfg, role) in labels:
                return letter
        return "T"

    def _is_tracker(self, issue):
        return tracker_label(self.cfg, "milestoneTracker") in issue["labels"]

    def _tag(self, issue, letter):
        labels = issue["labels"]
        if letter == "B":
            pre = tracker_label(self.cfg, "priorityPrefix")
            for l in labels:
                m = re.fullmatch(re.escape(pre) + r"(\d+)", l)
                if m:
                    return f"P{m.group(1)}"
        elif letter == "F":
            pre = tracker_label(self.cfg, "sizePrefix")
            for l in labels:
                if l.startswith(pre) and len(l) > len(pre):
                    return l[len(pre):]
        return ""

    @staticmethod
    def _milestone(issue, block):
        title = _one_line(issue.get("milestone") or "")
        if title:
            m = re.match(r"M\d+", title)
            return m.group(0) if m else title
        return block.get("Milestone", "")

    def _fields(self, issue, block):
        """Rendered field values in _TODO_FIELD_NAMES order (Milestone first)."""
        out = {}
        ms = self._milestone(issue, block)
        if ms:
            out["Milestone"] = ms
        for name in _BLOCK_FIELDS:
            v = block.get(name, "")
            if v:
                out[name] = _bracket_ids(v) if name == "Related" else v
        return out

    # -- rendering ---------------------------------------------------------

    def _bullet_inner(self, issue):
        """`**[F3] [Major] Title.** text Milestone: M07 ...` for one issue."""
        letter = self._letter(issue)
        text, block = parse_fields_block(issue["body"])
        title = _one_line(issue["title"].replace("*", "")) or "(untitled)"
        if title[-1] not in ".!?":
            title += "."
        tag = self._tag(issue, letter)
        head = f"**[{letter}{issue['number']}] " + (f"[{tag}] " if tag else "") + f"{title}**"
        paras = [p for p in re.split(r"\n\s*\n", text) if p.strip()]
        desc = _one_line(paras[0]) if paras else ""
        if len(desc) > 200:
            desc = desc[:199].rstrip() + "\u2026"
        parts = [desc] + [f"{k}: {v}" for k, v in self._fields(issue, block).items()]
        return " ".join([head] + [p for p in parts if p])

    def _done_line(self, issue):
        date = (issue.get("closed_at") or "1970-01-01")[:10]
        suffix = " (dropped)" if issue.get("state_reason") == "not_planned" else ""
        return f"- ~~{self._bullet_inner(issue)}~~ Done {date} [`#{issue['number']}`]{suffix}"

    def backlog_markdown(self, closed_limit=20):
        """BACKLOG.md-shaped rendering: open issues by type, newest `closed_limit`
        closed ones (all when None, none when 0) as Done lines, newest first."""
        opened = [i for i in self.adapter.list(state="open") if not self._is_tracker(i)]
        sections = {"B": [], "F": [], "T": []}
        for i in sorted(opened, key=lambda i: i["number"]):
            sections[self._letter(i)].append(f"- {self._bullet_inner(i)}")
        out = ["# Backlog", ""]
        for letter in "BFT":
            out += [f"## {_SECTION_FOR_LETTER[letter]}", "", *sections[letter]]
            if sections[letter]:
                out.append("")
        done = []
        if closed_limit is None or closed_limit > 0:
            closed = [i for i in self.adapter.list(state="closed") if not self._is_tracker(i)]
            closed.sort(key=lambda i: (i.get("closed_at") or "", i["number"]), reverse=True)
            done = [self._done_line(i) for i in (closed if closed_limit is None else closed[:closed_limit])]
        out += ["## Completed", "", *done]
        return "\n".join(out).rstrip("\n") + "\n"

    def list_open(self):
        """Same contract as FileBackend.list_open, derived from the rendering."""
        content = self.backlog_markdown(closed_limit=0)
        return content, list(iter_open_sections(content))

    # -- single items ------------------------------------------------------

    def _lookup(self, ref):
        """The issue behind `ref`, or None (malformed, absent, tracker issue or
        type-letter mismatch). Other tracker failures raise TrackerError."""
        try:
            n, letter = resolve_item_ref(ref)
        except ValueError:
            return None
        try:
            issue = self.adapter.get(n)
        except TrackerError as e:
            if e.code == 1 and _NOT_FOUND_RE.search(e.message):
                return None
            raise
        if self._is_tracker(issue) or (letter and letter != self._letter(issue)):
            return None
        return issue

    def canonical_id(self, ref):
        """`#2` / `2` / `F2` -> `F2` (None when no such item)."""
        issue = self._lookup(ref)
        return None if issue is None else f"{self._letter(issue)}{issue['number']}"

    def fields(self, ref):
        """Same keys as FileBackend.fields; `detail` is the issue URL. None when unknown."""
        issue = self._lookup(ref)
        if issue is None:
            return None
        _text, block = parse_fields_block(issue["body"])
        rendered = self._fields(issue, block)
        out = {name.lower(): "" for name in _TODO_FIELD_NAMES}
        for k, v in rendered.items():
            out[k.lower()] = v
        out["detail"] = issue["url"]
        closed = issue["state"] == "closed"
        out["reason"] = ("dropped" if issue.get("state_reason") == "not_planned" else "done") if closed else ""
        out["note"] = ""
        out["title"] = _one_line(issue["title"].replace("*", "")).rstrip(".").strip() or "(untitled)"
        return out

    def detail_text(self, ref):
        """Issue body without the fields block; None when absent or empty."""
        issue = self._lookup(ref)
        if issue is None:
            return None
        text, _block = parse_fields_block(issue["body"])
        return text if text.strip() else None

    # -- writes ------------------------------------------------------------

    def _milestone_title(self, value):
        """Native milestone title for hv ID `value` (`M07`); TrackerError(1) when absent."""
        value = value.strip()
        if not re.fullmatch(r"M\d+", value):
            raise ValueError(f"issue mode takes one milestone ID like M07, got '{value}'")
        title = self.adapter.find_milestone(value)
        if title is None:
            raise TrackerError(
                1, f"milestone {value} not found on the tracker \u2014 create it with /hv-vision (M07-S05)")
        return title

    def create(self, kind, title, tag="", desc="", fields=None, body=None):
        """Capture one item as an issue and return its ID (`F42`).

        Labels: type, `<priorityPrefix><n>` for P-tags, `<sizePrefix><Tag>` for
        sizes. Body: desc, then `body` (bytes, a detail file's content) after a
        blank line, then the fields block (Milestone excluded: it is the native
        milestone). `{ID}` tokens in `body` are substituted by a second edit
        once the number exists (only when a token is present).
        """
        title, tag, fields = _check_create(kind, title, tag, fields)
        letter = _KIND_PREFIX[kind]
        labels = [tracker_label(self.cfg, {"B": "types.bug", "F": "types.feature", "T": "types.task"}[letter])]
        if tag and letter == "B":
            labels.append(tracker_label(self.cfg, "priorityPrefix") + tag[1:])
        elif tag:
            labels.append(tracker_label(self.cfg, "sizePrefix") + tag)
        ms_title = self._milestone_title(fields.pop("Milestone")) if "Milestone" in fields else None
        text = "\n\n".join(p for p in ((desc or "").strip(),
                                       body.decode(errors="replace").strip("\n") if body is not None else "") if p)
        full = render_fields_block(text, fields)
        self.adapter.ensure_labels(labels, auto_create=bool(config_value(self.cfg, "issues.autoCreateLabel")))
        number = self.adapter.create(title, full, labels, milestone=ms_title)
        if "{ID}" in full:
            self.adapter.edit(number, body=full.replace("{ID}", f"{letter}{number}"))
        return f"{letter}{number}"

    def set_field(self, ref, field, value):
        """Set/replace/clear a field on an open issue; same contract as FileBackend.

        Milestone is the native milestone; the others live in the body's fields
        block. Returns True when the tracker changed. LookupError: unknown or
        closed item. ValueError: field not settable (Detail included).
        """
        field = field.lower()
        if field not in _SETTABLE_FIELDS:
            raise ValueError(
                f"{field} is not a settable field; pick one of {'/'.join(_SETTABLE_FIELDS)}")
        issue = self._lookup(ref)
        if issue is None or issue["state"] != "open":
            raise LookupError(f"[{ref}] is not an open item on the issue tracker (unknown or closed)")
        value = value.strip()
        n = issue["number"]
        if field == "milestone":
            if not value:
                if not issue["milestone"]:
                    return False
                self.adapter.edit(n, remove_milestone=True)
                return True
            title = self._milestone_title(value)
            if issue["milestone"] == title:
                return False
            self.adapter.edit(n, milestone=title)
            return True
        name = field.capitalize()
        text, block = parse_fields_block(issue["body"])
        value = _one_line(value)
        if block.get(name, "") == value:
            return False
        new = dict(block)
        if value:
            new[name] = value
        else:
            new.pop(name, None)
        self.adapter.edit(n, body=render_fields_block(text, new))
        return True

    # -- marker notes and comments ------------------------------------------

    def _number(self, ref):
        try:
            return resolve_item_ref(ref)[0]
        except ValueError as e:
            raise LookupError(str(e))

    def _note_comments(self, n, kind):
        """[(comment, body_after_marker)] of the `kind` note in part order."""
        found = []
        for c in self.adapter.comments(n):
            m = _MARKER_RE.match(c["body"].replace("\r\n", "\n"))
            if m and m.group(1) == kind:
                found.append((int(m.group(2) or 1), c["id"], c, c["body"].replace("\r\n", "\n")[m.end():]))
        found.sort(key=lambda t: (t[0], t[1]))
        return [(c, rest) for _i, _id, c, rest in found]

    def note_get(self, ref, kind):
        """The `kind` (proof|design|plan) note text, None when absent. Trailing
        newlines are not kept."""
        self._check_kind(kind)
        parts = self._note_comments(self._number(ref), kind)
        return _note_norm("".join(rest for _c, rest in parts)) if parts else None

    def note_put(self, ref, kind, text):
        """Upsert the note: edit existing parts in place, add missing ones,
        delete surplus ones. Returns False (no API writes) when unchanged."""
        self._check_kind(kind)
        n = self._number(ref)
        existing = self._note_comments(n, kind)
        want = _note_parts(kind, text)
        changed = False
        for i, body in enumerate(want):
            if i < len(existing):
                cur = existing[i][0]["body"].replace("\r\n", "\n")
                if i == len(want) - 1:  # the tracker may trim trailing newlines
                    cur, body = cur.rstrip("\n"), body.rstrip("\n")
                if cur != body:
                    self.adapter.edit_comment(n, existing[i][0]["id"], body)
                    changed = True
            else:
                self.adapter.add_comment(n, body)
                changed = True
        for c, _rest in existing[len(want):]:
            self.adapter.delete_comment(n, c["id"])
            changed = True
        return changed

    def note_rm(self, ref, kind):
        """Delete every part of the note; False when there was none."""
        self._check_kind(kind)
        n = self._number(ref)
        parts = self._note_comments(n, kind)
        for c, _rest in parts:
            self.adapter.delete_comment(n, c["id"])
        return bool(parts)

    @staticmethod
    def _check_kind(kind):
        if kind not in NOTE_KINDS:
            raise ValueError(f"note kind must be one of {'/'.join(NOTE_KINDS)}")

    def comment_add(self, ref, kind, text):
        """Append-only `<!-- hv:comment <kind> -->` comment; returns its id."""
        if kind not in COMMENT_KINDS:
            raise ValueError(f"comment kind must be one of {'/'.join(COMMENT_KINDS)}")
        return self.adapter.add_comment(
            self._number(ref), f"<!-- hv:comment {kind} -->\n{_note_norm(text)}")

    def append(self, *_a, **_k):
        raise BackendUnavailable("issue mode creates items with hv-item-create")

    # -- lifecycle ---------------------------------------------------------

    backlog_name = "the issue tracker"

    def _state_labels(self, *roles):
        return [tracker_label(self.cfg, r) for r in (roles or _STATE_ROLES)]

    def _require(self, ref):
        issue = self._lookup(ref)
        if issue is None:
            raise LookupError(f"[{ref}] not found in the issue tracker")
        return issue, f"{self._letter(issue)}{issue['number']}"

    def complete(self, ref, hash_s, date_s, reason="done", note="", proof_show=None):
        """Close the issue with the reason's tracker state; same contract as
        FileBackend.complete (False = already closed, LookupError unknown,
        ProofMissing for an unproven `done`).

        done -> closed as completed + "Done in `<hash>`"; dropped / handed-off ->
        closed as not planned + "Closed: <reason>"; blocked -> stays open with
        the blocked label and a "Blocked" comment. Closing also clears the
        in-progress / needs-review / changes-requested / blocked labels.
        """
        issue, item_id = self._require(ref)
        if issue["state"] == "closed":
            return False
        n = issue["number"]
        labels = issue["labels"]
        note = _one_line(note)
        suffix = f" \u2014 {note}" if note else ""
        if reason == "blocked":
            label = tracker_label(self.cfg, "blocked")
            if label in labels:
                return False
            self.adapter.add_labels(n, [label], auto_create=bool(config_value(self.cfg, "issues.autoCreateLabel")))
            self.adapter.add_comment(n, "Blocked" + suffix)
            return True
        _proof_gate(item_id, reason, proof_show)
        stale = [l for l in self._state_labels() if l in labels]
        if stale:
            self.adapter.remove_labels(n, stale)
        if reason == "done":
            self.adapter.close(n, "completed", comment=f"Done in `{hash_s}`" + suffix)
        else:
            self.adapter.close(n, "not_planned", comment=f"Closed: {reason}" + suffix)
        return True

    def uncomplete(self, ref):
        """Reopen a closed issue (clearing not-planned / blocked) or unblock an
        open one. "restored", or "active" when there was nothing to undo."""
        issue, _id = self._require(ref)
        n = issue["number"]
        stale = [l for l in self._state_labels("notPlanned", "blocked") if l in issue["labels"]]
        if issue["state"] == "closed":
            self.adapter.reopen(n)
        elif tracker_label(self.cfg, "blocked") not in stale:
            return "active"
        if stale:
            self.adapter.remove_labels(n, stale)
        return "restored"

    # -- claim lock, readiness, state labels ---------------------------------

    def _open_claims(self, n):
        """Claim ids with no later release, in claim order (earliest holds)."""
        held = []
        for c in self.adapter.comments(n):
            m = _CLAIM_RE.match(c["body"].replace("\r\n", "\n"))
            if not m:
                continue
            if m.group(1) == "claim":
                if m.group(2) not in held:
                    held.append(m.group(2))
            elif m.group(2) in held:
                held.remove(m.group(2))
        return held

    def _apply_state(self, issue, want):
        """One edit call leaving only the `want` role label (None = none) of
        in-progress / needs-review / changes-requested. True when it wrote."""
        labels = issue["labels"]
        keep = tracker_label(self.cfg, want) if want else None
        drop = [l for l in self._state_labels("inProgress", "needsReview", "changesRequested")
                if l != keep and l in labels]
        add = [keep] if keep and keep not in labels else []
        if not (drop or add):
            return False
        if add:
            self.adapter.ensure_labels(add, auto_create=bool(config_value(self.cfg, "issues.autoCreateLabel")))
        self.adapter.edit(issue["number"], add_labels=add, remove_labels=drop)
        return True

    def claim(self, ref, claim_id):
        """Take the item: post a claim marker, re-read, and the earliest open
        claim wins. Returns (won, holder). A loser posts its release marker and
        changes no labels; the winner gets in-progress and the assignment.
        LookupError for an unknown or closed item."""
        issue, _id = self._require(ref)
        if issue["state"] != "open":
            raise LookupError(f"[{ref}] is closed")
        n = issue["number"]
        held = self._open_claims(n)
        if not (held and held[0] == claim_id):
            self.adapter.add_comment(n, f"<!-- hv:claim {claim_id} -->\nClaimed by {claim_id}")
            held = self._open_claims(n)
            if held[0] != claim_id:
                self.adapter.add_comment(n, f"<!-- hv:release {claim_id} -->")
                return False, held[0]
        if self._apply_state(issue, "inProgress") or not issue["assignees"]:
            self.adapter.assign_self(n)
        return True, claim_id

    def release(self, ref, claim_id):
        """Post the release marker; drops in-progress when no claim remains.
        False (no writes) when `claim_id` holds no open claim."""
        issue, _id = self._require(ref)
        n = issue["number"]
        held = self._open_claims(n)
        if claim_id not in held:
            return False
        self.adapter.add_comment(n, f"<!-- hv:release {claim_id} -->")
        if held == [claim_id]:
            label = tracker_label(self.cfg, "inProgress")
            if label in issue["labels"]:
                self.adapter.remove_labels(n, [label])
        return True

    def set_state(self, ref, state):
        """Ensure exactly one state label (in-progress|needs-review|changes-requested)
        or none. True when the tracker changed."""
        if state not in _STATE_ROLE_FOR:
            raise ValueError(f"state must be one of {'/'.join(_STATE_ROLE_FOR)}")
        issue, _id = self._require(ref)
        return self._apply_state(issue, _STATE_ROLE_FOR[state])

    # -- review queue ----------------------------------------------------------

    def review_queue(self):
        """Open issues labelled needs-review with the open PRs/MRs that close
        them: [{"id", "number", "title", "prs": [{number, title, branch, url, body}]}].
        One issue list and one PR list; matching happens in memory."""
        label = tracker_label(self.cfg, "needsReview")
        issues = [i for i in self.adapter.list(state="open", labels=[label]) if not self._is_tracker(i)]
        by_issue = {}
        for pr in self.adapter.open_prs():
            for n in self.adapter.closed_numbers(pr["body"]):
                by_issue.setdefault(n, []).append(pr)
        issues.sort(key=lambda i: i["number"])
        return [{"id": f"{self._letter(i)}{i['number']}", "number": i["number"], "title": i["title"],
                 "prs": by_issue.get(i["number"], [])} for i in issues]

    def merge_pr(self, pr, items=None):
        """Merge PR/MR `pr` and make sure its linked items end up closed.

        Linked = `items` when given, else every issue the PR body closes. Proof is
        checked BEFORE merging: a merge into the default branch makes the host close
        the issues itself, which would skip the gate. Any open linked item without
        proof blocks the merge: nothing is merged, each such item flips to
        changes-requested with a feedback comment, and merge_sha is None. Otherwise
        the PR merges; linked items the host left open are closed through complete().
        Returns (merge_sha, closed_ids, unproven_ids). LookupError for an unknown PR.
        """
        pr = int(pr)
        explicit = items is not None
        found = [p for p in self.adapter.open_prs() if p["number"] == pr]
        if items is None:
            if not found:
                raise LookupError(f"PR {pr} is not open")
            items = [f"#{n}" for n in self.adapter.closed_numbers(found[0]["body"])]
        linked = []
        for ref in items:  # resolve before merging so a bad ref fails with nothing merged
            if explicit:
                linked.append(self._require(ref)[1])
            elif (issue := self._lookup(ref)) is not None:  # a tracker issue is not an item
                linked.append(f"{self._letter(issue)}{issue['number']}")
        proof_show = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hv-proof-show")
        unproven = []
        for ref in linked:
            issue, item_id = self._require(ref)
            if issue["state"] != "open":
                continue
            try:
                _proof_gate(item_id, "done", proof_show)
            except ProofMissing:
                unproven.append(item_id)
        if unproven:
            for item_id in unproven:
                self.set_state(item_id, "changes-requested")
                self.comment_add(
                    item_id, "feedback",
                    f"PR {pr} not merged: no proof recorded for {item_id}. "
                    "Add proof with hv-proof-add, then run the review again.")
            return None, [], unproven
        sha = self.adapter.pr_merge(pr)
        closed = []
        for ref in linked:
            issue, item_id = self._require(ref)
            if issue["state"] == "open":
                self.complete(item_id, sha[:7], date.today().isoformat(), "done", "", proof_show)
            else:  # the host closed it on merge; it leaves the state label behind
                self._apply_state(issue, None)
            closed.append(item_id)
        return sha, closed, unproven

    def ready_reasons(self, ref):
        """What is missing before work starts: [] when ready. Ready = acceptance
        criteria in the body (an Acceptance heading or a checkbox line) or a
        design / plan note."""
        issue, _id = self._require(ref)
        text, _block = parse_fields_block(issue["body"])
        return _ready_reasons(
            _has_criteria(text),
            bool(self.note_get(ref, "design")) or bool(self.note_get(ref, "plan")))


_STATE_ROLES = ("inProgress", "needsReview", "changesRequested", "blocked")
_STATE_ROLE_FOR = {"in-progress": "inProgress", "needs-review": "needsReview",
                   "changes-requested": "changesRequested", "none": None}
_CLAIM_RE = re.compile(r"^<!-- hv:(claim|release) (\S+) -->")
_ACCEPT_HEADING_RE = re.compile(r"^#{1,6}[ \t]+.*acceptance", re.IGNORECASE | re.MULTILINE)
_CHECKBOX_RE = re.compile(r"^[ \t]*[-*][ \t]+\[[ xX]\]", re.MULTILINE)


def _has_criteria(text):
    return bool(_ACCEPT_HEADING_RE.search(text or "") or _CHECKBOX_RE.search(text or ""))


def _ready_reasons(has_criteria, has_note):
    reasons = []
    if not has_criteria:
        reasons.append("no acceptance criteria in the issue body")
    if not has_note:
        reasons.append("no design or plan note")
    return [] if (has_criteria or has_note) else reasons


def get_backend(cfg=None):
    """The backend selected by backlog.backend. ValueError on a bad value."""
    if cfg is None:
        cfg = load_config()
    if backlog_backend(cfg) == "file":
        return FileBackend()
    return IssueBackend(cfg)


def require_file_backend(helper, pointer, cfg=None):
    """Guard for helpers that only make sense on BACKLOG.md.

    Returns None under the file backend; raises BackendUnavailable (message
    names the tracker equivalent) under "issues"; ValueError on a bad value.
    """
    if cfg is None:
        cfg = load_config()
    if backlog_backend(cfg) != "file":
        raise BackendUnavailable(f'not available with backlog.backend "issues" \u2014 {pointer}')


def _main(argv):
    """`python3 -m hvlib_backend require-file <helper> <pointer>`: shell guard.

    Exit 0 under the file backend, 2 when refused, 1 on an invalid backend.
    `python3 -m hvlib_backend is-issues`: exit 0 in issue mode, 1 otherwise.
    """
    if len(argv) == 2 and argv[1] == "is-issues":
        # Exit 0 when backlog.backend is "issues", 1 otherwise (an unreadable or invalid config
        # counts as file mode so file-mode helpers keep ignoring config).
        try:
            return 0 if isinstance(get_backend(), IssueBackend) else 1
        except Exception:
            return 1
    if len(argv) != 4 or argv[1] != "require-file":
        sys.stderr.write("usage: hvlib_backend require-file <helper> <pointer> | is-issues\n")
        return 1
    helper, pointer = argv[2], argv[3]
    try:
        require_file_backend(helper, pointer)
    except BackendUnavailable as e:
        sys.stderr.write(f"error: {helper}: {e}\n")
        return 2
    except ValueError as e:
        sys.stderr.write(f"error: {helper}: {e}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
