package knowledge

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScopePaths(t *testing.T) {
	s := Store{Root: "/p", Repos: map[string]string{"web": "/p/web"}}
	got, err := s.KnowledgePath(Umbrella)
	if err != nil || got != "/p/.hv/KNOWLEDGE.md" {
		t.Errorf("umbrella: %q %v", got, err)
	}
	got, err = s.TierPath("web")
	if err != nil || got != "/p/.hv/knowledge/web/knowledge-tier.json" {
		t.Errorf("web tier: %q %v", got, err)
	}
	if _, err = s.KnowledgePath("ghost"); !errors.Is(err, ErrScope) {
		t.Errorf("unregistered: %v", err)
	}
	if _, err = (Store{Root: "/p"}).KnowledgePath("web"); !errors.Is(err, ErrScope) || !strings.Contains(err.Error(), "umbrella mode is off") {
		t.Errorf("outside umbrella mode: %v", err)
	}
}

func TestSidecarVersionMismatch(t *testing.T) {
	p := filepath.Join(t.TempDir(), "knowledge-tier.json")
	os.WriteFile(p, []byte(`{"version": 2, "entries": {}}`), 0o666)
	if _, err := LoadSidecar(p); err == nil || !strings.Contains(err.Error(), "schema version mismatch — expected 1, got 2") {
		t.Errorf("err = %v", err)
	}
	// No version field: legacy data is treated as version 1.
	os.WriteFile(p, []byte(`{"entries": {}}`), 0o666)
	if _, err := LoadSidecar(p); err != nil {
		t.Errorf("legacy: %v", err)
	}
	os.WriteFile(p, []byte(`{not json`), 0o666)
	if _, err := LoadSidecar(p); err == nil {
		t.Error("corrupt sidecar loaded")
	}
}

func TestSidecarKeepsUnknownFieldsAndOrder(t *testing.T) {
	p := filepath.Join(t.TempDir(), "knowledge-tier.json")
	os.WriteFile(p, []byte(`{
  "version": 1,
  "note": "keep me",
  "entries": {
    "B::z": {
      "tier": "confirmed",
      "hits": 2,
      "lastSeen": "2026-01-01",
      "extra": true
    }
  }
}
`), 0o666)
	err := Update(p, func(s *Sidecar) (bool, error) { s.Bump("B", "z"); s.Init("A", "a"); return true, nil })
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(p)
	got := string(raw)
	if !strings.Contains(got, `"note": "keep me"`) || !strings.Contains(got, `"extra": true`) {
		t.Errorf("unknown fields lost:\n%s", got)
	}
	if strings.Index(got, "B::z") > strings.Index(got, "A::a") {
		t.Errorf("entry order changed:\n%s", got)
	}
}

func TestRekeyTopicMovesEveryEntry(t *testing.T) {
	p := filepath.Join(t.TempDir(), "t.json")
	err := Update(p, func(s *Sidecar) (bool, error) {
		s.Init("X", "one")
		s.Init("Y", "keep")
		s.Init("X", "two")
		return true, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	var moved int
	Update(p, func(s *Sidecar) (bool, error) { moved = s.RekeyTopic("X", "Z"); return moved > 0, nil })
	s, _ := LoadSidecar(p)
	if moved != 2 || len(s.List("")) != 3 {
		t.Fatalf("moved = %d, entries = %v", moved, s.List(""))
	}
	if _, ok := s.Get("Z", "two"); !ok {
		t.Error("Z::two missing")
	}
	if _, ok := s.Get("X", "one"); ok {
		t.Error("X::one still present")
	}
}

func TestAmendAmbiguousAcrossFiles(t *testing.T) {
	root := t.TempDir()
	umb := "## T\n\n- **a** — shared text <!-- 2026-01-01 -->\n"
	os.MkdirAll(filepath.Join(root, ".hv", "knowledge", "web"), 0o777)
	os.WriteFile(filepath.Join(root, ".hv", "KNOWLEDGE.md"), []byte(umb), 0o666)
	os.WriteFile(filepath.Join(root, ".hv", "knowledge", "web", "KNOWLEDGE.md"), []byte(umb), 0o666)
	s := Store{Root: root, Repos: map[string]string{"web": filepath.Join(root, "web")}}
	if _, _, err := s.Amend("web", false, "T", "shared", "x"); !errors.Is(err, ErrAmbiguous) {
		t.Fatalf("err = %v", err)
	}
	if _, _, err := s.Amend("web", true, "T", "shared", "x"); err != nil {
		t.Fatalf("explicit scope: %v", err)
	}
}
