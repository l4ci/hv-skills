package cli

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/l4ci/hv/v5/internal/migrate"
	"github.com/l4ci/hv/v5/internal/version"
)

// migrateCommands is the `hv migrate` group. `migrate issues` (A4) joins it.
func migrateCommands() *Command {
	return &Command{Name: "migrate", Summary: "one-shot project migrations", Subs: []*Command{
		{Name: "v4", Summary: "migrate a v3 project to v4 (preview unless --apply)", Verb: migrateV4},
		{Name: "issues", Summary: "move the file backlog onto the issue tracker (preview unless --apply)", Verb: a4dMigrateIssues},
	}}
}

func migrateV4(fs *flag.FlagSet) RunFunc {
	apply := fs.Bool("apply", false, "write the changes; without it only report them")
	verbose := fs.Bool("verbose", false, "include a diff for every rewritten file")
	return func(c *Ctx, args []string) (Result, error) {
		if err := knNoArgs(args); err != nil {
			return Result{}, err
		}
		root, repos, err := c.Repos()
		if err != nil {
			return Result{}, err
		}
		cwd, _ := os.Getwd()
		migrate.InstalledVersion = installedVersionFn
		rep, err := migrate.Run(root, repos, migrate.Options{Apply: *apply, Verbose: *verbose, Cwd: cwd})
		if err != nil {
			var ref *migrate.Refusal
			switch {
			case errors.As(err, &ref):
				changed := rep != nil && rep.Changed
				res := Result{Data: knObj("blockedBy", ref.Blocked, "changed", changed || (rep != nil && rep.Backup != ""))}
				return res, Refused("%s", ref.Message)
			case errors.Is(err, migrate.ErrConfig):
				return Result{}, Resolution("%s", strings.TrimPrefix(err.Error(), "config: "))
			case errors.Is(err, migrate.ErrGit):
				return Result{}, Unavailable("%s", strings.TrimPrefix(err.Error(), "git: "))
			}
			return Result{}, knErr(err)
		}
		if !*apply {
			c.Warn("preview only; pass --apply")
		} else if installedVersionFn() == "" {
			c.Warn("version unknown (dev build); config.json not stamped")
		}
		return migrateResult(rep), nil
	}
}

// installedVersionFn is a seam for tests.
var installedVersionFn = installedVersion

func installedVersion() string {
	if v := version.Get().Version; v != "dev" {
		return v
	}
	return ""
}

func migrateResult(r *migrate.Report) Result {
	ctxs := []any{}
	for _, m := range r.Contexts {
		ctxs = append(ctxs, knObj("scope", m.Scope, "message", m.Message))
	}
	d := knObj("applied", r.Applied, "filesScanned", r.FilesScanned, "filesRewritten", r.FilesRewritten,
		"referencesRewritten", r.ReferencesRewritten, "manualReview", len(r.ManualReview),
		"contextMigrations", ctxs, "removedBinaries", len(r.RemovedBinaries),
		"strippedBlocks", strSlice(r.StrippedBlocks), "noop", r.Noop, "changed", r.Changed)
	if r.VersionStamp != "" {
		d.Set("versionStamp", r.VersionStamp)
	}
	if r.Backup != "" {
		d.Set("backup", r.Backup)
	}
	if len(r.Diffs) > 0 {
		d.Set("diffs", strSlice(r.Diffs))
	}
	if len(r.ManualReview) > 0 {
		d.Set("manualReviewItems", strSlice(r.ManualReview))
	}

	var b strings.Builder
	mode := "dry-run"
	if r.Applied {
		mode = "apply"
	}
	fmt.Fprintf(&b, "hv migrate v4 (%s)\n\n", mode)
	fmt.Fprintf(&b, "  files scanned:      %d\n", r.FilesScanned)
	fmt.Fprintf(&b, "  files rewritten:    %d\n", r.FilesRewritten)
	fmt.Fprintf(&b, "  references rewritten: %d\n", r.ReferencesRewritten)
	fmt.Fprintf(&b, "  manual review:      %d\n", len(r.ManualReview))
	for _, m := range r.Contexts {
		if m.Scope == "umbrella" {
			fmt.Fprintf(&b, "  CONTEXT.md:         %s\n", m.Message)
		} else {
			fmt.Fprintf(&b, "  CONTEXT.md (%s):  %s\n", m.Scope, m.Message)
		}
	}
	fmt.Fprintf(&b, "  removed binaries:   %d\n\n", len(r.RemovedBinaries))
	if len(r.Diffs) > 0 {
		b.WriteString("— per-file diffs —\n")
		for _, df := range r.Diffs {
			b.WriteString(df + "\n")
		}
		b.WriteString("\n")
	}
	if len(r.Rewritten) > 0 {
		b.WriteString("— rewrites —\n")
		for _, p := range r.Rewritten {
			fmt.Fprintf(&b, "  %s\n", p)
		}
		b.WriteString("\n")
	}
	if len(r.ManualReview) > 0 {
		b.WriteString("— manual review —\n")
		for _, m := range r.ManualReview {
			fmt.Fprintf(&b, "  %s\n", m)
		}
		b.WriteString("\n")
	}
	if len(r.RemovedBinaries) > 0 {
		b.WriteString("— removed stale helper copies —\n")
		for _, p := range r.RemovedBinaries {
			fmt.Fprintf(&b, "  %s\n", p)
		}
		b.WriteString("\n")
	}
	switch {
	case r.Noop:
		b.WriteString("noop: project is already on v4 (no rewrites, no CONTEXT.md, no stale bins).\n")
		if r.VersionStamp != "" {
			fmt.Fprintf(&b, "version stamp bumped to %s\n", r.VersionStamp)
		}
	case !r.Applied:
		b.WriteString("Run with --apply to write the changes above.\n")
	default:
		if r.VersionStamp != "" {
			fmt.Fprintf(&b, "version stamp bumped to %s\n", r.VersionStamp)
		}
		fmt.Fprintf(&b, "applied. backup at: %s\n", r.Backup)
	}
	return Result{Data: d, Text: b.String()}
}
