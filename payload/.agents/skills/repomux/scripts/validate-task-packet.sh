#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: validate-task-packet.sh <absolute-assignments-file>" >&2
}

fail() {
  echo "$1" >&2
  exit 1
}

section_body() {
  local document_path="$1"
  local heading="$2"

  awk -v heading="## $heading" '
    $0 == heading {
      in_section = 1
      next
    }
    in_section && /^## / {
      exit
    }
    in_section {
      print
    }
  ' "$document_path"
}

require_section() {
  local document_path="$1"
  local heading="$2"
  local body

  if ! grep -Fqx "## $heading" "$document_path"; then
    fail "Missing section '$heading': $document_path"
  fi

  body="$(section_body "$document_path" "$heading")"

  if [[ -z "${body//[[:space:]]/}" ]]; then
    fail "Empty section '$heading': $document_path"
  fi
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

assignments_file="$1"

if [[ "$assignments_file" != /* ]]; then
  echo "Assignments file must be absolute: $assignments_file" >&2
  exit 2
fi

if [[ -L "$assignments_file" || ! -f "$assignments_file" ]]; then
  echo "Assignments file does not exist or is not a regular file: $assignments_file" >&2
  exit 2
fi

for required_command in awk git grep jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
registry_path="$coordinate_root/.repomux/repositories.json"
canonical_assignments_file="$(cd -- "$(dirname -- "$assignments_file")" && pwd -P)/$(basename -- "$assignments_file")"
tasks_root="$coordinate_root/tasks"

if [[ ! -f "$registry_path" ]]; then
  fail "Repository registry does not exist: $registry_path"
fi

feature_directory="$(dirname -- "$canonical_assignments_file")"

if [[ "$(dirname -- "$feature_directory")" != "$tasks_root" ]]; then
  fail "Assignments file must be under: $tasks_root"
fi

if [[ "$(basename -- "$canonical_assignments_file")" != "assignments.txt" ]]; then
  fail "Assignments file must be named assignments.txt: $canonical_assignments_file"
fi

feature_id="$(basename -- "$feature_directory")"
request_file="$coordinate_root/requests/$feature_id.md"

if [[ -L "$request_file" || ! -f "$request_file" ]]; then
  fail "Feature request does not exist or is not a regular file: $request_file"
fi

request_sections=(
  "User outcome"
  "Repositories"
  "Shared contract"
  "State transitions and invariants"
  "Authorization"
  "Completion rules"
)

for heading in "${request_sections[@]}"; do
  require_section "$request_file" "$heading"
done

if grep -Eq '<(Add|Copy|Define|Describe|Explain|State)[^>]*>' "$request_file"; then
  fail "Feature request contains an unfinished placeholder: $request_file"
fi

task_sections=(
  "Repository"
  "Mission"
  "Dependencies"
  "Context to read first"
  "Environment"
  "File scope"
  "Shared contract"
  "Steps"
  "Failure and restart behavior"
  "Authorization and data handling"
  "Acceptance criteria"
  "Required verification"
  "Documentation requirements"
  "Completion criteria"
  "Commit"
  "Do not"
)

assignment_count=0
repository_keys=()

while IFS='|' read -r repository_key repository_path task_file extra_field || [[ -n "$repository_key$repository_path$task_file$extra_field" ]]; do
  if [[ -n "$extra_field" || -z "$repository_key" || -z "$repository_path" || -z "$task_file" ]]; then
    fail "Invalid assignment line: $canonical_assignments_file"
  fi

  if [[ "$repository_key" == *[!A-Za-z0-9._-]* ]]; then
    fail "Invalid repository key in assignment: $repository_key"
  fi

  for existing_key in ${repository_keys[@]+"${repository_keys[@]}"}; do
    if [[ "$existing_key" == "$repository_key" ]]; then
      fail "Duplicate repository key in assignments: $repository_key"
    fi
  done

  repository_keys+=("$repository_key")
  assignment_count=$((assignment_count + 1))

  registered_path="$(jq -r --arg key "$repository_key" '
    [.repositories[] | select(.key == $key)] |
    if length == 1 then .[0].path else "" end
  ' "$registry_path")"

  if [[ -z "$registered_path" || "$registered_path" != "$repository_path" ]]; then
    fail "Assignment does not match the repository registry: $repository_key"
  fi

  expected_task_file="$feature_directory/$repository_key.md"

  if [[ "$task_file" != "$expected_task_file" ]]; then
    fail "Assignment task path is not canonical for '$repository_key': $task_file"
  fi

  if [[ -L "$task_file" || ! -f "$task_file" ]]; then
    fail "Repository task does not exist or is not a regular file: $task_file"
  fi

  for heading in "${task_sections[@]}"; do
    require_section "$task_file" "$heading"
  done

  if grep -Eq '<(Add|Copy|Define|Describe|Explain|State)[^>]*>|<modified or new>' "$task_file"; then
    fail "Repository task contains an unfinished placeholder: $task_file"
  fi

  if ! grep -Fqx "Repository key: \`$repository_key\`" "$task_file"; then
    fail "Repository task has the wrong repository key: $task_file"
  fi

  if ! grep -Fqx "Repository path: \`$repository_path\`" "$task_file"; then
    fail "Repository task has the wrong repository path: $task_file"
  fi

  if ! grep -Eq '^- \[[ xX]\] .+' "$task_file"; then
    fail "Repository task has no outcome checklist items: $task_file"
  fi

  verification_body="$(section_body "$task_file" "Required verification")"

  if ! grep -Eq '`[^`]+`' <<< "$verification_body"; then
    fail "Repository task has no required verification command: $task_file"
  fi

  if ! grep -Eq '^Commit message: `([a-z]+)(\([A-Za-z0-9._-]+\))?: .+`$' "$task_file"; then
    fail "Repository task has an invalid Conventional Commit message: $task_file"
  fi
done < "$canonical_assignments_file"

if [[ "$assignment_count" -lt 2 ]]; then
  fail "RepoMux task packets require at least two repository assignments."
fi

echo "Task packet validation passed: $feature_id"
