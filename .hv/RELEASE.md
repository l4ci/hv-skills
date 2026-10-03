# Release Checklist

Each `- [ ]` line is a gate `/hv-release` walks before bumping the version. Edit freely — nothing here is hardcoded. Items marked `- [x]` are ignored. Append `(manual)` to any item that must interject even in `autonomy.level: auto`/`loop`.

- [ ] `.claude-plugin/marketplace.json` versions match the new `plugin.json` version (both `metadata.version` and `plugins[0].version`)
- [ ] `.claude-plugin/plugin.json` `skills` lists every `hv-*/` skill dir, and `python3 test/validate-skills.py` passes
- [ ] `goreleaser release --snapshot --clean` builds `hv_<os>_<arch>` for linux and darwin on amd64 and arm64, plus `checksums.txt` (asset names are the contract with `bin/hv`)
- [ ] GitHub Actions is enabled for this repo, so the `v*` tag runs `.github/workflows/release.yml` (manual)
- [ ] CLAUDE.md template managed blocks reflect any new query helpers or topic indexes
- [ ] `bash test/smoke.sh` is green on this branch
- [ ] CHANGELOG.md entry for the version is human-readable — bullets compressed, themes named, no raw commit dumps

(Add release-cycle-specific items below as they come up; trim entries that stop being load-bearing.)
