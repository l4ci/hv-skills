"""Config defaults: the one table of every known `.hv/config.json` key.

Consumed by `hv-config-show` (value + source layer) and `hv-config-schema-check`
(its EXPECTED list is the rows flagged `required`). Defaults mirror
docs/reference/config-options.md and docs/usage/configuration.md; the skills'
prose still carries the wording, this table carries the values.

Each row is `(dotted_key, default, required)`. `required` rows are the keys
`/hv-init` writes and the schema check treats as present-or-STALE; the rest
(release.*, issues.label...) are known and shown but never make a config STALE.
Leaf keys only: dict-valued parents are not rows.
"""

CONFIG_KEYS = [
    ("models.orchestrator", "opus", True),
    ("models.worker", "sonnet", True),
    ("work.isolation", "branch", True),
    ("work.mergeStrategy", "direct", True),
    ("work.dispatch", "subagent", True),  # subagent | tmux | herdr
    ("work.workerSlots", 3, True),
    ("work.workerCommand", "", True),
    ("work.accounts", [], True),
    ("work.operatorCommand", "", True),
    ("refactor.confirmBeforeExecute", True, True),
    ("refactor.verifyCommands", [], True),
    ("learn.verify", True, True),
    ("learn.promoteThreshold", 3, True),
    ("ship.review", True, True),
    ("ship.secondOpinion", False, True),
    ("ship.secondOpinionRunner", "subagent", True),  # subagent | codex
    ("ship.qa", False, True),
    ("qa.gate", "advisory", True),
    ("qa.afterWork", False, True),
    ("autonomy.level", "off", True),
    ("debug.competingHypotheses", False, True),
    ("docs.path", "docs", True),
    ("docs.autoCreate", False, True),
    ("docs.afterWork", False, True),
    ("git.baseBranch", "", True),
    ("umbrella.enabled", False, True),
    ("issues.providers.github", True, True),
    ("issues.providers.gitlab", True, True),
    ("hvSkills.version", "", True),
    ("loop.webResearch", False, False),
    ("issues.label", "in-progress", False),  # legacy alias of issues.labels.inProgress
    ("backlog.backend", "file", False),  # file | issues
    ("issues.provider", "auto", False),  # auto | github | gitlab
    ("issues.retryWaitSeconds", 60, False),
    ("issues.bulkPaceMs", 1000, False),  # hv-migrate-issues: pause between tracker writes
    ("issues.labels.inProgress", "in-progress", False),
    ("issues.labels.needsReview", "needs-review", False),
    ("issues.labels.changesRequested", "changes-requested", False),
    ("issues.labels.released", "released", False),
    ("issues.labels.notPlanned", "not-planned", False),
    ("issues.labels.blocked", "blocked", False),
    ("issues.labels.milestoneTracker", "milestone-tracker", False),
    ("issues.labels.types.bug", "type:bug", False),
    ("issues.labels.types.feature", "type:feature", False),
    ("issues.labels.types.task", "type:task", False),
    ("issues.labels.priorityPrefix", "p", False),
    ("issues.labels.sizePrefix", "size:", False),
    ("issues.autoCreateLabel", True, False),
    ("issues.filterMineOnly", False, False),
    ("issues.homeRepo", "", False),  # umbrella: sub-repo holding milestone tracking issues ("" = first registered)
    ("release.checklistPath", ".hv/RELEASE.md", False),
    ("release.confirmLargePushCommits", 10, False),
    ("release.nudgeAfterCommits", 10, False),
    ("release.nudgeAfterDays", 14, False),
]

BACKLOG_BACKENDS = ("file", "issues")


def _walk(cfg, key):
    """Dotted-key lookup; missing or None counts as absent (returns None)."""
    cur = cfg
    for seg in key.split("."):
        if not isinstance(cur, dict) or cur.get(seg) is None:
            return None
        cur = cur[seg]
    return cur


def config_value(cfg: dict, key: str):
    """Value of a dotted key in cfg, else its CONFIG_KEYS default. KeyError if unknown."""
    for k, default, _ in CONFIG_KEYS:
        if k == key:
            value = _walk(cfg, key)
            return default if value is None else value
    raise KeyError(key)


def backlog_backend(cfg: dict) -> str:
    """The configured backlog backend ("file" or "issues"); ValueError otherwise."""
    v = config_value(cfg, "backlog.backend")
    if v not in BACKLOG_BACKENDS:
        raise ValueError(f"invalid backlog.backend '{v}' (expected file|issues)")
    return v


def tracker_label(cfg: dict, role: str) -> str:
    """Label name for a role under issues.labels (e.g. "inProgress", "types.bug").

    "inProgress" falls back to the legacy `issues.label` when the new key is unset.
    """
    if role == "inProgress" and _walk(cfg, "issues.labels.inProgress") is None:
        legacy = _walk(cfg, "issues.label")
        if legacy is not None:
            return legacy
    return config_value(cfg, f"issues.labels.{role}")
