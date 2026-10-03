# `hv` verb reference

`hv` is the single binary behind every hv-skills skill. Skills call it for all
backlog, knowledge, plan, status, git and release bookkeeping, and you can call
it directly when scripting against `.hv/`. There is no helper copy to refresh in a
project: `hv` ships with the plugin and updates with it.

```sh
hv item create --kind bugs --title "Crash on save" --tag P1 --desc "Why."
hv backlog list --json
hv knowledge query "Auth & Sessions"
```

## Conventions

- **Global flags.** `--json` prints one JSON envelope on stdout, `-C <dir>` runs
  as if started in `<dir>`, `--repo <name>` scopes a verb to an umbrella
  sub-repo, `-h` prints help for any group or verb.
- **No prompts.** `hv` never asks anything. A missing decision is exit 2 naming
  the flag. Skills do the asking.
- **Bodies on stdin.** Any flag that takes a file path also accepts `-`
  (`--body-file -`).
- **Project root.** Verbs walk up from the working directory to the nearest
  `.hv/`. Only `hv init`, `hv init check`, `hv init umbrella`, `hv version` and
  `hv update` run without one.
- **Idempotent writes.** A mutating verb reports `changed: true|false`. A no-op
  is exit 0.

| Exit | Meaning |
|---|---|
| 0 | Success, including idempotent no-ops |
| 1 | The verb ran and the answer is no (a guard or check failed) |
| 2 | Usage error: unknown verb or flag, missing argument |
| 3 | Something named could not be resolved (item, plan, sub-repo, base branch, `.hv/` itself) |
| 4 | A mutating verb refused to break an invariant |
| 5 | An external dependency is missing or failing (`git`, `gh`, `glab`, network) |
| 6 | Transient: rate limit or lock timeout, retry later |
| 70 | Bug in `hv`; report it |

Not a stable API across major versions, but `--json` shapes only change
additively within one. Full rules:
[CLI conventions](../design/5.0-cli-conventions.md). Per-verb `data` shapes,
exit codes and repo scope: [verb contract](../design/5.0-verb-contract.md).
`hv <group> --help` lists a group's verbs, `hv <group> <verb> --help` its flags.

## Verbs

## `hv version`

| Usage | What it does |
|---|---|
| `hv version [--drift]` | print the hv version |

## `hv update`

| Usage | What it does |
|---|---|
| `hv update` | check for a newer hv-skills release |

## `hv config`

| Usage | What it does |
|---|---|
| `hv config show [<key>]` | effective value and source of config keys |
| `hv config set <key> <value>` | set one key in .hv/config.json |
| `hv config check` | compare .hv/config.json with the schema |
| `hv config fill` | write the schema default for every missing key |

## `hv repo`

| Usage | What it does |
|---|---|
| `hv repo which` | the registered sub-repo the working directory is in |
| `hv repo resolve [<name>…]` | names to registered sub-repo paths |
| `hv repo umbrella` | is this an umbrella project |

## `hv id`

| Usage | What it does |
|---|---|
| `hv id next --kind <bugs\|features\|tasks\|milestones>` | mint the next counter ID |

## `hv item`

| Usage | What it does |
|---|---|
| `hv item create --kind <bugs\|features\|tasks> --title <text> [--tag <tag>] [--desc <text>] [--body-file <path\|->] [--related <text>] [--milestone <text>] [--repos <csv>] [--subsystem <text>] [--captured <YYYY-MM-DD>] \| --kind <kind> --raw-file <path\|->` | capture one item |
| `hv item show <ID>` | status block of an issue-mode item |
| `hv item claim <ID> --as <claim-id>` | take an item so two agents never work it at once |
| `hv item release <ID> --as <claim-id>` | give a claimed item back |
| `hv item ready <ID>` | is the item specified well enough to start |
| `hv item state <ID> --to <in-progress\|needs-review\|changes-requested\|none>` | set the workflow state label of an item |
| `hv item comment add <ID> --kind <question\|answer\|decision\|feedback> --body-file <path\|->` | append a comment |
| `hv item comment list <ID> [--kind <question\|answer\|decision\|feedback>]` | list comments |
| `hv item note add <ID> --kind <proof\|design\|plan> --body-file <path\|->` | write a note |
| `hv item note show <ID> --kind <proof\|design\|plan>` | print a note |
| `hv item note rm <ID> --kind <proof\|design\|plan>` | delete a note |
| `hv item field get <ID> --name <title\|detail\|related\|milestone\|repos\|subsystem\|since\|reason\|note>` | print one field of an item |
| `hv item field set <ID> --name <milestone\|related\|repos\|subsystem\|detail> --value <text>` | set, replace or clear a field of an open item |
| `hv item field list <ID>` | every field of an item |
| `hv item complete <ID> [--commit <hash>] [--reason <done\|handed-off\|blocked\|dropped>] [--note <text>] [--no-proof]` | close an item |
| `hv item reopen <ID>` | restore a completed item |
| `hv item rm <ID>... [--scrub-archive] [--apply]` | remove items with their cross-references and files |
| `hv item shipped <title>...` | look for evidence that titles already shipped |

## `hv backlog`

| Usage | What it does |
|---|---|
| `hv backlog list [--grep <pattern>]` | open items as sorted tables, with clusters |
| `hv backlog ids --milestone <id>` | IDs of the open items tagged with a milestone |
| `hv backlog milestones <ID>...` | milestones the given items are tagged with |
| `hv backlog drift` | open items that commits already mention |
| `hv backlog backfill` | stamp Since: on open items that lack it |
| `hv backlog archive [--days <n>]` | move old completed items to ARCHIVE.md |
| `hv backlog stale --kind <map\|knowledge\|todo> [--days <n>]` | stale map, knowledge or backlog entries |

## `hv summary`

| Usage | What it does |
|---|---|
| `hv summary` | compact project state |

## `hv issues`

| Usage | What it does |
|---|---|
| `hv issues list [--mine] [--label <name>] [--limit <n>]` | open upstream issues |
| `hv issues label <issue> (--add <name> \| --remove <name>)` | add or remove a label on an upstream issue |
| `hv issues imported [--for-repo <name>] [--open-only]` | backlog items that point at upstream issues |
| `hv issues close <issue> --commit <sha> [--item <ID>]` | close an upstream issue naming the shipping commit |
| `hv issues provider` | github, gitlab or unknown for the origin remote |

## `hv status`

| Usage | What it does |
|---|---|
| `hv status add <branch> --items <csv> [--worktree <path>] [--if-absent]` | record an active work stream |
| `hv status rm <branch>` | end a work stream and drop its handoff note |
| `hv status show <branch>` | which repo a branch's stream is in |
| `hv status handoff <branch> [--canonical]` | path of a branch's handoff note |
| `hv status loop start` | stamp the loop start, first write wins |
| `hv status loop clear` | remove the loop start stamp |
| `hv status loop show` | print the loop start stamp |

## `hv refactor`

| Usage | What it does |
|---|---|
| `hv refactor age` | features and bugs completed since the last refactor |
| `hv refactor reset` | zero the since-refactor counters |
| `hv refactor targets` | what a refactor can cover |

## `hv migrate`

| Usage | What it does |
|---|---|
| `hv migrate issues [--apply] [--limit <n>]` | move the file backlog onto the issue tracker (preview unless --apply) |
| `hv migrate v4 [--apply] [--verbose]` | migrate a v3 project to v4 (preview unless --apply) |

## `hv knowledge`

| Usage | What it does |
|---|---|
| `hv knowledge query <topic>… [--tier provisional\|confirmed\|deprecated] [--include-deprecated]` | print topic sections, tier-aware |
| `hv knowledge stats` | bullet count and size per topic |
| `hv knowledge add --topic <T> --title <S> --body-file <path\|-> [--date YYYY-MM-DD]` | add a bullet under a topic |
| `hv knowledge amend --topic <T> --fragment <F> --mode append --body-file <path\|->` | append text to an existing bullet |
| `hv knowledge rename-topic --from <X> --to <Y> [--title <T>]` | rename a topic or move one bullet |
| `hv knowledge hit --topic <T> --title <S>` | register a consulted bullet |
| `hv knowledge tier get --topic <T> --title <S>` | show one bullet's tier |
| `hv knowledge tier set --topic <T> --title <S> --tier provisional\|confirmed\|deprecated` | set one bullet's tier |
| `hv knowledge tier list [--tier provisional\|confirmed\|deprecated]` | list tracked bullets |
| `hv knowledge contradiction add --topic <T> --title <S> --text <text>` | queue a contradiction candidate |
| `hv knowledge contradiction list` | list the queue |
| `hv knowledge contradiction clear` | empty the queue |
| `hv knowledge contradiction has --topic <T> --title <S>` | exit 0 when the pair is queued |

## `hv decisions`

| Usage | What it does |
|---|---|
| `hv decisions query <topic>…` | print topic sections |
| `hv decisions auto-log --topic <T> --title <rule-title> --why <text> [--plan-key <key>] [--date YYYY-MM-DD]` | log an [Auto:Loop] decision |
| `hv decisions auto-since` | list this loop session's auto-logged decisions |

## `hv glossary`

| Usage | What it does |
|---|---|
| `hv glossary read <term>…` | print term entries |
| `hv glossary write <term> --def <text> [--alias <a,b>] [--not <n,m>] [--touch]` | add or update one term |
| `hv glossary import --body-file <path\|-> [--touch]` | add many terms atomically |

## `hv block`

| Usage | What it does |
|---|---|
| `hv block <key> [--body-file <path\|->]` | regenerate a managed block in the instructions file |
| `hv block skills` | regenerate the skills block |

## `hv instructions`

| Usage | What it does |
|---|---|
| `hv instructions init` | make AGENTS.md the instructions file, CLAUDE.md its importer |

## `hv map`

| Usage | What it does |
|---|---|
| `hv map query <name>…` | print subsystem files |
| `hv map index` | regenerate the map block |
| `hv map stats [--cap]` | size and broken-reference counts |

## `hv qa`

| Usage | What it does |
|---|---|
| `hv qa query <target>…` | print QA target files |
| `hv qa index` | regenerate the QA block |

## `hv milestone`

| Usage | What it does |
|---|---|
| `hv milestone add --title <text> --summary <text> [--depends M01,M02]` | mint a milestone |
| `hv milestone list` | list milestones |
| `hv milestone show <id>` | print a milestone |
| `hv milestone put <id> --body-file <path\|->` | replace a milestone's text |
| `hv milestone status <id> --to <planned\|active\|shipped\|archived>` | change a milestone's status |
| `hv milestone active` | IDs of active milestones |
| `hv milestone index` | regenerate the overview and vision block |

## `hv plan`

| Usage | What it does |
|---|---|
| `hv plan add <milestone>-<unit> --title <text> [--design <ID>] [--repos a,b]` | create a plan stub |
| `hv plan list [--milestone M01]` | list plans |
| `hv plan show <key>` | print a plan |
| `hv plan put <key> --body-file <path\|->` | replace a plan's text |
| `hv plan rm <key>` | delete a plan |
| `hv plan validate-docs <key>` | check doc-by-path deliverables |
| `hv plan rename-check <old> [-- <pathspec>…]` | files that mention a name |
| `hv plan uncertain <ID>` | uncertainty pre-flight for an item |

## `hv design`

| Usage | What it does |
|---|---|
| `hv design add <ID> --title <text>` | create a design stub |
| `hv design list` | list designs |
| `hv design show <ID>` | print a design |
| `hv design put <ID> --body-file <path\|->` | replace a design's text |
| `hv design rm <ID>` | delete a design |
| `hv design amend <ID> --section <heading> --mode <append\|replace> --body-file <path\|->` | amend one section of a design |

## `hv spike`

| Usage | What it does |
|---|---|
| `hv spike add <name> --question <text>` | create spike/<name> and its file |
| `hv spike finish <name>` | mark a spike done |
| `hv spike list` | list spikes |
| `hv spike show <name>` | print a spike file |

## `hv proof`

| Usage | What it does |
|---|---|
| `hv proof add <ID> --check <text> --result <PASS\|FAIL> --evidence <text> [--sha <commit>]` | append a proof row |
| `hv proof show <ID> [--count]` | list an item's proof rows |

## `hv debug`

| Usage | What it does |
|---|---|
| `hv debug counter init <bugId>` | start the counter for a bug |
| `hv debug counter record-attempt --hypothesis <text> --commit <hash>` | record a pending fix attempt |
| `hv debug counter fail` | mark the last attempt failed |
| `hv debug counter pass` | mark the last attempt passed |
| `hv debug counter show` | print the counter state |
| `hv debug counter summary` | Iron Law halt note |
| `hv debug counter clear` | delete the counter |
| `hv debug counter inc-cycle` | count a hypothesis cycle |

## `hv worker`

| Usage | What it does |
|---|---|
| `hv worker pool init --slots <n> [--base <branch>] [--session <name>]` | create the slots' worktrees and register them |
| `hv worker pool list` | list the registered slots |
| `hv worker pool reap (<slot>... \| --all)` | remove slots, their worktrees and branches |
| `hv worker reset <slot> [--task <id>] [--check-only]` | refuse a slot that holds work, else cut a fresh task branch |
| `hv worker dispatch <slot> --body-file <path\|-> [--task <id>] [--relay] [--round <n>] [--boot-timeout <s>]` | send a brief into a slot's session |
| `hv worker poll [<slot>] [--settle <seconds>] [--lines <n>]` | classify slot states from their panes |
| `hv worker gate <slot> --base <branch> [--check-only] [--no-verify] [--confirm --confirm-note <answer>]` | merge gate for one slot's branch or PR; exit 4 when `ship.mergeApproval` needs a human |
| `hv worker session check [--session <name>]` | inside a managed host session? (exit 1 when outside) |
| `hv worker session ensure [--session <name>] [--body-file <path\|->] [--boot-timeout <s>]` | hand the orchestrator off into a host session |
| `hv worker account list` | list accounts with their usage verdict |
| `hv worker account pick [--exclude <name>[,<name>...]]` | name the account with the most headroom |
| `hv worker account assign <slot> [--account <name>]` | put an account's config dir on a slot |

## `hv tracker`

| Usage | What it does |
|---|---|
| `hv tracker call [--provider auto\|github\|gitlab] -- <cli-arg>...` | run gh or glab with list limits and rate-limit handling |
| `hv tracker suggest-upstream --title <text> --body-file <path\|-> [--upstream-repo <owner/repo>] --confirm --confirm-note <answer>` | file a hv-skills issue from a learning (manual gate) |

## `hv git`

| Usage | What it does |
|---|---|
| `hv git base` | print the resolved base branch |
| `hv git guard clean [--context <text>]` | fail when the working tree is dirty |
| `hv git guard feature-branch [<branch>]` | fail on the base branch or a detached HEAD |
| `hv git branch <name> --repos <a,b,...>` | create one branch in several sub-repos, or in none |
| `hv git worktree-path <branch>` | print the umbrella worktree path of a sub-repo branch |

## `hv review`

| Usage | What it does |
|---|---|
| `hv review scope [<branch>]` | commits, files, item IDs and origin entries of a branch |
| `hv review brief [<branch>]` | fresh-eyes second-opinion brief for a branch |
| `hv review scaffolding [<branch>] [--base <branch>]` | added diff lines that look like leftover task scaffolding |
| `hv review queue` | open issues waiting for review |

## `hv ship`

| Usage | What it does |
|---|---|
| `hv ship body [<branch>]` | build a PR body from a branch's commits |
| `hv ship pr <branch> --title <text> --body-file <path\|-> [--items <ID>[,<ID>…]]` | push a branch and open a PR or MR |
| `hv ship merge <branch> --body-file <path\|-> [--confirm --confirm-note <answer>]` | merge a branch into the base branch with --no-ff; exit 4 when `ship.mergeApproval` needs a human |
| `hv ship pr-merge <pr> [--items <ID>[,<ID>…]] [--confirm --confirm-note <answer>]` | merge a PR in issue mode; exit 4 when `ship.mergeApproval` needs a human |
| `hv ship undo [--cycle <hash>] [--allow-post-merge] [--apply]` | roll back the last cycle merge on the base branch |

## `hv release`

| Usage | What it does |
|---|---|
| `hv release version [--level patch\|minor\|major \| --to <X.Y.Z>]` | print the version file, and the next version with --level or --to |
| `hv release bump (--level patch\|minor\|major \| --to <X.Y.Z>) [--file <path>] [--kind <kind>]` | write the next version into the version file |
| `hv release host` | print the hosting kind of origin |
| `hv release notes --from commits [--since <ref>]` | release notes from commits |
| `hv release changelog <X.Y.Z> --body-file <path\|-> [--path <file>]` | add a release section to the changelog |
| `hv release pending` | how much has landed since the last release tag |
| `hv release milestone-check <MNN>` | list the open issues that block a milestone release |
| `hv release close-milestone <MNN> --release <X.Y.Z>` | close out a released milestone |
| `hv release push <X.Y.Z> [--branch <name>] --confirm --confirm-note <answer>` | push the release tag and branch to origin (manual gate) |
| `hv release publish <X.Y.Z> --title <text> --body-file <path\|-> [--draft] --confirm --confirm-note <answer>` | create the GitHub or GitLab release (manual gate) |

## `hv gate`

| Usage | What it does |
|---|---|
| `hv gate list` | list every manual gate and the verbs that enforce it |

A gated verb refuses with exit 4 (`blockedBy: "manual gate"`) at every autonomy level unless `--confirm` and `--confirm-note` carry the human's answer, and appends each approval to `.hv/gate-audit.jsonl`. See [`references/manual-gates.md`](../../references/manual-gates.md).

## `hv init`

| Usage | What it does |
|---|---|
| `hv init` | create or refresh `.hv/`, the managed blocks and `.gitignore` |
| `hv init check` | is `.hv/` initialized (exit 1 when not) |
| `hv init umbrella (--repos <csv> \| --all \| --list)` | register sub-repos and make this directory an umbrella |

## Keeping this page current

The tables are generated from the usage lines in the
[verb contract](../design/5.0-verb-contract.md) and the summaries from
`hv <group> <verb> --help --json`. When a verb changes, regenerate the row
rather than editing prose around it.
