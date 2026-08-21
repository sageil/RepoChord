#!/usr/bin/env bash

# Generated from src/skill-scripts by scripts/build-skill-scripts.sh.
# Do not edit this script in the payload directly.

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

export GIT_OPTIONAL_LOCKS=0

usage() {
  echo "Usage: report-run.sh <run-id>" >&2
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

single_line() {
  local result_path="$1"
  local filter="$2"

  jq -r "$filter | gsub(\"[\\u0000-\\u001F\\u007F]\"; \" \")" "$result_path"
}

markdown_code() {
  local value="$1"
  local delimiter='`'

  while [[ "$value" == *"$delimiter"* ]]; do
    delimiter="${delimiter}"'`'
  done

  printf '%s%s%s' "$delimiter" "$value" "$delimiter"
}

display_string_list() {
  local result_path="$1"
  local filter="$2"
  local empty_text="$3"
  local item_count
  local item

  item_count="$(jq "$filter | length" "$result_path")"

  if [[ "$item_count" -eq 0 ]]; then
    printf '    %s\n' "$(markdown_code "$empty_text")"
    return
  fi

  while IFS= read -r item; do
    printf '    - %s\n' "$(markdown_code "$item")"
  done < <(jq -r "${filter}[] | gsub(\"[\\u0000-\\u001F\\u007F]\"; \" \")" "$result_path")
}

inline_string_list() {
  local result_path="$1"
  local filter="$2"
  local empty_text="$3"

  jq -r \
    --arg empty_text "$empty_text" \
    "$filter | if length == 0 then \$empty_text else map(gsub(\"[\\u0000-\\u001F\\u007F]\"; \" \")) | join(\"; \") end" \
    "$result_path"
}
