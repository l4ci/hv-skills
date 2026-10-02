# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
#
# Core: argument parsing, the envelope, exit mapping, the staged helper dir,
# the @verb registry and helpers shared by the adapter modules. Each other
# module in this directory registers the adapters of one verb group.
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))

EXIT_CODES = {
    1: "failed", 2: "usage", 3: "resolution", 4: "refused",
    5: "unavailable", 6: "retry", 70: "internal", 71: "not_implemented",
}


class HvError(Exception):
    """Ends the verb with a contract exit code; data rides along on exit 1 and 4."""

    def __init__(self, exit, message, hint=None, data=None):
        super().__init__(message)
        self.exit = exit
        self.message = message
        self.hint = hint
        self.data = data


def usage(message):
    return HvError(2, message)


# ---------------------------------------------------------------- invocation
#
# Argument rule from the CLI conventions: before the verb only command words
# and global flags may appear; after it, one parser reads global and verb
# flags mixed with positionals. A value flag always takes the next token, a
# boolean takes none (`--flag=false` allowed), a repeated flag keeps its last
# value, and `--` ends flag parsing.

GLOBAL_VALUES = {"C": "cwd", "cwd": "cwd", "repo": "repo"}
GLOBAL_BOOLS = {"json": "json", "h": "help", "help": "help"}
BOOL_WORDS = {"1": True, "t": True, "T": True, "true": True, "TRUE": True, "True": True,
              "0": False, "f": False, "F": False, "false": False, "FALSE": False, "False": False}


class Spec:
    """A verb's own flags and positional count, declared with @verb."""

    def __init__(self, values=(), bools=(), pos=(0, 0), root=True, repo=True):
        self.values, self.bools = set(values), set(bools)
        self.min_pos, self.max_pos = pos
        self.root = root            # needs a .hv/ root (conventions: all but init/version/update)
        self.repo = repo            # accepts the global --repo


class Ctx:
    def __init__(self, path, flags, pos, repo, cwd):
        self.path = path            # ("item", "field")
        self.flags = flags          # verb flags, by name without dashes
        self.pos = pos              # positional args
        self.repo = repo            # global --repo value or None
        self.cwd = cwd              # effective working directory
        self.warnings = []

    @property
    def name(self):
        return "hv " + " ".join(self.path)

    def helper(self, name, *args, stdin=None, cwd=None, env=None):
        """Run a staged old helper. Returns (rc, stdout, stderr)."""
        full_env = dict(os.environ)
        full_env.update(env or {})
        proc = subprocess.run(
            [os.path.join(helpers_dir(), name), *args],
            input=stdin, capture_output=True, text=True,
            cwd=cwd or self.cwd, env=full_env,
        )
        return proc.returncode, proc.stdout, proc.stderr


def is_flag(tok):
    return tok.startswith("-") and tok != "-"


def to_bool(name, val):
    if val not in BOOL_WORDS:
        raise usage(f"invalid boolean value {val!r} for --{name}")
    return BOOL_WORDS[val]


def take_value(argv, i, name, eq, val):
    """Value of the flag at argv[i]; returns (value, next index)."""
    if eq:
        return val, i + 1
    if i + 1 >= len(argv):
        raise usage(f"flag needs an argument: --{name}")
    return argv[i + 1], i + 2


def take_global(argv, i, g):
    """Apply a global flag at argv[i] to g; next index, or None if not global."""
    name, eq, val = argv[i].lstrip("-").partition("=")
    if name in GLOBAL_BOOLS:
        g[GLOBAL_BOOLS[name]] = to_bool(name, val) if eq else True
        return i + 1
    if name in GLOBAL_VALUES:
        g[GLOBAL_VALUES[name]], i = take_value(argv, i, name, eq, val)
        return i
    return None


def scan_command(argv, known):
    """Command words and globals up to the verb. Returns (path, rest, globals)."""
    g = {"json": False, "help": False, "cwd": None, "repo": None}
    words, i = [], 0
    while i < len(argv) and argv[i] != "--":
        tok = argv[i]
        if is_flag(tok):
            if tuple(words) in known:
                break                   # the verb is reached; the rest is its parser's
            if tok == "--version" and not words:
                words, i = ["version"], i + 1
                continue
            nxt = take_global(argv, i, g)
            if nxt is None:
                raise usage(f"unknown flag before the verb: {tok}")
            i = nxt
            continue
        cand = tuple(words + [tok])
        if not any(p[:len(cand)] == cand for p in known):
            break
        words.append(tok)
        i += 1
    path = tuple(words)
    if path not in known:
        raise usage(f"unknown command: hv {' '.join(argv[:i + 1]) or '(none)'}")
    return path, argv[i:], g


def parse_args(name, rest, spec, g):
    """One pass over the tokens after the verb: verb flags, globals, positionals."""
    flags, pos, i = {}, [], 0
    while i < len(rest):
        tok = rest[i]
        if tok == "--":
            pos.extend(rest[i + 1:])
            break
        if not is_flag(tok):
            pos.append(tok)
            i += 1
            continue
        fname, eq, val = tok.lstrip("-").partition("=")
        if fname in spec.bools:
            flags[fname] = to_bool(fname, val) if eq else True
            i += 1
        elif fname in spec.values:
            flags[fname], i = take_value(rest, i, fname, eq, val)
        elif fname == "repo" and not spec.repo:
            raise usage(f"{name}: unknown flag --repo (the verb has no repo scope)")
        else:
            nxt = take_global(rest, i, g)
            if nxt is None:
                raise usage(f"{name}: unknown flag {tok.partition('=')[0]}")
            i = nxt
    if len(pos) < spec.min_pos or (spec.max_pos is not None and len(pos) > spec.max_pos):
        raise usage(f"{name}: wrong number of arguments")
    return flags, pos


# ---------------------------------------------------------------- environment

_staged = None


def helpers_dir():
    """Directory holding the old helpers, outside every project (leak guard)."""
    global _staged
    d = os.environ.get("HV_SHIM_HELPERS")
    if d:
        return d
    if _staged is None:
        _staged = os.path.join(tempfile.mkdtemp(prefix="hv-shim-"), "bin")
        shutil.copytree(os.path.join(REPO, "bin"), _staged, symlinks=True)
    return _staged


def find_root(start):
    d = os.path.realpath(start)
    while True:
        if os.path.isdir(os.path.join(d, ".hv")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def require_root(ctx):
    root = find_root(ctx.cwd)
    if root is None:
        raise HvError(3, "no .hv/ found in this directory or any parent", hint="run: hv init")
    return root


def first_error_line(stderr):
    """The old helper's message, without its `error: hv-foo:` prefix."""
    for line in stderr.splitlines():
        line = line.strip()
        if line:
            return re.sub(r"^(error|warn(ing)?):\s*(hv-[\w-]+:\s*)?", "", line)
    return ""


def json_body(stdout):
    try:
        return json.loads(stdout)
    except ValueError as e:
        raise HvError(70, f"old helper printed unparseable JSON: {e}")


# ---------------------------------------------------------------- adapters
#
# An adapter takes a Ctx and returns (data, text). `text` is what the verb
# prints without --json; the shim passes the old helper's stdout through
# there, since the contract leaves text output free. Raise HvError to fail.
# @verb declares the verb's flags and positional count; main parses them
# before the adapter runs, so ctx.flags and ctx.pos are ready.

ADAPTERS = {}


def verb(*path, **spec):
    """Register an adapter for `hv <path>` with its Spec (flags, positionals)."""
    def register(fn):
        ADAPTERS[path] = (fn, Spec(**spec))
        return fn
    return register


# Every verb the contract defines. A path here with no adapter exits 71.
CONTRACT_VERBS = set()
# Verbs whose contract `data` reports `changed`; the rest are read-only.
MUTATING_VERBS = set()


def load_contract_verbs():
    """Read the verb list from the contract's `### hv …` headings."""
    path = os.path.join(REPO, "docs", "design", "5.0-verb-contract.md")
    current = None
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r"^### hv ((?:[a-z][\w-]*)(?: [a-z][\w-]*)*)(?: <\w+>)?\s*$", line)
                if m:
                    current = tuple(m.group(1).split())
                    CONTRACT_VERBS.add(current)
                elif line.startswith("data:") and current and '"changed"' in line:
                    MUTATING_VERBS.add(current)
    except OSError:
        pass


# ---------------------------------------------------------------- shared adapter helpers

def backend_error(rc, err):
    """Old backend helper failure -> HvError (the contract's rc mapping)."""
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 1:
        if re.search(r"usage:|unknown argument|expects|invalid|not a valid", err):
            return HvError(2, msg)
        if "ambiguous across sub-repos" in err:
            # Shared definitions: an ambiguous bare ID is a usage error, and the
            # candidates use the `id` spelling (`repo:12`, rule 11).
            return HvError(2, re.sub(r"\b([\w.-]+):[BFT](\d+)\b", r"\1:\2", msg))
        return HvError(3, msg)
    if rc == 2:
        # Backend mismatch: default exit-4 failure data; main() makes it 1 on read-only verbs.
        return HvError(4, msg, data={"blockedBy": "backend", "changed": False})
    code = {3: 5, 4: 6}.get(rc, 70)
    return HvError(code, msg)


def call(ctx, helper, *args, **kw):
    """Run an old helper; return stdout on rc 0, else raise via backend_error."""
    rc, out, err = ctx.helper(helper, *args, **kw)
    if rc != 0:
        raise backend_error(rc, err)
    return out


def check_repo(ctx):
    """Global --repo must name a registered sub-repo (exit 3)."""
    if ctx.repo is None:
        return
    rc, _, err = ctx.helper("hv-resolve-repos", ctx.repo, cwd=find_root(ctx.cwd))
    if rc != 0:
        raise HvError(3, err.strip() or f"unregistered sub-repo: {ctx.repo}")


def enter_repo(ctx):
    """For verbs that act on a checkout: run in the --repo sub-repo, not the umbrella root."""
    if ctx.repo is None:
        return
    rc, out, err = ctx.helper("hv-resolve-repos", ctx.repo, cwd=find_root(ctx.cwd))
    if rc != 0:
        raise HvError(3, first_error_line(err) or f"unregistered sub-repo: {ctx.repo}")
    ctx.cwd = json_body(out)[0]["path"]


def read_text(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def read_json_file(path, default):
    try:
        return json.loads(read_text(path))
    except (TypeError, ValueError):
        return default


def status_entries(root):
    return read_json_file(os.path.join(root, ".hv", "status.json"), {}).get("active", [])


def stdin_to_file(path):
    """`-` means stdin; old helpers want a path, so spool it to a temp file."""
    if path != "-":
        return path, None
    fd, tmp = tempfile.mkstemp(prefix="hv-shim-stdin-")
    with os.fdopen(fd, "w") as f:
        f.write(sys.stdin.read())
    return tmp, tmp


KINDS = ("bugs", "features", "tasks")
TYPE_OF_KIND = {"bugs": "B", "features": "F", "tasks": "T"}


def item_type(item, kind=None):
    """The `type` letter of an item: from its ID in file mode, else from its kind."""
    m = re.search(r"(?:^|[:#])([BFT])\d", item)
    return m.group(1) if m else TYPE_OF_KIND.get(kind)
SECTION = {"bugs": "## Bugs", "features": "## Features", "tasks": "## Tasks"}


# ---------------------------------------------------------------- main

def emit(as_json, name, data=None, text=None, err=None, warnings=()):
    for w in warnings:
        print(f"{name}: warning: {w}", file=sys.stderr)
    if err is None:
        if as_json:
            env = {"ok": True, "data": data if data is not None else {}}
            if warnings:
                env["warnings"] = list(warnings)
            print(json.dumps(env))
        elif text:
            sys.stdout.write(text if text.endswith("\n") else text + "\n")
        return 0
    if err.message.startswith(name + ": "):
        err.message = err.message[len(name) + 2:]
    print(f"{name}: {err.message}", file=sys.stderr)
    if err.hint:
        print(f"hint: {err.hint}", file=sys.stderr)
    if as_json:
        e = {"code": EXIT_CODES.get(err.exit, "internal"), "exit": err.exit,
             "message": err.message}
        if err.hint:
            e["hint"] = err.hint
        env = {"ok": False, "error": e}
        if err.exit in (1, 4) and err.data is not None:
            env["data"] = err.data
        if warnings:
            env["warnings"] = list(warnings)
        print(json.dumps(env))
    return err.exit


def main(argv):
    # Conventions: a usage error is an envelope when any token before `--` is
    # exactly `--json`, since no parse exists yet to say otherwise.
    head = argv[:argv.index("--")] if "--" in argv else argv
    as_json, name, path = "--json" in head, "hv", None
    try:
        load_contract_verbs()
        path, rest, g = scan_command(argv, set(ADAPTERS) | CONTRACT_VERBS)
        name = "hv " + " ".join(path)
        if path not in ADAPTERS:
            raise HvError(71, "not ported to the test shim yet")
        fn, spec = ADAPTERS[path]
        flags, pos = parse_args(name, rest, spec, g)
        as_json = g["json"]
        if g["help"]:
            print(f"usage: {name} … (see docs/design/5.0-verb-contract.md)")
            return 0
        if g["repo"] is not None and not spec.repo:
            raise usage(f"{name}: unknown flag --repo (the verb has no repo scope)")
        cwd = os.path.realpath(g["cwd"] or os.getcwd())
        if not os.path.isdir(cwd):
            raise HvError(3, f"-C {g['cwd']}: not a directory")
        ctx = Ctx(path, flags, pos, g["repo"], cwd)
        if spec.root:
            require_root(ctx)
        check_repo(ctx)
        data, text = fn(ctx)
        return emit(as_json, name, data, text, warnings=ctx.warnings)
    except HvError as e:
        # Conventions: a read-only verb never exits 4. A backend refusal on one
        # (the verb runs on the other backlog backend only) answers no: exit 1.
        if e.exit == 4 and (e.data or {}).get("blockedBy") == "backend" \
                and path is not None and path not in MUTATING_VERBS:
            e.exit = 1
        return emit(as_json, name, err=e)
    finally:
        if _staged:
            shutil.rmtree(os.path.dirname(_staged), ignore_errors=True)
