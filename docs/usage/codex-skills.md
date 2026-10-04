# Using the skills in Codex

The skills follow the [Agent Skills spec](https://agentskills.io/specification), so Codex reads them as well as Claude Code. Codex finds skills in `.agents/skills/<name>/SKILL.md`: `~/.agents/skills` for your user, and from the working directory up to the repo root for a project.

```sh
hv skills install                                # user: ~/.agents/skills (and ~/.claude/skills)
hv skills install --scope project --agent codex  # this repo: .agents/skills
```

`hv` carries the skills inside the binary. `install` copies each `hv-*` skill, plus the references it cites, into the root and writes a `.hv-manifest.json` that lists what it wrote. These are copies, not symlinks, so they work without a checkout and can be committed. A file you edited, or one hv did not write, is kept and reported; `--overwrite` replaces it.

After upgrading `hv`, run `hv skills update` to refresh every root that has a manifest. `hv skills status` shows whether each root matches the binary.

This page is about calling the skills from Codex. To run Codex as a worker in a [parallel round](parallel-rounds.md), see [Codex workers](codex-workers.md).

In Codex, type `$hv-pause` where Claude Code uses `/hv-pause`. It is the same skill.

Not covered: skill bodies still name Claude Code tools (`AskUserQuestion`, `TaskCreate`, `Agent`), so a skill may not run end to end in Codex. `hv` also has to be on `PATH` (install hv: see [install](../install.md)).

## Checking discovery

With `CODEX_HOME` unset, run `codex debug prompt-input hi` in a scratch repo. It prints the model-visible input, skills included, without starting a model session. Each `hv-*` skill should appear as `hv-x: <description>`. It reads your own `~/.codex` and writes nothing to the project. `hv doctor` checks that your Codex version is in the supported range, and that installed skills match the binary.
