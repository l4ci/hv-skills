// Package cli is the hv command dispatcher. It owns the global conventions
// in docs/design/5.0-cli-conventions.md (global flags, the --json envelope,
// the stderr format and the exit codes); verbs return data or an *Error and
// never print those parts themselves.
package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Command is a group (Subs) or a verb (Run) in the hv tree.
type Command struct {
	Name    string
	Summary string
	// Repo marks a verb that accepts the global --repo scope.
	Repo bool
	Run  func(c *Ctx, args []string) (Result, error)
	Subs []*Command
}

// Result is a verb's success output: Data goes into the --json envelope,
// Text is printed otherwise. Data nil means {}.
type Result struct {
	Data any
	Text string
}

// Ctx is what a verb sees of the invocation.
type Ctx struct {
	Path   string // "hv group verb", the prefix of every stderr line
	JSON   bool
	Repo   string
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
			return "", NotFound("no .hv/ directory here or in any parent").WithHint("run: hv init")
		}
		dir = parent
	}
}

// globals are the flags every verb accepts, anywhere before "--".
type globals struct {
	json, help, version bool
	cwd, repo           string
}

func parseGlobals(args []string) (globals, []string, error) {
	var g globals
	var rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			rest = append(rest, args[i:]...)
			break
		}
		name, val, hasVal := strings.Cut(a, "=")
		switch name {
		case "--json", "--help", "-h", "--version":
			if hasVal {
				return g, nil, Usage("%s takes no value", name)
			}
			switch name {
			case "--json":
				g.json = true
			case "--version":
				g.version = true
			default:
				g.help = true
			}
		case "-C", "--cwd", "--repo":
			if !hasVal {
				if i+1 >= len(args) {
					return g, nil, Usage("%s needs a value", name)
				}
				i++
				val = args[i]
			}
			if name == "--repo" {
				g.repo = val
			} else {
				g.cwd = val
			}
		default:
			rest = append(rest, a)
		}
	}
	return g, rest, nil
}

// Main runs hv with the default command tree and returns the exit code.
func Main(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	return run(Tree(), args, stdin, stdout, stderr)
}

func run(root *Command, args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	c := &Ctx{Path: "hv", Stdin: stdin, Stderr: stderr}
	g, rest, err := parseGlobals(args)
	c.JSON = g.json || containsJSON(args)
	defer func() {
		if r := recover(); r != nil {
			code = fail(c, stdout, asError(fmt.Errorf("panic: %v", r)))
		}
	}()
	if err != nil {
		return fail(c, stdout, err)
	}
	c.Repo = g.repo
	if g.version {
		rest = append([]string{"version"}, rest...)
	}
	if g.cwd != "" {
		if err := os.Chdir(g.cwd); err != nil {
			return fail(c, stdout, NotFound("cannot use -C %s: %v", g.cwd, unwrapPathErr(err)))
		}
	}

	cmd := root
	for len(rest) > 0 && cmd.Subs != nil {
		sub := cmd.sub(rest[0])
		if sub == nil {
			if strings.HasPrefix(rest[0], "-") {
				break
			}
			return fail(c, stdout, Usage("unknown command %q", rest[0]).WithHint("run: "+c.Path+" --help"))
		}
		cmd, rest = sub, rest[1:]
		c.Path += " " + cmd.Name
	}
	if g.help {
		return ok(c, stdout, helpResult(c.Path, cmd))
	}
	if cmd.Run == nil {
		if len(rest) > 0 {
			return fail(c, stdout, Usage("unknown flag %q", rest[0]))
		}
		if cmd == root {
			return fail(c, stdout, Usage("missing command").WithHint("run: hv --help"))
		}
		return fail(c, stdout, Usage("missing verb; one of: %s", strings.Join(cmd.subNames(), ", ")))
	}
	if c.Repo != "" && !cmd.Repo {
		return fail(c, stdout, Usage("--repo is not supported here"))
	}
	res, err := cmd.Run(c, rest)
	if err != nil {
		return fail(c, stdout, err)
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

func fail(c *Ctx, stdout io.Writer, err error) int {
	e := asError(err)
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

func helpResult(path string, cmd *Command) Result {
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
	b.WriteString("\nGlobal flags: --json, -C/--cwd <dir>, --repo <name>, -h/--help\n")
	return Result{Data: data, Text: b.String()}
}
