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
    ("issues.label", "in-progress", False),
    ("issues.autoCreateLabel", True, False),
    ("issues.filterMineOnly", False, False),
    ("release.checklistPath", ".hv/RELEASE.md", False),
    ("release.confirmLargePushCommits", 10, False),
    ("release.nudgeAfterCommits", 10, False),
    ("release.nudgeAfterDays", 14, False),
]
