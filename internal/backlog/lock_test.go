package backlog

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

// Python's next_id and Go's NextID lock the same counters.json.lock, so a
// mixed-version race cannot mint one ID twice: while Go holds the lock,
// Python waits, then mints the ID after Go's.
func TestNextIDSharesPythonLock(t *testing.T) {
	pytest.Require(t)
	root := t.TempDir()
	hv := filepath.Join(root, ".hv")
	os.MkdirAll(hv, 0o755)
	os.WriteFile(filepath.Join(hv, "BACKLOG.md"), []byte("## Bugs\n"), 0o644)
	counters := filepath.Join(hv, "counters.json")
	bin, _ := filepath.Abs("../../bin")

	py := exec.Command("python3", "-c", "from hvlib_backend import FileBackend; print(FileBackend().next_id('bugs'))")
	py.Dir = root
	py.Env = append(os.Environ(), "PYTHONPATH="+bin)
	var out strings.Builder
	py.Stdout = &out
	err := fsio.Locked(counters, fsio.LockTimeout, func() error {
		if err := py.Start(); err != nil {
			return err
		}
		time.Sleep(500 * time.Millisecond) // Python must still be waiting on the lock
		if _, err := os.Stat(counters); err == nil {
			t.Error("Python wrote counters.json while Go held the lock")
		}
		return fsio.WriteJSONAtomic(counters, map[string]any{"bugs": 1})
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := py.Wait(); err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(out.String()); got != "B02" {
		t.Fatalf("Python minted %q after Go's B01, want B02", got)
	}
}
