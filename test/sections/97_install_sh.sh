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
for bad in "https://x:y@github.com/l4ci/hv-skills/releases" "http://evil.example/releases" "http://localhost:1@evil.example/r"; do
  RC=0; OUT=$(HV_RELEASE_BASE_URL="$bad" sh "$INSTALL" --prefix "$IS/p6" 2>&1) || RC=$?
  [ "$RC" != 0 ] || fail "install.sh accepted release URL $bad"
  case $OUT in *"refusing release URL"*) ;; *) fail "$bad should be refused by name: $OUT" ;; esac
done
[ ! -e "$IS/p6" ] || fail "a refused URL still created the prefix"

# Bad flags and versions.
RC=0; sh "$INSTALL" --bogus >/dev/null 2>&1 || RC=$?; [ "$RC" != 0 ] || fail "unknown flag should fail"
RC=0; sh "$INSTALL" --version '1;rm' --prefix "$IS/p7" >/dev/null 2>&1 || RC=$?; [ "$RC" != 0 ] || fail "odd version should fail"
pass "install.sh verifies sha256, fails closed, guards the URL"
unset HV_RELEASE_BASE_URL
