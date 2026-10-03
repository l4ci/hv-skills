# Using the skills in Codex

The skills follow the [Agent Skills spec](https://agentskills.io/specification), so Codex reads them as well as Claude Code. Codex finds skills in `.agents/skills/<name>/SKILL.md`, from the working directory up to the repo root.

```sh
hv init --codex                          # hv beside the plugin's skills
hv init --codex --skills-dir ~/src/hv-skills   # a go-installed hv, or any checkout
```

`--codex` links each `hv-*` skill into `.agents/skills/` as a symlink and adds `.agents/skills/hv-*` to `.gitignore`. Links, not copies: skills read `../references/*.md`, which only resolves through the checkout. The link targets are absolute paths on your machine, so they are not committed. An existing path is never overwritten; it is reported as `skipped`. Without `--codex`, `hv init` creates no `.agents/`.

In Codex, type `$hv-pause` where Claude Code uses `/hv-pause`. It is the same skill; Codex lists it as `hv-skills:hv-pause`.

Not covered: skill bodies still name Claude Code tools (`AskUserQuestion`, `TaskCreate`, `Agent`), so a skill may not run end to end in Codex. `hv` also has to be on `PATH` (release binary or `go install`; the Claude Code plugin supplies it only inside Claude Code).

## Checking discovery

In a scratch repo with the links in place, `codex debug prompt-input hi` prints the model-visible input, skills included, without starting a model session. Each `hv-*` skill should appear as `hv-skills:hv-x: <description>`. It reads your own `~/.codex` and writes nothing to the project. `hv doctor` checks that your Codex version is in the supported range.
