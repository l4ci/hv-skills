# Release host commands

Loaded by `/hv-release` Step 13 (Create Remote Release) to emit the right host-specific command after `bin/hv-release-detect-host` returns the host type. Each block corresponds to one value of the helper's `host` output. Skip the whole step in `--dry-run` mode (the SKILL.md print the would-run command instead).

## `github` or `github-enterprise`

```bash
gh release create v<new_version> \
  --title "v<new_version> — <one-line summary>" \
  --notes-file "$NOTES_FILE" \
  [--draft]   # add when release.draft: true
```

Capture the release URL on stdout for the Step 14 summary.

## `gitlab` or `gitlab-self-hosted`

```bash
glab release create v<new_version> --notes "$(cat "$NOTES_FILE")"
```

If `glab` is not on the `PATH`, print *"glab not found. Create the release manually: `glab release create v<new_version> --notes-file <path>`"* and continue — don't fail the whole flow.

## `none`

Print *"No recognized remote — skipping remote release creation."* and continue.

## Release title

`v<new_version> — <one-line summary>` where the summary comes from Step 6.
