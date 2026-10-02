package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestProjectDigest(t *testing.T) {
	base, _ := fx{}.build(t)
	d1 := projectDigest(base)
	if d := projectDigest(copyTree(t, base)); d != d1 {
		t.Errorf("a copy digests differently: %s vs %s", d, d1)
	}
	// The git index carries stat data and the objects follow from the refs:
	// neither may move the digest.
	idx := filepath.Join(base, ".git", "index")
	saved, _ := os.ReadFile(idx)
	os.WriteFile(idx, []byte("scribble"), 0o644)
	os.WriteFile(filepath.Join(base, ".git", "COMMIT_EDITMSG"), []byte("scribble"), 0o644)
	if d := projectDigest(base); d != d1 {
		t.Errorf("index/COMMIT_EDITMSG changed the digest")
	}
	os.WriteFile(idx, saved, 0o644)
	// A file change and a new commit both do.
	write(t, base, ".hv/BACKLOG.md", "changed\n")
	d2 := projectDigest(base)
	if d2 == d1 {
		t.Error("a changed file left the digest alone")
	}
	git(t, base, "add", "-A")
	git(t, base, "commit", "-q", "-m", "more")
	if d := projectDigest(base); d == d2 {
		t.Error("a new commit left the digest alone")
	}
	// A nested repository (an umbrella sub-repo) counts too.
	sub, _ := fx{subs: map[string][]string{"web": {"feat: one"}}}.build(t)
	before := projectDigest(sub)
	commitFile(t, filepath.Join(sub, "web"), "feat: two", "g.txt", "x\n")
	if projectDigest(sub) == before {
		t.Error("a commit in a sub-repo left the digest alone")
	}
}

func TestFixtureHashesRepeat(t *testing.T) {
	_, a := fx{commits: 2}.build(t)
	// Another description shares nothing with the template above, but a fixed
	// commit time makes an independent build reproduce the same hashes.
	dir := t.TempDir()
	b := fx{commits: 2}.buildIn(t, dir)
	if a.h1 != b.h1 || a.refactor != b.refactor || a.head != b.head {
		t.Errorf("fixture hashes differ between builds: %+v vs %+v", a, b)
	}
}

func TestOracleKey(t *testing.T) {
	k1 := oracleKey(t, map[string]any{"argv": []string{"a", "b"}, "env": []string{"X=1"}})
	if k2 := oracleKey(t, map[string]any{"env": []string{"X=1"}, "argv": []string{"a", "b"}}); k1 != k2 {
		t.Error("key depends on map order")
	}
	for name, in := range map[string]map[string]any{
		"argv": {"argv": []string{"a", "c"}, "env": []string{"X=1"}},
		"env":  {"argv": []string{"a", "b"}, "env": []string{"X=2"}},
	} {
		if oracleKey(t, in) == k1 {
			t.Errorf("a different %s gave the same key", name)
		}
	}
}

func TestOracleCacheRoundTrip(t *testing.T) {
	t.Setenv("HV_PARITY_CACHE", t.TempDir())
	type val struct {
		A int
		B map[string]string
	}
	want := val{3, map[string]string{"k": "v"}}
	var got val
	t.Setenv("HV_PARITY_ORACLE", "off")
	oracleStore(t, "k1", want)
	if oracleLoad("k1", &got) {
		t.Error("off mode stored or loaded")
	}
	t.Setenv("HV_PARITY_ORACLE", "cache")
	if oracleLoad("k1", &got) {
		t.Error("hit before any store")
	}
	oracleStore(t, "k1", want)
	if !oracleLoad("k1", &got) || !reflect.DeepEqual(got, want) {
		t.Errorf("round trip = %+v", got)
	}
	t.Setenv("HV_PARITY_ORACLE", "fresh")
	if oracleLoad("k1", &got) {
		t.Error("fresh mode read the cache")
	}
	oracleStore(t, "k1", val{4, nil}) // fresh refreshes the entry
	t.Setenv("HV_PARITY_ORACLE", "cache")
	if !oracleLoad("k1", &got) || got.A != 4 {
		t.Errorf("fresh did not refresh: %+v", got)
	}
	os.WriteFile(filepath.Join(oracleCacheDir(), "bad.json"), []byte("{not json"), 0o644)
	if oracleLoad("bad", &got) {
		t.Error("a corrupt entry counted as a hit")
	}
}

func TestPruneOracleCache(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HV_PARITY_CACHE", dir)
	old := time.Now().Add(-10 * 24 * time.Hour)
	for _, n := range []string{"old.json", ".tmp-old", "keep.txt"} {
		p := filepath.Join(dir, n)
		os.WriteFile(p, []byte("x"), 0o644)
		os.Chtimes(p, old, old)
	}
	os.WriteFile(filepath.Join(dir, "new.json"), []byte("x"), 0o644)
	pruneOracleCache(3 * 24 * time.Hour)
	for n, want := range map[string]bool{"old.json": false, ".tmp-old": false, "keep.txt": true, "new.json": true} {
		if _, err := os.Stat(filepath.Join(dir, n)); (err == nil) != want {
			t.Errorf("%s: exists=%v, want %v", n, err == nil, want)
		}
	}
}

func TestFixtureTemplatesAreIndependent(t *testing.T) {
	var seen []string
	f := fx{after: func(t *testing.T, dir string, in *info) {
		in.x["tag"] = dir
		seen = append(seen, dir)
	}}
	a, ia := f.build(t)
	b, ib := f.build(t)
	if a == b || ia.x["tag"] == ib.x["tag"] || len(seen) != 2 {
		t.Fatalf("copies share state: %s %s %v", a, b, seen)
	}
	write(t, a, ".hv/extra.md", "only in a\n")
	if _, err := os.Stat(filepath.Join(b, ".hv", "extra.md")); err == nil {
		t.Error("a write to one copy reached the other")
	}
	if _, err := os.Stat(filepath.Join(b, ".hv", "BACKLOG.md")); err != nil {
		t.Error("the template lost its files")
	}
	if ia.h1 == "" || ia.h1 != ib.h1 {
		t.Errorf("hashes: %q %q", ia.h1, ib.h1)
	}
}
