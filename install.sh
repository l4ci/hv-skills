#!/bin/sh
# Install the hv binary from a GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/l4ci/hv-skills/main/install.sh | sh
#
# Downloads hv_<os>_<arch> and checksums.txt from the release, refuses a binary
# whose sha256 does not match (fail closed: nothing is installed), then copies
# it to <prefix>/bin/hv. The checksum is an integrity check, not authenticity:
# checksums.txt comes from the same release as the binary. Signatures are a
# 5.1 follow-up.
#
# Options (flag wins over env):
#   --version X.Y.Z   HV_VERSION   release to install (default: latest)
#   --prefix DIR      HV_PREFIX    install to DIR/bin (default: $HOME/.local)
#
# Env:
#   HV_RELEASE_BASE_URL  default https://github.com/l4ci/hv-skills/releases.
#                        Layout: <base>/latest/download/<asset> and
#                        <base>/download/v<version>/<asset>. https or file, or
#                        http only for localhost / 127.0.0.1 (tests).
#
# No sudo, no shell-profile edits: it prints the PATH line if it is needed.
set -eu

die() {
  printf 'install.sh: %s\n' "$1" >&2
  [ -z "${2:-}" ] || printf 'hint: %s\n' "$2" >&2
  exit 1
}

version=${HV_VERSION:-}
prefix=${HV_PREFIX:-}
while [ $# -gt 0 ]; do
  case $1 in
    --version) [ $# -ge 2 ] || die "--version needs a value"; version=$2; shift 2 ;;
    --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix=$2; shift 2 ;;
    -h | --help) sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument $1" "see install.sh --help" ;;
  esac
done

if [ -z "$prefix" ]; then
  [ -n "${HOME:-}" ] || die "HOME is not set" "pass --prefix DIR"
  prefix=$HOME/.local
fi
version=${version#v}
case $version in
  *[!0-9A-Za-z.+-]*) die "bad version $version" ;;
esac

case $(uname -s) in Linux) os=linux ;; Darwin) os=darwin ;; *) die "unsupported OS $(uname -s)" ;; esac
case $(uname -m) in x86_64 | amd64) arch=amd64 ;; aarch64 | arm64) arch=arm64 ;; *) die "unsupported CPU $(uname -m)" ;; esac

root=${HV_RELEASE_BASE_URL:-https://github.com/l4ci/hv-skills/releases}
root=${root%/}
# No userinfo anywhere (http://localhost:1@evil.example is evil.example).
# Plain http only when the whole host is localhost or 127.0.0.1, with an
# optional numeric port.
url_ok=
case $root in
  *@*) ;;
  https://* | file://*) url_ok=1 ;;
  http://*)
    hostport=${root#http://}
    hostport=${hostport%%/*}
    case $hostport in
      localhost | 127.0.0.1) url_ok=1 ;;
      localhost:* | 127.0.0.1:*)
        port=${hostport#*:}
        case $port in '' | *[!0-9]*) ;; *) url_ok=1 ;; esac ;;
    esac ;;
esac
[ -n "$url_ok" ] || die "refusing release URL $root" "use https without userinfo (plain http only for localhost or 127.0.0.1)"

if [ -n "$version" ]; then base=$root/download/v$version; label=v$version
else base=$root/latest/download; label="the latest release"
fi
asset=hv_${os}_${arch}

bindir=$prefix/bin
mkdir -p "$bindir" 2>/dev/null || die "cannot create $bindir" "pass --prefix with a writable directory"
work=$(mktemp -d "$bindir/.hv-install.XXXXXX") || die "cannot write to $bindir" "pass --prefix with a writable directory"
trap 'rm -rf "$work"' EXIT

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 300 --proto-redir =https -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    # wget cannot limit redirects to https (GitHub release assets always
    # redirect). The sha256 check below still applies.
    wget -q --tries=1 --timeout=30 -O "$2" "$1"
  else
    die "need curl or wget"
  fi
}

printf 'Downloading %s from %s\n' "$asset" "$label"
fetch "$base/$asset" "$work/$asset" || die "download failed: $base/$asset" "check the version exists and is published"
fetch "$base/checksums.txt" "$work/checksums.txt" || die "download failed: $base/checksums.txt"

want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$work/checksums.txt")
[ -n "$want" ] || die "checksums.txt has no entry for $asset"
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$work/$asset" | cut -d' ' -f1)
elif command -v shasum >/dev/null 2>&1; then got=$(shasum -a 256 "$work/$asset" | cut -d' ' -f1)
else die "need sha256sum or shasum to verify the download"
fi
[ "$got" = "$want" ] || die "checksum mismatch for $asset (want $want, got $got); nothing installed"

chmod 755 "$work/$asset"
# Same directory as the target, so the rename is atomic.
mv -f "$work/$asset" "$bindir/hv" || die "cannot install $bindir/hv"
printf 'Installed %s\n' "$bindir/hv"

# shellcheck disable=SC2016  # $PATH is meant literally in the hint
case ":${PATH:-}:" in
  *":$bindir:"*) ;;
  *) printf '\n%s is not on your PATH. Add it:\n  export PATH="%s:$PATH"\n' "$bindir" "$bindir" ;;
esac
printf '\nNext: hv skills install\n'
