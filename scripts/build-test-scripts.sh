#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  echo "Usage: build-test-scripts.sh [--check]" >&2
}

check_only=false

if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi

if [[ "$#" -ne 0 ]]; then
  usage
  exit 2
fi

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$script_directory/.." && pwd -P)"
source_root="$repository_directory/src/test-scripts"
output_root="$repository_directory/tests"
test_names=(
  test-installer
  test-repository-agent
)
output_stages=()

cleanup() {
  local output_stage

  for output_stage in "${output_stages[@]}"; do
    rm -f -- "$output_stage"
  done
}

trap cleanup EXIT

for test_name in "${test_names[@]}"; do
  source_files=("$source_root/$test_name"/*.sh)
  output_path="$output_root/$test_name.sh"
  output_stage="$(mktemp "${TMPDIR:-/tmp}/repochord-${test_name}.XXXXXX")"
  output_stages+=("$output_stage")
  : > "$output_stage"

  for ((source_index = 0; source_index < ${#source_files[@]}; source_index++)); do
    awk '1' "${source_files[$source_index]}" >> "$output_stage"

    if ((source_index + 1 < ${#source_files[@]})); then
      printf '\n' >> "$output_stage"
    fi
  done

  chmod +x "$output_stage"

  if [[ "$check_only" == true ]]; then
    if ! diff -u -- "$output_path" "$output_stage"; then
      echo "Generated test script is stale: $output_path" >&2
      exit 1
    fi

    continue
  fi

  mv -- "$output_stage" "$output_path"
  output_stages[-1]=""
done
