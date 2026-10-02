// Package update is `hv update`: it finds how hv-skills is installed, reads
// the running version, asks GitHub for the latest release and says what the
// user would run to update. It never runs the update. Ported from
// bin/hv-update-check.
package update

import (
	"context"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Repo is the GitHub repository whose latest release hv update asks about.
const Repo = "l4ci/hv-skills"

// Install types.
const (
	Plugin   = "plugin"
	Stow     = "stow"
	RepoType = "repo"
	Override = "override"
	Unknown  = "unknown"
)

// Result is the data of `hv update`.
type Result struct {
	InstallType    string
	InstallRoot    string
	CurrentVersion string
	LatestVersion  string
	Status         string
	UpdateCommand  string
}

// Env is everything Check reads from the machine, so tests can pin it.
type Env struct {
	Getenv  func(string) string
	Home    string
	ExeDir  string // the directory of the running binary: the old BIN_DIR
	Current string // the running binary's version
	// Latest returns the latest release version, or "" when it cannot be found.
	Latest func() string
}

// DefaultEnv is the real machine. Latest reads HV_TEST_LATEST_VERSION first
// (no network) and otherwise runs `gh api repos/<repo>/releases/latest`, which
// only reads.
func DefaultEnv(current string) Env {
	home, _ := os.UserHomeDir()
	exe, _ := os.Executable()
	if real, err := filepath.EvalSymlinks(exe); err == nil {
		exe = real
	}
	return Env{Getenv: os.Getenv, Home: home, ExeDir: filepath.Dir(exe), Current: current, Latest: ghLatest}
}

// lookPath finds gh. It is a variable so tests can refuse any gh that is not
// the fake in test/fakes: hv update must never reach the network from a test.
var lookPath = exec.LookPath

// ghLatest is fetch_latest: HV_TEST_LATEST_VERSION (the new name of the old
// HV_LATEST_VERSION) skips the network; without gh or on any failure it is "".
func ghLatest() string {
	if v := os.Getenv("HV_TEST_LATEST_VERSION"); v != "" {
		return v
	}
	gh, err := lookPath("gh")
	if err != nil {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, gh, "api", "repos/"+Repo+"/releases/latest", "--jq", ".tag_name").Output()
	if err != nil {
		return ""
	}
	tag := strings.TrimRight(string(out), "\n")
	return strings.TrimPrefix(tag, "v")
}

// Check is hv-update-check. currentVersion is the running binary's version,
// but empty when no install resolves, as the old helper gave when it found no
// plugin.json.
func Check(e Env) Result {
	kind, root := detect(e)
	r := Result{InstallType: kind, InstallRoot: root}
	if root != "" {
		r.CurrentVersion = e.Current
	}
	if e.Latest != nil {
		r.LatestVersion = e.Latest()
	}
	r.Status = "unknown"
	if r.CurrentVersion != "" && r.LatestVersion != "" {
		switch c := Compare(r.CurrentVersion, r.LatestVersion); {
		case c < 0:
			r.Status = "behind"
		case c > 0:
			r.Status = "ahead"
		default:
			r.Status = "current"
		}
	}
	r.UpdateCommand = command(kind, root)
	return r
}

func command(kind, root string) string {
	switch kind {
	case Plugin:
		return "claude plugin update hv-skills"
	case Stow:
		if root != "" {
			return "cd " + root + " && git pull"
		}
		return "cd ~/Code/hv-skills && git pull"
	case RepoType:
		if root != "" {
			return "cd " + root + " && git pull"
		}
		return "git pull in your hv-skills clone"
	case Override:
		return "manual — HV_INSTALL_ROOT was set"
	}
	return "reinstall: claude plugin install hv-skills"
}

func isFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}

func isDir(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

func manifest(root string) string { return filepath.Join(root, ".claude-plugin", "plugin.json") }

// detect is resolve_root of hv-update-check: hvlib_paths.resolve_plugin_root
// first, then the stow symlink walk, then a walk up from the binary.
func detect(e Env) (kind, root string) {
	if r, k := resolvePluginRoot(e); k != "" {
		return k, r
	}
	for _, link := range []string{
		filepath.Join(e.Home, ".claude/skills/hv-update"),
		filepath.Join(e.Home, ".agents/skills/hv-update"),
		filepath.Join(e.Home, ".claude/skills/hv-init"),
		filepath.Join(e.Home, ".agents/skills/hv-init"),
	} {
		fi, err := os.Lstat(link)
		if err != nil || fi.Mode()&os.ModeSymlink == 0 || !isDir(link) {
			continue
		}
		target, err := filepath.EvalSymlinks(link)
		if err != nil {
			continue
		}
		repo := filepath.Dir(target)
		if isFile(manifest(repo)) {
			return Stow, repo
		}
	}
	for _, up := range []string{e.ExeDir, filepath.Join(e.ExeDir, ".."), filepath.Join(e.ExeDir, "..", "..")} {
		if e.ExeDir != "" && isFile(manifest(up)) {
			abs, _ := filepath.Abs(up)
			return RepoType, abs
		}
	}
	return Unknown, ""
}

// resolvePluginRoot is hvlib_paths.resolve_plugin_root: the kind is "" when
// nothing matched.
func resolvePluginRoot(e Env) (root, kind string) {
	if o := e.Getenv("HV_INSTALL_ROOT"); o != "" && isDir(o) {
		return o, Override
	}
	if cpr := e.Getenv("CLAUDE_PLUGIN_ROOT"); cpr != "" {
		if mf := manifest(cpr); isFile(mf) {
			if m, ok := fsio.LoadJSON(mf, nil).(*jsonx.Object); ok {
				if n, _ := m.Get("name"); n == "hv-skills" {
					return cpr, Plugin
				}
			}
		}
	}
	cands, _ := filepath.Glob(filepath.Join(e.Home, ".claude/plugins/*/hv-skills"))
	sort.Strings(cands)
	cands = append(cands, filepath.Join(e.Home, ".claude/plugins/hv-skills"))
	for _, c := range cands {
		if isFile(manifest(c)) {
			return c, Plugin
		}
	}
	cache := filepath.Join(e.Home, ".claude/plugins/cache/hv-skills/hv-skills")
	if isDir(cache) {
		var versions []string
		if ents, err := os.ReadDir(cache); err == nil {
			for _, ent := range ents {
				if isDir(filepath.Join(cache, ent.Name())) {
					versions = append(versions, ent.Name())
				}
			}
		}
		sort.SliceStable(versions, func(i, j int) bool { return cmpRuns(versions[i], versions[j]) > 0 })
		for _, v := range versions {
			if c := filepath.Join(cache, v); isFile(manifest(c)) {
				return c, Plugin
			}
		}
	}
	for _, c := range []string{filepath.Join(e.Home, ".agents/skills/hv-skills"), filepath.Join(e.Home, ".agents/skills")} {
		if isFile(manifest(c)) {
			return c, Stow
		}
	}
	return "", ""
}

var digits = regexp.MustCompile(`[0-9]+`)

// runs is tuple(int(p) for p in re.findall(r"\d+", v)).
func runs(v string) []*big.Int {
	var out []*big.Int
	for _, m := range digits.FindAllString(v, -1) {
		n, _ := new(big.Int).SetString(m, 10)
		out = append(out, n)
	}
	return out
}

// cmpRuns compares the numeric runs of a and b as Python tuples do, with
// (0,) standing for a name that has none.
func cmpRuns(a, b string) int {
	pa, pb := runs(a), runs(b)
	if len(pa) == 0 {
		pa = []*big.Int{new(big.Int)}
	}
	if len(pb) == 0 {
		pb = []*big.Int{new(big.Int)}
	}
	for i := 0; i < len(pa) && i < len(pb); i++ {
		if c := pa[i].Cmp(pb[i]); c != 0 {
			return c
		}
	}
	switch {
	case len(pa) < len(pb):
		return -1
	case len(pa) > len(pb):
		return 1
	}
	return 0
}

// Compare is cmp_semver: the first three numeric runs of each version, zero
// padded to three, compared as numbers. It returns -1, 0 or 1.
func Compare(a, b string) int {
	three := func(v string) []*big.Int {
		p := runs(v)
		if len(p) > 3 {
			p = p[:3]
		}
		for len(p) < 3 {
			p = append(p, new(big.Int))
		}
		return p
	}
	pa, pb := three(a), three(b)
	for i := range pa {
		if c := pa[i].Cmp(pb[i]); c != 0 {
			return c
		}
	}
	return 0
}
