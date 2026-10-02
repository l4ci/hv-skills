package worker

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const acctConfig = `{"work":{"accounts":[
 {"name":"alpha","configDir":"/acct/alpha"},
 {"name":"beta","configDir":"/acct/beta"},
 {"name":"gamma","configDir":"/acct/gamma"},
 {"name":"delta","configDir":"/acct/delta"},
 {"name":"epsilon","configDir":"/acct/epsilon"},
 {"name":"zeta","configDir":"/acct/zeta"}]}}`

var future = time.Now().UTC().Add(48 * time.Hour).Format("2006-01-02T15:04:05.000000+00:00")

// usageDir writes the per-account fixture payloads the helper reads from
// HV_ACCOUNT_USAGE_DIR. alpha: 30% / 10%; beta: five-hour spent with a future
// reset (cooling); gamma: weekly spent but extra usage live (free, discounted);
// delta: weekly spent, no extra usage, future reset (cooling); epsilon:
// spent window with no reset (free); zeta: no fixture (unknown).
func usageDir(t *testing.T) string {
	dir := t.TempDir()
	put := func(name, body string) { os.WriteFile(filepath.Join(dir, name+".json"), []byte(body), 0o644) }
	put("alpha", `{"five_hour":{"utilization":30,"resets_at":null},"seven_day":{"utilization":10.5,"resets_at":null}}`)
	put("beta", `{"five_hour":{"utilization":100,"resets_at":"`+future+`"},"seven_day":{"utilization":5,"resets_at":null}}`)
	put("gamma", `{"five_hour":{"utilization":20,"resets_at":null},"seven_day":{"utilization":100,"resets_at":"`+future+`"},"extra_usage":{"is_enabled":true,"spend_limit_reached":false}}`)
	put("delta", `{"five_hour":{"utilization":1,"resets_at":null},"seven_day":{"utilization":100,"resets_at":"`+future+`"},"extra_usage":{"is_enabled":true,"spend_limit_reached":true}}`)
	put("epsilon", `{"five_hour":{"utilization":100,"resets_at":null},"seven_day":{"utilization":57.45,"resets_at":null}}`)
	return dir
}

func goMeters(t *testing.T, dir, usage string) []Meter {
	t.Helper()
	acc := &Accounts{Getenv: func(k string) string {
		if k == "HV_ACCOUNT_USAGE_DIR" {
			return usage
		}
		return ""
	}}
	return acc.Meters(bg, dir)
}

func TestAccountListParity(t *testing.T) {
	dir, usage := newProject(t, acctConfig), usageDir(t)
	r := runOld(t, dir, []string{"HV_ACCOUNT_USAGE_DIR=" + usage}, "hv-worker-account", "list", "--json")
	if r.Code != 0 {
		t.Fatalf("old: %+v", r)
	}
	var old []map[string]any
	if err := json.Unmarshal([]byte(r.Stdout), &old); err != nil {
		t.Fatal(err)
	}
	got := goMeters(t, dir, usage)
	if len(got) != len(old) {
		t.Fatalf("%d rows, old %d", len(got), len(old))
	}
	for i, m := range got {
		o := old[i]
		if m.Name != o["name"] || m.ConfigDir != o["configDir"] || m.Verdict != o["verdict"] || m.Reason != o["reason"] {
			t.Errorf("row %d: %+v vs old %v", i, m, o)
		}
		for key, v := range map[string]*float64{"fiveHour": m.FiveHour, "sevenDay": m.SevenDay, "headroom": m.Headroom} {
			if (o[key] == nil) != (v == nil) || (v != nil && o[key].(float64) != *v) {
				t.Errorf("%s %s = %v, old %v", m.Name, key, v, o[key])
			}
		}
		oldReset, _ := o["resetsAt"].(string)
		gotReset := ""
		if m.ResetsAt != nil {
			gotReset = ISOFormat(*m.ResetsAt)
		}
		if oldReset != gotReset {
			t.Errorf("%s resetsAt = %q, old %q", m.Name, gotReset, oldReset)
		}
	}
	verdicts := map[string]string{}
	for _, m := range got {
		verdicts[m.Name] = m.Verdict
	}
	want := map[string]string{"alpha": "free", "beta": "cooling", "gamma": "free", "delta": "cooling", "epsilon": "free", "zeta": "unknown"}
	for k, v := range want {
		if verdicts[k] != v {
			t.Errorf("%s verdict = %s, want %s", k, verdicts[k], v)
		}
	}
	// gamma's weekly window is discounted, so its headroom comes from five_hour alone
	for _, m := range got {
		if m.Name == "gamma" && (m.Headroom == nil || *m.Headroom != 80) {
			t.Errorf("gamma headroom = %v, want 80", m.Headroom)
		}
		if m.Name == "epsilon" && (m.Headroom == nil || *m.Headroom != 0) {
			t.Errorf("epsilon headroom = %v", m.Headroom)
		}
	}
}

func TestAccountListWithoutAccounts(t *testing.T) {
	if got := goMeters(t, newProject(t, `{}`), ""); len(got) != 0 {
		t.Errorf("%v", got)
	}
}

func TestAccountPickParity(t *testing.T) {
	dir, usage := newProject(t, acctConfig), usageDir(t)
	acc := &Accounts{Getenv: func(k string) string {
		if k == "HV_ACCOUNT_USAGE_DIR" {
			return usage
		}
		return ""
	}}
	env := []string{"HV_ACCOUNT_USAGE_DIR=" + usage}
	for _, excl := range []string{"", "gamma", "gamma,alpha", " gamma , alpha ", "gamma,alpha,epsilon,zeta", "alpha,beta,gamma,delta,epsilon,zeta"} {
		args := []string{"pick"}
		if excl != "" {
			args = append(args, "--exclude", excl)
		}
		r := runOld(t, dir, env, "hv-worker-account", args...)
		var skip []string
		if excl != "" {
			skip = strings.Split(excl, ",")
		}
		name, ok := acc.Pick(bg, dir, skip)
		if r.Code == 0 {
			if !ok || name != strings.TrimSpace(r.Stdout) {
				t.Errorf("exclude %q: go %q/%v, old %q", excl, name, ok, r.Stdout)
			}
		} else if ok {
			t.Errorf("exclude %q: old exit %d, go picked %q", excl, r.Code, name)
		}
	}
}

func TestAccountPickRotatesWhenNoMeterIsReadable(t *testing.T) {
	dir := newProject(t, acctConfig)
	empty := t.TempDir()
	acc := &Accounts{Getenv: func(string) string { return empty }}
	name, ok := acc.Pick(bg, dir, nil)
	r := runOld(t, dir, []string{"HV_ACCOUNT_USAGE_DIR=" + empty}, "hv-worker-account", "pick")
	if !ok || name != strings.TrimSpace(r.Stdout) || name != "alpha" {
		t.Errorf("unknown meters must stay eligible: go %q old %q", name, r.Stdout)
	}
}

func TestAccountAssignParity(t *testing.T) {
	a, b := newProject(t, acctConfig), newProject(t, acctConfig)
	runOld(t, a, nil, "hv-worker-pool", "init", "--slots", "2", "--base", "main")
	goInit(t, b, InitOpts{Slots: 2, Base: "main"})
	usage := usageDir(t)
	acc := &Accounts{Getenv: func(k string) string {
		if k == "HV_ACCOUNT_USAGE_DIR" {
			return usage
		}
		return ""
	}}
	env := []string{"HV_ACCOUNT_USAGE_DIR=" + usage}

	r := runOld(t, a, env, "hv-worker-account", "assign", "--slot", "w1", "--account", "beta")
	name, changed, err := acc.Assign(bg, b, "w1", "beta")
	if r.Code != 0 || err != nil || name != "beta" || !changed || r.Stdout != "assigned: w1 -> beta\n" {
		t.Fatalf("old %+v go %v %v %v", r, name, changed, err)
	}
	mustEqual(t, "workers.json", registry(t, a), registry(t, b))

	if _, changed, _ := acc.Assign(bg, b, "w1", "beta"); changed {
		t.Error("assigning the same account again must report changed=false")
	}

	// no --account: the best pick
	r = runOld(t, a, env, "hv-worker-account", "assign", "--slot", "w2")
	name, _, err = acc.Assign(bg, b, "w2", "")
	if r.Code != 0 || err != nil || r.Stdout != "assigned: w2 -> "+name+"\n" {
		t.Fatalf("old %+v go %v %v", r, name, err)
	}
	mustEqual(t, "workers.json after pick", registry(t, a), registry(t, b))

	exitOf := func(err error) int {
		if we, ok := err.(*Error); ok {
			return we.Exit
		}
		return -1
	}
	_, _, err = acc.Assign(bg, b, "w1", "nope")
	if exitOf(err) != ExitResolution || !strings.Contains(err.Error(), "account 'nope' is not in work.accounts") {
		t.Errorf("unknown account: %v", err)
	}
	_, _, err = acc.Assign(bg, b, "w9", "alpha")
	if exitOf(err) != ExitResolution || !strings.Contains(err.Error(), "slot 'w9' is not in the pool") {
		t.Errorf("unknown slot: %v", err)
	}
	_, _, err = acc.Assign(bg, newProject(t, acctConfig), "w1", "alpha")
	if exitOf(err) != ExitResolution || !strings.Contains(err.Error(), "no worker pool") {
		t.Errorf("no registry: %v", err)
	}
}

func TestAccountAssignWithEveryAccountCoolingIsRefused(t *testing.T) {
	cfg := `{"work":{"accounts":[{"name":"beta","configDir":"/acct/beta"}]}}`
	dir := newProject(t, cfg)
	goInit(t, dir, InitOpts{Slots: 1, Base: "main"})
	acc := &Accounts{Getenv: func(k string) string {
		if k == "HV_ACCOUNT_USAGE_DIR" {
			return usageDir(t)
		}
		return ""
	}}
	_, _, err := acc.Assign(bg, dir, "w1", "")
	if we, ok := err.(*Error); !ok || we.Exit != ExitRefused {
		t.Errorf("err = %v, want exit 4", err)
	}
}

// pool init spreads slots across accounts by headroom, resetting the
// exclusion list when accounts run out.
func TestPoolInitSpreadsAccountsLikeTheOldHelper(t *testing.T) {
	a, b := newProject(t, acctConfig), newProject(t, acctConfig)
	usage := usageDir(t)
	env := []string{"HV_ACCOUNT_USAGE_DIR=" + usage}
	if r := runOld(t, a, env, "hv-worker-pool", "init", "--slots", "5", "--base", "main"); r.Code != 0 {
		t.Fatalf("old: %+v", r)
	}
	acc := &Accounts{Getenv: func(k string) string {
		if k == "HV_ACCOUNT_USAGE_DIR" {
			return usage
		}
		return ""
	}}
	if _, err := (Env{}).PoolInit(bg, b, InitOpts{Slots: 5, Base: "main"}, acc); err != nil {
		t.Fatal(err)
	}
	mustEqual(t, "workers.json", registry(t, a), registry(t, b))
	if !strings.Contains(registry(t, b), `"account": "alpha"`) {
		t.Error("no slot was assigned an account")
	}
}

func TestISOFormatMatchesPython(t *testing.T) {
	for in, want := range map[string]string{
		"2026-10-02T15:00:00Z":             "2026-10-02T15:00:00+00:00",
		"2026-10-02T15:00:00.5Z":           "2026-10-02T15:00:00.500000+00:00",
		"2026-10-02T17:00:00.123456+02:00": "2026-10-02T17:00:00.123456+02:00",
	} {
		tm := parseReset(in)
		if tm == nil || ISOFormat(*tm) != want {
			t.Errorf("%s -> %v, want %s", in, tm, want)
		}
	}
	if parseReset("garbage") != nil || parseReset(nil) != nil || parseReset("") != nil {
		t.Error("unparseable resets must read as none")
	}
}

func TestExpiredTokenReportsUnknownWithoutNetwork(t *testing.T) {
	cfgDir := t.TempDir()
	os.WriteFile(filepath.Join(cfgDir, ".credentials.json"), []byte(`{"claudeAiOauth":{"accessToken":"x","expiresAt":1000}}`), 0o600)
	acc := &Accounts{HTTP: nil}
	if tok, why := acc.token(cfgDir); tok != "" || why != "token expired" {
		t.Errorf("token = %q, %q", tok, why)
	}
	if tok, why := acc.token(t.TempDir()); tok != "" || why != "no credentials file" {
		t.Errorf("token = %q, %q", tok, why)
	}
}
