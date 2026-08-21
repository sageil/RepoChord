#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  echo "Usage: build-skill-scripts.sh [--check]" >&2
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
source_root="$repository_directory/src/skill-scripts"
output_root="$repository_directory/payload/.agents/skills/repochord/scripts"
script_names=(
  integrate-run
  report-run
  run-repository-agent
  run-repository-agents
)
output_stages=()

cleanup() {
  local output_stage

  for output_stage in "${output_stages[@]}"; do
    rm -f -- "$output_stage"
  done
}

trap cleanup EXIT

for script_name in "${script_names[@]}"; do
  source_files=("$source_root/$script_name"/*.sh)
  output_path="$output_root/$script_name.sh"
  output_stage="$(mktemp "${TMPDIR:-/tmp}/repochord-${script_name}.XXXXXX")"
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
      echo "Generated skill script is stale: $output_path" >&2
      exit 1
    fi

    continue
  fi

  mv -- "$output_stage" "$output_path"
  output_stages[-1]=""
done
