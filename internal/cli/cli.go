// Package cli is the hv command dispatcher. It owns the global conventions
// in docs/design/5.0-cli-conventions.md (global flags, the --json envelope,
// the stderr format and the exit codes); verbs return data or an *Error and
// never print those parts themselves.
package cli

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Command is a group (Subs) or a verb (Verb) in the hv tree.
type Command struct {
	Name    string
	Summary string
	// Repo marks a verb that takes the global --repo flag.
	Repo bool
	// Verb defines the verb's flags on fs and returns the function that
	// runs with the parsed values. Nil for a group.
	Verb func(fs *flag.FlagSet) RunFunc
	Subs []*Command
}

// RunFunc runs a verb with its positional args.
type RunFunc func(c *Ctx, args []string) (Result, error)

// Result is a verb's output: Data goes into the --json envelope, Text is
// printed otherwise. Data nil means {}. A verb failing with exit 1 or 4 may
// return a Result too: its answer, or what blocked it and what it changed.
type Result struct {
	Data any
	Text string
}

// Ctx is what a verb sees of the invocation.
type Ctx struct {
	Path   string // "hv group verb", the prefix of every stderr line
	JSON   bool
	Repo   string // the --repo value; resolve it with RepoPath
	Stdin  io.Reader
	Stderr io.Writer

	warnings []string
}

// Warn records a warning: it goes to stderr now and into the envelope.
func (c *Ctx) Warn(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	c.warnings = append(c.warnings, msg)
	fmt.Fprintf(c.Stderr, "%s: warning: %s\n", c.Path, msg)
}

// Root finds the project root: the nearest directory at or above the
// working directory that holds .hv/.
func (c *Ctx) Root() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if fi, err := os.Stat(filepath.Join(dir, ".hv")); err == nil && fi.IsDir() {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", Resolution("no .hv/ directory here or in any parent").WithHint("run: hv init")
		}
		dir = parent
	}
}

// RepoPath resolves --repo to the sub-repo's absolute path through
// .hv/repos.json (paths there are relative to the project root). It returns
// "" when --repo was not given, and a resolution error (exit 3) outside
// umbrella mode or for a name that is not registered.
func (c *Ctx) RepoPath() (string, error) {
	if c.Repo == "" {
		return "", nil
	}
	root, err := c.Root()
	if err != nil {
		return "", err
	}
	repos := map[string]string{}
	if reg, ok := fsio.LoadJSON(filepath.Join(root, ".hv", "repos.json"), nil).(*jsonx.Object); ok {
		list, _ := reg.Get("repos")
		entries, _ := list.([]any)
		for _, e := range entries {
			obj, ok := e.(*jsonx.Object)
			if !ok {
				continue
			}
			name, _ := obj.Get("name")
			rel, _ := obj.Get("path")
			n, _ := name.(string)
			r, _ := rel.(string)
			if n != "" && r != "" {
				repos[n] = r
			}
		}
	}
	if len(repos) == 0 {
		return "", Resolution("--repo %s: not in umbrella mode (no sub-repos in .hv/repos.json)", c.Repo)
	}
	rel, ok := repos[c.Repo]
	if !ok {
		return "", Resolution("--repo %s is not registered in .hv/repos.json", c.Repo)
	}
	p := rel
	if !filepath.IsAbs(p) {
		p = filepath.Join(root, p)
	}
	if real, err := filepath.EvalSymlinks(p); err == nil {
		return real, nil
	}
	return filepath.Clean(p), nil
}

// globals are the flags every verb accepts (docs/design/5.0-cli-conventions.md,
// Invocation): before the verb they are the only flags allowed, after it they
// are parsed together with the verb's own flags.
type globals struct {
	json, help, version bool
	cwd, repo           string
}

// register adds the globals to fs. preVerb adds --version and --repo, which
// before the verb are always accepted; after it, --repo only on repo verbs.
func (g *globals) register(fs *flag.FlagSet, preVerb, repo bool) {
	fs.BoolVar(&g.json, "json", false, "machine output: one JSON envelope on stdout")
	fs.BoolVar(&g.help, "h", false, "help")
	fs.BoolVar(&g.help, "help", false, "help")
	fs.StringVar(&g.cwd, "C", "", "run as if started in `dir`")
	fs.StringVar(&g.cwd, "cwd", "", "run as if started in `dir`")
	if preVerb || repo {
		fs.StringVar(&g.repo, "repo", "", "umbrella sub-repo `name`")
	}
	if preVerb {
		fs.BoolVar(&g.version, "version", false, "print the hv version")
	}
}

func (g *globals) merge(o globals) {
	g.json = g.json || o.json
	g.help = g.help || o.help
	g.version = g.version || o.version
	if o.cwd != "" {
		g.cwd = o.cwd
	}
	if o.repo != "" {
		g.repo = o.repo
	}
}

func newFlagSet(name string) *flag.FlagSet {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	return fs
}

// isFlag: a token starting with "-", except "-" alone (stdin).
func isFlag(tok string) bool { return len(tok) > 1 && tok[0] == '-' }

// parseFlag parses the flag at args[i] into fs and returns how many tokens
// it used. A value flag always takes the next token; booleans never do.
func parseFlag(fs *flag.FlagSet, args []string, i int) (int, error) {
	name := strings.TrimPrefix(strings.TrimPrefix(args[i], "-"), "-")
	name, val, hasVal := strings.Cut(name, "=")
	if name == "" || name[0] == '-' {
		return 0, Usage("bad flag syntax %q", args[i])
	}
	f := fs.Lookup(name)
	if f == nil {
		return 0, Usage("unknown flag %q", args[i])
	}
	used := 1
	if b, ok := f.Value.(interface{ IsBoolFlag() bool }); ok && b.IsBoolFlag() {
		if !hasVal {
			val = "true"
		}
	} else if !hasVal {
		if i+1 >= len(args) {
			return 0, Usage("flag --%s needs a value", name)
		}
		val, used = args[i+1], 2
	}
	if err := fs.Set(name, val); err != nil {
		return 0, Usage("invalid value %q for --%s", val, name)
	}
	return used, nil
}

// Main runs hv with the default command tree and returns the exit code.
func Main(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	return run(Tree(), args, stdin, stdout, stderr)
}

func run(root *Command, args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	// Until the arguments parse, an error answers in JSON if any token
	// before "--" is exactly --json.
	c := &Ctx{Path: "hv", Stdin: stdin, Stderr: stderr, JSON: containsJSON(args)}
	defer func() {
		if r := recover(); r != nil {
			code = fail(c, stdout, asError(fmt.Errorf("panic: %v", r)))
		}
	}()

	// Before the verb: command words and global flags only.
	var g globals
	pre := newFlagSet("hv")
	g.register(pre, true, false)
	cmd := root
	i := 0
	for ; i < len(args) && cmd.Verb == nil; i++ {
		tok := args[i]
		switch {
		case tok == "--":
			return fail(c, stdout, Usage("unexpected -- before the verb"))
		case isFlag(tok):
			n, err := parseFlag(pre, args, i)
			if err != nil {
				return fail(c, stdout, err)
			}
			i += n - 1
		default:
			sub := cmd.sub(tok)
			if sub == nil {
				return fail(c, stdout, Usage("unknown command %q", tok).WithHint("run: "+c.Path+" --help"))
			}
			cmd = sub
			c.Path += " " + cmd.Name
		}
	}
	if g.version && cmd == root {
		cmd = root.sub("version")
		c.Path = "hv version"
	}

	// After the verb: verb and global flags, mixed with positional args.
	var runVerb RunFunc
	var verbFlags *flag.FlagSet
	var positional []string
	if cmd.Verb != nil {
		verbFlags = newFlagSet(c.Path)
		runVerb = cmd.Verb(verbFlags)
		var post globals
		post.register(verbFlags, false, cmd.Repo)
		for ; i < len(args); i++ {
			tok := args[i]
			if tok == "--" {
				positional = append(positional, args[i+1:]...)
				break
			}
			if !isFlag(tok) {
				positional = append(positional, tok)
				continue
			}
			n, err := parseFlag(verbFlags, args, i)
			if err != nil {
				return fail(c, stdout, err)
			}
			i += n - 1
		}
		g.merge(post)
	}
	c.JSON = g.json

	if g.help {
		return ok(c, stdout, helpResult(c.Path, cmd, verbFlags))
	}
	if cmd.Verb == nil {
		if cmd == root {
			return fail(c, stdout, Usage("missing command").WithHint("run: hv --help"))
		}
		return fail(c, stdout, Usage("missing verb; one of: %s", strings.Join(cmd.subNames(), ", ")))
	}
	if g.repo != "" && !cmd.Repo {
		return fail(c, stdout, Usage("unknown flag \"--repo\""))
	}
	c.Repo = g.repo
	if g.cwd != "" {
		if err := os.Chdir(g.cwd); err != nil {
			return fail(c, stdout, Resolution("cannot use -C %s: %v", g.cwd, unwrapPathErr(err)))
		}
	}
	res, err := runVerb(c, positional)
	if err != nil {
		return failWith(c, stdout, err, res)
	}
	return ok(c, stdout, res)
}

// containsJSON lets a failed global-flag parse still answer in JSON.
func containsJSON(args []string) bool {
	for _, a := range args {
		if a == "--" {
			return false
		}
		if a == "--json" {
			return true
		}
	}
	return false
}

func unwrapPathErr(err error) error {
	var pe *os.PathError
	if errors.As(err, &pe) {
		return pe.Err
	}
	return err
}

func (cmd *Command) sub(name string) *Command {
	for _, s := range cmd.Subs {
		if s.Name == name {
			return s
		}
	}
	return nil
}

func (cmd *Command) subNames() []string {
	names := make([]string, 0, len(cmd.Subs))
	for _, s := range cmd.Subs {
		names = append(names, s.Name)
	}
	sort.Strings(names)
	return names
}

func ok(c *Ctx, stdout io.Writer, res Result) int {
	if !c.JSON {
		if res.Text != "" {
			fmt.Fprint(stdout, strings.TrimSuffix(res.Text, "\n")+"\n")
		}
		return ExitOK
	}
	env := jsonx.NewObject()
	env.Set("ok", true)
	data := res.Data
	if data == nil {
		data = jsonx.NewObject()
	}
	env.Set("data", data)
	if len(c.warnings) > 0 {
		env.Set("warnings", append([]string(nil), c.warnings...))
	}
	if err := writeEnvelope(stdout, env); err != nil {
		return fail(c, stdout, err)
	}
	return ExitOK
}

func fail(c *Ctx, stdout io.Writer, err error) int { return failWith(c, stdout, err, Result{}) }

// failWith reports err; res is kept only on exit 1 and 4, the codes whose
// failure may carry data.
func failWith(c *Ctx, stdout io.Writer, err error, res Result) int {
	e := asError(err)
	if e.Exit != ExitFailed && e.Exit != ExitRefused {
		res = Result{}
	}
	if !c.JSON && res.Text != "" {
		fmt.Fprint(stdout, strings.TrimSuffix(res.Text, "\n")+"\n")
	}
	fmt.Fprintf(c.Stderr, "%s: %s\n", c.Path, e.Message)
	if e.Hint != "" {
		fmt.Fprintf(c.Stderr, "hint: %s\n", e.Hint)
	}
	if c.JSON {
		eo := jsonx.NewObject()
		eo.Set("code", CodeName(e.Exit))
		eo.Set("exit", e.Exit)
		eo.Set("message", e.Message)
		if e.Hint != "" {
			eo.Set("hint", e.Hint)
		}
		env := jsonx.NewObject()
		env.Set("ok", false)
		env.Set("error", eo)
		if res.Data != nil {
			env.Set("data", res.Data)
		}
		if len(c.warnings) > 0 {
			env.Set("warnings", append([]string(nil), c.warnings...))
		}
		writeEnvelope(stdout, env)
	}
	return e.Exit
}

func writeEnvelope(w io.Writer, env *jsonx.Object) error {
	b, err := jsonx.MarshalCompact(env)
	if err != nil {
		return err
	}
	_, err = w.Write(append(b, '\n'))
	return err
}

// globalNames are left out of a verb's own flag list in help.
var globalNames = map[string]bool{"json": true, "h": true, "help": true, "C": true, "cwd": true, "repo": true, "version": true}

func helpResult(path string, cmd *Command, verbFlags *flag.FlagSet) Result {
	var b strings.Builder
	data := jsonx.NewObject()
	data.Set("command", path)
	data.Set("summary", cmd.Summary)
	fmt.Fprintf(&b, "%s: %s\n", path, cmd.Summary)
	if cmd.Subs != nil {
		subs := []any{}
		fmt.Fprintf(&b, "\nUsage: %s <command> [flags]\n\nCommands:\n", path)
		for _, name := range cmd.subNames() {
			s := cmd.sub(name)
			fmt.Fprintf(&b, "  %-12s %s\n", s.Name, s.Summary)
			so := jsonx.NewObject()
			so.Set("name", s.Name)
			so.Set("summary", s.Summary)
			subs = append(subs, so)
		}
		data.Set("commands", subs)
	}
	if verbFlags != nil {
		flags := []any{}
		verbFlags.VisitAll(func(f *flag.Flag) {
			if globalNames[f.Name] {
				return
			}
			if len(flags) == 0 {
				b.WriteString("\nFlags:\n")
			}
			fmt.Fprintf(&b, "  --%-14s %s\n", f.Name, f.Usage)
			fo := jsonx.NewObject()
			fo.Set("name", f.Name)
			fo.Set("usage", f.Usage)
			flags = append(flags, fo)
		})
		data.Set("flags", flags)
	}
	b.WriteString("\nGlobal flags: --json, -C/--cwd <dir>, --repo <name>, -h/--help\n")
	return Result{Data: data, Text: b.String()}
}
