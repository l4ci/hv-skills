# hv-update verdict templates

Loaded by `/hv-update` Step 3 to emit a status-keyed message after `bin/hv-update-check` returns. Each block corresponds to one value of the helper's `status` field. Substitute the JSON fields (`currentVersion`, `latestVersion`, `installType`, `installRoot`, `updateCommand`) verbatim into the template — no editorial massaging.

## `current`

```
hv-skills <currentVersion> — up to date.
Installed as <installType> at <installRoot>.
```

## `behind`

```
hv-skills update available: <currentVersion> → <latestVersion>
Installed as <installType> at <installRoot>.

Update:
  <updateCommand>

After updating, run /hv-init in your project to refresh .hv/bin/ helpers.
```

## `ahead`

```
hv-skills <currentVersion> — ahead of the latest release (<latestVersion>).
Likely a local dev build or unpushed repo clone.
```

## `unknown`

```
Could not determine update status.
Current: <currentVersion or "unknown">
Latest: <not reachable — check `gh auth status` or network>
```
