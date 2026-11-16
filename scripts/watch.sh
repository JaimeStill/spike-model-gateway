#!/usr/bin/env bash
# Prints each entry of docs/watch.md with its upstream issues and pull requests and its watched
# release fields, each beside the value the entry records, and exits 1 if any differs (or can't be
# read); `differs` marks each such line. Reads the network through gh; writes nothing. The
# register's head describes the entries and their line forms; the check reads only the lines below,
# each a list item whose text starts with a backticked span:
#
#   `upstream <owner/repo>#<n> = <state>`          an issue's or pull request's state: open,
#                                                  closed, or merged
#   `json <owner/repo> <path> <jq expr> = <value>` the jq expression's compact output on the file
#                                                  at the repository's latest release tag
#   `text <owner/repo> <path> <string> = present|absent`
#                                                  whether the file at that tag holds the fixed
#                                                  string
#   `release-contains <owner/repo> <commit> = present|absent`
#                                                  whether that tag's history holds the commit
#
# The latest release is `gh release view`'s, as scripts/currency.sh reads agentgateway's; each
# repository's tag is read once a run and named on every line that reads it.
set -euo pipefail
cd "$(dirname "$0")/.."

register=docs/watch.md
# shellcheck disable=SC2016 # The backticks are the register's, matched literally.
item='^[[:space:]]*-[[:space:]]+`((upstream|json|text|release-contains) [^`]+)`'

declare -A tags=()
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT
differs=0

# Sets tag to the repository's latest release tag, read once a run; empty if it can't be read.
# These set globals rather than print, so the reads they cache outlive the call.
load_tag() {
  [[ -n ${tags[$1]+set} ]] ||
    tags[$1]=$(gh release view -R "$1" --json tagName --jq .tagName 2>/dev/null) || tags[$1]=''
  tag=${tags[$1]}
}

# Sets file to a copy of the repository's file at its latest release tag, raw, read once a run;
# fails if either can't be read.
load_file() {
  load_tag "$1"
  [[ -n $tag ]] || return 1
  file=$cache/${1//\//_}@$tag@${2//\//_}
  [[ -s $file ]] && return
  # A failed read may leave gh's error body behind; it is removed, so no later line reads it.
  gh api -H 'Accept: application/vnd.github.raw' "repos/$1/contents/$2?ref=$tag" \
    >"$file" 2>/dev/null || {
    rm -f "$file"
    return 1
  }
}

# An issue's or pull request's state, lowercase: a pull request's if the number is one, else the
# issue's.
state_of() {
  local repo=${1%#*} n=${1##*#}
  gh pr view "$n" -R "$repo" --json state --jq '.state | ascii_downcase' 2>/dev/null ||
    gh issue view "$n" -R "$repo" --json state --jq '.state | ascii_downcase' 2>/dev/null
}

# Prints one item's line, recorded beside now, and counts a difference.
report() {
  local what=$1 recorded=$2 now=$3
  if [[ $now == "$recorded" ]]; then
    printf '  %s: recorded %s, now %s\n' "$what" "$recorded" "$now"
  else
    printf '  %s: recorded %s, now %s; differs\n' "$what" "$recorded" "${now:-unreadable}"
    differs=1
  fi
}

printf 'checked %s\n' "$(date -u +%FT%H:%MZ)"
while IFS= read -r line; do
  if [[ $line == '## '* ]]; then
    printf '%s\n' "${line#'## '}"
    continue
  fi
  [[ $line =~ $item ]] || continue
  spec=${BASH_REMATCH[1]}
  form=${BASH_REMATCH[2]}
  recorded=${spec##* = }
  read -r _ repo rest <<<"${spec% = *}"
  now=''
  case $form in
    upstream)
      now=$(state_of "$repo") || now=''
      report "$repo" "$recorded" "$now"
      ;;
    json)
      path=${rest%% *} expr=${rest#* }
      if load_file "$repo" "$path"; then
        now=$(jq -c "$expr" "$file" 2>/dev/null | paste -sd ' ') || now=''
      fi
      report "$repo@$tag $path $expr" "$recorded" "$now"
      ;;
    text)
      path=${rest%% *} string=${rest#* }
      if load_file "$repo" "$path"; then
        if grep -qF -- "$string" "$file"; then now=present; else now=absent; fi
      fi
      report "$repo@$tag $path \"$string\"" "$recorded" "$now"
      ;;
    release-contains)
      commit=$rest
      load_tag "$repo"
      if [[ -n $tag ]]; then
        # The tag holds the commit when it is the commit or ahead of it; behind or diverged, not.
        case $(gh api "repos/$repo/compare/$commit...$tag" --jq .status 2>/dev/null) in
          ahead | identical) now=present ;;
          behind | diverged) now=absent ;;
        esac
      fi
      report "$repo@$tag contains ${commit:0:12}" "$recorded" "$now"
      ;;
  esac
done <"$register"

exit "$differs"
