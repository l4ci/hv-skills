package cli

import (
	"context"
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/gate"
	"github.com/l4ci/hv-skills/v5/internal/release"
	"github.com/l4ci/hv-skills/v5/internal/tracker"
)

// The B1 (#54) release verbs: the two release steps that create public state,
// each behind its manual gate.

// releaseTagArg is the one <X.Y.Z> positional of push and publish.
func releaseTagArg(args []string, usage string) (string, error) {
	if len(args) != 1 {
		return "", Usage("usage: %s", usage)
	}
	if !release.IsSemver(args[0]) {
		return "", Usage("version must be a bare X.Y.Z, got %q", args[0])
	}
	return "v" + args[0], nil
}

// releaseGitOK runs git in dir and reports whether it exited 0, with stdout.
func releaseGitOK(c *Ctx, dir string, args ...string) (string, bool, error) {
	res, err := shipGit(c, dir, args...)
	if err != nil {
		return "", false, err
	}
	return shipLine(res.Stdout), res.Code == 0, nil
}

func releasePush(fs *flag.FlagSet) RunFunc {
	branchFlag := fs.String("branch", "", "the branch to push with the tag (default: the current branch)")
	tagOnly := fs.Bool("tag-only", false, "push only the tag (the release workflow builds from it)")
	branchOnly := fs.Bool("branch-only", false, "push only the branch, once the tag's release has its binaries")
	confirm := confirmFlags(fs)
	return func(c *Ctx, args []string) (Result, error) {
		tag, err := releaseTagArg(args, "hv release push <X.Y.Z> [--branch <name>] [--tag-only|--branch-only] --confirm --confirm-note <answer>")
		if err != nil {
			return Result{}, err
		}
		if *tagOnly && *branchOnly {
			return Result{}, Usage("--tag-only and --branch-only are mutually exclusive")
		}
		conf, err := confirm()
		if err != nil {
			return Result{}, err
		}
		dir, err := releaseDir(c)
		if err != nil {
			return Result{}, err
		}
		sha, ok, err := releaseGitOK(c, dir, "rev-parse", "-q", "--verify", "refs/tags/"+tag+"^{commit}")
		if err != nil {
			return Result{}, err
		}
		if !ok {
			return Result{}, Resolution("tag %s does not exist", tag)
		}
		branch := *branchFlag
		if branch == "" {
			cur, ok, err := releaseGitOK(c, dir, "symbolic-ref", "-q", "--short", "HEAD")
			if err != nil {
				return Result{}, err
			}
			if !ok {
				return Result{}, Resolution("HEAD is detached; pass --branch")
			}
			branch = cur
		} else if _, ok, err := releaseGitOK(c, dir, "rev-parse", "-q", "--verify", "refs/heads/"+branch); err != nil {
			return Result{}, err
		} else if !ok {
			return Result{}, Resolution("branch %s does not exist", branch)
		}
		if _, ok, err := releaseGitOK(c, dir, "remote", "get-url", "origin"); err != nil {
			return Result{}, err
		} else if !ok {
			return Result{}, Resolution("no 'origin' remote")
		}
		if *branchOnly {
			// The plugin version on the branch points at the tag's binaries,
			// so the branch follows the tag, never leads it.
			remote, ok, err := releaseGitOK(c, dir, "ls-remote", "--tags", "origin", "refs/tags/"+tag)
			if err != nil {
				return Result{}, err
			}
			if !ok {
				return Result{}, Unavailable("git ls-remote origin failed")
			}
			if remote == "" {
				return Result{}, Resolution("tag %s is not on origin", tag).WithHint("push the tag first: hv release push " + strings.TrimPrefix(tag, "v") + " --tag-only")
			}
		}
		if res, err := clearGate(c, gate.TagPush, tag, conf, nil, nil); err != nil {
			return res, err
		}
		// The default is one push, so the commit and the tag land together.
		refs, scope, text := []string{branch, tag}, "both", "pushed "+branch+" and "+tag+" to origin"
		switch {
		case *tagOnly:
			refs, scope, text = []string{tag}, "tag", "pushed "+tag+" to origin"
		case *branchOnly:
			refs, scope, text = []string{branch}, "branch", "pushed "+branch+" to origin"
		}
		res, err := shipGit(c, dir, append([]string{"push", "origin"}, refs...)...)
		if err != nil {
			return Result{}, err
		}
		if res.Code != 0 {
			return Result{}, Unavailable("git push origin %s: %s (tag %s is at %s)", strings.Join(refs, " "), shipFirstLine(res.Stderr), tag, sha)
		}
		return Result{Data: gitObj("tag", tag, "branch", branch, "remote", "origin", "scope", scope, "changed", true), Text: text}, nil
	}
}

func releasePublish(fs *flag.FlagSet) RunFunc {
	title := fs.String("title", "", "release title")
	bodyFile := fs.String("body-file", "", "release notes: a path, or - for stdin")
	draft := fs.Bool("draft", false, "create a draft release (GitHub only)")
	confirm := confirmFlags(fs)
	return func(c *Ctx, args []string) (Result, error) {
		tag, err := releaseTagArg(args, "hv release publish <X.Y.Z> --title <text> --body-file <path|-> [--draft] --confirm --confirm-note <answer>")
		if err != nil {
			return Result{}, err
		}
		conf, err := confirm()
		if err != nil {
			return Result{}, err
		}
		if *title == "" {
			return Result{}, Usage("--title is required")
		}
		body, err := shipBodyArg(c, *bodyFile, "the release notes")
		if err != nil {
			return Result{}, err
		}
		dir, err := releaseDir(c)
		if err != nil {
			return Result{}, err
		}
		url, _, err := releaseGitOK(c, dir, "remote", "get-url", "origin")
		if err != nil {
			return Result{}, err
		}
		host := release.Host(url)
		data := func(url string, changed bool) any {
			return gitObj("tag", tag, "host", host, "url", url, "draft", *draft, "changed", changed)
		}
		provider := ""
		switch host {
		case "github", "github-enterprise":
			provider = "github"
		case "gitlab", "gitlab-self-hosted":
			provider = "gitlab"
			if *draft {
				return Result{}, Usage("--draft: GitLab has no draft releases")
			}
		default:
			c.Warn("no recognized remote; nothing published")
			return Result{Data: data("", false)}, nil
		}
		remote, ok, err := releaseGitOK(c, dir, "ls-remote", "--tags", "origin", "refs/tags/"+tag)
		if err != nil {
			return Result{}, err
		}
		if !ok {
			return Result{}, Unavailable("git ls-remote origin failed")
		}
		if remote == "" {
			return Result{}, Resolution("tag %s is not on origin", tag).WithHint("push it first: hv release push " + strings.TrimPrefix(tag, "v"))
		}
		if res, err := clearGate(c, gate.ReleasePublish, tag, conf, nil, nil); err != nil {
			return res, err
		}
		notes, err := os.CreateTemp("", "hv-release-notes-*.md")
		if err != nil {
			return Result{}, err
		}
		defer os.Remove(notes.Name())
		_, werr := notes.WriteString(body + "\n")
		if cerr := notes.Close(); werr == nil {
			werr = cerr
		}
		if werr != nil {
			return Result{}, werr
		}
		cliArgs := []string{"release", "create", tag, "--title", *title, "--notes-file", notes.Name()}
		verb := "create"
		if provider == "gitlab" {
			cliArgs = []string{"release", "create", tag, "--name", *title, "--notes-file", notes.Name()}
		} else if *draft {
			cliArgs = append(cliArgs, "--draft")
		}
		ctx := c.Context()
		cl, err := tracker.NewCLI(ctx, tracker.SettingsFromConfig(releaseConfig(dir)), provider, dir, trackerOptions...)
		if err != nil {
			return Result{}, trackerErr(err)
		}
		if provider == "github" {
			// The release workflow (goreleaser) may already have made a
			// draft with the binaries: finish that one, never make a second.
			existing, err := releaseExisting(ctx, cl, dir, tag)
			if err != nil {
				return Result{}, err
			}
			if existing {
				verb = "edit"
				cliArgs = []string{"release", "edit", tag, "--title", *title, "--notes-file", notes.Name(), "--draft=" + strconv.FormatBool(*draft)}
			}
		}
		r, err := cl.Run(ctx, cliArgs, nil)
		if err != nil {
			return Result{}, trackerErr(err)
		}
		if r.ExitCode != 0 {
			return Result{}, Unavailable("%s release %s failed: %s", cliName(provider), verb, strings.TrimSpace(string(r.Stderr)))
		}
		lines := strings.Split(strings.TrimSpace(string(r.Stdout)), "\n")
		link := strings.TrimSpace(lines[len(lines)-1])
		return Result{Data: data(link, true), Text: link}, nil
	}
}

// releaseExisting reports whether GitHub already has a release for tag. A
// draft must carry the binaries (checksums.txt and an hv_* asset) before it
// is finished; and where the repo builds releases with goreleaser, a missing
// release means the workflow has not run, so creating one here would put the
// plugin version ahead of its binaries.
func releaseExisting(ctx context.Context, cl *tracker.CLI, dir, tag string) (bool, error) {
	r, err := cl.Run(ctx, []string{"release", "view", tag, "--json", "isDraft,assets"}, nil)
	if err != nil {
		return false, trackerErr(err)
	}
	if r.ExitCode != 0 {
		if !strings.Contains(strings.ToLower(string(r.Stderr)), "release not found") {
			return false, Unavailable("gh release view failed: %s", strings.TrimSpace(string(r.Stderr)))
		}
		for _, f := range []string{".goreleaser.yaml", ".goreleaser.yml"} {
			if _, err := os.Stat(filepath.Join(dir, f)); err == nil {
				return false, Resolution("no release for %s yet, and %s builds releases", tag, f).
					WithHint("wait for the release workflow to create the draft with the binaries")
			}
		}
		return false, nil
	}
	var rel struct {
		IsDraft bool `json:"isDraft"`
		Assets  []struct {
			Name string `json:"name"`
		} `json:"assets"`
	}
	if err := json.Unmarshal(r.Stdout, &rel); err != nil {
		return false, Unavailable("gh release view: unreadable output: %v", err)
	}
	if rel.IsDraft {
		sums, bins := false, false
		for _, a := range rel.Assets {
			sums = sums || a.Name == "checksums.txt"
			bins = bins || strings.HasPrefix(a.Name, "hv_")
		}
		if !sums || !bins {
			return false, Resolution("the draft release for %s has no binaries yet", tag).
				WithHint("wait for the release workflow to attach hv_* and checksums.txt")
		}
	}
	return true, nil
}

func cliName(provider string) string {
	if provider == "gitlab" {
		return "glab"
	}
	return "gh"
}
