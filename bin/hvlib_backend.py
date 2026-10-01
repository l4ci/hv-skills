"""Backlog backend seam: FileBackend owns the create/read verbs on .hv/BACKLOG.md.

Helpers (hv-append, hv-todo-field, hv-todo-set-field, hv-backlog) call
get_backend() and keep argv parsing, printing and exit codes to themselves;
the methods here take and return data. backlog.backend = "issues" has no
backend yet (M07-S02) and raises BackendUnavailable.

Imports sibling hvlib_* modules by direct path, never through the hvlib shim.
"""
import re
from pathlib import Path

from hvlib_io import load_config, write_text_atomic
from hvlib_config import backlog_backend
from hvlib_section import BACKLOG_FILE, find_section, iter_open_sections, load_backlog_corpus
from hvlib_bullet import find_origin_bullet, parse_todo_fields, parse_done_line, set_todo_field

ISSUES_UNAVAILABLE = "issues backend not available yet (M07-S02)"


class BackendUnavailable(Exception):
    """The configured backend cannot serve this call."""


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

    def list_open(self):
        """(content, [(section_name, body), ...]) for the open sections, or
        None when BACKLOG.md does not exist."""
        if not self.path.exists():
            return None
        content = self.path.read_text()
        return content, list(iter_open_sections(content))


def get_backend(cfg=None):
    """The backend selected by backlog.backend. ValueError on a bad value,
    BackendUnavailable for "issues" until M07-S02."""
    if cfg is None:
        cfg = load_config()
    if backlog_backend(cfg) == "file":
        return FileBackend()
    raise BackendUnavailable(ISSUES_UNAVAILABLE)
