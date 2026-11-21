#!/usr/bin/env bash
# Shellchecks every tracked file whose first line is a sh or bash shebang, and checks that every
# relative link in a tracked Markdown file resolves to a tracked or present file, vets the retry
# test's module (retry/) and runs its tests, every live case skipping, and runs lint-context and
# lint-references. Reads no network but the Go module proxy, once, while go-ai's release isn't yet
# in the module cache.
set -uo pipefail
cd "$(dirname "$0")/.." || exit

shellcheck_scripts() {
  local scripts=() file
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -Eq '^#!.*\b(ba)?sh\b'; then
      scripts+=("$file")
    fi
  done < <(git ls-files -z)
  if ((${#scripts[@]})); then
    shellcheck "${scripts[@]}"
  fi
}

check_relative_links() {
  local file dir target status=0
  while IFS= read -r -d '' file; do
    dir=$(dirname "$file") || return
    while read -r target; do
      target=${target%%#*}
      [[ -z $target ]] && continue
      if [[ ! -e "$dir/$target" ]]; then
        echo "FAIL: $file: link $target does not resolve" >&2
        status=1
      fi
    done < <(grep -oP '\]\(\K(?![a-z][a-z0-9+.-]*:|#)[^)\s]+' "$file")
  done < <(git ls-files -z -- '*.md')
  return "$status"
}

vet_and_test_retry_with_no_live_case() {
  (cd retry && go vet ./... && env -u RETRY_CASE go test -count=1 ./...)
}

run_lint() {
  if ! command -v "$1" >/dev/null; then
    echo "FAIL: $1 is not on PATH; run mise install" >&2
    return 1
  fi
  "$1"
}

fail=0
shellcheck_scripts || fail=1
check_relative_links || fail=1
vet_and_test_retry_with_no_live_case || fail=1
run_lint lint-context || fail=1
run_lint lint-references || fail=1
exit "$fail"
