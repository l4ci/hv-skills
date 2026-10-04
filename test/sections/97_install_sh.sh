echo "install.sh: checksum-verified install from a local fake release (F6b, #230)"
# No network: HV_RELEASE_BASE_URL points at file:// trees built here.
IS="$(mktemp -d)"
trap 'rm -rf "${IS:?}"' EXIT
INSTALL="$REPO/install.sh"
case $(uname -s) in Linux) ios=linux ;; *) ios=darwin ;; esac
case $(uname -m) in x86_64 | amd64) iarch=amd64 ;; *) iarch=arm64 ;; esac
ASSET="hv_${ios}_${iarch}"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# mkrel DIR LABEL: a release dir holding a fake hv plus a matching checksums.txt.
mkrel() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "hv fake %s"\n' "$2" > "$1/$ASSET"
  printf '%s  %s\n%s  hv_other_arch\n' "$(sha "$1/$ASSET")" "$ASSET" "0000" > "$1/checksums.txt"
}
mkrel "$IS/rel/latest/download" latest
mkrel "$IS/rel/download/v1.2.3" 1.2.3
export HV_RELEASE_BASE_URL="file://$IS/rel"

# Latest release into a fresh prefix: installs, runs, prints the next step.
OUT=$(sh "$INSTALL" --prefix "$IS/p1" 2>&1) || fail "latest install failed: $OUT"
[ -x "$IS/p1/bin/hv" ] || fail "latest install left no executable hv"
[ "$("$IS/p1/bin/hv")" = "hv fake latest" ] || fail "installed hv is not the latest asset"
case $OUT in *"hv skills install"*) ;; *) fail "install.sh should print the next step: $OUT" ;; esac
case $OUT in *"is not on your PATH"*) ;; *) fail "install.sh should say the prefix is off PATH: $OUT" ;; esac
[ -z "$(ls -A "$IS/p1/bin" | grep -v '^hv$' || true)" ] || fail "install left temp files in the bin dir"

# Pinned version, via the env and via a leading v; PATH already holding bin: no PATH hint.
OUT=$(PATH="$IS/p2/bin:$PATH" HV_PREFIX="$IS/p2" HV_VERSION=v1.2.3 sh "$INSTALL" 2>&1) || fail "pinned install failed: $OUT"
[ "$("$IS/p2/bin/hv")" = "hv fake 1.2.3" ] || fail "pinned install is not v1.2.3"
case $OUT in *"is not on your PATH"*) fail "install.sh warned about PATH though bin is on it" ;; esac

# Checksum mismatch: fails closed, nothing installed, an existing hv is untouched.
mkrel "$IS/bad/download/v9.9.9" 9.9.9
printf 'tampered\n' >> "$IS/bad/download/v9.9.9/$ASSET"
mkdir -p "$IS/p3/bin"; printf 'old\n' > "$IS/p3/bin/hv"
RC=0; OUT=$(HV_RELEASE_BASE_URL="file://$IS/bad" sh "$INSTALL" --prefix "$IS/p3" --version 9.9.9 2>&1) || RC=$?
[ "$RC" != 0 ] || fail "a checksum mismatch should fail"
case $OUT in *"checksum mismatch"*) ;; *) fail "mismatch should say so: $OUT" ;; esac
[ "$(cat "$IS/p3/bin/hv")" = "old" ] || fail "a failed install replaced the existing hv"
[ -z "$(ls -A "$IS/p3/bin" | grep -v '^hv$' || true)" ] || fail "a failed install left temp files"

# No checksums entry for this platform: fails closed too.
mkrel "$IS/noent/download/v1.0.0" 1.0.0
printf '0000  hv_other_arch\n' > "$IS/noent/download/v1.0.0/checksums.txt"
RC=0; HV_RELEASE_BASE_URL="file://$IS/noent" sh "$INSTALL" --prefix "$IS/p4" --version 1.0.0 >/dev/null 2>&1 || RC=$?
[ "$RC" != 0 ] || fail "a checksums.txt without this asset should fail"
[ ! -e "$IS/p4/bin/hv" ] || fail "an install with no checksum entry still wrote hv"

# Missing release: fails, installs nothing.
RC=0; sh "$INSTALL" --prefix "$IS/p5" --version 0.0.1 >/dev/null 2>&1 || RC=$?
[ "$RC" != 0 ] && [ ! -e "$IS/p5/bin/hv" ] || fail "an unpublished version should fail without installing"

# URL guard: userinfo and remote http are refused before any download.
for bad in "https://x:y@github.com/l4ci/hv-skills/releases" "http://evil.example/releases" "http://localhost:1@evil.example/r" "http://127.0.0.1:8000/releases"; do
  RC=0; OUT=$(HV_RELEASE_BASE_URL="$bad" sh "$INSTALL" --prefix "$IS/p6" 2>&1) || RC=$?
  [ "$RC" != 0 ] || fail "install.sh accepted release URL $bad"
  case $OUT in *"refusing release URL"*) ;; *) fail "$bad should be refused by name: $OUT" ;; esac
done
[ ! -e "$IS/p6" ] || fail "a refused URL still created the prefix"

# curl | sh: a script cut short runs nothing. Cut it at every line of main()'s
# body and just before the closing call; each cut must leave no hv behind, and
# HOME is a scratch dir, so a cut that did run would show up there.
n=$(wc -l < "$INSTALL")
for cut in 30 45 60 80 100 $((n - 2)) $((n - 1)); do
  head -n "$cut" "$INSTALL" > "$IS/cut.sh"
  rm -rf "$IS/home"; mkdir -p "$IS/home"
  HOME="$IS/home" sh < "$IS/cut.sh" >/dev/null 2>&1 || true
  [ -z "$(ls -A "$IS/home")" ] || fail "a script cut at line $cut touched HOME: $(ls -A "$IS/home")"
done
# The last line is the only call: drop it and nothing runs, even with env set that would install.
head -n "$((n - 1))" "$INSTALL" > "$IS/cut.sh"
OUT=$(HV_PREFIX="$IS/pcut" sh < "$IS/cut.sh" 2>&1) || fail "a copy without its last line should exit 0 quietly: $OUT"
[ -z "$OUT" ] && [ ! -e "$IS/pcut" ] || fail "a copy without its last line did something: $OUT"
# --help reads no file: it works with the script on stdin ($0 is just sh).
OUT=$(sh -s -- --help < "$INSTALL" 2>&1) || fail "--help over stdin failed: $OUT"
case $OUT in *"Usage: install.sh"*) ;; *) fail "--help should print usage: $OUT" ;; esac
[ ! -e "$IS/phelp" ] || fail "--help touched the filesystem"

# A signal mid-run leaves no temp dir behind.
mkdir -p "$IS/sigrel/latest/download"
printf '#!/bin/sh\n' > "$IS/sigrel/latest/download/$ASSET"
sleepbin="$IS/fakebin"; mkdir -p "$sleepbin"
printf '#!/bin/sh\nsleep 30\n' > "$sleepbin/curl"; chmod +x "$sleepbin/curl"
PATH="$sleepbin:$PATH" HV_RELEASE_BASE_URL="file://$IS/sigrel" sh "$INSTALL" --prefix "$IS/psig" >/dev/null 2>&1 &
SIGPID=$!
i=0; while [ ! -d "$IS/psig/bin" ] || [ -z "$(ls -A "$IS/psig/bin" 2>/dev/null)" ]; do i=$((i + 1)); [ "$i" -lt 100 ] || break; sleep 0.1; done
kill -TERM "$SIGPID" 2>/dev/null || true
wait "$SIGPID" 2>/dev/null || true
[ -z "$(ls -A "$IS/psig/bin" 2>/dev/null)" ] || fail "a terminated install left temp files: $(ls -A "$IS/psig/bin")"

# Transport: an https base makes curl https-only with TLS 1.2+, redirects included.
mkdir -p "$IS/tbin"
printf '#!/bin/sh\necho "$*" >> "$IS_CURL_LOG"\nexit 22\n' > "$IS/tbin/curl"; chmod +x "$IS/tbin/curl"
IS_CURL_LOG="$IS/curl.log" PATH="$IS/tbin:$PATH" HV_RELEASE_BASE_URL="https://example.invalid/releases" \
  sh "$INSTALL" --prefix "$IS/ptr" >/dev/null 2>&1 || true
CL=$(cat "$IS/curl.log")
case $CL in *"--proto =https"*"--proto-redir =https"*"--tlsv1.2"*) ;; *) fail "curl should be pinned to https and TLS 1.2: $CL" ;; esac
: > "$IS/curl.log"
IS_CURL_LOG="$IS/curl.log" PATH="$IS/tbin:$PATH" HV_RELEASE_BASE_URL="file://$IS/rel" sh "$INSTALL" --prefix "$IS/ptr" >/dev/null 2>&1 || true
CL=$(cat "$IS/curl.log")
case $CL in *"--proto =file"*) ;; *) fail "a file:// base should limit curl to file: $CL" ;; esac
case $CL in *https*) fail "a file:// base should not allow https: $CL" ;; esac

# Bad flags and versions.
RC=0; sh "$INSTALL" --bogus >/dev/null 2>&1 || RC=$?; [ "$RC" != 0 ] || fail "unknown flag should fail"
RC=0; sh "$INSTALL" --version '1;rm' --prefix "$IS/p7" >/dev/null 2>&1 || RC=$?; [ "$RC" != 0 ] || fail "odd version should fail"
pass "install.sh verifies sha256, fails closed, guards the URL"
unset HV_RELEASE_BASE_URL
