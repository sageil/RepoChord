#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: validate-task-skill.sh <skill-directory>" >&2
  exit 2
fi

skill_directory="$1"
required_files=(
  "SKILL.md"
  "references/request-template.md"
  "references/repository-task-template.md"
)

if [[ ! -d "$skill_directory" ]]; then
  echo "Task-authoring skill directory does not exist: $skill_directory" >&2
  exit 1
fi

for relative_path in "${required_files[@]}"; do
  if [[ ! -f "$skill_directory/$relative_path" ]]; then
    echo "Required task-authoring skill file is missing: $relative_path" >&2
    exit 1
  fi
done

if ! grep -q '^name: create-repochord-task$' "$skill_directory/SKILL.md"; then
  echo "Task-authoring SKILL.md has the wrong skill name." >&2
  exit 1
fi

if ! grep -q '^description: .\+' "$skill_directory/SKILL.md"; then
  echo "Task-authoring SKILL.md has no description." >&2
  exit 1
fi

if grep -R -Eq '\[[A-Z_]+\]|\[TODO\]|TODO:' "$skill_directory"; then
  echo "Task-authoring skill contains an unfinished scaffold placeholder." >&2
  exit 1
fi

echo "Task-authoring skill validation passed: $skill_directory"
