#!/bin/sh
# Rewrite every testdata/golden/*.json from the Python helpers in bin/.
# Needs python3. Review the git diff before committing the result.
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
for pkg in backlog config fsio initproj jsonx pystr section; do
	go test "./internal/$pkg" -count=1 -run 'Python|Golden' -args -update-golden
done
