# Install

Available from v5.0.0. `hv` is a single binary that carries the skills; there is no plugin to enable. Install the binary, install the skills, then run `hv init` in your project.

## The binary

### Install script

```bash
curl -fsSL https://raw.githubusercontent.com/l4ci/hv/main/install.sh | sh
```

It installs to `~/.local/bin/hv`. It needs no sudo and does not edit your shell profile; if the directory is not on your `PATH` it prints the line to add. It needs `curl`, or `wget` as a fallback.

| Option | Env var | Meaning |
|---|---|---|
| `--version X.Y.Z` | `HV_VERSION` | install this release instead of the latest |
| `--prefix DIR` | `HV_PREFIX` | install to `DIR/bin` instead of `~/.local/bin` |

### Homebrew

```bash
brew install l4ci/tap/hv
```

### Release binaries by hand

Download `hv_<os>_<arch>` from the [releases](https://github.com/l4ci/hv/releases) page (linux and macOS, amd64 and arm64), make it executable, and put it on your `PATH`. Compare its sha256 with the line for that file in `checksums.txt` from the same release.

### Integrity, not authenticity

`install.sh` verifies the download against `checksums.txt` and refuses a mismatch. The checksums come from the same release as the binary, so this catches a corrupted or swapped download. It does not prove who built the release. Signing is tracked in [#220](https://github.com/l4ci/hv/issues/220) for 5.1.

Check the result with `hv version`. `hv doctor` checks the machine, including whether the installed skills match the binary.

## The skills

```bash
hv skills install
```

With no flags this writes the skills to the user roots for both agents: `~/.claude/skills` (or `$CLAUDE_CONFIG_DIR/skills`) for Claude Code and `~/.agents/skills` for Codex.

| Flag | Meaning |
|---|---|
| `--agent claude\|codex\|all` | which agent's root to write (default: both) |
| `--scope user\|project` | `user` (default), or `project` for `.claude/skills` and `.agents/skills` in the current repo |
| `--overwrite` | replace files you edited or hv did not write |

The skills are copies, not symlinks, and `install` writes a `.hv-manifest.json` listing what it put there. A file you edited is kept and reported unless you pass `--overwrite`. A project-scope install can be committed so collaborators get the same skills.

`hv skills status` compares the installed skills with the binary. For Codex, see [skills in Codex](usage/codex-skills.md) and, to run Codex as a round worker, [Codex workers](usage/codex-workers.md).

## Upgrading

```bash
hv update
```

`hv update` (needs `gh`) works out how you installed, compares versions and prints the command to run. It does not run it. Typical output:

- Homebrew: `brew update && brew upgrade hv && hv skills update`
- install script: the `curl` line above, then `hv skills update`

`hv skills update` refreshes every skill root that has a manifest. In a project, `hv version --drift` compares the version stamped in `.hv/` with the binary.

## Uninstalling

```bash
hv skills uninstall    # removes what hv installed
brew uninstall hv      # Homebrew; otherwise delete the hv binary
```

Your projects' `.hv/` folders are untouched.

## Next

Run `hv init` once at the project root (`hv init --no-blocks` skips `AGENTS.md` and the managed blocks; `hv init umbrella` sets up a multi-repo coordinator). [Getting started](getting-started.md) walks through the first cycle.
