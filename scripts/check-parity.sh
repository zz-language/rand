#!/bin/sh
# VM-vs-AOT bit-identity check for int-domain streams.
# Floats are excluded by design (see tests/parity_dump.zz header).
set -e
cd "$(dirname "$0")/../tests"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM
zz run parity_dump.zz >"$tmpdir/vm.out"
zz build parity_dump.zz -o parity_aot
./bin/parity_aot >"$tmpdir/aot.out"
rm -f ./bin/parity_aot
if diff "$tmpdir/vm.out" "$tmpdir/aot.out"; then
	echo "parity_ok"
else
	echo "parity FAILED: VM and AOT streams differ" >&2
	exit 1
fi
