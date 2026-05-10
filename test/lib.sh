#!/usr/bin/env bash
# Shared helpers for smoke test sections.
#
# Sourced by test/runner.sh. Defines pass/fail for assertion narration.
#
# Local-trap convention (F38) — when a section creates its own tmp tree,
# it MUST install a local trap immediately after mktemp -d and restore the
# global trap before its terminal `pass` line. Example:
#
#   TMP_X="$(mktemp -d)"
#   trap 'rm -rf "$TMP_X"' EXIT
#   ... assertions ...
#   trap 'rm -rf "$TMP"' EXIT
#   pass "..."
#
# This survives mid-block fail() under set -euo pipefail; the bare
# rm-at-end pattern leaks. Apply the same pattern in any new section.

pass() { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }
