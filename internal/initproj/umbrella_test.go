package initproj

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// tree builds an umbrella fixture: git children (dir or worktree-style .git
// file), a plain dir, a hidden git child, plus extra files.
func tree(t *testing.T, umbrellaGit bool, files map[string]string, gitKids ...string) string {
	t.Helper()
	root := t.TempDir()
	for _, k := range gitKids {
		if err := os.MkdirAll(filepath.Join(root, k, ".git"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	os.MkdirAll(filepath.Join(root, "docs"), 0o755)
	os.MkdirAll(filepath.Join(root, ".hidden", ".git"), 0o755)
	if umbrellaGit {
		os.MkdirAll(filepath.Join(root, ".git"), 0o755)
	}
	for name, body := range files {
		p := filepath.Join(root, name)
		os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func read(t *testing.T, root, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, rel))
	if err != nil {
		return "<missing>"
	}
	return string(b)
}

func TestCandidates(t *testing.T) {
	root := tree(t, false, nil, "web", "api")
	// a worktree-style child has a .git file; a symlink to a git dir counts
	os.MkdirAll(filepath.Join(root, "wt"), 0o755)
	os.WriteFile(filepath.Join(root, "wt", ".git"), []byte("gitdir: x\n"), 0o644)
	os.Symlink(filepath.Join(root, "web"), filepath.Join(root, "link"))
	got, err := Candidates(root)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"api", "link", "web", "wt"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestListIsReadOnly(t *testing.T) {
	root := tree(t, true, nil, "web")
	l, err := List(root)
	if err != nil || !l.IsGitRepo || !reflect.DeepEqual(l.Candidates, []string{"web"}) {
		t.Fatalf("%+v %v", l, err)
	}
	if _, err := os.Stat(filepath.Join(root, ".hv")); err == nil {
		t.Fatal("List wrote .hv")
	}
	empty, _ := List(t.TempDir())
	if empty.IsGitRepo || len(empty.Candidates) != 0 {
		t.Fatalf("%+v", empty)
	}
}

func TestNoCandidatesLeavesNothing(t *testing.T) {
	root := t.TempDir()
	seeded := false
	_, err := Umbrella(root, UmbrellaOptions{All: true}, func() error { seeded = true; return nil })
	if !errors.Is(err, ErrNoCandidates) || seeded {
		t.Fatalf("err=%v seeded=%v", err, seeded)
	}
	if _, err := os.Stat(filepath.Join(root, ".hv")); err == nil {
		t.Fatal(".hv created")
	}
}

func TestSeedFailureIsReturned(t *testing.T) {
	root := tree(t, false, nil, "web")
	boom := errors.New("corrupt")
	if _, err := Umbrella(root, UmbrellaOptions{All: true}, func() error { return boom }); !errors.Is(err, boom) {
		t.Fatal(err)
	}
}

func TestIdempotent(t *testing.T) {
	root := tree(t, true, nil, "web", "api")
	first, err := Umbrella(root, UmbrellaOptions{All: true}, nil)
	if err != nil || !first.Changed || len(first.Created) == 0 {
		t.Fatalf("%+v %v", first, err)
	}
	second, err := Umbrella(root, UmbrellaOptions{All: true}, nil)
	if err != nil || second.Changed || len(second.Created) != 0 {
		t.Fatalf("second run changed: %+v %v", second, err)
	}
}

// TestParityWithOldHelper runs hv-umbrella-init and Umbrella on identical
// trees and compares what they write and report.
func TestParityWithOldHelper(t *testing.T) {
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not installed")
	}
	helper, _ := filepath.Abs("../../bin/hv-umbrella-init")
	if _, err := os.Stat(helper); err != nil {
		t.Skip("old helper gone (A9 S7): parity frozen")
	}
	prior := `{"repos": [{"name": "web", "path": "./web"}, {"name": "gone", "path": "./gone"}, {"name": "api", "path": "./api"}]}`
	cases := []struct {
		name  string
		git   bool
		files map[string]string
		kids  []string
		stdin string // the old helper's line
		opts  UmbrellaOptions
	}{
		{"all", true, nil, []string{"web", "api"}, "all", UmbrellaOptions{All: true}},
		{"subset", true, nil, []string{"web", "api", "db"}, "web,db", UmbrellaOptions{Names: []string{"web", "db"}}},
		{"none", false, nil, []string{"web"}, "none", UmbrellaOptions{}},
		{"empty line is none", false, nil, []string{"web"}, "", UmbrellaOptions{}},
		{"unknown and blank names", true, nil, []string{"web"}, " web , nope,,", UmbrellaOptions{Names: []string{" web ", " nope", "", ""}}},
		{"prior kept, stale dropped", false, map[string]string{".hv/repos.json": prior}, []string{"web", "api", "db"}, "db", UmbrellaOptions{Names: []string{"db"}}},
		{"gitignore appended", true, map[string]string{".gitignore": "node_modules/\n.hv/\n"}, []string{"web"}, "all", UmbrellaOptions{All: true}},
		{"gitignore no trailing newline", true, map[string]string{".gitignore": "a\nb"}, []string{"web"}, "all", UmbrellaOptions{All: true}},
		{"gitignore crlf", true, map[string]string{".gitignore": "a\r\n.claude/\r\n"}, []string{"web"}, "all", UmbrellaOptions{All: true}},
		{"gitignore complete", true, map[string]string{".gitignore": ".claude/\n.hv/\n/web/\n"}, []string{"web"}, "all", UmbrellaOptions{All: true}},
		{"corrupt repos.json", false, map[string]string{".hv/repos.json": "{nope"}, []string{"web"}, "all", UmbrellaOptions{All: true}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			oldRoot := tree(t, tc.git, tc.files, tc.kids...)
			newRoot := tree(t, tc.git, tc.files, tc.kids...)
			cmd := exec.Command("bash", helper)
			cmd.Dir = oldRoot
			cmd.Stdin = strings.NewReader(tc.stdin + "\n")
			var stdout, stderr bytes.Buffer
			cmd.Stdout, cmd.Stderr = &stdout, &stderr
			if err := cmd.Run(); err != nil {
				t.Fatalf("old helper: %v\n%s", err, stderr.String())
			}
			res, err := Umbrella(newRoot, tc.opts, nil)
			if err != nil {
				t.Fatal(err)
			}
			for _, f := range []string{".hv/repos.json", ".gitignore"} {
				if o, n := read(t, oldRoot, f), read(t, newRoot, f); o != n {
					t.Errorf("%s differs\nold: %q\nnew: %q", f, o, n)
				}
			}
			for _, n := range res.Registered {
				if _, err := os.Stat(filepath.Join(newRoot, ".hv", "knowledge", n)); err != nil {
					t.Errorf("knowledge dir for %s missing", n)
				}
			}
			oldSnap, newSnap := snapshot(oldRoot), snapshot(newRoot)
			if !reflect.DeepEqual(oldSnap, newSnap) {
				t.Errorf("tree differs\nold: %v\nnew: %v", oldSnap, newSnap)
			}
			wantOut := `{"registered":[` + quoteJoin(res.Registered) + `],"umbrellaIsGitRepo":` + map[bool]string{true: "true", false: "false"}[res.IsGitRepo] + "}\n"
			if stdout.String() != wantOut {
				t.Errorf("summary\nold: %q\nnew: %q", stdout.String(), wantOut)
			}
			var oldWarn []string
			for _, l := range strings.Split(strings.TrimSpace(stderr.String()), "\n") {
				if strings.HasPrefix(l, "warning: ") {
					oldWarn = append(oldWarn, strings.TrimPrefix(l, "warning: "))
				}
			}
			if !reflect.DeepEqual(oldWarn, append([]string(nil), res.Warnings...)) && !(len(oldWarn) == 0 && len(res.Warnings) == 0) {
				t.Errorf("warnings\nold: %q\nnew: %q", oldWarn, res.Warnings)
			}
		})
	}
}

func quoteJoin(l []string) string {
	q := make([]string, len(l))
	for i, s := range l {
		q[i] = `"` + s + `"`
	}
	return strings.Join(q, ",")
}
