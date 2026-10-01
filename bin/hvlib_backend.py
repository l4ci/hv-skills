"""Backlog backend seam: FileBackend owns the create/read verbs on .hv/BACKLOG.md.

Helpers (hv-append, hv-todo-field, hv-todo-set-field, hv-backlog) call
get_backend() and keep argv parsing, printing and exit codes to themselves;
the methods here take and return data. backlog.backend = "issues" has no
backend yet (M07-S02) and raises BackendUnavailable.

Imports sibling hvlib_* modules by direct path, never through the hvlib shim.
"""
import re
import subprocess
import sys
from pathlib import Path

from hvlib_io import load_config, write_text_atomic, update_json
from hvlib_config import backlog_backend
from hvlib_section import BACKLOG_FILE, find_section, iter_open_sections, load_backlog_corpus
from hvlib_bullet import (
    find_origin_bullet, parse_todo_fields, parse_done_line, set_todo_field, format_done_line,
)
from hvlib_paths import detail_dir_for_id, section_name_for_dir
from hvlib_types import COUNTABLE_TYPES

ISSUES_UNAVAILABLE = "issues backend not available yet (M07-S02)"


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


def get_backend(cfg=None):
    """The backend selected by backlog.backend. ValueError on a bad value,
    BackendUnavailable for "issues" until M07-S02."""
    if cfg is None:
        cfg = load_config()
    if backlog_backend(cfg) == "file":
        return FileBackend()
    raise BackendUnavailable(ISSUES_UNAVAILABLE)


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
