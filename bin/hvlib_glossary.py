"""Glossary entry parsing + rendering for the `## Glossary` topic in
KNOWLEDGE.md. Pure stdlib; no dependency on other hvlib_<name> modules.
Re-exported by hvlib for backward compat.

parse_glossary_entries and build_glossary_entry are mirror functions —
parse takes markdown nested-bullet entries and yields dict records;
build takes a record and re-renders the same nested-bullet markdown.
Both are shared by hv-glossary-write (single) and hv-glossary-import
(batch) so the on-disk format stays byte-identical across writers.

parse_term_entry handles the legacy CONTEXT.md per-entry `## <term>`
shape (preserved post-F18 for migration callers). first_sentence is a
small definition-to-gloss helper used by the CLAUDE.md Project Context
renderer.
"""
import re


def parse_term_entry(body: str) -> dict:
    """Extract definition, aliases, nots from a CONTEXT.md term section body.

    Body is the text after `## <term>` up to the next `## ` heading (the same
    string `iter_topics` yields). Recognized markers in the body:

      - `**Aliases:** a, b, c`  (or `_none_` for empty list)
      - `**Not:** x, y, z`      (optional; absent → empty list)
      - `<!-- YYYY-MM-DD -->`   (date stamp; ignored here, parsed by callers)

    Everything before the first marker line is the definition (whitespace-
    stripped). The HTML date comment is treated as a marker (definition ends
    above it) but its value is not parsed by this helper.

    Returns: {"definition": str, "aliases": list[str], "nots": list[str]}
    """
    aliases: list[str] = []
    nots: list[str] = []
    def_lines: list[str] = []
    seen_marker = False
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("**Aliases:**"):
            value = stripped[len("**Aliases:**"):].strip()
            if value and value != "_none_":
                aliases = [a.strip() for a in value.split(",") if a.strip()]
            seen_marker = True
            continue
        if stripped.startswith("**Not:**"):
            value = stripped[len("**Not:**"):].strip()
            if value:
                nots = [n.strip() for n in value.split(",") if n.strip()]
            seen_marker = True
            continue
        if stripped.startswith("<!--") and stripped.endswith("-->"):
            seen_marker = True
            continue
        if not seen_marker:
            def_lines.append(line)
    definition = "\n".join(def_lines).strip()
    return {"definition": definition, "aliases": aliases, "nots": nots}


def first_sentence(text: str, max_chars: int = 160) -> str:
    """Return the leading sentence of `text` (up to the first `.`, `!`, or `?`
    followed by whitespace or EOL). If the result exceeds `max_chars`, hard-cut
    at the last word boundary <= max_chars and append `…`. Never raises;
    returns `""` for empty input.

    Used by the CLAUDE.md `## Project Context` block renderer to derive a
    one-line gloss from a term's full definition paragraph.
    """
    if not text:
        return ""
    text = text.strip()
    m = re.search(r"[.!?](?:\s|$)", text)
    sentence = text[:m.end()].rstrip() if m else text
    if len(sentence) <= max_chars:
        return sentence
    cut = sentence[:max_chars].rsplit(" ", 1)[0]
    return cut.rstrip(",;") + "…"


def parse_glossary_entries(body: str) -> "tuple[list[dict], str]":
    """Parse nested-bullet term entries from a `## Glossary` topic body.

    Each entry shape:
        - **<term>** — <definition>
          - **Aliases:** X, Y
          - **Not:** Z              (optional)
          <!-- YYYY-MM-DD -->       (optional but conventional)

    Returns (entries, leading) where leading is the prose between the
    heading and the first entry (or the "(no terms yet)" placeholder).
    Entries preserve document order. Shared by hv-glossary-write (single)
    and hv-glossary-import (batch) so the on-disk format stays
    byte-identical across both paths.
    """
    lines = body.splitlines(keepends=True)
    i = 0
    leading: list[str] = []
    while i < len(lines):
        if re.match(r"^- \*\*", lines[i]):
            break
        leading.append(lines[i])
        i += 1
    entries: list[dict] = []
    while i < len(lines):
        m = re.match(r"^- \*\*([^*]+)\*\*\s*(?:—\s*(.*))?\s*$", lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1).strip()
        first_line_rest = (m.group(2) or "").rstrip()
        def_parts: list[str] = []
        if first_line_rest:
            def_parts.append(first_line_rest)
        aliases: list[str] = []
        nots: list[str] = []
        date: "str | None" = None
        i += 1
        while i < len(lines):
            sub = lines[i]
            if re.match(r"^- \*\*", sub):
                break
            stripped = sub.strip()
            if not stripped:
                i += 1
                continue
            m_al = re.match(r"^- \*\*Aliases:\*\*\s*(.*)$", stripped)
            if m_al:
                value = m_al.group(1).strip()
                if value and value != "_none_":
                    aliases = [a.strip() for a in value.split(",") if a.strip()]
                i += 1
                continue
            m_no = re.match(r"^- \*\*Not:\*\*\s*(.*)$", stripped)
            if m_no:
                value = m_no.group(1).strip()
                if value:
                    nots = [n.strip() for n in value.split(",") if n.strip()]
                i += 1
                continue
            m_dt = re.match(r"^<!--\s*(\d{4}-\d{2}-\d{2})\s*-->\s*$", stripped)
            if m_dt:
                date = m_dt.group(1)
                i += 1
                continue
            def_parts.append(stripped)
            i += 1
        entries.append({
            "name": name,
            "definition": " ".join(def_parts).strip(),
            "aliases": aliases,
            "nots": nots,
            "date": date,
        })
    return entries, "".join(leading)


def build_glossary_entry(e: dict, today: str) -> str:
    """Render one entry dict to its nested-bullet markdown form.

    Mirror of parse_glossary_entries — fields in, markdown out. Uses
    `e['date']` when set, else `today`. Both writers feed the same `today`
    string so renders are deterministic across the batch + single paths.
    """
    lines = [f"- **{e['name']}** — {e['definition']}"]
    aliases_value = ", ".join(e["aliases"]) if e["aliases"] else "_none_"
    lines.append(f"  - **Aliases:** {aliases_value}")
    if e["nots"]:
        lines.append(f"  - **Not:** {', '.join(e['nots'])}")
    lines.append(f"  <!-- {e['date'] or today} -->")
    return "\n".join(lines)


def split_csv_list(s: str) -> "list[str]":
    """Split a comma-separated string into stripped non-empty tokens.
    Shared CSV-cell parser for Glossary alias/not fields."""
    return [x.strip() for x in s.split(",") if x.strip()]


def check_alias_collisions(
    existing_entries: "list[dict]",
    candidates: "list[dict]",
) -> "list[str]":
    """Return a list of human-readable conflict strings (empty if none).

    Each candidate is a dict with keys: `name` (str), `aliases` (list[str]),
    and optionally `lineno` (int — included in messages when present).

    Rules:
      - alias in `candidate.aliases` collides if it matches another term's
        existing alias (case-insensitive) AND the other term is not the
        candidate's own term.
      - within `candidates`, two distinct terms cannot claim the same alias
        (case-insensitive intra-batch check).
      - aliases owned by the same term across candidates and existing
        entries are NOT a conflict (re-asserting your own alias is fine).
    """
    conflicts: list[str] = []
    existing_alias_owner: dict[str, str] = {}
    for e in existing_entries:
        for a in e["aliases"]:
            existing_alias_owner[a.lower()] = e["name"].lower()

    batch_alias_owner: "dict[str, tuple[str, int | None, str]]" = {}
    for cand in candidates:
        cand_key = cand["name"].lower()
        lineno = cand.get("lineno")
        prefix = f"line {lineno}: " if lineno is not None else ""
        for a in cand["aliases"]:
            al = a.lower()
            owner = existing_alias_owner.get(al)
            if owner and owner != cand_key:
                owner_name = next(
                    (e["name"] for e in existing_entries if e["name"].lower() == owner),
                    owner,
                )
                conflicts.append(
                    f"{prefix}alias '{a}' on '{cand['name']}' collides with existing term '{owner_name}'"
                )
                continue
            prior = batch_alias_owner.get(al)
            if prior and prior[0] != cand_key:
                prior_term, prior_lineno, _ = prior
                prior_term_name = next(
                    (c["name"] for c in candidates if c["name"].lower() == prior_term),
                    prior_term,
                )
                if prior_lineno is not None:
                    conflicts.append(
                        f"{prefix}alias '{a}' on '{cand['name']}' collides with '{prior_term_name}' on line {prior_lineno} (intra-batch)"
                    )
                else:
                    conflicts.append(
                        f"{prefix}alias '{a}' on '{cand['name']}' collides with '{prior_term_name}' (intra-batch)"
                    )
                continue
            batch_alias_owner[al] = (cand_key, lineno, cand["name"])
    return conflicts


def merge_into_by_key(
    by_key: "dict[str, dict]",
    candidates: "list[dict]",
    today: str,
    *,
    touch: bool,
    nots_provided: bool = True,
) -> "dict[str, dict]":
    """Return a new by_key dict with each candidate merged in.

    Each candidate dict has: `name` (str), `definition` (str),
    `aliases` (list[str]), `nots` (list[str]).

    For an existing term:
      - aliases = union(prev.aliases, cand.aliases), de-duped case-insensitively
        in first-seen order.
      - nots = union if `nots_provided`, else prev.nots verbatim.
      - definition = cand.definition (replaced).
      - date = today if `touch` else (prev.date or today).
      - name keeps prev.name (preserves original casing).

    For a new term: copies the candidate verbatim; date = today.
    """
    new_by_key = dict(by_key)
    for cand in candidates:
        key = cand["name"].lower()
        if key in new_by_key:
            prev = new_by_key[key]
            merged_aliases: list[str] = []
            seen: set[str] = set()
            for a in prev["aliases"] + cand["aliases"]:
                al = a.lower()
                if al not in seen:
                    seen.add(al)
                    merged_aliases.append(a)
            if nots_provided:
                merged_nots: list[str] = []
                seen_n: set[str] = set()
                for n in prev["nots"] + cand["nots"]:
                    nl = n.lower()
                    if nl not in seen_n:
                        seen_n.add(nl)
                        merged_nots.append(n)
            else:
                merged_nots = list(prev["nots"])
            new_by_key[key] = {
                "name": prev["name"],
                "definition": cand["definition"],
                "aliases": merged_aliases,
                "nots": merged_nots,
                "date": today if touch else (prev["date"] or today),
            }
        else:
            new_by_key[key] = {
                "name": cand["name"],
                "definition": cand["definition"],
                "aliases": list(cand["aliases"]),
                "nots": list(cand["nots"]),
                "date": today,
            }
    return new_by_key


def render_glossary_body(
    by_key: "dict[str, dict]",
    leading: str,
    today: str,
) -> str:
    """Return the body to splice back via `replace_section(text, "Glossary", body)`.

    Handles the `_(no terms yet ...)_` empty placeholder removal and the
    leading-block-vs-rendered-entries formatting that both helpers do today.
    """
    import re

    ordered_keys = sorted(by_key.keys())
    rendered = "\n\n".join(build_glossary_entry(by_key[k], today) for k in ordered_keys)

    leading_clean = re.sub(
        r"^_\(no terms yet[^)]*\)_\s*$\n?",
        "",
        leading,
        flags=re.MULTILINE,
    ).rstrip("\n")
    if leading_clean.strip():
        return "\n" + leading_clean.strip() + "\n\n" + rendered + "\n"
    return "\n" + rendered + "\n"
