"""Item-type registry for hv-* helpers. Pure stdlib leaf module — imports no
other hvlib_* module (hvlib_section / hvlib_bullet / hvlib_paths import it,
so any hvlib import here would cycle). Re-exported by hvlib for backward
compat.

At import time this parses the HV_TYPE_REGISTRY row-table out of the sibling
bin/hv-types.sh, so bash (which sources that file) and python (which imports
this module) derive from the same single line. Most helpers run python
heredocs WITHOUT sourcing hv-types.sh, so this module must never read HV_*
env vars or fall back to hardcoded defaults — a missing file or registry
line raises RuntimeError instead.

Row format: <prefix>:<open-section>:<detail-dir>:<flags>
flags: C=countable (counters.json), P=plannable (plan keys).
A row with empty section/dir (S=Slice) is a plan-key-only type.
"""
import re
from pathlib import Path

_TYPES_SH = Path(__file__).with_name("hv-types.sh")


def _load_rows() -> list[tuple[str, str, str, str]]:
    try:
        text = _TYPES_SH.read_text()
    except OSError as e:
        raise RuntimeError(
            f"hvlib_types: cannot read the item-type registry {_TYPES_SH} "
            f"(hv-types.sh must live next to hvlib_types.py): {e}"
        ) from e
    m = re.search(r'^HV_TYPE_REGISTRY="([^"]*)"', text, re.MULTILINE)
    if not m:
        raise RuntimeError(
            f'hvlib_types: no HV_TYPE_REGISTRY="..." line in {_TYPES_SH}'
        )
    rows = []
    for raw in m.group(1).split():
        parts = raw.split(":")
        if len(parts) != 4:
            raise RuntimeError(
                f"hvlib_types: malformed registry row {raw!r} in {_TYPES_SH} "
                f"(want <prefix>:<open-section>:<detail-dir>:<flags>)"
            )
        rows.append(tuple(parts))
    if not rows:
        raise RuntimeError(
            f"hvlib_types: empty HV_TYPE_REGISTRY in {_TYPES_SH}"
        )
    return rows


def _validate(rows: list[tuple[str, str, str, str]]) -> None:
    prefixes = [r[0] for r in rows]
    if len(set(prefixes)) != len(prefixes):
        raise RuntimeError(
            f"hvlib_types: duplicate prefixes in {_TYPES_SH}: {prefixes}"
        )
    for prefix, section, dir_, flags in rows:
        if bool(section) != bool(dir_):
            raise RuntimeError(
                f"hvlib_types: row {prefix!r} in {_TYPES_SH} must have both "
                f"a section and a detail-dir, or neither "
                f"(got section={section!r}, dir={dir_!r})"
            )
        if "C" in flags and not section:
            raise RuntimeError(
                f"hvlib_types: countable row {prefix!r} in {_TYPES_SH} "
                f"must have a section"
            )


_ROWS = _load_rows()
_validate(_ROWS)

# "BFT" — prefixes of types that appear as bullets in open BACKLOG sections.
ITEM_TYPES = "".join(p for p, section, _, _ in _ROWS if section)
# ["Bugs", "Features", "Tasks"] — `## <name>` headings holding open items.
OPEN_SECTIONS = [section for _, section, _, _ in _ROWS if section]
# Open sections plus Completed — full BACKLOG.md scan order.
ALL_BACKLOG_SECTIONS = OPEN_SECTIONS + ["Completed"]
# "BF" — types whose resolutions bump counters.json since_refactor.
COUNTABLE_TYPES = "".join(p for p, _, _, flags in _ROWS if "C" in flags)
# "BFTS" — types that can carry a milestone plan key (S=Slice).
PLANNABLE_TYPES = "".join(p for p, _, _, flags in _ROWS if "P" in flags)
# Prefix → section / detail-dir lookups, and detail-dir → section.
SECTION_FOR_PREFIX = {p: section for p, section, _, _ in _ROWS if section}
DIR_FOR_PREFIX = {p: dir_ for p, _, dir_, _ in _ROWS if dir_}
SECTION_FOR_DIR = {dir_: section for _, section, dir_, _ in _ROWS if dir_}
