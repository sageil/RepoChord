#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  echo "Usage: build-installer.sh [--check]" >&2
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
source_files=("$repository_directory"/src/install/*.sh)
output_path="$repository_directory/install.sh"
output_stage="$(mktemp "${TMPDIR:-/tmp}/repochord-installer.XXXXXX")"

cleanup() {
  rm -f -- "$output_stage"
}

trap cleanup EXIT
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
    echo "Generated RepoChord installer is stale. Run scripts/build-installer.sh." >&2
    exit 1
  fi

  exit 0
fi

mv -- "$output_stage" "$output_path"
output_stage=""
