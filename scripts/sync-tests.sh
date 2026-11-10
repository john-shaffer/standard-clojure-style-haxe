#!/usr/bin/env bash
# Copies the test suites from the upstream repository into tests/upstream
# and records the revision they came from in tests/upstream/REV.
#
# Usage: scripts/sync-tests.sh [rev]
#
# UPSTREAM_REPO overrides the repository, which may be a local path.
set -euo pipefail

repo=${UPSTREAM_REPO:-https://github.com/oakmac/standard-clojure-style-js}
rev=${1:-HEAD}
dest=$(cd "$(dirname "$0")/.." && pwd)/tests/upstream

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --quiet "$repo" "$tmp/src"
git -C "$tmp/src" checkout --quiet "$rev"

suites=(test_format test_parse_ns test_parser)
rm -rf "${dest:?}"
mkdir -p "$dest"
for suite in "${suites[@]}"; do
  cp -r "$tmp/src/$suite" "$dest/$suite"
done
git -C "$tmp/src" rev-parse HEAD > "$dest/REV"
echo "Synced tests from $repo at $(cat "$dest/REV")"
