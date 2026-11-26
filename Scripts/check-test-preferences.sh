#!/bin/sh
# Wrap a test command and fail if it creates a new fixture plist.
set -eu
[ "$#" -gt 0 ] || { echo 'Usage: check-test-preferences.sh command [args...]' >&2; exit 2; }
clean="$(dirname "$0")/clean-test-preferences.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
snapshot() {
    "$clean" > "$scratch/list"
    sed '$d' "$scratch/list" | LC_ALL=C sort
}
snapshot > "$scratch/before"
status=0
"$@" || status=$?
snapshot > "$scratch/after"
new=$(LC_ALL=C comm -13 "$scratch/before" "$scratch/after" | wc -l)
echo "Preference files before $(wc -l < "$scratch/before"), after $(wc -l < "$scratch/after"), new $new"
[ "$new" -eq 0 ] || exit 1
exit "$status"
