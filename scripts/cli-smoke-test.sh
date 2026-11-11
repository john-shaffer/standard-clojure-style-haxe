#!/bin/sh
# End-to-end smoke tests of the built CLI. Usage: cli-smoke-test.sh <standard-clj>
# Prints a line per failure; exits non-zero if any check fails.
cli=$(realpath "$1")
fails=0
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir" || exit 2
export NO_COLOR=1

mkdir -p src/gen test
printf '(ns a)\n' > src/a.clj
printf '(ns g)\n' > src/gen/g.clj
printf 'text\n' > src/n.txt
printf '(ns t)\n' > test/t.cljs

# expect <name> <expected exit code> <expected stdout> <args...>
expect() {
  name=$1 code=$2 want=$3
  shift 3
  got=$("$cli" "$@" 2>"$dir/stderr" </dev/null)
  rc=$?
  if [ "$rc" != "$code" ] || [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $rc (want $code), stdout:"
    echo "$got"
    fails=$((fails + 1))
  fi
}

expect "list directory" 0 "$dir/src/a.clj
$dir/src/gen/g.clj" list src
expect "list json" 0 "[\"$dir/src/a.clj\"]" list src --ignore src/gen --output json
expect "list edn" 0 "[\"$dir/src/a.clj\" \"$dir/src/gen/g.clj\"]" list src --output edn
expect "list glob with braces" 0 "$dir/src/a.clj
$dir/test/t.cljs" list --include 'src/*.{clj,cljs}' --include 'test/**/*'
expect "list with --file-ext" 0 "$dir/test/t.cljs" list . --file-ext cljs

printf '{:include ["test/"]\n :ignore ["src/gen"]}\n' > .standard-clj.edn
expect "list uses the EDN config" 0 "$dir/test/t.cljs" list
expect "command-line include replaces config" 0 "$dir/src/a.clj" list --include src --ignore src/gen
printf '{"include": "src"}' > alt.json
expect "list with --config" 0 "$dir/src/a.clj
$dir/src/gen/g.clj" list -c alt.json
rm .standard-clj.edn

expect "unreadable config exits 1" 1 "" list -c missing.edn
if ! grep -q "Unable to load config file: missing.edn" "$dir/stderr"; then
  echo "FAIL missing config message"
  fails=$((fails + 1))
fi

expect "list with no arguments or config uses the current directory" 0 "$dir/src/a.clj
$dir/src/gen/g.clj
$dir/test/t.cljs" list
mkdir empty
cd empty || exit 2
expect "check with no files exits 1" 1 "standard-clj check [dev]" check
cd "$dir" || exit 2
expect "no command exits 1" 1 ""
expect "version" 0 "[dev]" --version
expect "fix - with empty stdin exits 1" 1 "" fix -

# a missing ignore path only warns
"$cli" list src/a.clj --ignore nope >/dev/null 2>"$dir/stderr"
if ! grep -q 'WARN Could not find a file or directory to ignore at "nope"' "$dir/stderr"; then
  echo "FAIL ignore warning"
  fails=$((fails + 1))
fi

[ "$fails" = 0 ] || exit 1
echo "all CLI smoke tests passed"
