# Install alternatives

The primary install path is documented in the [project README](../README.md#install):

```bash
npx skills add l4ci/hv-skills
```

If that doesn't fit your setup, pick one of the alternatives below.

## Claude Code plugin marketplace

```bash
claude plugin marketplace add l4ci/hv-skills
claude plugin install hv-skills
```

Uses the built-in `claude` CLI plugin commands. Suitable when you already manage other Claude Code plugins this way.

## npx one-liner (Claude Code CLI)

```bash
npx @anthropic-ai/claude-code plugin marketplace add l4ci/hv-skills
npx @anthropic-ai/claude-code plugin install hv-skills
```

Same outcome as the `claude plugin` variant, but runs through `npx` without requiring a global `claude` install.

## Local development (GNU Stow)

```bash
git clone https://github.com/l4ci/hv-skills.git ~/Code/hv-skills
stow --dir="$HOME/Code" --target="$HOME/.agents/skills" hv-skills
# remove: stow --dir="$HOME/Code" --target="$HOME/.agents/skills" -D hv-skills
```

Use this when you want to edit skills locally and have changes reflected immediately without reinstalling.

## After install

Whichever path you pick, the next step is `/hv-init` at the project root. See [Getting started](getting-started.md) for the rest of the first cycle.
