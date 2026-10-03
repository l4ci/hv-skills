// Package roundcfg reads the round.* config keys (C3, #59).
package roundcfg

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/config"
)

// Scope values of round.scope: which issues a round may take.
const (
	ScopeSlate     = "slate"
	ScopeMilestone = "milestone"
	ScopeNext      = "next"
)

// Scopes lists the valid scope values.
var Scopes = []string{ScopeSlate, ScopeMilestone, ScopeNext}

// Settings are the round.* keys.
type Settings struct {
	Scope       string
	Roster      []string
	Brief       string
	SharedPaths []string
}

// agentRe is a name usable in a branch (`<agent>/<issue>-<slug>`,
// `park/<agent>`) and a directory (`.worktrees/<agent>`).
var agentRe = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)

// ValidScope reports whether s is a scope.
func ValidScope(s string) bool {
	for _, v := range Scopes {
		if s == v {
			return true
		}
	}
	return false
}

// Load reads and validates the round.* keys from the project config.
func Load(root string) (Settings, error) {
	cfg := config.Load(filepath.Join(root, ".hv", "config.json"))
	var s Settings
	v, err := config.Value(cfg, "round.scope")
	if err != nil {
		return s, err
	}
	s.Scope, _ = v.(string)
	if !ValidScope(s.Scope) {
		return s, fmt.Errorf("round.scope must be %s (got %v)", strings.Join(Scopes, ", "), v)
	}
	if s.Roster, err = list(cfg, "round.roster"); err != nil {
		return s, err
	}
	seen := map[string]bool{}
	for _, n := range s.Roster {
		if !agentRe.MatchString(n) {
			return s, fmt.Errorf("round.roster: %q is not a lowercase name usable in a branch (letters, digits, -)", n)
		}
		if seen[n] {
			return s, fmt.Errorf("round.roster: %q is listed twice", n)
		}
		seen[n] = true
	}
	if len(s.Roster) == 0 {
		return s, fmt.Errorf("round.roster is empty")
	}
	v, err = config.Value(cfg, "round.brief")
	if err != nil {
		return s, err
	}
	s.Brief, _ = v.(string)
	s.SharedPaths, err = list(cfg, "round.sharedPaths")
	return s, err
}

func list(cfg any, key string) ([]string, error) {
	v, err := config.Value(cfg, key)
	if err != nil {
		return nil, err
	}
	raw, ok := v.([]any)
	if !ok {
		return nil, fmt.Errorf("%s must be a list of strings", key)
	}
	var out []string
	for _, e := range raw {
		str, ok := e.(string)
		if !ok {
			return nil, fmt.Errorf("%s must be a list of strings", key)
		}
		if str = strings.TrimSpace(str); str != "" {
			out = append(out, str)
		}
	}
	return out, nil
}
