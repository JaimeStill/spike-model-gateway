#!/usr/bin/env bash
# Shellchecks every tracked file whose first line is a sh or bash shebang, and checks that every
# relative link in a tracked Markdown file resolves to a tracked or present file, then vets the
# retry test's module (retry/) and runs its tests, every live case skipping. Reads no network but
# the Go module proxy, once, while go-ai's release isn't yet in the module cache.
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

# RETRY_CASE is cleared, so a case left live in the caller's shell can't reach the gateway here.
(cd retry && go vet ./... && env -u RETRY_CASE go test -count=1 ./...) || fail=1

exit "$fail"
