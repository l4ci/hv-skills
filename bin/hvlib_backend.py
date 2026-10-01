"""Backlog backend seam: FileBackend owns the create/read verbs on .hv/BACKLOG.md.

Helpers (hv-append, hv-todo-field, hv-todo-set-field, hv-backlog) call
get_backend() and keep argv parsing, printing and exit codes to themselves;
the methods here take and return data. backlog.backend = "issues" selects
IssueBackend: reads come from the tracker as BACKLOG.md-shaped markdown
(backlog_markdown), so readers keep their parsers; write verbs raise
BackendUnavailable until M07-S02 T4 / M07-S03.

Imports sibling hvlib_* modules by direct path, never through the hvlib shim.
"""
import re
import subprocess
import sys
from pathlib import Path

from hvlib_io import load_config, write_text_atomic, update_json
from hvlib_config import backlog_backend, tracker_label
from hvlib_section import BACKLOG_FILE, find_section, iter_open_sections, load_backlog_corpus
from hvlib_bullet import (
    find_origin_bullet, parse_todo_fields, parse_done_line, set_todo_field, format_done_line,
    _TODO_FIELD_NAMES,
)
from hvlib_paths import detail_dir_for_id, section_name_for_dir
from hvlib_tracker import adapter_for, TrackerError
from hvlib_types import COUNTABLE_TYPES, ITEM_TYPES


class BackendUnavailable(Exception):
    """The configured backend cannot serve this call."""


class ProofMissing(Exception):
    """A `done` close with no proof row recorded (hv-complete exits 3)."""


_REFACTOR_SUBJECT = re.compile(r"^refactor(\(.+?\))?!?:")


class FileBackend:
    """Backlog verbs backed by .hv/BACKLOG.md (+ ARCHIVE.md for reads)."""

    path = Path(".hv") / BACKLOG_FILE

    def append(self, section, line):
        """Append `line` at the end of `section` ("## Bugs" or "Bugs").

        Raises FileNotFoundError when BACKLOG.md is missing, LookupError when
        the section is absent.
        """
        name = section[3:] if section.startswith("## ") else section
        content = open(self.path).read()
        span = find_section(content, name)
        if span is None:
            raise LookupError(f"section '{section}' not found")
        _start, end = span
        tail = "\n" + content[end:] if content[end:] else ""
        content = content[:end].rstrip("\n") + "\n" + line + "\n" + tail
        write_text_atomic(self.path, content)

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
        if reason == "done" and proof_show:
            n = subprocess.run([proof_show, item_id, "--count"],
                               capture_output=True, text=True).stdout.strip()
            if n in ("", "0"):
                raise ProofMissing(
                    f"[{item_id}] no proof recorded, pass --no-proof to override "
                    f"(hv-proof-add {item_id} --check <name> --result PASS --evidence <path-or-text>)")

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


# --- issue backend ---------------------------------------------------------

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
    """Backlog served from the issue tracker (reads only so far)."""

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

    # -- writes: not yet ---------------------------------------------------

    def append(self, *_a, **_k):
        raise BackendUnavailable("issues backend not available yet (M07-S02 T4)")

    def set_field(self, *_a, **_k):
        raise BackendUnavailable("issues backend not available yet (M07-S02 T4)")

    def complete(self, *_a, **_k):
        raise BackendUnavailable("issues backend not available yet (M07-S03)")

    def uncomplete(self, *_a, **_k):
        raise BackendUnavailable("issues backend not available yet (M07-S03)")


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
    """
    if len(argv) != 4 or argv[1] != "require-file":
        sys.stderr.write("usage: hvlib_backend require-file <helper> <pointer>\n")
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
