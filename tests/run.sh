#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord tests require Bash 5.2 or later." >&2
  exit 2
fi

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
test_scripts=("$test_directory"/test-*.sh)
shell_scripts=(
  "$repository_directory/install.sh"
  "$repository_directory/uninstall.sh"
  "$repository_directory/payload/rchord"
  "$repository_directory"/scripts/*.sh
  "$repository_directory"/payload/.agents/skills/repochord/scripts/*.sh
  "$test_directory"/*.sh
  "$test_directory"/fixtures/*.sh
)
source_fragments=(
  "$repository_directory"/src/rchord/*.sh
  "$repository_directory"/src/install/*.sh
  "$repository_directory"/src/skill-scripts/*/*.sh
  "$repository_directory"/src/test-scripts/*/*.sh
)

for required_command in bash git jq shellcheck zsh; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required test command is not installed: $required_command" >&2
    exit 2
  fi
done

echo "Checking the generated RepoChord command"
bash "$repository_directory/scripts/build-rchord.sh" --check
echo "Checking the generated RepoChord installer"
bash "$repository_directory/scripts/build-installer.sh" --check
echo "Checking the generated RepoChord skill scripts"
bash "$repository_directory/scripts/build-skill-scripts.sh" --check
echo "Checking the generated RepoChord test scripts"
bash "$repository_directory/scripts/build-test-scripts.sh" --check

for test_script in "${test_scripts[@]}"; do
  echo "Running $(basename -- "$test_script")"
  bash "$test_script"
done

echo "Checking Bash syntax"

for shell_script in "${shell_scripts[@]}" "${source_fragments[@]}"; do
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
