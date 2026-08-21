#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
test_scripts=("$test_directory"/test-*.sh)
shell_scripts=(
  "$repository_directory/install.sh"
  "$repository_directory/uninstall.sh"
  "$repository_directory"/scripts/*.sh
  "$repository_directory"/payload/.agents/skills/repochord/scripts/*.sh
  "$test_directory"/*.sh
  "$test_directory"/fixtures/*.sh
)

for required_command in bash git jq shellcheck; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required test command is not installed: $required_command" >&2
    exit 2
  fi
done

for test_script in "${test_scripts[@]}"; do
  echo "Running $(basename -- "$test_script")"
  bash "$test_script"
done

echo "Checking Bash syntax"

for shell_script in "${shell_scripts[@]}"; do
  bash -n "$shell_script"
done

echo "Running ShellCheck"
shellcheck -S warning "${shell_scripts[@]}"

echo "Validating the RepoChord skill"
bash "$repository_directory/scripts/validate-skill.sh" \
  "$repository_directory/payload/.agents/skills/repochord"

echo "Validating the RepoChord task-authoring skill"
bash "$repository_directory/scripts/validate-task-skill.sh" \
  "$repository_directory/payload/.agents/skills/create-repochord-task"

echo "Checking the Git diff"
git -C "$repository_directory" diff --check

echo "All RepoChord tests passed."
