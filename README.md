# hv-skills is no longer developed

hv-skills grew from a set of Claude Code skills into a CLI that runs autonomous rounds of AI coding agents. It continues as **[rota](https://github.com/l4ci/rota)**.

- What was going to be hv-skills 5.0 shipped as rota 0.9.0.
- The skills now come with the `rota` binary (`rota skills install`) instead of the Claude Code plugin or `npx skills`.
- `.hv/` became `.rota/`. In a project that used hv-skills, install rota and run `rota migrate hv` (a dry run first; `--apply` writes).

Install rota:

```sh
curl -fsSL https://raw.githubusercontent.com/l4ci/rota/main/install.sh | sh
# or
brew install l4ci/tap/rota
```

Issues and pull requests go to [l4ci/rota](https://github.com/l4ci/rota). This repo stays up for the 4.x history and tags.
