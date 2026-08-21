#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  echo "Usage: build-rchord.sh [--check]" >&2
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
source_directory="$repository_directory/src/rchord"
output_path="$repository_directory/payload/rchord"
output_stage="$(mktemp "${TMPDIR:-/tmp}/repochord-command.XXXXXX")"

cleanup() {
  rm -f -- "$output_stage"
}

trap cleanup EXIT

source_files=(
  "$source_directory/base.sh"
  "$source_directory/skill-validation.sh"
  "$source_directory/project-validation.sh"
  "$source_directory/skill-upgrade.sh"
  "$source_directory/project-resolution.sh"
  "$source_directory/completion-candidates.sh"
  "$source_directory/completion-bash.sh"
  "$source_directory/completion-zsh.sh"
  "$source_directory/completion-command.sh"
  "$source_directory/init-command.sh"
  "$source_directory/project-commands.sh"
  "$source_directory/run-commands.sh"
  "$source_directory/start-command.sh"
  "$source_directory/main.sh"
)

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
    echo "Generated RepoChord command is stale. Run scripts/build-rchord.sh." >&2
    exit 1
  fi

  exit 0
fi

mv -- "$output_stage" "$output_path"
output_stage=""
