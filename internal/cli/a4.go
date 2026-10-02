package cli

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/backlog"
	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pystr"
)

// The A4 item verbs: `hv id next` and `hv item create|field|complete|reopen|
// rm|shipped|ready|comment`. Shapes, flags and exits are the verb contract's
// (docs/design/5.0-verb-contract.md); the file backend does the work.

// newTracker builds the issue tracker the issue backend reads and writes
// through. The tracker adapter (A8, internal/tracker) is not ported, so issue
// mode stops here with exit 5 until it is.
var newTracker = func(root string, cfg any) (backlog.Tracker, error) {
	return nil, Unavailable("issue tracker adapter not ported yet (A8 internal/tracker)")
}

func a4Commands() []*Command {
	return append(a4ItemCommands(), a4bCommands()...)
}

func a4ItemCommands() []*Command {
	return []*Command{
		{Name: "id", Summary: "mint item and milestone IDs", Subs: []*Command{
			{Name: "next", Summary: "mint the next counter ID", Repo: true, Verb: a4IDNext},
		}},
		{Name: "item", Summary: "backlog items", Subs: []*Command{
			{Name: "create", Summary: "capture one item", Repo: true, Verb: a4Create},
			{Name: "field", Summary: "read and write item fields", Subs: []*Command{
				{Name: "get", Summary: "print one field of an item", Repo: true, Verb: a4FieldGet},
				{Name: "set", Summary: "set, replace or clear a field of an open item", Repo: true, Verb: a4FieldSet},
				{Name: "list", Summary: "every field of an item", Repo: true, Verb: a4FieldList},
			}},
			{Name: "complete", Summary: "close an item", Repo: true, Verb: a4Complete},
			{Name: "reopen", Summary: "restore a completed item", Repo: true, Verb: a4Reopen},
			{Name: "rm", Summary: "remove items with their cross-references and files", Repo: true, Verb: a4Rm},
			{Name: "shipped", Summary: "look for evidence that titles already shipped", Repo: true, Verb: a4Shipped},
			{Name: "ready", Summary: "is the item specified well enough to start", Repo: true, Verb: a4Ready},
			{Name: "comment", Summary: "item comments", Subs: []*Command{
				{Name: "add", Summary: "append a comment", Repo: true, Verb: a4CommentAdd},
				{Name: "list", Summary: "list comments", Repo: true, Verb: a4CommentList},
			}},
		}},
	}
}

// ---- shared helpers -------------------------------------------------------

func a4Obj(kv ...any) *jsonx.Object {
	o := jsonx.NewObject()
	for i := 0; i+1 < len(kv); i += 2 {
		o.Set(kv[i].(string), kv[i+1])
	}
	return o
}

// a4Args checks the positional count of a verb.
func a4Args(c *Ctx, args []string, min, max int, usage string) error {
	if len(args) < min || (max >= 0 && len(args) > max) {
		return Usage("%s", usage)
	}
	return nil
}

// a4Scope finds the project root and settles --repo: umbrella mode is not
// ported, so a valid scope stops here.
func a4Scope(c *Ctx) (string, error) {
	root, err := c.Root()
	if err != nil {
		return "", err
	}
	if c.Repo != "" {
		if _, err := c.RepoPath(); err != nil {
			return "", err
		}
		return "", Unavailable("umbrella mode not ported yet")
	}
	if backlog.IsUmbrella(root) {
		return "", Unavailable("umbrella mode not ported yet")
	}
	return root, nil
}

// a4Open selects the backlog backend from backlog.backend. A file-only verb
// under issues is refused (exit 4, backend) before the tracker is built.
func a4Open(root string, fileOnly bool, hint string) (backlog.Backend, error) {
	cfg := config.Load(filepath.Join(root, ".hv", "config.json"))
	name, err := config.Backend(cfg)
	if err != nil {
		// An invalid backlog.backend is a corrupt config (contract, shared definitions).
		return nil, &Error{Exit: ExitInternal, Message: err.Error()}
	}
	if name != "file" && fileOnly {
		return nil, &backlog.RefusedError{BlockedBy: "backend", Hint: hint, Err: backlog.ErrWrongBackend,
			Msg: `not available with backlog.backend "issues"`}
	}
	var tr backlog.Tracker
	if name != "file" {
		if tr, err = newTracker(root, cfg); err != nil {
			return nil, err
		}
	}
	return backlog.Open(root, cfg, tr)
}

// a4Fail maps a backlog error to a verb failure and, for a refusal, its
// failure data.
func a4Fail(err error) (Result, error) {
	var e *Error
	var ref *backlog.RefusedError
	var act *backlog.ActiveError
	var ex interface{ Exit() int }
	switch {
	case errors.As(err, &e):
		return Result{}, err
	case errors.As(err, &ex):
		return Result{}, &Error{Exit: ex.Exit(), Message: err.Error()}
	case errors.As(err, &ref):
		return Result{Data: a4Obj("blockedBy", ref.BlockedBy, "changed", false)},
			&Error{Exit: ExitRefused, Message: ref.Msg, Hint: ref.Hint}
	case errors.As(err, &act):
		return Result{Data: a4Obj("blockedBy", "active", "id", act.ID, "activeBranch", act.Branch, "changed", false)},
			&Error{Exit: ExitRefused, Message: act.Error(), Hint: "end the stream first: hv status rm " + act.Branch}
	case errors.Is(err, backlog.ErrWrongBackend):
		return Result{Data: a4Obj("blockedBy", "backend", "changed", false)}, Refused("%s", err.Error())
	case errors.Is(err, backlog.ErrNotFound):
		return Result{}, Resolution("%s", err.Error())
	case errors.Is(err, backlog.ErrInvalid):
		return Result{}, Usage("%s", err.Error())
	case errors.Is(err, backlog.ErrNotPorted):
		return Result{}, &Error{Exit: ExitNotImplemented, Message: err.Error()}
	}
	return Result{}, err
}

// a4FailRead is a4Fail for a read-only verb: the conventions forbid exit 4
// there, so a refusal (the wrong backend) becomes exit 1 with the same data.
func a4FailRead(err error) (Result, error) {
	res, ferr := a4Fail(err)
	var e *Error
	if errors.As(ferr, &e) && e.Exit == ExitRefused {
		e.Exit = ExitFailed
	}
	return res, ferr
}

func a4Type(id string) string {
	if id != "" && strings.Contains(backlog.ItemLetters, id[:1]) {
		return id[:1]
	}
	return ""
}

func a4Today() string { return time.Now().Format("2006-01-02") }

// a4Given is the set of flags the parser saw, by name.
func a4Given(fs *flag.FlagSet) map[string]bool {
	set := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { set[f.Name] = true })
	return set
}

// a4ReadInput reads a --body-file style path; "-" is stdin.
func a4ReadInput(c *Ctx, path string) ([]byte, error) {
	if path == "-" {
		return io.ReadAll(c.Stdin)
	}
	return os.ReadFile(path)
}

// a4ReadErr is exit 3: a named input that cannot be read did not resolve.
func a4ReadErr(flagName, path string, err error) error {
	return Resolution("cannot read --%s: %s: %s", flagName, unwrapPathErr(err), path)
}

// ---- id next --------------------------------------------------------------

var a4Counters = []string{"bugs", "features", "tasks", "milestones"}

func a4IDNext(fs *flag.FlagSet) RunFunc {
	kind := fs.String("kind", "", "bugs|features|tasks|milestones")
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 0, 0, "id next takes no positional arguments"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		if !a4In(a4Counters, *kind) {
			return Result{}, Usage("--kind must be bugs|features|tasks|milestones")
		}
		be, err := a4Open(root, true, "IDs are issue numbers; capture creates the issue")
		if err != nil {
			return a4Fail(err)
		}
		id, err := be.(*backlog.File).NextID(*kind)
		if err != nil {
			return a4Fail(err)
		}
		return Result{Data: a4Obj("kind", *kind, "id", id, "changed", true), Text: id}, nil
	}
}

func a4In(xs []string, x string) bool {
	for _, y := range xs {
		if x == y {
			return true
		}
	}
	return false
}

// ---- item create ----------------------------------------------------------

var (
	a4ItemKinds = []string{"bugs", "features", "tasks"}
	a4Sections  = map[string]string{"bugs": "## Bugs", "features": "## Features", "tasks": "## Tasks"}
	a4BulletID  = regexp.MustCompile(`\*\*\[([A-Z]\p{Nd}+)\]`)
)

func a4Create(fs *flag.FlagSet) RunFunc {
	kind := fs.String("kind", "", "bugs|features|tasks")
	title := fs.String("title", "", "item title")
	tag := fs.String("tag", "", "P0..P3 (bugs) or Major|Minor|Cosmetic (features)")
	desc := fs.String("desc", "", "one-line description")
	bodyFile := fs.String("body-file", "", "detail file content, path or - for stdin")
	rawFile := fs.String("raw-file", "", "a preformatted bullet to append verbatim, path or - for stdin")
	named := map[string]*string{}
	for _, n := range []string{"related", "milestone", "repos", "subsystem", "captured"} {
		named[n] = fs.String(n, "", n+" field")
	}
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 0, 0, "item create takes no positional arguments"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		given := a4Given(fs)
		if !a4In(a4ItemKinds, *kind) {
			return Result{}, Usage("--kind must be bugs|features|tasks")
		}
		if given["raw-file"] {
			for n := range given {
				if n != "kind" && n != "raw-file" && !globalNames[n] {
					return Result{}, Usage("--raw-file takes only --kind")
				}
			}
			raw, err := a4ReadInput(c, *rawFile)
			if err != nil {
				return Result{}, a4ReadErr("raw-file", *rawFile, err)
			}
			entry := strings.TrimRight(a4Newlines.Replace(string(raw)), "\n")
			m := a4BulletID.FindStringSubmatch(entry)
			if m == nil {
				return Result{}, Usage("--raw-file bullet needs a **[ID]")
			}
			be, err := a4Open(root, true, "--raw-file appends to BACKLOG.md; use item create --title")
			if err != nil {
				return a4Fail(err)
			}
			if err := be.(*backlog.File).Append(a4Sections[*kind], entry); err != nil {
				return a4Fail(err)
			}
			typ, _ := backlog.TypeByKind(*kind)
			return Result{Data: a4Obj("id", m[1], "type", typ.Letter, "kind", *kind, "changed", true), Text: m[1]}, nil
		}
		if *title == "" {
			return Result{}, Usage("--title is required")
		}
		in := backlog.CreateInput{Kind: *kind, Title: *title, Tag: *tag, Desc: *desc}
		for _, n := range backlog.CreateFields {
			key := strings.ToLower(n)
			if given[key] && pystr.Strip(*named[key]) == "" {
				return Result{}, Usage("--%s needs a value", key)
			}
			if v := *named[key]; v != "" {
				in.Fields = append(in.Fields, backlog.Field{Name: n, Value: v})
			}
		}
		if *bodyFile != "" {
			body, err := a4ReadInput(c, *bodyFile)
			if err != nil {
				return Result{}, a4ReadErr("body-file", *bodyFile, err)
			}
			in.Body, in.HasBody = body, true
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		res, err := be.Create(in)
		if err != nil {
			return a4Fail(err)
		}
		data := a4Obj("id", res.ID, "type", res.Type, "kind", *kind)
		if res.Detail != "" {
			data.Set("detail", res.Detail)
		}
		data.Set("changed", true)
		return Result{Data: data, Text: res.ID}, nil
	}
}

// ---- item field -----------------------------------------------------------

var (
	a4GetFields = []string{"title", "detail", "related", "milestone", "repos", "subsystem", "since", "reason", "note"}
	a4SetFields = backlog.SettableFields
)

func a4FieldValue(it *backlog.Item, name string) string {
	switch name {
	case "title":
		// The old helpers' title stops at the first "." (FindOrigin); issue
		// mode keeps the full title, as hv-todo-field did there.
		if it.Number == 0 {
			_, t, _ := backlog.FindOrigin("- "+it.Line, it.ID)
			return t
		}
		return it.Title
	case "reason":
		return it.Reason
	case "note":
		return it.Note
	}
	return it.Fields.Get(name)
}

// a4FieldName reads --name and checks it against allowed.
func a4FieldName(name string, allowed []string, what string) error {
	if name == "" {
		return Usage("--name is required")
	}
	if !a4In(allowed, name) {
		return Usage("%s field %s; pick one of %s", what, name, strings.Join(allowed, ", "))
	}
	return nil
}

func a4FieldGet(fs *flag.FlagSet) RunFunc {
	name := fs.String("name", "", strings.Join(a4GetFields, "|"))
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item field get takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		if err := a4FieldName(*name, a4GetFields, "unknown"); err != nil {
			return Result{}, err
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		it, err := be.Get(args[0])
		if err != nil {
			return a4Fail(err)
		}
		v := a4FieldValue(it, *name)
		return Result{Data: a4Obj("id", it.ID, "type", it.Type, "field", *name, "value", v), Text: v}, nil
	}
}

func a4FieldList(fs *flag.FlagSet) RunFunc {
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item field list takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		it, err := be.Get(args[0])
		if err != nil {
			return a4Fail(err)
		}
		fields := jsonx.NewObject()
		for _, n := range a4GetFields {
			fields.Set(n, a4FieldValue(it, n))
		}
		text, _ := jsonx.MarshalCompact(fields)
		return Result{Data: a4Obj("id", it.ID, "type", it.Type, "fields", fields), Text: string(text)}, nil
	}
}

func a4FieldSet(fs *flag.FlagSet) RunFunc {
	name := fs.String("name", "", strings.Join(a4SetFields, "|"))
	value := fs.String("value", "", "new value; empty clears the field")
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item field set takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		if err := a4FieldName(*name, a4SetFields, "unknown or read-only"); err != nil {
			return Result{}, err
		}
		if !a4Given(fs)["value"] {
			return Result{}, Usage("--value is required (--value '' clears the field)")
		}
		be, err := a4Open(root, *name == "detail", "--name detail points at a file; issues have a body instead")
		if err != nil {
			return a4Fail(err)
		}
		changed, err := be.SetField(args[0], *name, *value)
		if err != nil {
			return a4Fail(err)
		}
		return Result{Data: a4Obj("id", args[0], "type", a4Type(args[0]), "field", *name, "value", *value, "changed", changed),
			Text: fmt.Sprintf("%s %s: %s", args[0], *name, *value)}, nil
	}
}

// ---- item complete / reopen -----------------------------------------------

func a4Complete(fs *flag.FlagSet) RunFunc {
	commit := fs.String("commit", "", "commit hash for the Done line; default HEAD")
	reason := fs.String("reason", "done", "done|handed-off|blocked|dropped")
	note := fs.String("note", "", "closure note")
	noProof := fs.Bool("no-proof", false, "skip the proof gate")
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item complete takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		if !a4In(backlog.ClosureReasons, *reason) {
			return Result{}, Usage("--reason must be done|handed-off|blocked|dropped")
		}
		hash := *commit
		if hash == "" {
			out, gerr := exec.Command("git", "log", "-1", "--format=%h").Output()
			if hash = pystr.Strip(string(out)); gerr != nil || hash == "" {
				return Result{}, Unavailable("git has no HEAD to default --commit").WithHint("pass --commit <hash>")
			}
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		changed, err := be.Complete(args[0], backlog.CompleteInput{
			Commit: hash, Date: a4Today(), Reason: *reason,
			Note: strings.ReplaceAll(*note, "\n", " "), NoProof: *noProof,
		})
		if err != nil {
			res, e := a4Fail(err)
			if errors.Is(err, backlog.ErrProofMissing) {
				e.(*Error).Hint = "record proof with `hv proof add`, or pass --no-proof"
			}
			return res, e
		}
		return Result{Data: a4Obj("id", args[0], "type", a4Type(args[0]), "reason", *reason, "commit", hash, "changed", changed),
			Text: fmt.Sprintf("completed %s (%s) at %s", args[0], *reason, hash)}, nil
	}
}

func a4Reopen(fs *flag.FlagSet) RunFunc {
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item reopen takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		changed, err := be.Reopen(args[0])
		if err != nil {
			return a4Fail(err)
		}
		text := "reopened " + args[0]
		if !changed {
			text = args[0] + " is already active"
		}
		return Result{Data: a4Obj("id", args[0], "type", a4Type(args[0]), "changed", changed), Text: text}, nil
	}
}

// ---- item rm --------------------------------------------------------------

func a4Rm(fs *flag.FlagSet) RunFunc {
	scrub := fs.Bool("scrub-archive", false, "also remove the entries from ARCHIVE.md")
	apply := fs.Bool("apply", false, "remove for real; without it only a plan is shown")
	return func(c *Ctx, args []string) (Result, error) {
		var ids []string
		seen := map[string]bool{}
		for _, a := range args {
			for _, p := range strings.Split(a, ",") {
				if p = pystr.Strip(p); p != "" && !seen[p] {
					seen[p] = true
					ids = append(ids, p)
				}
			}
		}
		if len(ids) == 0 {
			return Result{}, Usage("item rm needs at least one item ID")
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		be, err := a4Open(root, true, "hv item complete <ID> --reason dropped")
		if err != nil {
			return a4Fail(err)
		}
		res, err := be.(*backlog.File).Remove(ids, *scrub, *apply)
		if err != nil {
			return a4Fail(err)
		}
		items := []any{}
		var lines []string
		for _, it := range res.Items {
			o := a4Obj("id", it.ID, "type", it.Type, "todoEntry", it.TodoEntry, "crossRefs", it.CrossRefs)
			if it.DetailFile != "" {
				o.Set("detailFile", it.DetailFile)
			}
			o.Set("planFiles", it.PlanFiles)
			o.Set("archive", it.Archive)
			if it.ActiveBranch != "" {
				o.Set("activeBranch", it.ActiveBranch)
			}
			items = append(items, o)
			lines = append(lines, a4RmLine(it, res.Applied))
		}
		if !res.Applied {
			c.Warn("preview only; pass --apply")
		}
		return Result{Data: a4Obj("applied", res.Applied, "items", items, "changed", res.Applied), Text: strings.Join(lines, "\n")}, nil
	}
}

func a4RmLine(it backlog.RmItem, applied bool) string {
	var parts []string
	if it.TodoEntry {
		parts = append(parts, "TODO entry")
	}
	if it.CrossRefs > 0 {
		parts = append(parts, fmt.Sprintf("%d cross-reference(s)", it.CrossRefs))
	}
	if it.DetailFile != "" {
		parts = append(parts, "detail file")
	}
	if n := len(it.PlanFiles); n > 0 {
		parts = append(parts, fmt.Sprintf("%d plan file(s)", n))
	}
	if it.Archive && it.Scrub {
		parts = append(parts, "ARCHIVE entry")
	}
	verb := "would remove"
	if applied {
		verb = "removed"
	}
	s := fmt.Sprintf("%s: %s %s", it.ID, verb, strings.Join(parts, ", "))
	if it.ActiveBranch != "" {
		s += " (active on " + it.ActiveBranch + ")"
	}
	return s
}

// ---- item shipped ---------------------------------------------------------

func a4Shipped(fs *flag.FlagSet) RunFunc {
	return func(c *Ctx, args []string) (Result, error) {
		var titles []string
		for _, a := range args {
			if pystr.Strip(a) != "" {
				titles = append(titles, a)
			}
		}
		if len(titles) == 0 {
			return Result{}, Usage("item shipped needs at least one title")
		}
		if _, err := a4Scope(c); err != nil {
			return Result{}, err
		}
		dir, err := os.Getwd()
		if err != nil {
			return Result{}, err
		}
		audits := backlog.Audit(dir, titles)
		found := false
		out := []any{}
		var text strings.Builder
		for _, a := range audits {
			hits := []any{}
			for _, h := range a.Hits {
				o := a4Obj("level", h.Level)
				switch h.Level {
				case backlog.HitPath:
					o.Set("token", h.Token)
					o.Set("path", h.Path)
				default:
					o.Set("hash", h.Hash)
					o.Set("subject", h.Subject)
					o.Set("tokens", h.Tokens)
				}
				hits = append(hits, o)
			}
			if len(a.Hits) > 0 {
				found = true
				fmt.Fprintf(&text, "=== %s ===\n", a.Title)
				for _, h := range a.Hits {
					switch h.Level {
					case backlog.HitStrong:
						fmt.Fprintf(&text, "  [STRONG] %s %s  (tokens: %s)\n", h.Hash, h.Subject, strings.Join(h.Tokens, ", "))
					case backlog.HitMedium:
						fmt.Fprintf(&text, "  [MEDIUM] %s %s  (tokens: %s)\n", h.Hash, h.Subject, strings.Join(h.Tokens, ", "))
					default:
						fmt.Fprintf(&text, "  [PATH]   %s → %s\n", h.Token, h.Path)
					}
				}
				text.WriteString("\n")
			}
			out = append(out, a4Obj("title", a.Title, "hits", hits))
		}
		res := Result{Data: a4Obj("found", found, "titles", out), Text: strings.TrimRight(text.String(), "\n")}
		if !found {
			res.Text = "no ship evidence found"
			return res, Failed("no ship evidence found")
		}
		return res, nil
	}
}

// ---- item ready -----------------------------------------------------------

func a4Ready(fs *flag.FlagSet) RunFunc {
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item ready takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		reasons, err := be.Ready(args[0])
		if err != nil {
			return a4Fail(err)
		}
		if reasons == nil {
			reasons = []string{}
		}
		ready := len(reasons) == 0
		res := Result{Data: a4Obj("id", args[0], "type", a4Type(args[0]), "ready", ready, "reasons", reasons)}
		if ready {
			res.Text = args[0] + " is ready"
			return res, nil
		}
		res.Text = strings.Join(reasons, "\n")
		return res, Failed("%s is not ready: %s", args[0], strings.Join(reasons, "; "))
	}
}

// ---- item comment ---------------------------------------------------------

func a4CommentAdd(fs *flag.FlagSet) RunFunc {
	kind := fs.String("kind", "", strings.Join(backlog.CommentKinds, "|"))
	bodyFile := fs.String("body-file", "", "comment text, path or - for stdin")
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item comment add takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		if !a4In(backlog.CommentKinds, *kind) {
			return Result{}, Usage("--kind must be %s", strings.Join(backlog.CommentKinds, "|"))
		}
		if *bodyFile == "" {
			return Result{}, Usage("--body-file is required")
		}
		raw, err := a4ReadInput(c, *bodyFile)
		if err != nil {
			return Result{}, a4ReadErr("body-file", *bodyFile, err)
		}
		text := a4Decode(raw)
		if pystr.Strip(text) == "" {
			return Result{}, Usage("empty comment body")
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		id, err := be.AddComment(args[0], *kind, text)
		if err != nil {
			return a4Fail(err)
		}
		data := a4Obj("id", args[0], "type", a4Type(args[0]), "kind", *kind)
		if id != "" {
			data.Set("commentId", id)
		}
		data.Set("changed", true)
		return Result{Data: data, Text: fmt.Sprintf("commented on %s (%s)", args[0], *kind)}, nil
	}
}

// a4Decode is bytes.decode(errors="replace"): every invalid byte becomes U+FFFD.
func a4Decode(b []byte) string { return string([]rune(string(b))) }

func a4CommentList(fs *flag.FlagSet) RunFunc {
	kind := fs.String("kind", "", strings.Join(backlog.CommentKinds, "|")+"; default all")
	return func(c *Ctx, args []string) (Result, error) {
		if err := a4Args(c, args, 1, 1, "item comment list takes one item ID"); err != nil {
			return Result{}, err
		}
		root, err := a4Scope(c)
		if err != nil {
			return Result{}, err
		}
		if *kind != "" && !a4In(backlog.CommentKinds, *kind) {
			return Result{}, Usage("--kind must be %s", strings.Join(backlog.CommentKinds, "|"))
		}
		be, err := a4Open(root, false, "")
		if err != nil {
			return a4Fail(err)
		}
		rows, err := be.Comments(args[0], *kind)
		if err != nil {
			return a4Fail(err)
		}
		list := []any{}
		var lines []string
		for _, r := range rows {
			list = append(list, a4Obj("who", r.Who, "kind", r.Kind, "text", r.Text))
			first, rest, _ := strings.Cut(r.Text, "\n")
			who := r.Who
			if who == "" {
				who = "?"
			}
			lines = append(lines, fmt.Sprintf("- %s · %s · %s", who, r.Kind, first))
			if rest != "" || strings.Contains(r.Text, "\n") {
				for _, l := range strings.Split(rest, "\n") {
					if pystr.Strip(l) != "" {
						lines = append(lines, "  "+l)
					} else {
						lines = append(lines, "")
					}
				}
			}
		}
		return Result{Data: a4Obj("id", args[0], "type", a4Type(args[0]), "comments", list), Text: strings.Join(lines, "\n")}, nil
	}
}

// a4Newlines applies read_text's universal newlines to text read from stdin.
var a4Newlines = strings.NewReplacer("\r\n", "\n", "\r", "\n")
