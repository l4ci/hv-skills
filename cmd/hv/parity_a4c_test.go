package main

// Scenarios for hv update, hv config show|set|check and hv repo
// which|resolve|umbrella (#48), on the differential harness of
// parity_a4_test.go. The shim has no adapter for these verbs, so the
// reference is the old helper run directly with the contract's `old:` argv
// (hv-config-show, hv-config-set, hv-config-schema-check, hv-resolve-repo with
// hv-resolve-repo-path, hv-resolve-repos, hv-umbrella-on, hv-update-check).
//
// Safety: hv update must never reach the network. Every update scenario sets
// HV_TEST_LATEST_VERSION (Go) and HV_LATEST_VERSION (old helper); the one
// scenario that leaves them unset runs with test/fakes first on PATH and
// proves, through the fake's call log, that gh resolved there.

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/config"
)

// ---- config fixtures ---------------------------------------------------------------

// nest turns dotted keys into the nested JSON object a config file holds.
func nest(kv map[string]any) string {
	root := map[string]any{}
	for k, v := range kv {
		segs := strings.Split(k, ".")
		cur := root
		for _, s := range segs[:len(segs)-1] {
			next, ok := cur[s].(map[string]any)
			if !ok {
				next = map[string]any{}
				cur[s] = next
			}
			cur = next
		}
		cur[segs[len(segs)-1]] = v
	}
	b, _ := json.MarshalIndent(root, "", "  ")
	return string(b) + "\n"
}

// fullConfig has every required key at its default: an up-to-date config.
func fullConfig(drop ...string) string {
	kv := map[string]any{}
	for _, k := range config.Keys {
		if k.Required {
			kv[k.Name] = k.Default
		}
	}
	for _, d := range drop {
		delete(kv, d)
	}
	return nest(kv)
}

func withFile(path, content string) fx { return fx{files: map[string]string{path: content}} }

func noConfigFile(t *testing.T, dir string, in *info) {
	os.Remove(filepath.Join(dir, ".hv", "config.json"))
}

// ---- config checks -----------------------------------------------------------------

var showLine = regexp.MustCompile(`^(\S+) = (.*)  \(source: (local|project|default)\)$`)

// checkShow compares data.entries with the lines the old helper printed, the
// way the contract's shim parses them.
func checkShow(wantRows int) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		rows, _ := at(e, "data.entries").([]any)
		old := lines(ref.stdout)
		if len(rows) != len(old) || (wantRows >= 0 && len(rows) != wantRows) {
			t.Fatalf("%d entries, old printed %d lines (want %d)", len(rows), len(old), wantRows)
		}
		for i, l := range old {
			m := showLine.FindStringSubmatch(l)
			if m == nil {
				t.Fatalf("old line %q does not parse", l)
			}
			var val any
			if err := json.Unmarshal([]byte(m[2]), &val); err != nil {
				t.Fatalf("old value %q: %v", m[2], err)
			}
			row := rows[i].(map[string]any)
			if row["key"] != m[1] || row["source"] != m[3] || !reflect.DeepEqual(row["value"], val) {
				t.Errorf("entry %d = %v, old %q", i, row, l)
			}
		}
	}
}

func showMap(rc int, stderr string) int {
	switch {
	case rc == 0:
		return 0
	case strings.Contains(stderr, "usage:"):
		return 2
	case strings.Contains(stderr, "unknown key"), strings.Contains(stderr, "no .hv/ found"):
		return 3
	}
	return 70
}

func setMap(rc int, stderr string) int {
	switch {
	case rc == 0:
		return 0
	case strings.Contains(stderr, "malformed key path"), strings.Contains(stderr, "usage:"):
		return 2
	case strings.Contains(stderr, "no .hv/ found"):
		return 3
	}
	return 70
}

func resolveMap(rc int, stderr string) int {
	switch rc {
	case 0:
		return 0
	case 1:
		return 3
	case 2:
		return 2
	}
	return 70
}

func whichMap(rc int, _ string) int {
	if rc == 0 {
		return 0
	}
	return 3
}

// checkVerdict compares data with the token hv-config-schema-check printed.
func checkVerdict(status string, missing ...string) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		tok := strings.TrimSpace(ref.stdout)
		want := map[string]string{"upToDate": "UP_TO_DATE", "fresh": "FRESH", "corrupt": "CORRUPT"}[status]
		if status == "stale" {
			want = "STALE:" + strings.Join(missing, ",")
		}
		if tok != want {
			t.Errorf("old printed %q, want %q", tok, want)
		}
		eq(t, e, "data.status", status)
		eq(t, e, "data.upToDate", status == "upToDate")
		got := strs(at(e, "data.missing"))
		if got == nil || len(got) != len(missing) || (len(missing) > 0 && !reflect.DeepEqual(got, missing)) {
			t.Errorf("data.missing = %v, want %v", got, missing)
		}
	}
}

// ---- repo checks -------------------------------------------------------------------

// dirNorm replaces a project directory, as written and with symlinks resolved,
// by <root>.
func dirNorm(s, dir string) string {
	real, err := filepath.EvalSymlinks(dir)
	if err != nil {
		real = dir
	}
	return strings.ReplaceAll(strings.ReplaceAll(s, real, "<root>"), dir, "<root>")
}

func goDirOf(e envl) string { d, _ := e["__godir"].(string); return d }

// checkWhich: the old helper printed the name; hv-resolve-repo-path, run from
// the umbrella root as the contract's shim does, gives the path.
func checkWhich(name, rel string) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		if got := strings.TrimSpace(ref.stdout); got != name {
			t.Errorf("old printed %q, want %q", got, name)
		}
		eq(t, e, "data.name", name)
		p := exec1(t, ref.dir, "", filepath.Join(stagedBin, "hv-resolve-repo-path"), name)
		if p.code != 0 {
			t.Fatalf("hv-resolve-repo-path %s: %d %s", name, p.code, p.stderr)
		}
		got, _ := at(e, "data.path").(string)
		if a, b := dirNorm(got, goDirOf(e)), dirNorm(strings.TrimSpace(p.stdout), ref.dir); a != b {
			t.Errorf("path = %s, old %s", a, b)
		}
		if want := "<root>/" + rel; dirNorm(got, goDirOf(e)) != want {
			t.Errorf("path = %s, want %s", dirNorm(got, goDirOf(e)), want)
		}
	}
}

func checkResolved(t *testing.T, e envl, ref run) {
	t.Helper()
	var old any
	if err := json.Unmarshal([]byte(dirNorm(ref.stdout, ref.dir)), &old); err != nil {
		t.Fatalf("old output is not JSON: %v\n%s", err, ref.stdout)
	}
	gj, _ := json.Marshal(at(e, "data.repos"))
	var got any
	json.Unmarshal([]byte(dirNorm(string(gj), goDirOf(e))), &got)
	if !reflect.DeepEqual(got, old) {
		oj, _ := json.Marshal(old)
		t.Errorf("repos differ\ngo:  %s\nold: %s", dirNorm(string(gj), goDirOf(e)), oj)
	}
}

func checkYesNo(want bool) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		old := strings.TrimSpace(ref.stdout)
		if (old == "yes") != want && !(old == "no" && !want) {
			// the old helper looks at the directory only; Go walks up (disagreement, see div)
			return
		}
		eq(t, e, "data.umbrella", want)
	}
}

func registry(reg string) fx {
	return withFx(umbFx, func(f *fx) {
		f.after = func(t *testing.T, dir string, in *info) { write(t, dir, ".hv/repos.json", reg) }
	})
}

func afterAll(fs ...func(t *testing.T, dir string, in *info)) func(t *testing.T, dir string, in *info) {
	return func(t *testing.T, dir string, in *info) {
		for _, f := range fs {
			f(t, dir, in)
		}
	}
}

// ---- update fixtures ---------------------------------------------------------------

const instVersion = "1.2.3"

var (
	updOnce sync.Once
	upd     struct {
		bin                                                   string // Go binary stamped with instVersion
		cloneBin, cloneOld                                    string // the binary and bin/ copy inside a repo clone
		clone, plain, empty, foreign                          string
		homeNone, homePlugin, homeCache, homeAgents, homeStow string
		stowRepo                                              string
	}
)

func manifest(t *testing.T, dir, name, version string) {
	t.Helper()
	write(t, dir, ".claude-plugin/plugin.json", fmt.Sprintf(`{"name": %q, "version": %q}`+"\n", name, version))
}

func updFixtures(t *testing.T) {
	t.Helper()
	updOnce.Do(func() {
		mk := func(name string) string {
			d := filepath.Join(harnessTmp, name)
			if err := os.MkdirAll(d, 0o755); err != nil {
				t.Fatal(err)
			}
			return d
		}
		upd.bin = filepath.Join(harnessTmp, "hv-stamped")
		build := exec.Command("go", "build", "-ldflags", "-X github.com/l4ci/hv-skills/v5/internal/version.Version="+instVersion, "-o", upd.bin, ".")
		build.Dir = filepath.Join(repoDir, "cmd", "hv")
		if out, err := build.CombinedOutput(); err != nil {
			t.Fatalf("go build: %v\n%s", err, out)
		}
		upd.plain, upd.empty, upd.foreign = mk("inst-plain"), mk("inst-empty"), mk("inst-foreign")
		manifest(t, upd.plain, "hv-skills", instVersion)
		manifest(t, upd.foreign, "other-plugin", "9.9.9")
		upd.homeNone = mk("home-none")
		upd.homePlugin = mk("home-plugin")
		manifest(t, filepath.Join(upd.homePlugin, ".claude/plugins/market/hv-skills"), "hv-skills", instVersion)
		upd.homeCache = mk("home-cache")
		for _, v := range []string{"4.9.0", "4.10.0", "4.2.0"} {
			manifest(t, filepath.Join(upd.homeCache, ".claude/plugins/cache/hv-skills/hv-skills", v), "hv-skills", instVersion)
		}
		if err := os.MkdirAll(filepath.Join(upd.homeCache, ".claude/plugins/cache/hv-skills/hv-skills/9.9.9"), 0o755); err != nil {
			t.Fatal(err)
		}
		upd.homeAgents = mk("home-agents")
		manifest(t, filepath.Join(upd.homeAgents, ".agents/skills/hv-skills"), "hv-skills", instVersion)
		upd.homeStow = mk("home-stow")
		upd.stowRepo = mk("stow-repo")
		manifest(t, upd.stowRepo, "hv-skills", instVersion)
		if err := os.MkdirAll(filepath.Join(upd.stowRepo, "hv-update"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Join(upd.homeStow, ".claude/skills"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(filepath.Join(upd.stowRepo, "hv-update"), filepath.Join(upd.homeStow, ".claude/skills/hv-update")); err != nil {
			t.Fatal(err)
		}
		upd.clone = mk("clone")
		manifest(t, upd.clone, "hv-skills", instVersion)
		upd.cloneOld = filepath.Join(upd.clone, "bin")
		if out, err := exec.Command("cp", "-a", stagedBin, upd.cloneOld).CombinedOutput(); err != nil {
			t.Fatalf("cp: %v\n%s", err, out)
		}
		upd.cloneBin = filepath.Join(upd.cloneOld, "hv")
		if out, err := exec.Command("cp", upd.bin, upd.cloneBin).CombinedOutput(); err != nil {
			t.Fatalf("cp: %v\n%s", err, out)
		}
	})
}

// checkUpdate compares the Go data with the JSON hv-update-check printed.
// currentVersion is compared too: the stamped binary and the fixture
// manifests both say instVersion.
func checkUpdate(installType, status string) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		var old map[string]any
		if err := json.Unmarshal([]byte(ref.stdout), &old); err != nil {
			t.Fatalf("old output is not JSON: %v\n%s", err, ref.stdout)
		}
		got, _ := at(e, "data").(map[string]any)
		if !reflect.DeepEqual(got, old) {
			gj, _ := json.Marshal(got)
			oj, _ := json.Marshal(old)
			t.Errorf("update data differs\ngo:  %s\nold: %s", gj, oj)
		}
		eq(t, e, "data.installType", installType)
		eq(t, e, "data.status", status)
		for _, k := range []string{"installType", "installRoot", "currentVersion", "latestVersion", "status", "updateCommand"} {
			if _, ok := got[k].(string); !ok {
				t.Errorf("data.%s = %#v, want a string", k, got[k])
			}
		}
	}
}

// updNoRoot is updScn where no install root resolves: currentVersion falls
// back to the binary's stamped version (orchestrator ruling, A4 acceptance)
// where the old helper gave "", so the status compares instead of unknown.
func updNoRoot(name, home, latest string, extra []string, status string) scn {
	s := updScn(name, home, latest, extra, "unknown", status)
	s.div, s.refWant = "no install root: Go falls back to the stamped version (ruling); old gave an empty currentVersion", 0
	s.check = func(t *testing.T, e envl, ref run) {
		t.Helper()
		var old map[string]any
		if err := json.Unmarshal([]byte(ref.stdout), &old); err != nil {
			t.Fatalf("old output is not JSON: %v\n%s", err, ref.stdout)
		}
		if old["currentVersion"] != "" || old["status"] != "unknown" {
			t.Errorf("old = %v, expected the empty version and unknown", old)
		}
		got, _ := at(e, "data").(map[string]any)
		g := map[string]any{}
		for k, v := range got {
			g[k] = v
		}
		eq(t, e, "data.currentVersion", instVersion)
		eq(t, e, "data.status", status)
		g["currentVersion"], g["status"] = "", "unknown"
		if !reflect.DeepEqual(g, old) {
			t.Errorf("update data differs beyond the fallback\ngo:  %v\nold: %v", got, old)
		}
	}
	return s
}

func updScn(name, home, latest string, extra []string, installType, status string) scn {
	env := []string{"HOME=" + home, "HV_TEST_LATEST_VERSION=" + latest, "HV_LATEST_VERSION=" + latest}
	return scn{name: "update/" + name, fx: fx{noHV: true}, argv: j("update"), old: []string{"hv-update-check"}, want: 0,
		env: append(env, extra...), bin: upd.bin, check: checkUpdate(installType, status)}
}

// ---- the scenarios -----------------------------------------------------------------

func TestParityA4C(t *testing.T) {
	updFixtures(t)
	var all []scn
	add := func(s ...scn) { all = append(all, s...) }
	stdFx := fx{}

	// ---- config show: every schema key, in each of the three sources
	show := func(name string, f fx, rows int, args ...string) scn {
		return scn{name: "config-show/" + name, fx: f, argv: j(append([]string{"config", "show"}, args...)...),
			old: append([]string{"hv-config-show"}, args...), oldMap: showMap, want: 0, text: true, check: checkShow(rows)}
	}
	showE := func(name string, f fx, want int, args ...string) scn {
		return scn{name: "config-show/" + name, fx: f, argv: j(append([]string{"config", "show"}, args...)...),
			old: append([]string{"hv-config-show"}, args...), oldMap: showMap, want: want}
	}
	for _, k := range config.Keys {
		add(
			show(k.Name+"/default", stdFx, 1, k.Name),
			show(k.Name+"/project", fx{config: nest(map[string]any{k.Name: "proj"})}, 1, k.Name),
			show(k.Name+"/local", fx{files: map[string]string{".hv/config.local.json": nest(map[string]any{k.Name: "loc"})}}, 1, k.Name),
		)
	}
	allProj, allLoc := map[string]any{}, map[string]any{}
	for i, k := range config.Keys {
		switch i % 3 {
		case 0:
			allProj[k.Name] = fmt.Sprintf("p%d", i)
		case 1:
			allLoc[k.Name] = []any{i, "l"}
			allProj[k.Name] = "shadowed"
		}
	}
	n := len(config.Keys)
	add(
		show("all/std", stdFx, n),
		show("all/no-config-file", withFx(stdFx, func(f *fx) { f.after = noConfigFile }), n),
		show("all/mixed-layers", fx{config: nest(allProj), files: map[string]string{".hv/config.local.json": nest(allLoc)}}, n),
		show("all/null-counts-as-unset", fx{config: `{"models": {"worker": null, "orchestrator": "o"}}`}, n),
		show("all/null-in-local-falls-to-project", fx{config: `{"models": {"worker": "p"}}`, files: map[string]string{".hv/config.local.json": `{"models": {"worker": null}}`}}, n),
		show("all/parent-is-scalar", fx{config: `{"models": "x", "work": 3}`}, n),
		show("all/config-is-list", fx{config: `[1]`}, n),
		show("all/config-corrupt", fx{config: `{oops`}, n),
		show("all/local-is-list-ignored", fx{files: map[string]string{".hv/config.local.json": `[1]`}}, n),
		show("all/local-corrupt", fx{files: map[string]string{".hv/config.local.json": `{`}}, n),
		show("all/nested-object-values", fx{config: `{"work": {"accounts": [{"a": 1}, "b"], "workerCommand": "kü \"q\""}}`}, n),
		show("all/number-forms", fx{config: `{"work": {"workerSlots": 1.50}, "learn": {"promoteThreshold": 1e2}, "issues": {"bulkPaceMs": 12345678901234567890}}`}, n),
		show("all/unicode-and-escapes", fx{config: `{"docs": {"path": "dé😀\n\t/"}}`}, n),
		show("all/from-subdir", withFile("sub/x.txt", "x\n"), n),
		show("one/from-subdir", withFile("sub/x.txt", "x\n"), 1, "docs.path"),
		showE("one/unknown-key", stdFx, 3, "nope.nope"),
		showE("one/empty-key", stdFx, 3, ""),
		showE("one/case-matters", stdFx, 3, "Models.Worker"),
		showE("one/hand-edited-null-key", fx{config: `{"custom": null}`}, 3, "custom"),
		showE("two-keys-usage", stdFx, 2, "docs.path", "docs.afterWork"),
		show("one/under-issues-backend", fx{config: issuesConfig}, 1, "backlog.backend"),
		showE("no-hv", fx{noHV: true}, 3),
		scn{name: "config-show/repo-flag-outside-umbrella", goOnly: true, want: 3, argv: j("config", "show", "--repo", "web")},
		scn{name: "config-show/repo-flag-registered", fx: umbFx, argv: j("config", "show", "--repo", "web", "docs.path"), old: []string{"hv-config-show", "docs.path"}, want: 0, text: true, check: checkShow(1)},
		scn{name: "config-show/repo-flag-unregistered", goOnly: true, want: 3, fx: umbFx, argv: j("config", "show", "--repo", "nope")},
		scn{name: "config-show/hand-edited-key-is-readable", div: "old rejects any key outside the schema", refWant: 3, want: 0,
			fx: fx{config: `{"custom": {"x": 7}}`}, argv: j("config", "show", "custom.x"), old: []string{"hv-config-show", "custom.x"}, oldMap: showMap,
			check: both(eqCheck("data.entries.0.value", float64(7)), eqCheck("data.entries.0.source", "project"), eqCheck("data.entries.0.key", "custom.x"))},
		scn{name: "config-show/hand-edited-key-local-source", div: "old rejects any key outside the schema", refWant: 3, want: 0,
			fx: fx{config: `{"custom": 1}`, files: map[string]string{".hv/config.local.json": `{"custom": 2}`}}, argv: j("config", "show", "custom"), old: []string{"hv-config-show", "custom"}, oldMap: showMap,
			check: both(eqCheck("data.entries.0.value", float64(2)), eqCheck("data.entries.0.source", "local"))},
		scn{name: "config-show/hand-edited-parent-object", div: "old rejects any key outside the schema", refWant: 3, want: 0,
			fx: fx{config: `{"models": {"worker": "w"}}`}, argv: j("config", "show", "models"), old: []string{"hv-config-show", "models"}, oldMap: showMap,
			check: eqCheck("data.entries.0.value", map[string]any{"worker": "w"})},
	)

	// ---- config set
	set := func(name string, f fx, key, val string, check func(t *testing.T, e envl, ref run)) scn {
		return scn{name: "config-set/" + name, fx: f, argv: j("config", "set", key, val), old: []string{"hv-config-set", key, val},
			oldMap: setMap, want: 0, check: check}
	}
	for _, c := range []struct {
		name, raw string
		want      any
	}{
		{"true", "true", true}, {"false", "false", false}, {"int", "42", float64(42)}, {"negative", "-7", float64(-7)},
		{"float", "1.50", 1.5}, {"exponent", "1e2", float64(100)}, {"json-string", `"x"`, "x"},
		{"array", `[1, "a", null]`, []any{float64(1), "a", nil}}, {"object", `{"a": {"b": [1]}}`, map[string]any{"a": map[string]any{"b": []any{float64(1)}}}},
		{"raw-string", "opus", "opus"}, {"capital-true-is-a-string", "True", "True"}, {"quoted-true-stays-string", `"true"`, "true"},
		{"unicode", "kü\U0001F600", "kü\U0001F600"}, {"padded-int", " 7 ", float64(7)}, {"leading-zero-is-a-string", "0123", "0123"},
		{"underscore-int-is-a-string", "1_000", "1_000"}, {"broken-object", "{bad", "{bad"}, {"broken-array", "[1,", "[1,"},
		{"whitespace-only", "  ", "  "}, {"big-int", "9999999999999999999999", float64(9999999999999999999999)}, {"minus-zero", "-0", float64(0)},
		{"trailing-garbage", "5 x", "5 x"}, {"two-values", "1 2", "1 2"}, {"hash", "#x", "#x"}, {"dash-value", "-x", "-x"},
		{"escaped-newline", `"a\nb"`, "a\nb"}, {"empty-object", "{}", map[string]any{}}, {"empty-array", "[]", []any{}},
		{"surrogate-pair-escape", `"😀"`, "\U0001F600"}, {"null", "null", nil},
	} {
		s := set("coerce/"+c.name, stdFx, "models.worker", c.raw, func(t *testing.T, e envl, ref run) {
			t.Helper()
			eq(t, e, "data.value", c.want)
			eq(t, e, "data.changed", true)
		})
		if strings.HasPrefix(c.raw, "-") {
			// a value that starts with - is a flag until -- (conventions, rule 7)
			s.argv = j("config", "set", "models.worker", "--", c.raw)
		}
		add(s)
	}
	add(
		set("key/models.orchestrator", stdFx, "models.orchestrator", "haiku", eqCheck("data.key", "models.orchestrator")),
		set("key/four-segments", stdFx, "issues.labels.types.bug", "defect", eqCheck("data.key", "issues.labels.types.bug")),
		set("key/three-segments", stdFx, "issues.providers.github", "false", eqCheck("data.value", false)),
		set("key/hvSkills.version", stdFx, "hvSkills.version", "5.0.0", eqCheck("data.value", "5.0.0")),
		set("previous/scalar", fx{config: `{"models": {"worker": "sonnet"}}`}, "models.worker", "opus",
			both(eqCheck("data.previous", "sonnet"), eqCheck("data.changed", true))),
		set("previous/object", fx{config: `{"work": {"accounts": ["a"]}}`}, "work.accounts", `["b"]`, eqCheck("data.previous", []any{"a"})),
		set("previous/null-is-present", fx{config: `{"models": {"worker": null}}`}, "models.worker", "x", eqCheck("data.previous", nil)),
		set("previous/same-value-is-a-no-op", fx{config: "{\n  \"models\": {\n    \"worker\": \"opus\"\n  }\n}\n"}, "models.worker", "opus",
			both(eqCheck("data.changed", false), eqCheck("data.previous", "opus"))),
		set("previous/same-value-compact-file-is-reformatted", fx{config: `{"models":{"worker":"opus"}}`}, "models.worker", "opus", eqCheck("data.changed", false)),
		set("previous/int-vs-float-differs", fx{config: `{"work": {"workerSlots": 3}}`}, "work.workerSlots", "3.0", eqCheck("data.changed", true)),
		set("parent/created", fx{config: `{"backlog": {"backend": "file"}}`}, "docs.path", "d", eqCheck("data.changed", true)),
		set("parent/scalar-replaced", fx{config: `{"work": "scalar"}`}, "work.dispatch", "tmux", eqCheck("data.previous", nil)),
		set("parent/list-replaced", fx{config: `{"work": [1, 2]}`}, "work.dispatch", "tmux", nil),
		set("parent/null-replaced", fx{config: `{"work": null}`}, "work.dispatch", "tmux", nil),
		set("parent/sibling-keys-kept", fx{config: `{"work": {"isolation": "worktree", "extra": [1]}, "keep": true}`}, "work.dispatch", "tmux", nil),
		set("order/replace-keeps-position", fx{config: `{"z": 1, "models": {"b": 1, "worker": "a", "a": 2}, "a": 0}`}, "models.worker", "b", nil),
		set("order/new-key-is-last", fx{config: `{"z": 1, "models": {"b": 1}, "a": 0}`}, "models.worker", "b", nil),
		set("order/duplicate-keys-collapse", fx{config: `{"models": {"worker": "a", "orchestrator": "o", "worker": "b"}}`}, "models.worker", "c", nil),
		set("file/missing-is-created", withFx(stdFx, func(f *fx) { f.after = noConfigFile }), "ship.qa", "true", eqCheck("data.changed", true)),
		set("file/empty", fx{config: " "}, "ship.qa", "true", nil),
		set("file/corrupt-counts-as-empty", fx{config: `{oops`}, "ship.qa", "true", nil),
		set("file/unicode-kept-escaped", fx{config: `{"note": "kü😀", "x": "café"}`}, "ship.qa", "true", nil),
		set("file/numbers-normalised", fx{config: `{"a": 1.50, "b": 1e2, "c": 10000000000000000000000, "d": -0}`}, "ship.qa", "true", nil),
		set("file/deeply-nested-kept", fx{config: `{"x": {"y": {"z": [1, {"w": null}]}}}`}, "ship.qa", "true", nil),
		set("file/local-is-never-touched", fx{files: map[string]string{".hv/config.local.json": `{"models":{"worker":"local"}}`}}, "models.worker", "opus", nil),
		set("file/set-in-config-even-when-local-overrides", fx{files: map[string]string{".hv/config.local.json": `{"models":{"worker":"local"}}`}, config: `{"models": {"worker": "p"}}`}, "models.worker", "q", eqCheck("data.previous", "p")),
		set("from-subdir", withFile("sub/x.txt", "x\n"), "docs.path", "d", nil),
	)
	for _, body := range []string{"[1]", "null", `"s"`, "7", "true"} {
		body := body
		add(scn{name: "config-set/not-an-object/" + body, fx: fx{config: body}, argv: j("config", "set", "models.worker", "x"),
			old: []string{"hv-config-set", "models.worker", "x"}, oldMap: setMap, want: 70})
	}
	for _, key := range []string{"", ".a", "a.", "a..b", "."} {
		key := key
		add(scn{name: "config-set/malformed-key/" + fmt.Sprintf("%q", key), argv: j("config", "set", key, "1"),
			old: []string{"hv-config-set", key, "1"}, oldMap: setMap, want: 2})
	}
	add(
		scn{name: "config-set/missing-value", argv: j("config", "set", "models.worker"), old: []string{"hv-config-set", "models.worker"}, oldMap: setMap, want: 2},
		scn{name: "config-set/missing-both", argv: j("config", "set"), old: []string{"hv-config-set"}, oldMap: setMap, want: 2},
		scn{name: "config-set/no-hv", fx: fx{noHV: true}, argv: j("config", "set", "models.worker", "x"), old: []string{"hv-config-set", "models.worker", "x"}, oldMap: setMap, want: 3},
		scn{name: "config-set/umbrella-repo-flag-writes-the-root-config", fx: umbFx, argv: j("config", "set", "--repo", "web", "docs.path", "d"),
			old: []string{"hv-config-set", "docs.path", "d"}, oldMap: setMap, want: 0, check: eqCheck("data.changed", true)},
		scn{name: "config-set/repo-flag-unregistered", goOnly: true, want: 3, fx: umbFx, argv: j("config", "set", "--repo", "nope", "docs.path", "d")},
		scn{name: "config-set/repo-flag-outside-umbrella", goOnly: true, want: 3, argv: j("config", "set", "--repo", "web", "docs.path", "d")},
		scn{name: "config-set/value-with-leading-dash-without-double-dash-is-a-flag", goOnly: true, want: 2, argv: j("config", "set", "models.worker", "-5")},
		scn{name: "config-set/key-outside-schema-is-refused", goOnly: true, want: 2, argv: j("config", "set", "nope.key", "1"),
			check: func(t *testing.T, e envl, _ run) {
				b, _ := os.ReadFile(filepath.Join(goDirOf(e), ".hv", "config.json"))
				if string(b) != stdConfig {
					t.Errorf("config.json changed: %s", b)
				}
			}},
		scn{name: "config-set/parent-key-outside-schema-is-refused", goOnly: true, want: 2, argv: j("config", "set", "models", `{"worker": "x"}`)},
		scn{name: "config-set/key-below-a-leaf-is-refused", goOnly: true, want: 2, argv: j("config", "set", "models.worker.deep", "1")},
		scn{name: "config-set/three-positionals", goOnly: true, want: 2, argv: j("config", "set", "models.worker", "a", "b")},
		scn{name: "config-set/empty-string-value-is-stored", goOnly: true, want: 0, argv: j("config", "set", "git.baseBranch", ""),
			check: both(eqCheck("data.value", ""), eqCheck("data.changed", true))},
	)

	// ---- config check
	chk := func(name string, f fx, want int, status string, missing ...string) scn {
		return scn{name: "config-check/" + name, fx: f, argv: j("config", "check"), old: []string{"hv-config-schema-check"}, want: want,
			div: "old always exits 0; the contract exits 1 unless upToDate", refWant: 0, text: true, check: checkVerdict(status, missing...)}
	}
	allReq := []string{}
	for _, k := range config.Keys {
		if k.Required {
			allReq = append(allReq, k.Name)
		}
	}
	add(
		chk("up-to-date", fx{config: fullConfig()}, 0, "upToDate"),
		chk("up-to-date-extra-keys", fx{config: strings.Replace(fullConfig(), "{\n", "{\n  \"extra\": [1],\n", 1)}, 0, "upToDate"),
		chk("up-to-date-null-in-optional-key", fx{config: strings.Replace(fullConfig(), "{\n", "{\n  \"loop\": {\"webResearch\": null},\n", 1)}, 0, "upToDate"),
		chk("fresh", withFx(stdFx, func(f *fx) { f.after = noConfigFile }), 1, "fresh"),
		chk("stale-std-config", stdFx, 1, "stale", allReq...),
		chk("stale-empty-object", fx{config: "{}"}, 1, "stale", allReq...),
		chk("stale-one-key", fx{config: fullConfig("umbrella.enabled")}, 1, "stale", "umbrella.enabled"),
		chk("stale-schema-order", fx{config: fullConfig("hvSkills.version", "models.orchestrator", "docs.path")}, 1, "stale", "models.orchestrator", "docs.path", "hvSkills.version"),
		chk("stale-null-value", fx{config: strings.Replace(fullConfig(), `"enabled": false`, `"enabled": null`, 1)}, 1, "stale", "umbrella.enabled"),
		chk("stale-false-is-present", fx{config: fullConfig("ship.qa")}, 1, "stale", "ship.qa"),
		chk("stale-parent-scalar", fx{config: strings.Replace(fullConfig(), "\"models\": {", "\"models\": 5, \"zzz\": {", 1)}, 1, "stale", "models.orchestrator", "models.worker"),
		chk("stale-parent-null", fx{config: `{"models": null}`}, 1, "stale", allReq...),
		chk("stale-ignores-local-file", withFx(fx{config: "{}"}, func(f *fx) { f.files = map[string]string{".hv/config.local.json": fullConfig()} }), 1, "stale", allReq...),
		chk("stale-optional-keys-never-count", fx{config: fullConfig("docs.afterWork")}, 1, "stale", "docs.afterWork"),
		chk("corrupt-invalid-json", fx{config: `{oops`}, 1, "corrupt"),
		chk("corrupt-list", fx{config: `[1, 2]`}, 1, "corrupt"),
		chk("corrupt-null", fx{config: `null`}, 1, "corrupt"),
		chk("corrupt-scalar", fx{config: `7`}, 1, "corrupt"),
		chk("corrupt-empty-file", fx{config: " "}, 1, "corrupt"),
		chk("corrupt-truncated", fx{config: fullConfig()[:40]}, 1, "corrupt"),
		chk("from-subdir", withFile("sub/x.txt", "x\n"), 1, "stale", allReq...),
		scn{name: "config-check/no-hv", fx: fx{noHV: true}, argv: j("config", "check"), old: []string{"hv-config-schema-check"}, want: 3, div: "old fails in the preamble with rc 1", refWant: 3},
		scn{name: "config-check/repo-flag-registered", fx: withFx(umbFx, func(f *fx) { f.config = fullConfig() }), argv: j("config", "check", "--repo", "api"),
			old: []string{"hv-config-schema-check"}, want: 0, div: "old always exits 0", refWant: 0, check: checkVerdict("upToDate")},
		scn{name: "config-check/repo-flag-unregistered", goOnly: true, want: 3, fx: umbFx, argv: j("config", "check", "--repo", "nope")},
		scn{name: "config-check/positional", goOnly: true, want: 2, argv: j("config", "check", "x")},
		scn{name: "config-check/failure-data-keeps-the-verdict", goOnly: true, want: 1, fx: fx{config: "{}"}, argv: j("config", "check"),
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "ok", false)
				eq(t, e, "error.code", "failed")
				eq(t, e, "data.status", "stale")
				if got := len(strs(at(e, "data.missing"))); got != len(allReq) {
					t.Errorf("missing has %d keys, want %d", got, len(allReq))
				}
			}},
	)

	// ---- repo umbrella
	umb := func(name string, f fx, want bool) scn {
		w := 1
		if want {
			w = 0
		}
		return scn{name: "repo-umbrella/" + name, fx: f, argv: j("repo", "umbrella"), old: []string{"hv-umbrella-on"}, want: w,
			div: "old always exits 0 and prints yes or no", refWant: 0, text: true, check: both(eqCheck("data.umbrella", want), checkYesNo(want))}
	}
	add(
		umb("two-sub-repos", umbFx, true),
		umb("single-project", stdFx, false),
		umb("empty-registry", registry(`{"repos": []}`+"\n"), false),
		umb("no-repos-key", registry(`{}`), false),
		umb("corrupt-registry", registry(`{oops`), false),
		scn{name: "repo-umbrella/registry-is-a-list", fx: registry(`[1]`), argv: j("repo", "umbrella"), old: []string{"hv-umbrella-on"}, want: 1,
			div: "old crashes with a Python traceback on a registry that is not an object", refWant: 3, check: eqCheck("data.umbrella", false)},
		umb("entries-without-name-or-path", registry(`{"repos": [{"name": "a"}, {"path": "b"}, {"name": "", "path": "c"}]}`), false),
		umb("one-valid-entry-among-junk", registry(`{"repos": [{"name": "a"}, {"name": "ok", "path": "api"}]}`), true),
		umb("missing-path-still-counts", registry(`{"repos": [{"name": "ghost", "path": "not/there"}]}`), true),
		umb("config-flag-is-ignored-on", withFx(umbFx, func(f *fx) { f.config = `{"umbrella": {"enabled": false}}` }), true),
		umb("config-flag-is-ignored-off", withFx(stdFx, func(f *fx) { f.config = `{"umbrella": {"enabled": true}}` }), false),
		umb("no-registry-file-with-hv", withFx(stdFx, func(f *fx) {
			f.after = func(t *testing.T, d string, in *info) { os.Remove(filepath.Join(d, ".hv/repos.json")) }
		}), false),
		umb("no-hv-at-all", fx{noHV: true}, false),
		scn{name: "repo-umbrella/from-a-sub-repo-walks-up", fx: umbFx, cwd: "web", argv: j("repo", "umbrella"), old: []string{"hv-umbrella-on"}, want: 0,
			div: "old reads only the working directory's .hv/; the contract walks up to the nearest .hv/", refWant: 0,
			check: func(t *testing.T, e envl, ref run) {
				eq(t, e, "data.umbrella", true)
				if got := strings.TrimSpace(ref.stdout); got != "no" {
					t.Errorf("old printed %q, expected the documented no", got)
				}
			}},
		scn{name: "repo-umbrella/stray-hv-in-a-sub-repo-is-the-nearest", cwd: "web", want: 1, fx: withFx(umbFx, func(f *fx) {
			f.after = func(t *testing.T, d string, in *info) { os.MkdirAll(filepath.Join(d, "web", ".hv"), 0o755) }
		}), argv: j("repo", "umbrella"), old: []string{"hv-umbrella-on"}, div: "old exits 0", refWant: 0, check: eqCheck("data.umbrella", false)},
		scn{name: "repo-umbrella/with-C-on-the-root", fx: umbFx, cwd: "web", goOnly: true, want: 0, argv: j("-C", "..", "repo", "umbrella"), check: eqCheck("data.umbrella", true)},
		scn{name: "repo-umbrella/repo-flag-rejected", goOnly: true, want: 2, fx: umbFx, argv: j("repo", "umbrella", "--repo", "web")},
		scn{name: "repo-umbrella/positional-rejected", goOnly: true, want: 2, argv: j("repo", "umbrella", "x")},
		scn{name: "repo-umbrella/failure-carries-data", goOnly: true, want: 1, argv: j("repo", "umbrella"),
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "error.code", "failed"); eq(t, e, "data.umbrella", false) }},
		scn{name: "repo-umbrella/no-root-is-no-not-3", goOnly: true, want: 1, fx: fx{noHV: true}, argv: j("repo", "umbrella")},
	)

	// ---- repo resolve
	res := func(name string, f fx, want int, args ...string) scn {
		old := "hv-resolve-repos"
		return scn{name: "repo-resolve/" + name, fx: f, argv: j(append([]string{"repo", "resolve"}, args...)...),
			old: []string{old, strings.Join(args, ",")}, oldMap: resolveMap, want: want, text: want == 0 && len(args) > 0 && false, check: func(t *testing.T, e envl, ref run) {
				if want == 0 {
					checkResolved(t, e, ref)
				}
			}}
	}
	linkFx := withFx(umbFx, func(f *fx) {
		f.after = func(t *testing.T, dir string, in *info) {
			if err := os.Symlink("web", filepath.Join(dir, "link")); err != nil {
				t.Fatal(err)
			}
			write(t, dir, ".hv/repos.json", `{"repos": [{"name": "alias", "path": "link"}, {"name": "web", "path": "web"}, {"name": "ghost", "path": "not/there/yet"}, {"name": "deep", "path": "apps/deep"}, {"name": "up", "path": "../elsewhere"}]}`+"\n")
			os.MkdirAll(filepath.Join(dir, "apps", "deep"), 0o755)
		}
	})
	add(
		res("one", umbFx, 0, "web"),
		res("two-in-argument-order", umbFx, 0, "web", "api"),
		res("reversed", umbFx, 0, "api", "web"),
		res("duplicates-preserved", umbFx, 0, "web", "api", "web", "web"),
		res("zero-names", umbFx, 0),
		res("zero-names-outside-umbrella", stdFx, 0),
		res("zero-names-without-hv", fx{noHV: true}, 0),
		res("csv-in-one-argument", umbFx, 0, "web,api"),
		res("csv-with-spaces", umbFx, 0, "web, api ,web"),
		res("empty-argument-is-dropped", umbFx, 0, "", "web"),
		res("blank-arguments-give-none", umbFx, 0, " ", ""),
		res("trailing-comma", umbFx, 0, "web,"),
		res("symlinked-path", linkFx, 0, "alias", "web"),
		res("path-that-does-not-exist-yet", linkFx, 0, "ghost"),
		res("nested-path", linkFx, 0, "deep"),
		res("path-above-the-root", linkFx, 0, "up"),
		res("all-five", linkFx, 0, "alias", "web", "ghost", "deep", "up"),
		res("unknown-one", umbFx, 3, "nope"),
		res("unknown-two", umbFx, 3, "x", "web", "y"),
		res("unknown-all", umbFx, 3, "x", "y", "z"),
		res("unknown-is-case-sensitive", umbFx, 3, "Web"),
		res("not-an-umbrella", stdFx, 3, "web"),
		res("no-hv", fx{noHV: true}, 3, "web"),
		res("empty-registry", registry(`{"repos": []}`), 3, "web"),
		res("corrupt-registry", registry(`{oops`), 3, "web"),
		res("entries-without-path-are-not-registered", registry(`{"repos": [{"name": "web"}]}`), 3, "web"),
		res("duplicate-name-last-path-wins", registry(`{"repos": [{"name": "x", "path": "web"}, {"name": "y", "path": "api"}, {"name": "x", "path": "api"}]}`), 0, "x", "y"),
		res("absolute-registry-path", withFx(umbFx, func(f *fx) {
			f.after = func(t *testing.T, dir string, in *info) {
				write(t, dir, ".hv/repos.json", fmt.Sprintf(`{"repos": [{"name": "abs", "path": %q}]}`, filepath.Join(dir, "api")))
			}
		}), 0, "abs"),
		scn{name: "repo-resolve/from-a-sub-repo-walks-up", fx: umbFx, cwd: "web", argv: j("repo", "resolve", "api"), old: []string{"hv-resolve-repos", "api"}, oldMap: resolveMap,
			want: 0, div: "old reads only the working directory's .hv/; the contract walks up to the nearest .hv/", refWant: 3,
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.repos.0.name", "api")
				if p, _ := at(e, "data.repos.0.path").(string); dirNorm(p, goDirOf(e)) != "<root>/api" {
					t.Errorf("path = %s", p)
				}
			}},
		scn{name: "repo-resolve/error-names-every-unregistered-name", goOnly: true, want: 3, fx: umbFx, argv: j("repo", "resolve", "x", "web", "y"),
			check: func(t *testing.T, e envl, _ run) {
				m, _ := at(e, "error.message").(string)
				if !strings.Contains(m, "x, y") || strings.Contains(m, "web") {
					t.Errorf("message = %q", m)
				}
			}},
		scn{name: "repo-resolve/repo-flag-rejected", goOnly: true, want: 2, fx: umbFx, argv: j("repo", "resolve", "--repo", "web", "web")},
		scn{name: "repo-resolve/zero-names-envelope", goOnly: true, want: 0, fx: umbFx, argv: j("repo", "resolve"),
			check: func(t *testing.T, e envl, _ run) {
				if l, ok := at(e, "data.repos").([]any); !ok || len(l) != 0 {
					t.Errorf("data.repos = %#v", at(e, "data.repos"))
				}
			}},
	)

	// ---- repo which
	worktree := func(t *testing.T, dir string) {
		git(t, filepath.Join(dir, "web"), "worktree", "add", "-q", "-b", "feat/x", filepath.Join(dir, "web-wt"))
	}
	subdirs := func(t *testing.T, dir string, in *info) {
		write(t, dir, "web/src/deep/x.txt", "x\n")
		write(t, dir, "api/lib/x.txt", "x\n")
		write(t, dir, "docs/x.txt", "x\n")
		if err := os.Symlink("web", filepath.Join(dir, "weblink")); err != nil {
			t.Fatal(err)
		}
	}
	whichFx := withFx(umbFx, func(f *fx) { f.after = subdirs })
	which := func(name string, f fx, cwd string, want int, wn, wr string) scn {
		s := scn{name: "repo-which/" + name, fx: f, cwd: cwd, argv: j("repo", "which"), old: []string{"hv-resolve-repo"}, oldMap: whichMap, want: want}
		if want == 0 {
			s.check = checkWhich(wn, wr)
		}
		return s
	}
	maskedFx := withFx(whichFx, func(f *fx) {
		prev := f.after
		f.after = afterAll(prev, func(t *testing.T, dir string, in *info) { os.MkdirAll(filepath.Join(dir, "web", ".hv"), 0o755) })
	})
	nested := withFx(umbFx, func(f *fx) {
		f.after = func(t *testing.T, dir string, in *info) {
			os.MkdirAll(filepath.Join(dir, "apps", "deep"), 0o755)
			git(t, filepath.Join(dir, "apps", "deep"), "init", "-q", "-b", "main")
			git(t, filepath.Join(dir, "apps", "deep"), "config", "user.name", "F")
			git(t, filepath.Join(dir, "apps", "deep"), "config", "user.email", "f@e")
			commitFile(t, filepath.Join(dir, "apps", "deep"), "c", "f.txt", "x\n")
			write(t, dir, "apps/deep/src/x.txt", "x\n")
			write(t, dir, ".hv/repos.json", `{"repos": [{"name": "deep", "path": "apps/deep"}, {"name": "web", "path": "web"}]}`+"\n")
		}
	})
	add(
		which("inside-web", whichFx, "web", 0, "web", "web"),
		which("inside-api", whichFx, "api", 0, "api", "api"),
		which("deep-in-web", whichFx, "web/src/deep", 0, "web", "web"),
		which("deep-in-api", whichFx, "api/lib", 0, "api", "api"),
		which("through-a-symlinked-cwd", whichFx, "weblink", 0, "web", "web"),
		which("nested-registered-path", nested, "apps/deep", 0, "deep", "apps/deep"),
		which("nested-registered-path-deeper", nested, "apps/deep/src", 0, "deep", "apps/deep"),
		which("sibling-of-nested-path", nested, "web", 0, "web", "web"),
		which("umbrella-root-is-not-registered", whichFx, "", 3, "", ""),
		which("umbrella-subdir-in-the-root-repo", whichFx, "docs", 3, "", ""),
		which("not-an-umbrella", stdFx, "", 3, "", ""),
		which("no-hv", fx{noHV: true}, "", 3, "", ""),
		which("empty-registry", withFx(whichFx, func(f *fx) {
			prev := f.after
			f.after = afterAll(prev, func(t *testing.T, dir string, in *info) { write(t, dir, ".hv/repos.json", `{"repos": []}`+"\n") })
		}), "web", 3, "", ""),
		which("corrupt-registry", withFx(whichFx, func(f *fx) {
			prev := f.after
			f.after = afterAll(prev, func(t *testing.T, dir string, in *info) { write(t, dir, ".hv/repos.json", "{oops") })
		}), "web", 3, "", ""),
		which("git-repo-not-in-the-registry", withFx(whichFx, func(f *fx) {
			prev := f.after
			f.after = afterAll(prev, func(t *testing.T, dir string, in *info) {
				write(t, dir, ".hv/repos.json", `{"repos": [{"name": "api", "path": "api"}]}`+"\n")
			})
		}), "web", 3, "", ""),
		which("masked-by-a-stray-hv", maskedFx, "web", 3, "", ""),
		which("masked-from-a-subdir-of-the-sub-repo", maskedFx, "web/src/deep", 3, "", ""),
		which("stray-hv-in-another-sub-repo-does-not-mask", maskedFx, "api", 0, "api", "api"),
		which("stray-hv-in-the-root-subdir-docs-is-not-registered", withFx(whichFx, func(f *fx) {
			prev := f.after
			f.after = afterAll(prev, func(t *testing.T, dir string, in *info) { os.MkdirAll(filepath.Join(dir, "docs", ".hv"), 0o755) })
		}), "docs", 3, "", ""),
		scn{name: "repo-which/layout-b-worktree-maps-to-the-main-repo", fx: whichFx, prep: worktree, cwd: "web-wt", argv: j("repo", "which"), old: []string{"hv-resolve-repo"},
			oldMap: whichMap, want: 0, check: checkWhich("web", "web")},
		scn{name: "repo-which/layout-b-worktree-subdir", fx: whichFx, prep: func(t *testing.T, dir string) {
			worktree(t, dir)
			write(t, dir, "web-wt/pkg/x.txt", "x\n")
		}, cwd: "web-wt/pkg", argv: j("repo", "which"), old: []string{"hv-resolve-repo"}, oldMap: whichMap, want: 0, check: checkWhich("web", "web")},
		scn{name: "repo-which/worktree-of-an-unregistered-repo", fx: whichFx, prep: func(t *testing.T, dir string) {
			git(t, filepath.Join(dir, "api"), "worktree", "add", "-q", "-b", "feat/y", filepath.Join(dir, "api-wt"))
			write(t, dir, ".hv/repos.json", `{"repos": [{"name": "web", "path": "web"}]}`+"\n")
		}, cwd: "api-wt", argv: j("repo", "which"), old: []string{"hv-resolve-repo"}, oldMap: whichMap, want: 3},
		scn{name: "repo-which/worktree-inside-the-sub-repo-with-stray-hv-masks", fx: whichFx, prep: func(t *testing.T, dir string) {
			git(t, filepath.Join(dir, "web"), "worktree", "add", "-q", "-b", "feat/z", filepath.Join(dir, "web", "wt"))
			os.MkdirAll(filepath.Join(dir, "web", ".hv"), 0o755)
		}, cwd: "web/wt", argv: j("repo", "which"), old: []string{"hv-resolve-repo"}, oldMap: whichMap, want: 3},
		scn{name: "repo-which/git-missing-is-5", goOnly: true, fx: whichFx, cwd: "web", argv: j("repo", "which"), want: 5,
			env:   []string{"PATH=/nonexistent"},
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "error.code", "unavailable") }},
		scn{name: "repo-which/repo-flag-rejected", goOnly: true, want: 2, fx: whichFx, cwd: "web", argv: j("repo", "which", "--repo", "web")},
		scn{name: "repo-which/positional-rejected", goOnly: true, want: 2, argv: j("repo", "which", "x")},
		scn{name: "repo-which/masked-error-hint-names-the-stray-dir", goOnly: true, want: 3, fx: maskedFx, cwd: "web", argv: j("repo", "which"),
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "error.code", "resolution")
				if m, _ := at(e, "error.message").(string); !strings.Contains(m, "stray .hv/") || !strings.Contains(m, "web") {
					t.Errorf("message = %q", m)
				}
				if h, _ := at(e, "error.hint").(string); !strings.Contains(h, filepath.Join("web", ".hv")) {
					t.Errorf("hint = %q", h)
				}
			}},
		scn{name: "repo-which/with-C", goOnly: true, want: 0, fx: whichFx, argv: j("-C", "web/src", "repo", "which"),
			check: eqCheck("data.name", "web")},
		scn{name: "repo-which/not-in-a-git-repo-message", goOnly: true, want: 3, fx: fx{noHV: false, noCommit: false}, argv: j("-C", "/", "repo", "which"),
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "error.code", "resolution") }},
	)

	// ---- update: every install type, status and the safety net
	add(
		updScn("override/behind", upd.homeNone, "1.2.4", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "behind"),
		updScn("override/current", upd.homeNone, "1.2.3", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "current"),
		updScn("override/ahead", upd.homeNone, "1.2.2", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "ahead"),
		updScn("override/numeric-not-lexical", upd.homeNone, "1.10.0", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "behind"),
		updScn("override/major", upd.homeNone, "2.0.0", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "behind"),
		updScn("override/two-part-latest", upd.homeNone, "1.2", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "ahead"),
		updScn("override/v-prefixed-latest-from-the-variable", upd.homeNone, "v1.3.0", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "behind"),
		updScn("override/prerelease-suffix-ignored", upd.homeNone, "1.2.3-rc1", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "current"),
		updScn("override/four-parts-only-first-three-count", upd.homeNone, "1.2.3.9", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "current"),
		updScn("override/huge-component", upd.homeNone, "1.2.99999999999999999999999", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "behind"),
		updScn("override/latest-without-digits", upd.homeNone, "abc", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "ahead"),
		updScn("override/wins-over-the-plugin-root", upd.homePlugin, "1.2.4", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "behind"),
		updNoRoot("override/missing-dir-falls-through", upd.homeNone, "1.2.4", []string{"HV_INSTALL_ROOT=" + filepath.Join(upd.empty, "gone")}, "behind"),
		updScn("plugin/claude-plugin-root", upd.homeNone, "1.2.4", []string{"CLAUDE_PLUGIN_ROOT=" + upd.plain}, "plugin", "behind"),
		updNoRoot("plugin/foreign-claude-plugin-root-ignored", upd.homeNone, "1.2.4", []string{"CLAUDE_PLUGIN_ROOT=" + upd.foreign}, "behind"),
		updNoRoot("plugin/claude-plugin-root-without-manifest", upd.homeNone, "1.2.4", []string{"CLAUDE_PLUGIN_ROOT=" + upd.empty}, "behind"),
		updScn("plugin/marketplace-dir", upd.homePlugin, "1.2.3", nil, "plugin", "current"),
		updScn("plugin/cache-newest-version-with-manifest", upd.homeCache, "1.2.4", nil, "plugin", "behind"),
		updScn("plugin/override-beats-marketplace", upd.homePlugin, "1.2.3", []string{"HV_INSTALL_ROOT=" + upd.plain}, "override", "current"),
		updScn("stow/agents-skills-dir", upd.homeAgents, "1.2.4", nil, "stow", "behind"),
		updScn("stow/skill-symlink-walk", upd.homeStow, "1.2.4", nil, "stow", "behind"),
		updScn("stow/skill-symlink-walk-current", upd.homeStow, "1.2.3", nil, "stow", "current"),
		updNoRoot("unknown/no-install-anywhere", upd.homeNone, "1.2.4", nil, "behind"),
		updNoRoot("unknown/latest-still-reported", upd.homeNone, "9.9.9", nil, "behind"),
		scn{name: "update/repo-clone-found-by-walking-up-from-the-binary", fx: fx{noHV: true}, argv: j("update"), old: []string{"hv-update-check"}, want: 0,
			env: []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=1.2.4", "HV_LATEST_VERSION=1.2.4"}, bin: upd.cloneBin, oldBin: upd.cloneOld,
			check: checkUpdate("repo", "behind")},
		scn{name: "update/repo-clone-current", fx: fx{noHV: true}, argv: j("update"), old: []string{"hv-update-check"}, want: 0,
			env: []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=1.2.3", "HV_LATEST_VERSION=1.2.3"}, bin: upd.cloneBin, oldBin: upd.cloneOld,
			check: checkUpdate("repo", "current")},
		scn{name: "update/plugin-beats-repo-clone", fx: fx{noHV: true}, argv: j("update"), old: []string{"hv-update-check"}, want: 0,
			env: []string{"HOME=" + upd.homePlugin, "HV_TEST_LATEST_VERSION=1.2.3", "HV_LATEST_VERSION=1.2.3"}, bin: upd.cloneBin, oldBin: upd.cloneOld,
			check: checkUpdate("plugin", "current")},
		scn{name: "update/runs-inside-a-project", argv: j("update"), old: []string{"hv-update-check"}, want: 0, bin: upd.bin,
			env:   []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=1.2.4", "HV_LATEST_VERSION=1.2.4", "HV_INSTALL_ROOT=" + upd.plain},
			check: checkUpdate("override", "behind")},
		scn{name: "update/runs-from-a-subdirectory", fx: withFile("sub/x.txt", "x\n"), cwd: "sub", argv: j("update"), old: []string{"hv-update-check"}, want: 0, bin: upd.bin,
			env:   []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=1.2.4", "HV_LATEST_VERSION=1.2.4", "HV_INSTALL_ROOT=" + upd.plain},
			check: checkUpdate("override", "behind")},
		// A resolved root without plugin.json: currentVersion is "" and the
		// status unknown, as old read_version gave (ruling: the stamped
		// version is only the no-root fallback).
		scn{name: "update/override-without-manifest-is-empty", fx: fx{noHV: true}, argv: j("update"), old: []string{"hv-update-check"}, want: 0, bin: upd.bin,
			env: []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=1.2.4", "HV_LATEST_VERSION=1.2.4", "HV_INSTALL_ROOT=" + upd.empty},
			check: both(eqCheck("data.installType", "override"), eqCheck("data.currentVersion", ""), eqCheck("data.status", "unknown"))},
		scn{name: "update/dev-build-compares-as-zero", fx: fx{noHV: true}, argv: j("update"), goOnly: true, want: 0,
			env:   []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=0.0.0"},
			check: both(eqCheck("data.currentVersion", "dev"), eqCheck("data.status", "current"))},
		scn{name: "update/without-the-test-variable-only-the-fake-gh-runs", fx: fx{noHV: true}, argv: j("update"), old: []string{"hv-update-check"}, want: 0, bin: upd.bin,
			env: []string{"HOME=" + upd.homeNone, "HV_INSTALL_ROOT=" + upd.plain, "FAKE_TRACKER_LOG=" + filepath.Join(harnessTmp, "update-gh.log")},
			check: func(t *testing.T, e envl, ref run) {
				checkUpdate("override", "unknown")(t, e, ref)
				b, err := os.ReadFile(filepath.Join(harnessTmp, "update-gh.log"))
				if err != nil {
					t.Fatalf("the fake gh was not called: %v", err)
				}
				for _, l := range lines(string(b)) {
					if !strings.HasPrefix(l, "api repos/l4ci/hv-skills/releases/latest") {
						t.Errorf("gh was called with %q", l)
					}
				}
			}},
		scn{name: "update/positional-rejected", goOnly: true, want: 2, argv: j("update", "x"), env: []string{"HV_TEST_LATEST_VERSION=1.0.0"}},
		scn{name: "update/repo-flag-rejected", goOnly: true, want: 2, argv: j("update", "--repo", "web"), env: []string{"HV_TEST_LATEST_VERSION=1.0.0"}},
		scn{name: "update/data-shape", goOnly: true, want: 0, argv: j("update"), bin: upd.bin,
			env: []string{"HOME=" + upd.homeNone, "HV_TEST_LATEST_VERSION=1.2.4", "HV_INSTALL_ROOT=" + upd.plain},
			check: func(t *testing.T, e envl, _ run) {
				d, _ := at(e, "data").(map[string]any)
				var keys []string
				for k := range d {
					keys = append(keys, k)
				}
				sort.Strings(keys)
				want := []string{"currentVersion", "installRoot", "installType", "latestVersion", "status", "updateCommand"}
				if !reflect.DeepEqual(keys, want) {
					t.Errorf("keys = %v", keys)
				}
			}},
	)

	finish(t, all)
}

// TestUpdateOldHelperHonoursTheTestVariable: the reference must not reach
// the network either. With the variable set the old helper never looks for gh,
// so a PATH with no gh at all still answers.
func TestUpdateOldHelperHonoursTheTestVariable(t *testing.T) {
	r := exec1e(t, t.TempDir(), "", []string{"PATH=/usr/bin:/bin", "HV_LATEST_VERSION=3.2.1", "HOME=" + harnessTmp, "HV_INSTALL_ROOT=" + harnessTmp},
		filepath.Join(stagedBin, "hv-update-check"))
	if r.code != 0 || !strings.Contains(r.stdout, `"latestVersion": "3.2.1"`) {
		t.Fatalf("old helper: %d %s %s", r.code, r.stdout, r.stderr)
	}
}

// TestOldHelperDisagreements pins, against the real old helpers, each place
// where the verb contract and the helper differ and the Go binary follows the
// contract. A change in the helper makes this fail, so the list stays true.
func TestOldHelperDisagreements(t *testing.T) {
	dir, _ := fx{}.build(t)
	old := func(name string, args ...string) run {
		return exec1e(t, dir, "", nil, filepath.Join(stagedBin, name), args...)
	}
	// 1. contract: "falls back to a raw string (opus, empty string)"; helper: ${2:?} refuses an empty value.
	if r := old("hv-config-set", "git.baseBranch", ""); r.code == 0 {
		t.Errorf("hv-config-set accepts an empty value now: the contract and the helper agree, drop the note")
	}
	// 2. the helper accepts NaN and writes it bare; Go treats it as not JSON and stores the string.
	if r := old("hv-config-set", "git.baseBranch", "NaN"); r.code != 0 {
		t.Fatalf("hv-config-set NaN: %d %s", r.code, r.stderr)
	}
	b, _ := os.ReadFile(filepath.Join(dir, ".hv", "config.json"))
	if !strings.Contains(string(b), "NaN") || strings.Contains(string(b), `"NaN"`) {
		t.Errorf("expected a bare NaN in %s", b)
	}
	goDir, _ := fx{}.build(t)
	if r := exec1(t, goDir, "", hvBin, "--json", "config", "set", "git.baseBranch", "NaN"); r.code != 0 || !strings.Contains(r.stdout, `"value": "NaN"`) {
		t.Errorf("go: %d %s", r.code, r.stdout)
	}
	// 3. the helper stores a non-schema key; Go refuses it with exit 2.
	if r := old("hv-config-set", "nope.key", "1"); r.code != 0 {
		t.Errorf("hv-config-set accepted a non-schema key: %d", r.code)
	}
	// 4. a corrupt config.json is replaced silently by both helper and Go; the contract only names "not a JSON object" for exit 70.
	cdir, _ := fx{config: "{oops"}.build(t)
	if r := exec1e(t, cdir, "", nil, filepath.Join(stagedBin, "hv-config-set"), "docs.path", "x"); r.code != 0 {
		t.Errorf("old on corrupt: %d %s", r.code, r.stderr)
	}
}
