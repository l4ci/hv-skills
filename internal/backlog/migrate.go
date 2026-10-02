package backlog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/frontmatter"
	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pystr"
	"github.com/l4ci/hv-skills/v5/internal/repos"
	"github.com/l4ci/hv-skills/v5/internal/tracker"
)

// `hv migrate issues` (bin/hv-migrate-issues): move a file-backend project's
// open backlog and its planned or active milestones onto the issue tracker.
// The map .hv/issue-map.json is written after every successful write, so a
// run that stops (a tracker error, a rate limit, --limit) resumes from it.

// Migration refusals; the verb maps them to exits 3 and 4.
var (
	// ErrNothingToMigrate: .hv/BACKLOG.md does not exist.
	ErrNothingToMigrate = errors.New("nothing to migrate")
	// ErrUmbrellaMigrate: .hv/repos.json registers sub-repos.
	ErrUmbrellaMigrate = errors.New("umbrella mode: migrate each sub-repo separately")
	// ErrBadMap: .hv/issue-map.json is valid JSON but not an object.
	ErrBadMap = errors.New("issue-map.json is not a JSON object")
)

// MigrateTracker is the part of tracker.Adapter the migration calls: the
// issue backend's subset plus the native milestone calls.
type MigrateTracker interface {
	Tracker
	Milestones(ctx context.Context, state string) ([]tracker.Milestone, error)
	CreateMilestone(ctx context.Context, title, description string) (int, error)
	EditMilestone(ctx context.Context, number int, e tracker.MilestoneEdit) error
}

// MigrateOptions are the inputs of one run.
type MigrateOptions struct {
	Root  string // the project root, the directory that holds .hv/
	Apply bool   // false only reports what it would do
	Limit int    // create at most this many items; negative is no limit
	Cfg   any    // loaded config
	// Tracker builds the forge adapter on first use. A preview never calls it.
	Tracker func() (MigrateTracker, error)
	Sleep   func(time.Duration) // the issues.bulkPaceMs pause; nil is time.Sleep
	Warn    func(string)        // notices (dropped tags and milestones, duplicate tracking issues)
	Today   func() string       // YYYY-MM-DD; nil is the local date
}

// MigrateOp is one planned or run operation: Action is the first word of the
// old helper's output line, Text the rest.
type MigrateOp struct{ Action, Text string }

// MigrateResult is what a run did. It is returned with the error too, so a
// failed run still reports its progress.
type MigrateResult struct {
	Lines    []string // the old helper's stdout, line by line
	Ops      []MigrateOp
	Map      *jsonx.Object // preview: the would-be map; apply: .hv/issue-map.json afterwards
	Migrated int           // items with an issue in .hv/issue-map.json
	Total    int           // open items found
	Changed  bool          // the map or BACKLOG.md was written
	Done     bool          // apply only: every item and milestone exists and BACKLOG.md is frozen
}

type migrator struct {
	o      MigrateOptions
	ctx    context.Context
	apply  bool
	items  []*migItem
	ms     []*migMilestone
	msIDs  map[string]bool
	imap   *jsonx.Object
	mapRel string
	res    *MigrateResult

	tr      MigrateTracker
	be      *Issues
	doneOps int
	pending int
	created int
	msCache map[string]bool
}

var (
	migItemKey   = regexp.MustCompile(`\A[` + ItemLetters + `]\p{Nd}+\z`)
	msTitleRe    = regexp.MustCompile(`\A(M\p{Nd}+)`)
	frontmatterM = regexp.MustCompile(`(?s)\A---\n(.*?)\n---[ \t]*(?:\n|\z)`)
	fmIDRe       = regexp.MustCompile(`(?m)^id:[ \t]*(\S+)`)
	fmDependsRe  = regexp.MustCompile(`(?m)^depends:[ \t]*(.*)$`)
)

// frozenPrefix starts the banner a finished migration puts on BACKLOG.md.
const frozenPrefix = "> Frozen:"

const msStatusPrefix = "status:"

var msStatuses = []string{"planned", "active", "shipped", "archived"}

// MigrateIssues runs the migration. The error is ErrNothingToMigrate,
// ErrUmbrellaMigrate, ErrBadMap, a *tracker.Error when the forge stopped the
// run (the map keeps the progress), or another failure of a write; the result
// is non-nil whenever a run got as far as planning.
func MigrateIssues(o MigrateOptions) (*MigrateResult, error) {
	if o.Sleep == nil {
		o.Sleep = time.Sleep
	}
	if o.Warn == nil {
		o.Warn = func(string) {}
	}
	if o.Today == nil {
		o.Today = func() string { return time.Now().Format("2006-01-02") }
	}
	hv := filepath.Join(o.Root, ".hv")
	backlogPath := filepath.Join(hv, "BACKLOG.md")
	text, err := fsio.ReadText(backlogPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("%w: .hv/BACKLOG.md not found", ErrNothingToMigrate)
		}
		return nil, err
	}
	if len(repos.Load(o.Root)) > 0 {
		return nil, ErrUmbrellaMigrate
	}
	m := &migrator{o: o, ctx: context.Background(), apply: o.Apply, msCache: map[string]bool{},
		mapRel: filepath.Join(hv, "issue-map.json"), res: &MigrateResult{}}
	m.items = planItems(o.Root, text, o.Warn)
	m.ms = planMilestones(o.Root)
	m.msIDs = map[string]bool{}
	for _, ms := range m.ms {
		m.msIDs[ms.id] = true
	}
	m.res.Total = len(m.items)
	m.imap = jsonx.NewObject()
	if _, statErr := os.Stat(m.mapRel); statErr == nil {
		switch v := fsio.LoadJSON(m.mapRel, jsonx.NewObject()).(type) {
		case *jsonx.Object:
			m.imap = v
		default:
			return m.res, ErrBadMap
		}
	}
	before := m.state()
	if o.Apply {
		defer func() { m.res.Changed = m.state() != before }()
	}

	complete, runErr := m.run()
	var te *tracker.Error
	if runErr != nil && !errors.As(runErr, &te) {
		return m.finish(), runErr
	}
	if te != nil {
		migrated := 0
		for _, it := range m.items {
			if m.entryID(it.id) != "" {
				migrated++
			}
		}
		if te.Kind == tracker.KindRateLimited {
			m.say(fmt.Sprintf("rate limited: %d of %d items migrated; the map is saved in .hv/issue-map.json", migrated, len(m.items)))
			m.say("re-run to continue")
		} else {
			m.say("stopped on a tracker error; the map is saved in .hv/issue-map.json; fix the cause and re-run to continue")
		}
	}
	if !m.apply {
		m.say("would-be map:")
		shown := jsonx.NewObject()
		inItems := map[string]bool{}
		for _, it := range m.items {
			inItems[it.id] = true
		}
		for _, k := range m.imap.Keys() {
			if !inItems[k] && !m.msIDs[k] {
				continue
			}
			e, _ := m.imap.Get(k)
			eo, _ := e.(*jsonx.Object)
			row := jsonx.NewObject()
			for _, f := range []string{"id", "number", "url"} {
				if eo != nil {
					if v, ok := eo.Get(f); ok {
						row.Set(f, v)
						continue
					}
				}
				row.Set(f, "")
			}
			shown.Set(k, row)
		}
		b, _ := jsonx.Marshal(shown)
		m.say(string(b))
		m.res.Map = shown
		m.finish()
		return m.res, nil
	}
	if te != nil {
		m.finish()
		return m.res, runErr
	}
	if !complete {
		m.say(fmt.Sprintf("%d items remaining; notes, plans and Related rewrites run once every item exists. re-run to continue", m.pending))
		return m.finish(), nil
	}
	if !strings.HasPrefix(strings.TrimLeftFunc(text, pystr.IsSpace), frozenPrefix) {
		banner := fmt.Sprintf("%s this backlog moved to the issue tracker on %s (see .hv/issue-map.json). Edit issues, not this file.", frozenPrefix, o.Today())
		if err := fsio.WriteFileAtomic(backlogPath, []byte(banner+"\n\n"+text)); err != nil {
			return m.finish(), err
		}
		m.say("froze .hv/BACKLOG.md")
	}
	m.say("Next: /hv-config backlog.backend=issues")
	m.res.Done = true
	return m.finish(), nil
}

// finish loads the map as it is on disk and counts what it holds.
func (m *migrator) finish() *MigrateResult {
	disk, _ := fsio.LoadJSON(m.mapRel, jsonx.NewObject()).(*jsonx.Object)
	if disk == nil {
		disk = jsonx.NewObject()
	}
	if m.res.Map == nil {
		m.res.Map = disk
	}
	m.res.Migrated = 0
	for _, k := range disk.Keys() {
		if !migItemKey.MatchString(k) {
			continue
		}
		if e, ok := disk.Get(k); ok {
			if eo, ok := e.(*jsonx.Object); ok {
				if id, _ := eo.Get("id"); truthy(id) {
					m.res.Migrated++
				}
			}
		}
	}
	return m.res
}

func truthy(v any) bool {
	switch t := v.(type) {
	case nil:
		return false
	case string:
		return t != ""
	case bool:
		return t
	}
	return true
}

// state is the map file and BACKLOG.md as bytes, to tell whether a run wrote.
func (m *migrator) state() string {
	a, _ := os.ReadFile(m.mapRel)
	b, _ := os.ReadFile(filepath.Join(m.o.Root, ".hv", "BACKLOG.md"))
	return string(a) + "\x00" + string(b)
}

var opActions = []struct{ prefix, action string }{
	{"create milestone ", "create-milestone"}, {"create issue ", "create-issue"},
	{"note ", "note"}, {"rewrite ", "rewrite"}, {"skip ", "skip"}, {"set ", "set"},
}

// say records one output line of the old helper.
func (m *migrator) say(line string) {
	m.res.Lines = append(m.res.Lines, line)
	if strings.HasPrefix(line, "would-be map:") {
		return
	}
	for _, p := range opActions {
		if strings.HasPrefix(line, p.prefix) {
			m.res.Ops = append(m.res.Ops, MigrateOp{p.action, strings.TrimPrefix(line, p.prefix)})
			return
		}
	}
}

// op prints (preview) or runs (apply, paced) one operation.
func (m *migrator) op(desc string, fn func() error) error {
	if !m.apply {
		m.say(desc)
		return nil
	}
	if m.doneOps > 0 {
		if d := m.pace(); d > 0 {
			m.o.Sleep(d)
		}
	}
	m.doneOps++
	m.say(desc)
	return fn()
}

// pace is issues.bulkPaceMs as a duration: int() of the value, at least 0.
func (m *migrator) pace() time.Duration {
	v, _ := config.Value(m.o.Cfg, "issues.bulkPaceMs")
	var ms float64
	switch t := v.(type) {
	case bool:
		if t {
			ms = 1
		}
	case string:
		f, err := strconv.ParseFloat(pystr.Strip(t), 64)
		if err == nil {
			ms = f
		}
	case interface{ String() string }:
		f, err := strconv.ParseFloat(t.String(), 64)
		if err == nil {
			ms = f
		}
	}
	if ms < 1 {
		return 0
	}
	return time.Duration(int64(ms)) * time.Millisecond
}

// backend is the issue backend over the lazily built tracker.
func (m *migrator) backend() (*Issues, error) {
	if m.be != nil {
		return m.be, nil
	}
	tr, err := m.o.Tracker()
	if err != nil {
		return nil, err
	}
	m.tr = tr
	m.be = &Issues{Cfg: m.o.Cfg, Tracker: tr, Ctx: m.ctx}
	return m.be, nil
}

// ---- the map ------------------------------------------------------------------

func (m *migrator) entry(old string) *jsonx.Object {
	if v, ok := m.imap.Get(old); ok {
		if e, ok := v.(*jsonx.Object); ok {
			return e
		}
	}
	return nil
}

// entryID is the issue ID the map holds for old, or "".
func (m *migrator) entryID(old string) string {
	if e := m.entry(old); e != nil {
		if v, ok := e.Get("id"); ok {
			if s, ok := v.(string); ok {
				return s
			}
		}
	}
	return ""
}

func (m *migrator) save() error { return fsio.WriteJSONAtomic(m.mapRel, m.imap) }

func (m *migrator) setEntry(old, id string, number any, url string) error {
	e := jsonx.NewObject()
	e.Set("id", id)
	e.Set("number", number)
	e.Set("url", url)
	e.Set("done", []any{})
	m.imap.Set(old, e)
	return m.save()
}

func (m *migrator) hasStep(old, step string) bool {
	if e := m.entry(old); e != nil {
		if d, ok := e.Get("done"); ok {
			if list, ok := d.([]any); ok {
				for _, s := range list {
					if s == step {
						return true
					}
				}
			}
		}
	}
	return false
}

// addStep records a finished step (setdefault of the entry and its done list).
func (m *migrator) addStep(old, step string) {
	e := m.entry(old)
	if e == nil {
		e = jsonx.NewObject()
		m.imap.Set(old, e)
	}
	d, ok := e.Get("done")
	list, isList := d.([]any)
	if !ok || !isList {
		list = []any{}
	}
	for _, s := range list {
		if s == step {
			e.Set("done", list)
			return
		}
	}
	e.Set("done", append(list, step))
}

func (m *migrator) stepDone(old, step string) error {
	m.addStep(old, step)
	return m.save()
}

// newIDs is the old ID to new ID mapping of the migrated items.
func (m *migrator) newIDs() map[string]string {
	out := map[string]string{}
	for _, k := range m.imap.Keys() {
		if migItemKey.MatchString(k) {
			out[k] = m.entryID(k)
		}
	}
	return out
}

// rewrite swaps old item IDs for the new ones (exact tokens only; bracketedOnly
// leaves bare IDs alone).
func (m *migrator) rewrite(text string, bracketedOnly bool) string {
	ids := m.newIDs()
	if bracketedOnly {
		return bracketedRe.ReplaceAllStringFunc(text, func(s string) string {
			id := s[1 : len(s)-1]
			if n, ok := ids[id]; ok {
				return "[" + n + "]"
			}
			return s
		})
	}
	var b strings.Builder
	last := 0
	for _, t := range tokenMatches(text) {
		b.WriteString(text[last:t.start])
		if n, ok := ids[t.id]; ok {
			b.WriteString(n)
		} else {
			b.WriteString(t.id)
		}
		last = t.end
	}
	b.WriteString(text[last:])
	return b.String()
}

// ---- the run --------------------------------------------------------------------

func (m *migrator) labelNames(it *migItem) []string {
	role := map[string]string{"bugs": "types.bug", "features": "types.feature", "tasks": "types.task"}[it.kind]
	labels := []string{config.Label(m.o.Cfg, role)}
	if it.tag != "" && it.kind == "bugs" {
		labels = append(labels, config.Label(m.o.Cfg, "priorityPrefix")+it.tag[1:])
	} else if it.tag != "" {
		labels = append(labels, config.Label(m.o.Cfg, "sizePrefix")+it.tag)
	}
	return labels
}

func (m *migrator) milestoneAvailable(mid string) (bool, error) {
	if _, ok := m.imap.Get(mid); ok || m.msIDs[mid] {
		return true, nil
	}
	if !m.apply {
		return false, nil
	}
	if v, ok := m.msCache[mid]; ok {
		return v, nil
	}
	be, err := m.backend()
	if err != nil {
		return false, err
	}
	_, found, err := be.Tracker.FindMilestone(m.ctx, mid)
	if err != nil {
		return false, err
	}
	m.msCache[mid] = found
	return found, nil
}

// run is the three phases: milestones, items, then (once every item exists)
// notes, slice plans, milestone bodies and Related rewrites. It returns false
// when --limit left items for the next run.
func (m *migrator) run() (bool, error) {
	// phase 1: milestones
	for _, ms := range m.ms {
		mid := ms.id
		if _, ok := m.imap.Get(mid); !ok {
			ms := ms
			err := m.op(fmt.Sprintf("create milestone %s (%s)", mid, ms.status), func() error {
				if err := m.milestoneAdd(mid, ms); err != nil {
					return err
				}
				is, err := m.trackerIssue(mid)
				if err != nil {
					return err
				}
				return m.setEntry(mid, mid, jn(is.Number), is.URL)
			})
			if err != nil {
				return false, err
			}
			if !m.apply {
				e := jsonx.NewObject()
				e.Set("id", mid)
				e.Set("number", "?")
				e.Set("url", "")
				e.Set("done", []any{})
				m.imap.Set(mid, e)
			}
		}
		if ms.status != "planned" && !m.hasStep(mid, "status") {
			ms := ms
			err := m.op(fmt.Sprintf("set milestone %s status %s", mid, ms.status), func() error {
				if err := m.milestoneStatus(mid, ms.status); err != nil {
					return err
				}
				return m.stepDone(mid, "status")
			})
			if err != nil {
				return false, err
			}
			if !m.apply {
				m.addStep(mid, "status")
			}
		}
	}
	// phase 2: items
	for _, it := range m.items {
		old := it.id
		if _, ok := m.imap.Get(old); ok {
			m.say(fmt.Sprintf("skip %s (already migrated as %s)", old, m.entryID(old)))
			continue
		}
		if m.o.Limit >= 0 && m.created >= m.o.Limit {
			m.pending++
			continue
		}
		fields := []Field{}
		for _, n := range migOrder {
			if v := it.fields[n]; v != "" {
				fields = append(fields, Field{n, v})
			}
		}
		note := ""
		if it.milestone != "" {
			ok, err := m.milestoneAvailable(it.milestone)
			if err != nil {
				return false, err
			}
			if ok {
				fields = append(fields, Field{"Milestone", it.milestone})
				note = " milestone " + it.milestone
			} else {
				m.o.Warn(fmt.Sprintf("%s: milestone %s is not on the tracker (shipped/archived milestones are not migrated); Milestone field dropped", old, it.milestone))
			}
		}
		if len(it.unmapped) > 0 {
			note += " (Related not migrated: " + strings.Join(it.unmapped, ", ") + ")"
		}
		it, fields := it, fields
		desc := fmt.Sprintf("create issue %s → %s \"%s\" [%s]%s", old, strings.TrimSuffix(it.kind, "s"), it.title,
			strings.Join(m.labelNames(it), ", "), note)
		err := m.op(desc, func() error {
			be, err := m.backend()
			if err != nil {
				return err
			}
			in := CreateInput{Kind: it.kind, Title: it.title, Tag: it.tag, Desc: it.desc, Fields: fields, Since: it.since}
			if it.body != nil {
				in.Body, in.HasBody = []byte(*it.body), true
			}
			res, err := be.Create(in)
			if err != nil {
				return err
			}
			n, _ := strconv.Atoi(res.ID)
			got, err := be.Tracker.Get(m.ctx, n, false)
			if err != nil {
				return err
			}
			return m.setEntry(old, res.Type+res.ID, jn(n), got.URL)
		})
		if err != nil {
			return false, err
		}
		m.created++
		if !m.apply {
			e := jsonx.NewObject()
			e.Set("id", old[:1]+"?")
			e.Set("number", "?")
			e.Set("url", "")
			e.Set("done", []any{})
			m.imap.Set(old, e)
		}
	}
	if m.pending > 0 {
		return false, nil
	}
	// phase 3
	for _, it := range m.items {
		old, nid := it.id, m.entryID(it.id)
		for _, n := range []struct {
			kind string
			text *string
		}{{"proof", it.proof}, {"design", it.design}, {"plan", it.plan}} {
			if n.text == nil || pystr.Strip(*n.text) == "" || m.hasStep(old, n.kind) {
				continue
			}
			body := *n.text
			if n.kind != "proof" {
				body = m.rewrite(body, false)
			}
			kind := n.kind
			err := m.op(fmt.Sprintf("note %s on %s", kind, old), func() error {
				be, err := m.backend()
				if err != nil {
					return err
				}
				if _, err := be.NotePut(nid, kind, body); err != nil {
					return err
				}
				return m.stepDone(old, kind)
			})
			if err != nil {
				return false, err
			}
			if !m.apply {
				m.addStep(old, kind)
			}
		}
		rel := it.fields["Related"]
		if rel != "" && !m.hasStep(old, "related") {
			newRel := m.rewrite(rel, false)
			var ids []string
			for _, t := range tokenMatches(rel) {
				if m.entry(t.id) != nil {
					ids = append(ids, t.id)
				}
			}
			if newRel != rel || (!m.apply && len(ids) > 0) {
				var shown []string
				for _, t := range ids {
					to := "#?"
					if m.apply {
						to = m.entryID(t)
					}
					shown = append(shown, t+" → "+to)
				}
				newRel := newRel
				err := m.op(fmt.Sprintf("rewrite Related on %s: %s", old, strings.Join(shown, ", ")), func() error {
					be, err := m.backend()
					if err != nil {
						return err
					}
					if _, err := be.SetField(nid, "related", newRel); err != nil {
						return err
					}
					return m.stepDone(old, "related")
				})
				if err != nil {
					return false, err
				}
				if !m.apply {
					m.addStep(old, "related")
				}
			} else if m.apply {
				if err := m.stepDone(old, "related"); err != nil {
					return false, err
				}
			}
		}
	}
	for _, ms := range m.ms {
		mid, ms := ms.id, ms
		if !m.hasStep(mid, "body") {
			err := m.op(fmt.Sprintf("set plan body of milestone %s", mid), func() error {
				if err := m.putMilestone(mid, ms); err != nil {
					return err
				}
				return m.stepDone(mid, "body")
			})
			if err != nil {
				return false, err
			}
			if !m.apply {
				m.addStep(mid, "body")
			}
		}
		for _, s := range ms.slices {
			step := "plan:" + s.unit
			if pystr.Strip(s.text) == "" || m.hasStep(mid, step) {
				continue
			}
			s := s
			err := m.op(fmt.Sprintf("note %s on %s", step, mid), func() error {
				be, err := m.backend()
				if err != nil {
					return err
				}
				is, err := m.trackerIssue(mid)
				if err != nil {
					return err
				}
				if _, err := be.NotePut(strconv.Itoa(is.Number), step, m.rewrite(s.text, true)); err != nil {
					return err
				}
				return m.stepDone(mid, step)
			})
			if err != nil {
				return false, err
			}
			if !m.apply {
				m.addStep(mid, step)
			}
		}
	}
	return true, nil
}

// jn is an int as a JSON number.
func jn(n int) json.Number { return json.Number(strconv.Itoa(n)) }

// ---- milestones: a native milestone and a tracking issue ----------------------------

func oneLineMS(s string) string { return oneLine(s) }

func (m *migrator) trackingIssues() (map[string]Issue, error) {
	if _, err := m.backend(); err != nil {
		return nil, err
	}
	label := config.Label(m.o.Cfg, "milestoneTracker")
	list, err := m.tr.List(m.ctx, tracker.ListFilter{State: "all", Labels: []string{label}})
	if err != nil {
		return nil, err
	}
	groups := map[string][]Issue{}
	var order []string
	for _, is := range list {
		if t := msTitleRe.FindStringSubmatchIndex(pystr.Strip(is.Title)); t != nil {
			t0 := pystr.Strip(is.Title)
			end := t[3]
			if end < len(t0) {
				if r, _ := utf8.DecodeRuneInString(t0[end:]); pystr.IsWord(r) {
					continue
				}
			}
			id := t0[:end]
			if _, ok := groups[id]; !ok {
				order = append(order, id)
			}
			groups[id] = append(groups[id], is)
		}
	}
	out := map[string]Issue{}
	for _, mid := range order {
		g := groups[mid]
		sort.SliceStable(g, func(i, j int) bool {
			if (g[i].State != "open") != (g[j].State != "open") {
				return g[j].State != "open"
			}
			return g[i].Number < g[j].Number
		})
		out[mid] = g[0]
		if len(g) > 1 {
			nums := make([]int, len(g))
			for i, is := range g {
				nums[i] = is.Number
			}
			sort.Ints(nums)
			var parts []string
			for _, n := range nums {
				parts = append(parts, "#"+strconv.Itoa(n))
			}
			m.o.Warn(fmt.Sprintf("%d tracking issues carry %s (%s); using #%d", len(g), mid, strings.Join(parts, ", "), g[0].Number))
		}
	}
	return out, nil
}

// trackerIssue is the tracking issue of milestone mid (a LookupError there).
func (m *migrator) trackerIssue(mid string) (Issue, error) {
	all, err := m.trackingIssues()
	if err != nil {
		return Issue{}, err
	}
	is, ok := all[mid]
	if !ok {
		return Issue{}, errf(ErrNotFound, "milestone %s not found on the issue tracker", mid)
	}
	return is, nil
}

func milestoneStub(mid, title, summary string, depends []string, today string) string {
	return "---\nid: " + mid + "\ntitle: " + title + "\nstatus: planned\ndepends: [" + strings.Join(depends, ", ") + "]\ncreated: " + today + "\n---\n\n" +
		"# " + mid + " — " + title + "\n\n## Goal\n\n" + summary + "\n\n## Acceptance criteria\n\n- _(define what shipped looks like)_\n\n" +
		"## Rationale\n\n_(why this milestone, why now)_\n\n## Open risks\n\n_(unknowns, technical risks, dependencies that could shift)_\n\n" +
		"## Research findings\n\n_(prior art, references, lessons from /hv-vision web search)_\n\n## Notes\n\n_(free-form brainstorm)_\n"
}

func (m *migrator) milestoneAdd(mid string, ms *migMilestone) error {
	be, err := m.backend()
	if err != nil {
		return err
	}
	native := mid + " — " + ms.title
	labels := []string{config.Label(m.o.Cfg, "milestoneTracker"), msStatusPrefix + "planned"}
	if err := m.tr.EnsureLabels(m.ctx, labels, be.autoCreate()); err != nil {
		return err
	}
	if _, err := m.tr.CreateMilestone(m.ctx, native, oneLineMS(ms.summary)); err != nil {
		return err
	}
	body := RenderFieldsBlock(milestoneStub(mid, ms.title, ms.summary, ms.depends, m.o.Today()),
		[]string{"Depends"}, map[string]string{"Depends": strings.Join(ms.depends, ", ")})
	_, err = m.tr.Create(m.ctx, native, body, labels, native)
	return err
}

func msStatusOf(is Issue) string {
	for _, l := range is.Labels {
		if strings.HasPrefix(l, msStatusPrefix) && has(msStatuses, l[len(msStatusPrefix):]) {
			return l[len(msStatusPrefix):]
		}
	}
	if is.State == "closed" {
		if is.StateReason == "not_planned" {
			return "archived"
		}
		return "shipped"
	}
	return "planned"
}

func (m *migrator) milestoneStatus(mid, status string) error {
	be, err := m.backend()
	if err != nil {
		return err
	}
	is, err := m.trackerIssue(mid)
	if err != nil {
		return err
	}
	n := is.Number
	label := msStatusPrefix + status
	var stale []string
	for _, l := range is.Labels {
		if strings.HasPrefix(l, msStatusPrefix) && l != label {
			stale = append(stale, l)
		}
	}
	if !has(is.Labels, label) {
		if err := m.tr.AddLabels(m.ctx, n, []string{label}, be.autoCreate()); err != nil {
			return err
		}
	}
	if len(stale) > 0 {
		if err := m.tr.RemoveLabels(m.ctx, n, stale); err != nil {
			return err
		}
	}
	text, block, order := ParseFieldsBlock(is.Body)
	if newText, _ := frontmatter.UpdateField(text, "status", status); newText != text {
		body := RenderFieldsBlock(newText, order, block)
		if err := m.tr.Edit(m.ctx, n, tracker.IssueEdit{Body: &body}); err != nil {
			return err
		}
	}
	wantClosed := status == "shipped" || status == "archived"
	reason := "completed"
	if status == "archived" {
		reason = "not_planned"
	}
	if is.State == "closed" && (!wantClosed || is.StateReason != reason) {
		if err := m.tr.Reopen(m.ctx, n); err != nil {
			return err
		}
		is.State = "open"
	}
	if wantClosed && is.State == "open" {
		if err := m.tr.Close(m.ctx, n, reason, ""); err != nil {
			return err
		}
	}
	nm, err := m.nativeMilestone(mid, is)
	if err != nil {
		return err
	}
	want := "open"
	if wantClosed {
		want = "closed"
	}
	if nm != nil && nm.State != want {
		return m.tr.EditMilestone(m.ctx, nm.Number, tracker.MilestoneEdit{State: &want})
	}
	return nil
}

// nativeMilestone is the native milestone of mid: the issue's own, else the
// one whose title starts with mid, open ones first.
func (m *migrator) nativeMilestone(mid string, is Issue) (*tracker.Milestone, error) {
	found, err := m.tr.Milestones(m.ctx, "all")
	if err != nil {
		return nil, err
	}
	for i := range found {
		if is.Milestone != "" && found[i].Title == is.Milestone {
			return &found[i], nil
		}
	}
	var hits []tracker.Milestone
	for _, nm := range found {
		t := pystr.Strip(nm.Title)
		if strings.HasPrefix(t, mid) {
			if r, _ := utf8.DecodeRuneInString(t[len(mid):]); t[len(mid):] == "" || !pystr.IsWord(r) {
				hits = append(hits, nm)
			}
		}
	}
	sort.SliceStable(hits, func(i, j int) bool { return hits[i].State != "closed" && hits[j].State == "closed" })
	if len(hits) == 0 {
		return nil, nil
	}
	return &hits[0], nil
}

// putMilestone replaces the milestone plan text of the tracking issue; a text
// without `id: <mid>` frontmatter is skipped with a notice.
func (m *migrator) putMilestone(mid string, ms *migMilestone) error {
	text := strings.ReplaceAll(m.rewrite(ms.text, false), "\r\n", "\n")
	fm := frontmatterM.FindStringSubmatch(text)
	var idm []string
	if fm != nil {
		idm = fmIDRe.FindStringSubmatch(fm[1])
	}
	if idm == nil || idm[1] != mid {
		m.o.Warn(fmt.Sprintf("%s: plan body not copied (milestone text needs frontmatter with 'id: %s')", mid, mid))
		return nil
	}
	is, err := m.trackerIssue(mid)
	if err != nil {
		return err
	}
	_, block, order := ParseFieldsBlock(is.Body)
	if dm := fmDependsRe.FindStringSubmatch(fm[1]); dm != nil {
		if _, ok := block["Depends"]; !ok {
			order = append(order, "Depends")
		}
		block["Depends"] = strings.Join(migMSAllRe.FindAllString(dm[1], -1), ", ")
	}
	text, _ = frontmatter.UpdateField(text, "status", msStatusOf(is))
	body := RenderFieldsBlock(text, order, block)
	return m.tr.Edit(m.ctx, is.Number, tracker.IssueEdit{Body: &body})
}
