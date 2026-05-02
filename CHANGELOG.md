# Changelog

## v1.12.0 — 2026-05-02

## Highlights

- **New skill: `/hv-release`** — cuts a release end-to-end. Bumps the project version (`major`/`minor`/`patch` or explicit semver), generates categorized release notes from commits since the last tag, prepends a section to `CHANGELOG.md` (creating it if absent), creates an annotated git tag, pushes commit + tag, and publishes a release on GitHub or GitLab when origin is set. Auto-detects the version source across `.claude-plugin/plugin.json`, `package.json`, `pyproject.toml`, `Cargo.toml`, and plain `VERSION` / `version.txt`; honors a `release.versionFile` override in `.hv/config.json`.
- **5 new bin helpers**, each small / atomic / stdlib-only:
  - `hv-release-detect-version` — emit `{file, version, kind}` JSON
  - `hv-release-bump-version` — apply a semver bump (or explicit version) in-place via atomic write
  - `hv-release-changelog-from-commits` — categorize commits in a git range by Conventional Commits prefix; detects `BREAKING CHANGE:` footer
  - `hv-release-update-changelog` — prepend a release section to `CHANGELOG.md` (creates the file with `# Changelog` header if absent); idempotent — refuses if the version section already exists
  - `hv-release-detect-host` — classify origin URL as `github` / `github-enterprise` / `gitlab` / `gitlab-self-hosted` / `none`
- **22 new smoke assertions** cover every helper across each version-file kind, all semver bump rules, full bucket categorization including BREAKING CHANGE, idempotent CHANGELOG prepend, and host detection over SSH/HTTPS variants.

## Configuration

New keys under `release.*` in `.hv/config.json` (all optional):

| Key | Default | Notes |
|---|---|---|
| `release.versionFile` | (auto-detect) | Explicit path override |
| `release.changelogPath` | `CHANGELOG.md` | Project-root relative |
| `release.tagPrefix` | `v` | Set to `""` for unprefixed tags |
| `release.draft` | `false` | Pass `--draft` to `gh` / `glab` |
| `release.requireCleanTree` | `true` | Set `false` to allow dirty releases (testing only) |

## Stats

9 commits · 11 files · +1,130 / −1 lines · all smoke tests pass.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.11.0...v1.12.0

