# Release Checklist

Each `- [ ]` line is a gate `/hv-release` walks before bumping the version. Edit freely — nothing here is hardcoded. Items marked `- [x]` are ignored. Append `(manual)` to any item that must interject even in `autonomy.level: auto`/`loop`.

- [ ] `.claude-plugin/marketplace.json` versions match the new `plugin.json` version (both `metadata.version` and `plugins[0].version`)
- [ ] `bin/hv-skills-index` heredoc lists every shipping skill (re-check after adding or removing one)
- [ ] CLAUDE.md template managed blocks reflect any new query helpers or topic indexes
- [ ] `bash test/smoke.sh` is green on this branch
- [ ] CHANGELOG.md entry for the version is human-readable — bullets compressed, themes named, no raw commit dumps

(Add release-cycle-specific items below as they come up; trim entries that stop being load-bearing.)
