"""
validate-skills.py — static schema validator for hv-skills SKILL.md files,
plus the Agent Skills spec frontmatter lint (E2, #69), the legacy-name doclint
over skills and references (A9, #53) and the prose-contract lint (PROSE_RULES, #173).
Stdlib only. `--list-legacy` prints the frozen legacy helper names and exits. Exit 0 on all-pass, exit 1 on any failure, exit 2 on unexpected error.
"""

import json
import os
import re
import sys
from pathlib import Path


def parse_frontmatter(text):
    """Return (dict_of_keys, post_frontmatter_text) or (None, text) if no frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    end = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end = i
            break
    if end is None:
        return None, text
    fm_lines = lines[1:end]
    post = "\n".join(lines[end + 1:])
    keys = {}
    for line in fm_lines:
        m = re.match(r'^(\w[\w-]*):\s*(.*)', line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            # strip surrounding quotes if present
            if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                v = v[1:-1]
            keys[k] = v
    return keys, post


def check_frontmatter(path, text, issues):
    fm, _ = parse_frontmatter(text)
    if fm is None:
        issues.append(f"{path}: no frontmatter block found")
        return
    for key in ("name", "description"):
        if key not in fm or not fm[key]:
            issues.append(f"{path}: frontmatter missing required key '{key}'")


# Agent Skills spec frontmatter (E2, #69; https://agentskills.io/specification).
# Codex and Claude Code read the same SKILL.md, and a strict spec validator
# rejects any key outside SPEC_KEYS. The two sets below excuse a violation a
# slice has not fixed yet (empty since E2 fixed them all). An entry with nothing
# left to excuse fails the check, so the sets can only shrink.
SPEC_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
PENDING_KEYS = set()
PENDING_LONG = set()


def pending_spec():
    # HV_SPEC_PENDING (whitespace-separated; a token ending .md is a path for
    # PENDING_LONG, anything else a key for PENDING_KEYS) replaces both sets, so
    # smoke sections can test the check on a fixture tree.
    override = os.environ.get("HV_SPEC_PENDING")
    if override is None:
        return PENDING_KEYS, PENDING_LONG
    toks = override.split()
    return {t for t in toks if not t.endswith(".md")}, {t for t in toks if t.endswith(".md")}


BLOCK_SCALARS = {">", "|", ">-", "|-", ">+", "|+"}


def spec_fields(text):
    """Top-level frontmatter as {key: value}, folding indented continuation
    lines into the value; None without a frontmatter block."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    out, key = {}, None
    for line in lines[1:]:
        if line.strip() == "---":
            return out
        m = re.match(r"^([A-Za-z0-9_-]+):[ \t]*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if len(val) > 1 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            out[key] = "" if val in BLOCK_SCALARS else val
        elif key and line[:1] in (" ", "\t"):
            out[key] = (out[key] + " " + line.strip()).strip()
    return None


def plain_scalar_hazards(text):
    """Top-level keys whose unquoted single-line value is not valid YAML: a
    ': ' or ' #' inside it, or a leading indicator. Claude Code reads such a
    value anyway; Codex's strict parser drops the whole skill without a word."""
    lines = text.splitlines()
    bad = []
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"^([A-Za-z0-9_-]+):[ \t]+(\S.*)$", line)
        if not m:
            continue
        val = m.group(2).rstrip()
        if val[0] in "\"'" or val in BLOCK_SCALARS:
            continue
        if ": " in val or " #" in val or val.endswith(":") or val[0] in "&*!|>%@`[]{},#?-":
            bad.append(m.group(1))
    return bad


def check_spec_frontmatter(path, text, issues):
    pending_keys, pending_long = pending_spec()
    path = Path(path)
    fm = spec_fields(text)
    if fm is None:
        return
    rel = path.as_posix()
    name, desc = fm.get("name", ""), fm.get("description", "")
    if name and name != path.parent.name:
        issues.append(f"{rel}: frontmatter name '{name}' must equal the directory '{path.parent.name}'")
    if name and (len(name) > 64 or not NAME_RE.match(name)):
        issues.append(f"{rel}: name '{name}' must be 1-64 chars of lowercase letters, digits and single hyphens, not starting or ending with one")
    if len(desc) > 1024:
        if rel not in pending_long:
            issues.append(f"{rel}: description is {len(desc)} chars; the spec allows 1024")
    elif rel in pending_long:
        issues.append(f"{rel}: description is within 1024 chars; remove it from PENDING_LONG")
    for key in plain_scalar_hazards(text):
        issues.append(f"{rel}: frontmatter '{key}' is not valid YAML unquoted (': ', ' #' or a leading indicator); "
                      f"use a folded block (>-) or quote it")
    if len(fm.get("compatibility", "")) > 500:
        issues.append(f"{rel}: compatibility is over 500 chars")
    extra = sorted(set(fm) - SPEC_KEYS)
    bad = [k for k in extra if k not in pending_keys]
    if bad:
        issues.append(f"{rel}: frontmatter key(s) {', '.join(bad)} are not in the Agent Skills spec "
                      f"(allowed: {', '.join(sorted(SPEC_KEYS))})")


def check_pending_spec(skill_files, issues):
    """A pending entry nothing uses any more must be deleted."""
    pending_keys, pending_long = pending_spec()
    used = set()
    for p in skill_files:
        used |= set(spec_fields(Path(p).read_text(encoding="utf-8")) or {}) & pending_keys
    for k in sorted(pending_keys - used):
        issues.append(f"PENDING_KEYS: no SKILL.md uses '{k}' any more; remove it")
    present = {Path(p).as_posix() for p in skill_files}
    for rel in sorted(pending_long - present):
        issues.append(f"{rel}: listed in PENDING_LONG but missing; remove the entry")


def check_banner(path, text, issues):
    # Only validate banner for skills that declare one (delegation/alias stubs omit it by design)
    if "Print the banner" not in text:
        return

    _, post = parse_frontmatter(text)
    post_lines = post.splitlines()
    # Search within first 30 lines of post-frontmatter content
    window = post_lines[:30]
    # Find opening fence
    in_block = False
    block_lines = []
    found_block = False
    for line in window:
        if not in_block:
            if line.strip().startswith("```"):
                in_block = True
                block_lines = []
                found_block = True
        else:
            if line.strip().startswith("```"):
                in_block = False
                break
            block_lines.append(line)

    if not found_block or not block_lines:
        issues.append(f"{path}: banner block missing or malformed")
        return

    has_box = any("═" in l for l in block_lines)
    has_triggers_pairs = any("triggers:" in l and "pairs:" in l for l in block_lines)
    if not has_box or not has_triggers_pairs:
        issues.append(f"{path}: banner block missing or malformed")


def check_references(path, text, issues):
    # Skills cite references/<x>.md; `hv skills install` copies each cited file
    # next to the skill, so in the source tree the link resolves against the
    # repo-root references/ dir.
    pattern = re.compile(r'\((references/[^)\s]+\.md)\)')
    for m in pattern.finditer(text):
        target = m.group(1)
        resolved = Path(target).resolve()
        if not resolved.exists():
            issues.append(f"{path}: broken reference '{target}' -> '{resolved}'")


# Legacy-name doclint (A9, #53). After the cutover no skill or shared reference
# may name an old bin/ helper, the .hv/bin mirror or hvlib: skills call `hv
# <verb>`. The name list is frozen from bin/ at the start of A9, so the check
# keeps working once S7 deletes bin/. hv-migrate is left out because it is also
# the name of the `hv migrate` verb. A name preceded by "/" is a slash command, not a helper call;
# bin/ paths are caught by the bin/hv- and .hv/bin patterns instead.
LEGACY_HELPERS = """
    hv-append hv-archive-old hv-artifact-amend.sh hv-artifact-rm.sh
    hv-artifact-show.sh hv-auto-decision-log hv-auto-decisions-since
    hv-backfill-since hv-backlog hv-base-branch hv-bootstrap hv-capture-audit
    hv-codex-verify hv-complete hv-config-schema-check hv-config-set hv-config-show
    hv-debug-counter hv-decisions-query hv-design-add hv-design-amend hv-design-list
    hv-design-put hv-design-rm hv-design-show hv-find-milestone-for-items hv-fm-list
    hv-glossary-import hv-glossary-read hv-glossary-write hv-guard-clean
    hv-guard-feature-branch hv-host-herdr.sh hv-host-select.sh hv-host-tmux.sh
    hv-instructions-init hv-issue-suggest hv-issues-close hv-issues-common.sh
    hv-issues-imported hv-issues-label hv-issues-list hv-issues-provider
    hv-item-claim hv-item-comment hv-item-create hv-item-note hv-item-ready
    hv-item-release hv-item-show hv-item-state hv-knowledge-amend
    hv-knowledge-contradiction hv-knowledge-hit hv-knowledge-merge
    hv-knowledge-migrate hv-knowledge-query hv-knowledge-rename-topic
    hv-knowledge-scope.sh hv-knowledge-stats hv-knowledge-tier hv-loop-stamp
    hv-managed-block hv-managed-block-strip-deprecated hv-map-cap-check hv-map-index
    hv-map-query hv-map-stats hv-merge hv-migrate-issues hv-multi-branch-create
    hv-next-id hv-plan-add hv-plan-list hv-plan-put hv-plan-rename-check hv-plan-rm
    hv-plan-show hv-plan-validate-docs hv-pr hv-pr-merge hv-preamble.sh hv-preflight
    hv-proof-add hv-proof-show hv-qa-index hv-qa-query hv-reconcile hv-refactor-age
    hv-refactor-reset hv-refactor-targets hv-release-bump-version
    hv-release-changelog-from-commits hv-release-close-milestone
    hv-release-detect-host hv-release-detect-version hv-release-milestone-check
    hv-release-notes-from-issues hv-release-pending hv-release-update-changelog
    hv-repo-flag.sh hv-require-git-context hv-resolve-handoff hv-resolve-plugin-root
    hv-resolve-repo hv-resolve-repo-path hv-resolve-repos hv-resolve-umbrella
    hv-review-queue hv-review-scaffolding hv-review-scope hv-rm
    hv-second-opinion-brief hv-section-query hv-self-locate.sh hv-ship-body
    hv-skills-index hv-spike-add hv-spike-finish hv-spike-list hv-spike-show
    hv-stale-summary hv-staleness hv-status-add hv-status-add-multi hv-status-remove
    hv-status-repo-for hv-summary hv-todo-by-milestone hv-todo-drift hv-todo-field
    hv-todo-set-field hv-tracker-call hv-types.sh hv-umbrella-init hv-umbrella-on
    hv-uncertain hv-uncomplete hv-undo hv-update-check hv-version-check
    hv-vision-active hv-vision-add hv-vision-empty-active hv-vision-index
    hv-vision-list hv-vision-put hv-vision-show hv-vision-status hv-walk-up
    hv-worker-account hv-worker-dispatch hv-worker-gate hv-worker-poll
    hv-worker-pool hv-worker-reset hv-worker-session hv-worktree-clear
    hv-worktree-path
""".split()

LEGACY_RE = re.compile(
    r"(?<![\w/.-])(?:"
    + "|".join(re.escape(n) for n in sorted(LEGACY_HELPERS, key=len, reverse=True))
    + r")(?![\w-])"
    + r"|\.hv/bin|hvlib|(?<![\w.-])bin/hv-"
)

# Files not yet converted to hv verbs. Each A9 slice deletes its own lines in
# the PR that converts the files; the groups are kept apart so two slices'
# deletions never touch adjacent lines. An entry whose file is already clean
# (or gone) fails the check, so the list can only shrink. It is empty after S5.
UNCONVERTED = set()


def doclint_files():
    # One level each: a recursive walk would reach .worktrees/ checkouts (section 70).
    files = list(Path(".").glob("hv-*/*.md")) + list(Path("references").glob("*.md"))
    return sorted(p.as_posix() for p in files)


def unconverted():
    # HV_DOCLINT_UNCONVERTED (whitespace-separated paths) replaces the list, so
    # smoke section 29 can test the check on a fixture tree.
    override = os.environ.get("HV_DOCLINT_UNCONVERTED")
    return set(override.split()) if override is not None else UNCONVERTED


def check_legacy_names(issues):
    allow = unconverted()
    for path in doclint_files():
        text = Path(path).read_text(encoding="utf-8")
        hits = [(n, m.group(0)) for n, line in enumerate(text.splitlines(), 1)
                for m in LEGACY_RE.finditer(line)]
        if path in allow:
            if not hits:
                issues.append(f"{path}: no legacy names left; remove it from UNCONVERTED")
            continue
        for n, name in hits:
            issues.append(f"{path}:{n}: names legacy '{name}'; call the hv verb instead")
    for path in sorted(allow - set(doclint_files())):
        issues.append(f"{path}: listed in UNCONVERTED but missing; remove the entry")

# Prose-contract lint (#173). Skills and docs document hv verbs and flags that
# other skills and tests rely on; these rules pin that wiring (a skill names the
# verb it calls, a documented flag keeps its section, a retired phrase stays
# gone). They replaced the grep blocks that lived in test/sections. Each rule is
# a tuple, built by the helpers below:
#   has(path, text, msg)              path must contain text (re=True: a regex)
#   lacks(path, text, msg)            path must not contain text
#   count_ge(path, text, n, msg)      text appears at least n times
#   only_in(glob, text, names, msg)   exactly these skill dirs contain text
#   paired(glob, trigger, need, msg)  every file with trigger also has need
# A rule on a missing file fails. HV_DOCLINT_PROSE=off skips the lint so section
# 29 can run the legacy-name check on a fixture tree.
def has(path, text, msg, re_=False, flags=0):
    return ("has", path, text, msg, re_, flags)


def lacks(path, text, msg, re_=False, flags=0):
    return ("lacks", path, text, msg, re_, flags)


def count_ge(path, text, n, msg):
    return ("count_ge", path, text, n, msg)


def only_in(glob, text, names, msg):
    return ("only_in", glob, text, names, msg)


def paired(glob, trigger, need, msg):
    return ("paired", glob, trigger, need, msg)


def prose_rules():
    r = []
    sk = lambda n: f"hv-{n}/SKILL.md"
    CALLOUT = "**always manual** — never auto-invoked, regardless of `autonomy.level`"
    # /hv-plan and /hv-brainstorm --auto-loop (F32, B28)
    r += [has(sk("plan"), "--auto-loop", "must document the --auto-loop flag"),
          has(sk("plan"), "Auto-loop mode", "must include the dedicated 'Auto-loop mode' section"),
          has(sk("brainstorm"), "--auto-loop", "must document the --auto-loop flag"),
          has(sk("brainstorm"), "## Auto-loop mode", "must include the dedicated 'Auto-loop mode' section"),
          has(sk("brainstorm"), "auto: true", "must document 'auto: true' frontmatter under --auto-loop"),
          has(sk("brainstorm"), "AUTO_LOOP", "must parse the --auto-loop flag in Step 1"),
          has(sk("work"), "Loop-mode auto-dispatch chain", "must title Step 4 'Loop-mode auto-dispatch chain'"),
          has(sk("work"), "/hv-plan --auto-loop", "must reference /hv-plan --auto-loop"),
          has(sk("work"), "/hv-brainstorm --auto-loop", "must reference /hv-brainstorm --auto-loop dispatch"),
          has(sk("work"), "defer to Step 4", "Step 2 must defer Major + Milestone-tagged ambiguity to the Step 4 chain"),
          has("references/loop-mode-plan-dispatch.md", "Design pre-flight", "must include the Design pre-flight section"),
          only_in("hv-*/SKILL.md", "hv decisions auto-since", {"hv-brainstorm", "hv-plan"},
                  "hv decisions auto-since is surfaced in exactly hv-brainstorm and hv-plan"),
          has(sk("work"), "hv status loop start", "must call hv status loop start"),
          has(sk("pause"), "hv status loop clear", "must call hv status loop clear"),
          has(sk("work"), "hv status loop clear", "must call hv status loop clear"),
          has(sk("work"), "hv status handoff", "must call hv status handoff"),
          has(sk("ship"), "hv git guard feature-branch", "must call hv git guard feature-branch"),
          has(sk("pause"), "hv git guard feature-branch", "must call hv git guard feature-branch")]
    # map / backlog touchpoints
    r += [has(sk("work"), r"hv map stats --cap|hv map index", "has no map touchpoint", True),
          has(sk("debug"), r"hv map stats --cap|hv map index", "has no map touchpoint", True),
          has(sk("work"), "hv backlog stale", "missing the stale-summary call"),
          has(sk("capture"), "Subsystem:", "missing the Subsystem field")]
    # F37 TaskCreate progress checklists: tiers S/A/B have it, tier C does not
    for n in "work debug ship release refactor learn decide spike vision capture pause review plan".split():
        r.append(has(sk(n), "TaskCreate(", "Tier S/A/B skill must reference TaskCreate("))
    # config verbs and the positional-args doc (F09, F78)
    for n in ("ship",):
        r.append(has(sk(n), "hv config set", "missing hv config set call"))
    r += [has(sk("ship"), r"\| Manual invoke.*after-work.*manual mode",
              "Docs Mode Modes row for manual invocation must reflect after-work in manual mode", True),
          has(sk("ship"), "Route to the After-work sub-flow", "Docs Mode Step D1 'Already true' branch must route to the after-work sub-flow"),
          has(sk("ship"), "Manual entry bypasses the gate", "Docs Mode Step D-A1 missing the manual-entry bypass clause"),
          lacks(sk("ship"), r"Re-running .*hv-docs.* manually has no further effect",
                "stale 'no further effect' no-op text is still present in Docs Mode", True),
          has("docs/reference/config-options.md", "positional", "missing positional-args mention"),
          has("docs/usage/configuration.md", r"positional|<key>=<value>", "missing positional-args mention", True),
          has("docs/usage/configuration.md", "work.dispatch", "does not explain work.dispatch")]
    for key in ("models.orchestrator models.worker work.isolation work.mergeStrategy ship.review learn.verify "
                "refactor.confirmBeforeExecute debug.competingHypotheses autonomy.level docs.path docs.autoCreate "
                "docs.afterWork git.baseBranch umbrella.enabled work.dispatch work.workerSlots work.workerCommand").split():
        r.append(has("docs/reference/config-options.md", key, f"does not document {key}"))
    for key in ("work.dispatch", "work.workerSlots", "work.workerCommand"):
        r.append(has("docs/reference/config-options.md", key, f"does not document {key}"))
    # multi-repo flow (M03)
    r += [has(sk("capture"), r"multiSelect:.*true", "Step 4.6 must declare multiSelect: true for the Repos question", True),
          has(sk("capture"), "comma-separated list of registered sub-repos", "field-order line must say 'comma-separated list of registered sub-repos'"),
          lacks(sk("capture"), "single name in V1", "must no longer carry the 'single name in V1' qualifier"),
          has(sk("plan"), "multi-repo items pass the full comma-list", "must explain the multi-repo --repo flow"),
          has(sk("work"), "one line per repo for multi-repo items", "Preview Mode peek must show one Repo line per sub-repo"),
          has(sk("work"), "hv git branch", "must reference hv git branch for multi-repo branch creation"),
          has(sk("work"), r"hv status add .*--repos", "must reference hv status add --repos for multi-repo status entries", True),
          has(sk("work"), "hv repo resolve", "must reference hv repo resolve for multi-repo validation"),
          lacks(sk("work"), "M03 (deferred)", "must no longer say 'M03 (deferred)'"),
          lacks(sk("work"), "wait for M03 multi-repo support", "must no longer say 'wait for M03 multi-repo support'")]
    # worker reset guard, proof path, manual gates
    r += [has(sk("work"), "reset guard", "does not describe the slot reset guard"),
          paired("hv-*/SKILL.md", "hv item complete", "hv proof add",
                 "calls hv item complete without an hv proof add path"),
          has(sk("capture"), "Step I6", "missing Step I6 (Import Mode label gate)"),
          has(sk("capture"), "Step R3", "missing Step R3 (Remove Mode de-tag gate)"),
          count_ge(sk("capture"), CALLOUT, 2, "needs the manual-gate callout at Step R3 and Step I6"),
          has(sk("ship"), "Step 6c", "missing Step 6c (direct-push close gate)"),
          has(sk("ship"), CALLOUT, "missing the manual-gate callout (Step 6c)"),
          has("references/manual-gates.md", r"Step I6|hv-capture --from-.*label|label.*hv-capture --from",
              "missing the /hv-capture --from-* Step I6 row", True),
          has("references/manual-gates.md", r"Step R3|hv-capture --remove.*de-tag|de-tag.*hv-capture --remove",
              "missing the /hv-capture --remove Step R3 row", True),
          has("references/manual-gates.md", r"Step 6c|direct-push close", "missing the hv-ship Step 6c row", True)]
    # F73 subagent-dispatch discipline
    D = "references/subagent-dispatch.md"
    for h in ("When to dispatch", "Small-brief template", "Return-shape contract", "Model tier per work type",
              "Parallel fan-out pattern", "What stays on the orchestrator"):
        r.append(has(D, f"^## {h}", f"section '{h}' missing", True, re.M))
    r += [has(D, "DECISIONS.md", "must cite the .hv/DECISIONS.md worktree-isolation rule"),
          lacks(D, r"TBD|TODO|FIXME|XXX", "contains placeholders", True, re.I),
          has("references/authoring-conventions.md", "^## Dispatch heavy work to subagents",
              "missing the 'Dispatch heavy work to subagents' rule", True, re.M),
          has("references/authoring-conventions.md", D, "missing the cross-reference to subagent-dispatch.md")]
    for n, pats in (("vision", ["context-bundle worker", "haiku", "research worker", "per angle"]),
                    ("debug", ["reproduce worker", "verification worker"])):
        for t in pats:
            r.append(has(sk(n), t, f"missing '{t}'"))
    r += [has(sk("debug"), "when the repro is heavy", "Step 5 missing conditional dispatch criteria", True, re.I),
          has(sk("debug"), "when verification.*requires.*file reads", "Step 7 missing conditional dispatch criteria", True, re.I)]
    for n in ("vision", "debug"):
        r.append(has(sk(n), D, "missing the subagent-dispatch reference cite"))
    return r


def check_prose(issues):
    if os.environ.get("HV_DOCLINT_PROSE") == "off":
        return
    cache = {}

    def read(path):
        if path not in cache:
            p = Path(path)
            cache[path] = p.read_text(encoding="utf-8") if p.is_file() else None
        return cache[path]

    def found(text, pat, re_, flags):
        return re.search(pat, text, flags) if re_ else pat in text

    for rule in prose_rules():
        kind = rule[0]
        if kind in ("has", "lacks", "count_ge"):
            path = rule[1]
            text = read(path)
            if text is None:
                issues.append(f"{path}: prose rule target is missing")
                continue
        if kind == "has":
            _, path, pat, msg, re_, flags = rule
            if not found(text, pat, re_, flags):
                issues.append(f"{path}: {msg}")
        elif kind == "lacks":
            _, path, pat, msg, re_, flags = rule
            if found(text, pat, re_, flags):
                issues.append(f"{path}: {msg}")
        elif kind == "count_ge":
            _, path, pat, n, msg = rule
            if text.count(pat) < n:
                issues.append(f"{path}: {msg} (found {text.count(pat)}, need {n})")
        elif kind == "only_in":
            _, glob, pat, names, msg = rule
            got = {p.parent.name for p in sorted(Path(".").glob(glob)) if pat in p.read_text(encoding="utf-8")}
            if got != names:
                issues.append(f"{glob}: {msg}, got {sorted(got)}")
        elif kind == "paired":
            _, glob, trigger, need, msg = rule
            hits = [p for p in sorted(Path(".").glob(glob)) if trigger in p.read_text(encoding="utf-8")]
            if not hits:
                issues.append(f"{glob}: expected at least one file containing '{trigger}'")
            for p in hits:
                if need not in p.read_text(encoding="utf-8"):
                    issues.append(f"{p.as_posix()}: {msg}")


def main():
    if "--list-legacy" in sys.argv[1:]:
        print("\n".join(LEGACY_HELPERS))
        sys.exit(0)
    issues = []

    skill_files = sorted(Path(".").glob("hv-*/SKILL.md"))

    for skill_path in skill_files:
        text = skill_path.read_text(encoding="utf-8")
        check_frontmatter(skill_path, text, issues)
        check_spec_frontmatter(skill_path, text, issues)
        check_banner(skill_path, text, issues)
        check_references(skill_path, text, issues)

    check_pending_spec(skill_files, issues)
    check_legacy_names(issues)
    check_prose(issues)

    n = len(skill_files)
    if issues:
        for line in issues:
            print(line, file=sys.stderr)
        print(f"validate-skills: FAIL ({len(issues)} issues)")
        sys.exit(1)
    else:
        print(f"validate-skills: PASS ({n} SKILL.md files checked)")
        sys.exit(0)


try:
    main()
except Exception as exc:
    print(f"validate-skills: ERROR {exc}", file=sys.stderr)
    sys.exit(2)
