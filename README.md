# hv-skills

A lightweight project backlog and workflow system for Claude Code. Capture bugs, features, and tasks into a per-project `.hv/TODO.md`, then pick items off the backlog and execute them with parallel subagents.

## Skills

| Skill | Description |
|-------|-------------|
| `/hv:init` | Initialize `.hv/` folder with `TODO.md` and `counters.json` |
| `/hv:bug` | Capture a bug with priority (P0/P1/P2) and auto-incrementing ID `[B-N]` |
| `/hv:feature` | Capture a feature idea with size (Major/Minor/Cosmetic) and ID `[F-N]` |
| `/hv:todo` | Capture a general task or chore with ID `[T-N]` |
| `/hv:next` | Review backlog, suggest what to work on next, route to `/hv:work` |
| `/hv:work` | Opus-orchestrated parallel implementation with per-task commits |
| `/hv:refactor` | Full architectural refactor cycle with parallel subagents |

## Install

### Claude Code skill installer

```
/install-skill l4ci/hv-skills hv:bug
/install-skill l4ci/hv-skills hv:feature
/install-skill l4ci/hv-skills hv:todo
/install-skill l4ci/hv-skills hv:init
/install-skill l4ci/hv-skills hv:next
/install-skill l4ci/hv-skills hv:work
/install-skill l4ci/hv-skills hv:refactor
```

### Local development (GNU Stow)

Clone the repo and use `stow` to symlink all skills into `~/.agents/skills/`:

```bash
git clone https://github.com/l4ci/hv-skills.git ~/Code/hv-skills
stow --dir="$HOME/Code" --target="$HOME/.agents/skills" hv-skills
```

To remove the symlinks:

```bash
stow --dir="$HOME/Code" --target="$HOME/.agents/skills" -D hv-skills
```
