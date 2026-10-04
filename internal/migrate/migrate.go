// Package migrate ports hv-migrate v4: the one-shot v3 to v4 codemod that
// rewrites retired slash commands, folds CONTEXT.md terms into the glossary,
// drops stale helper copies and the deprecated managed blocks, and stamps the
// version. File contents match bin/hv-migrate byte for byte.
package migrate

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/l4ci/hv/v5/internal/fsio"
	"github.com/l4ci/hv/v5/internal/jsonx"
	"github.com/l4ci/hv/v5/internal/knowledge"
)

// Sentinels the verb maps to exit codes.
var (
	// ErrConfig: .hv/config.json is missing, unreadable or has no version (exit 3).
	ErrConfig = errors.New("config")
	// ErrRefused: a safety precondition does not hold, or an import failed (exit 4).
	ErrRefused = errors.New("refused")
	// ErrGit: git is missing or the project is not a git repository (exit 5).
	ErrGit = errors.New("git")
)

// Refusal is the error of a refused run: Blocked names the invariant in a
// word or phrase, for the verb's failure data.
type Refusal struct{ Blocked, Message string }

func (r *Refusal) Error() string { return r.Message }

// Unwrap lets errors.Is(err, ErrRefused) match.
func (r *Refusal) Unwrap() error { return ErrRefused }

func refuse(blocked, format string, a ...any) error {
	return &Refusal{blocked, fmt.Sprintf(format, a...)}
}

// InstalledVersion is the version stamped into hv.version; "" skips the
// stamp. It is the running binary's version, and tests replace it.
var InstalledVersion = func() string { return "" }

// removedBinaries are the .hv/bin files orphaned when /hv-context was folded
// into the glossary.
var removedBinaries = []string{"hv-context-add", "hv-context-index", "hv-context-map", "hv-context-query"}

var staticPaths = []string{".hv/BACKLOG.md", ".hv/MILESTONES.md", ".hv/KNOWLEDGE.md", ".hv/DECISIONS.md", "CLAUDE.md", "AGENTS.md"}

var globDirs = []string{".hv/plans", ".hv/designs", ".hv/handoffs", ".hv/handoff", ".hv/qa", ".hv/milestones"}

// Options of Run.
type Options struct {
	Apply   bool
	Verbose bool
	// Cwd is the directory the verb was started in (for the backup-dir guard).
	Cwd string
}

// ContextMigration describes what happens to one CONTEXT.md.
type ContextMigration struct{ Scope, Message string }

// Report is what Run found and, with Apply, did.
type Report struct {
	Applied             bool
	FilesScanned        int
	FilesRewritten      int
	ReferencesRewritten int
	ManualReview        []string
	Contexts            []ContextMigration
	RemovedBinaries     []string
	StrippedBlocks      []string
	Rewritten           []string // paths, relative to the root
	Diffs               []string
	Noop                bool
	Changed             bool
	VersionStamp        string
	Backup              string
}

type rewriteJob struct {
	path, rel, original, text string
	count                     int
}

type ctxPlan struct {
	scope   string // "" for the umbrella file, else the sub-repo name
	file    string // absolute path of the CONTEXT.md
	action  string // none, delete or migrate
	terms   []knowledge.TermEntryNamed
	tsv     string
	message string
}

// Run previews or applies the v4 migration in the project at root.
func Run(root string, repos map[string]string, o Options) (*Report, error) {
	if err := checkPreconditions(root, o.Cwd); err != nil {
		return nil, err
	}
	store := knowledge.Store{Root: root, Repos: repos}

	targets := scanTargets(root)
	rep := &Report{Applied: o.Apply, FilesScanned: len(targets)}
	var jobs []rewriteJob
	for _, rel := range targets {
		raw, err := fsio.ReadText(filepath.Join(root, rel))
		if err != nil || !utf8.ValidString(raw) {
			continue
		}
		text, n, manual := Rewrite(raw, rel)
		rep.ManualReview = append(rep.ManualReview, manual...)
		if n > 0 {
			jobs = append(jobs, rewriteJob{filepath.Join(root, rel), rel, raw, text, n})
			rep.Rewritten = append(rep.Rewritten, rel)
			rep.ReferencesRewritten += n
			if o.Verbose {
				rep.Diffs = append(rep.Diffs, UnifiedDiff(raw, text, rel))
			}
		}
	}
	rep.FilesRewritten = len(jobs)

	plans, err := planContexts(root, repos)
	if err != nil {
		return nil, err
	}
	for _, p := range plans {
		scope := "umbrella"
		if p.scope != "" {
			scope = p.scope
		}
		rep.Contexts = append(rep.Contexts, ContextMigration{scope, p.message})
	}
	var bins []string
	for _, n := range removedBinaries {
		if _, err := os.Stat(filepath.Join(root, ".hv", "bin", n)); err == nil {
			bins = append(bins, n)
		}
	}
	rep.RemovedBinaries = bins

	// The deprecated-block strip runs on every call (contract: a project whose
	// only v3 leftover is such a block reports it with noop false).
	stripped, err := store.StripDeprecatedBlocks(false)
	if err != nil {
		return nil, err
	}
	rep.StrippedBlocks = stripped

	pending := len(jobs) > 0 || len(bins) > 0
	for _, p := range plans {
		if p.action != "none" {
			pending = true
		}
	}
	onlyStrip := !pending && len(stripped) > 0
	pending = pending || len(stripped) > 0
	if !pending {
		rep.Noop = true
		if o.Apply {
			stamped, err := stampVersion(root)
			if err != nil {
				return nil, err
			}
			rep.VersionStamp, rep.Changed = stamped, stamped != ""
		}
		return rep, nil
	}

	if !o.Apply {
		return rep, nil
	}

	rel := filepath.Join(".hv", "migrate-backup", time.Now().Format("20060102T150405"))
	backup := filepath.Join(root, rel)
	if err := os.MkdirAll(backup, 0o777); err != nil {
		return nil, err
	}
	rep.Backup = rel
	if len(stripped) > 0 && onlyStrip {
		// A strip-only run (no old-helper equivalent: it skipped the strip)
		// would otherwise leave the backup empty; keep the instructions file
		// the strip rewrites. With other work pending the backup matches the
		// old helper's: rewritten files only.
		for _, rel := range []string{"AGENTS.md", "CLAUDE.md"} {
			if _, err := os.Stat(filepath.Join(root, rel)); err == nil {
				if err := copyFile(filepath.Join(root, rel), filepath.Join(backup, rel)); err != nil {
					return nil, err
				}
			}
		}
	}
	for _, j := range jobs {
		if err := copyFile(j.path, filepath.Join(backup, j.rel)); err != nil {
			return nil, err
		}
		if err := fsio.WriteFileAtomic(j.path, []byte(j.text)); err != nil {
			return nil, err
		}
	}
	for _, p := range plans {
		if p.action == "none" {
			continue
		}
		dest := filepath.Join(backup, "CONTEXT.md")
		if p.scope != "" {
			dest = filepath.Join(backup, "contexts", p.scope, "CONTEXT.md")
		}
		if err := copyFile(p.file, dest); err != nil {
			return nil, err
		}
		if p.action == "migrate" {
			scope := knowledge.Umbrella
			if p.scope != "" {
				scope = p.scope
			}
			if _, _, err := store.GlossaryImport(scope, p.tsv, false); err != nil {
				who := "CONTEXT migration failed"
				if p.scope != "" {
					who += " for sub-repo '" + p.scope + "'"
				}
				kept, _ := filepath.Rel(root, dest)
				return rep, refuse("glossary-import", "%s: %v\n%s backed up at %s; not deleted. Resolve the conflict and re-run.", who, err, filepath.Base(p.file), kept)
			}
		}
		if err := os.Remove(p.file); err != nil {
			return nil, err
		}
	}
	for _, n := range bins {
		src := filepath.Join(root, ".hv", "bin", n)
		if err := copyFile(src, filepath.Join(backup, "bin", n)); err != nil {
			return nil, err
		}
		if err := os.Remove(src); err != nil {
			return nil, err
		}
	}
	if _, err := store.StripDeprecatedBlocks(true); err != nil {
		return nil, err
	}
	stamped, err := stampVersion(root)
	if err != nil {
		return nil, err
	}
	rep.VersionStamp = stamped
	rep.Changed = true
	return rep, nil
}

// scanTargets lists the existing files in scope, relative to root.
func scanTargets(root string) []string {
	seen := map[string]bool{}
	var out []string
	add := func(rel string) {
		if !seen[rel] {
			seen[rel] = true
			out = append(out, rel)
		}
	}
	for _, rel := range staticPaths {
		if fi, err := os.Stat(filepath.Join(root, rel)); err == nil && !fi.IsDir() {
			add(rel)
		}
	}
	for _, d := range globDirs {
		files, _ := filepath.Glob(filepath.Join(root, d, "*.md"))
		sort.Strings(files)
		for _, f := range files {
			if fi, err := os.Stat(f); err == nil && !fi.IsDir() {
				r, _ := filepath.Rel(root, f)
				add(r)
			}
		}
	}
	return out
}

func checkPreconditions(root, cwd string) error {
	if abs, err := filepath.EvalSymlinks(cwd); err == nil {
		cwd = abs
	}
	if strings.Contains(cwd+"/", "/.hv/migrate-backup/") {
		return refuse("backup-dir", "cwd is inside .hv/migrate-backup/. Run from project root.")
	}
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = root
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("%w: not inside a git repo (or git unavailable)", ErrGit)
	}
	var dirty []string
	for _, line := range strings.Split(string(out), "\n") {
		if len(line) < 4 {
			continue
		}
		path := strings.TrimSpace(line[3:])
		if _, dest, ok := strings.Cut(path, " -> "); ok {
			path = dest
		}
		if !strings.HasPrefix(path, ".hv/") {
			dirty = append(dirty, path)
		}
	}
	if len(dirty) > 0 {
		return refuse("dirty-tree", "uncommitted changes outside .hv/:\n  %s\nCommit or stash these before running hv migrate v4.", strings.Join(dirty, "\n  "))
	}

	cfg, err := loadConfig(root)
	if err != nil {
		return err
	}
	version := ""
	for _, parent := range []string{"hv", "hvSkills"} {
		if version == "" {
			if o, ok := getObj(cfg, parent); ok {
				version = getString(o, "version")
			}
		}
	}
	if version == "" {
		version = getString(cfg, "version")
	}
	if version == "" {
		return fmt.Errorf("%w: .hv/config.json has no 'version' field — run hv init", ErrConfig)
	}
	major, _, _ := strings.Cut(version, ".")
	n, err := strconv.Atoi(major)
	if err != nil {
		return fmt.Errorf("%w: .hv/config.json version '%s' is not parseable", ErrConfig, version)
	}
	if n < 3 {
		return refuse("pre-3.0", "project hv-skills version is %s (pre-3.0). Bring it current with hv init before hv migrate v4.", version)
	}
	return nil
}

func configPath(root string) string { return filepath.Join(root, ".hv", "config.json") }

func loadConfig(root string) (*jsonx.Object, error) {
	raw, err := os.ReadFile(configPath(root))
	if os.IsNotExist(err) {
		return nil, fmt.Errorf("%w: .hv/config.json missing — run hv init first", ErrConfig)
	}
	if err != nil {
		return nil, err
	}
	v, err := jsonx.Decode(raw)
	obj, _ := v.(*jsonx.Object)
	if err != nil || obj == nil {
		return nil, fmt.Errorf("%w: .hv/config.json is not valid JSON", ErrConfig)
	}
	return obj, nil
}

func getObj(o *jsonx.Object, k string) (*jsonx.Object, bool) {
	v, _ := o.Get(k)
	r, ok := v.(*jsonx.Object)
	return r, ok
}

func getString(o *jsonx.Object, k string) string {
	v, _ := o.Get(k)
	s, _ := v.(string)
	return s
}

// stampVersion writes hv.version and drops both legacy forms: hvSkills.version
// (with its hvSkills object once empty) and the top-level "version". It
// returns the stamped version, or "" when nothing changed (no installed
// version known, or hv.version already holds it and no legacy form remains).
func stampVersion(root string) (string, error) {
	want := InstalledVersion()
	if want == "" {
		return "", nil
	}
	cfg, err := loadConfig(root)
	if err != nil {
		return "", err
	}
	hv, _ := getObj(cfg, "hv")
	old, _ := getObj(cfg, "hvSkills")
	_, legacy := cfg.Get("version")
	if old != nil {
		_, hasOld := old.Get("version")
		legacy = legacy || hasOld
	}
	if hv != nil && getString(hv, "version") == want && !legacy {
		return "", nil
	}
	if hv == nil {
		hv = jsonx.NewObject()
		cfg.Set("hv", hv)
	}
	hv.Set("version", want)
	if old != nil {
		old.Delete("version")
		if len(old.Keys()) == 0 {
			cfg.Delete("hvSkills")
		}
	}
	cfg.Delete("version")
	return want, fsio.WriteJSONAtomic(configPath(root), cfg)
}

func planContexts(root string, repos map[string]string) ([]ctxPlan, error) {
	var plans []ctxPlan
	one := func(scope, file, label, where string) error {
		raw, err := fsio.ReadText(file)
		if os.IsNotExist(err) {
			if scope == "" {
				plans = append(plans, ctxPlan{scope: scope, file: file, action: "none", message: "no CONTEXT.md"})
			}
			return nil
		}
		if err != nil {
			return err
		}
		var terms []knowledge.TermEntryNamed
		for _, t := range knowledge.TopicEntries(raw) {
			if t.Definition != "" {
				terms = append(terms, t)
			}
		}
		prefix := ""
		if scope != "" {
			prefix = scope + ": "
		}
		p := ctxPlan{scope: scope, file: file}
		if len(terms) == 0 {
			p.action = "delete"
			p.message = prefix + "placeholder only — file will be removed (no terms to migrate)"
		} else {
			p.action, p.terms = "migrate", terms
			p.message = fmt.Sprintf("%swill migrate %d term(s) to %s (Glossary)", prefix, len(terms), where)
			rows := []string{"# auto-generated by hv migrate v4 from " + label}
			for _, t := range terms {
				rows = append(rows, strings.Join([]string{t.Name, strings.Join(strings.Fields(t.Definition), " "), strings.Join(t.Aliases, ", "), strings.Join(t.Nots, ", ")}, "\t"))
			}
			p.tsv = strings.Join(rows, "\n") + "\n"
		}
		plans = append(plans, p)
		return nil
	}
	if err := one("", filepath.Join(root, ".hv", "CONTEXT.md"), ".hv/CONTEXT.md", ".hv/KNOWLEDGE.md"); err != nil {
		return nil, err
	}
	names := make([]string, 0, len(repos))
	for n := range repos {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		if err := one(n, filepath.Join(root, ".hv", "contexts", n, "CONTEXT.md"),
			".hv/contexts/"+n+"/CONTEXT.md", ".hv/knowledge/"+n+"/KNOWLEDGE.md"); err != nil {
			return nil, err
		}
	}
	return plans, nil
}

func copyFile(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o777); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	fi, err := in.Stat()
	if err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, fi.Mode().Perm())
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	return os.Chtimes(dst, fi.ModTime(), fi.ModTime())
}
