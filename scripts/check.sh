#!/usr/bin/env bash
# Shellchecks every tracked file whose first line is a sh or bash shebang, and checks that every
# relative link in a tracked Markdown file resolves to a tracked or present file. Reads no network.
set -uo pipefail
cd "$(dirname "$0")/.." || exit

fail=0

scripts=()
while IFS= read -r -d '' file; do
  if head -n 1 "$file" | grep -Eq '^#!.*\b(ba)?sh\b'; then
    scripts+=("$file")
  fi
done < <(git ls-files -z)
if ((${#scripts[@]})); then
  shellcheck "${scripts[@]}" || fail=1
fi

# A link is relative when it names no scheme and isn't an in-page anchor; its fragment is dropped.
while IFS= read -r -d '' file; do
  dir=$(dirname "$file")
  while read -r target; do
    target=${target%%#*}
    [[ -z $target ]] && continue
    if [[ ! -e "$dir/$target" ]]; then
      echo "FAIL: $file: link $target does not resolve" >&2
      fail=1
    fi
  done < <(grep -oP '\]\(\K(?![a-z][a-z0-9+.-]*:|#)[^)\s]+' "$file")
done < <(git ls-files -z -- '*.md')

exit "$fail"
