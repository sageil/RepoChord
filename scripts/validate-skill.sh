#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: validate-skill.sh <skill-directory>" >&2
  exit 2
fi

skill_directory="$1"

if [[ ! -d "$skill_directory" ]]; then
  echo "Skill directory does not exist: $skill_directory" >&2
  exit 1
fi

required_files=(
  "SKILL.md"
  "agents/openai.yaml"
  "assets/repository-agent-response.schema.json"
  "assets/repository-agent-result.schema.json"
  "references/file-formats.md"
  "scripts/run-repository-agent.sh"
  "scripts/run-repository-agents.sh"
  "scripts/scaffold-feature.sh"
  "scripts/report-run.sh"
  "scripts/integrate-run.sh"
)

for relative_path in "${required_files[@]}"; do
  if [[ ! -f "$skill_directory/$relative_path" ]]; then
    echo "Required skill file is missing: $relative_path" >&2
    exit 1
  fi
done

if ! grep -q '^name: repomux$' "$skill_directory/SKILL.md"; then
  echo "SKILL.md has the wrong skill name." >&2
  exit 1
fi

if ! grep -q '^description: .\+' "$skill_directory/SKILL.md"; then
  echo "SKILL.md has no description." >&2
  exit 1
fi

if ! grep -Fq 'Stop and wait for explicit user approval.' "$skill_directory/SKILL.md"; then
  echo "SKILL.md does not require contract approval." >&2
  exit 1
fi

if ! grep -Fq 'Do not run `scaffold-feature.sh`, create or edit feature files, or start repository agents until the user approves the contract.' "$skill_directory/SKILL.md"; then
  echo "SKILL.md does not enforce the contract approval boundary." >&2
  exit 1
fi

for script_path in "$skill_directory"/scripts/*.sh; do
  bash -n "$script_path"

  if [[ ! -x "$script_path" ]]; then
    echo "Skill script is not executable: $script_path" >&2
    exit 1
  fi
done

for schema_path in "$skill_directory"/assets/*.schema.json; do
  jq empty "$schema_path"
done

echo "Skill validation passed: $skill_directory"
