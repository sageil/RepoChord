#!/usr/bin/env bash

# The single-quoted format strings intentionally contain Markdown backticks.
# shellcheck disable=SC2016

set -euo pipefail

usage() {
  echo "Usage: scaffold-feature.sh <feature-id> <repository-key>..." >&2
  echo "   or: scaffold-feature.sh --title <feature-title> <repository-key>..." >&2
}

feature_id=""
feature_title=""
generate_feature_id=false
reuse_existing_feature=false

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -lt 2 ]]; then
  usage
  exit 2
fi

case "$1" in
  --title)
    if [[ "$#" -lt 3 || -z "$2" ]]; then
      usage
      exit 2
    fi

    feature_title="$2"
    generate_feature_id=true
    shift 2
    ;;
  -*)
    echo "Unknown argument: $1" >&2
    usage
    exit 2
    ;;
  *)
    feature_id="$1"
    shift
    ;;
esac

if [[ "$#" -lt 1 ]]; then
  usage
  exit 2
fi

if [[ "$generate_feature_id" == true ]]; then
  if [[ "$feature_title" == *$'\n'* || "$feature_title" == *$'\r'* ]]; then
    echo "Feature title must be one line." >&2
    exit 2
  fi
elif [[ ! "$feature_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Feature ID contains unsupported characters: $feature_id" >&2
  exit 2
fi

required_commands=(git jq tr)

for required_command in "${required_commands[@]}"; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

if [[ "$generate_feature_id" != true ]] &&
  ! git check-ref-format "refs/heads/repomux/$feature_id-run-validation/repository" >/dev/null 2>&1
then
  echo "Feature ID cannot form a valid RepoMux branch: $feature_id" >&2
  exit 2
fi

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
registry_path="$coordinate_root/.repomux/repositories.json"

resolved_existing_feature_id=""

resolve_existing_feature_id() {
  local requested_feature_id="$1"
  local normalized_requested_feature_id
  local candidate_path
  local candidate_feature_id
  local normalized_candidate_feature_id
  local existing_feature_id
  local already_recorded
  local matching_feature_ids=()

  normalized_requested_feature_id="$(printf '%s' "$requested_feature_id" | LC_ALL=C tr '[:upper:]' '[:lower:]')"

  for candidate_path in "$coordinate_root/requests/"*.md "$coordinate_root/tasks/"*; do
    if [[ ! -e "$candidate_path" && ! -L "$candidate_path" ]]; then
      continue
    fi

    candidate_feature_id="$(basename -- "$candidate_path")"

    if [[ "$candidate_path" == "$coordinate_root/requests/"*.md ]]; then
      candidate_feature_id="${candidate_feature_id%.md}"
    fi

    normalized_candidate_feature_id="$(printf '%s' "$candidate_feature_id" | LC_ALL=C tr '[:upper:]' '[:lower:]')"

    if [[ "$normalized_candidate_feature_id" != "$normalized_requested_feature_id" ]]; then
      continue
    fi

    already_recorded=false

    for existing_feature_id in ${matching_feature_ids[@]+"${matching_feature_ids[@]}"}; do
      if [[ "$existing_feature_id" == "$candidate_feature_id" ]]; then
        already_recorded=true
        break
      fi
    done

    if [[ "$already_recorded" == false ]]; then
      matching_feature_ids+=("$candidate_feature_id")
    fi
  done

  if [[ "${#matching_feature_ids[@]}" -gt 1 ]]; then
    echo "Feature ID differs only by letter case: $requested_feature_id" >&2
    exit 2
  fi

  if [[ "${#matching_feature_ids[@]}" -eq 1 ]]; then
    resolved_existing_feature_id="${matching_feature_ids[0]}"
  fi
}

identifier_reservation=""
staging_directory=""
request_path=""
task_directory=""
assignment_path=""
request_installed=false
tasks_installed=false

# shellcheck disable=SC2329
cleanup() {
  if [[ "$tasks_installed" == true && -n "$task_directory" ]]; then
    rm -rf -- "$task_directory"
  fi

  if [[ "$request_installed" == true && -n "$request_path" ]]; then
    rm -f -- "$request_path"
  fi

  if [[ -n "$staging_directory" ]]; then
    rm -rf -- "$staging_directory"
  fi

  if [[ -n "$identifier_reservation" ]]; then
    rm -rf -- "$identifier_reservation"
  fi
}

trap cleanup EXIT

if [[ ! -f "$registry_path" ]]; then
  echo "Repository registry does not exist: $registry_path" >&2
  exit 2
fi

if [[ "$generate_feature_id" == true ]]; then
  feature_slug="$(printf '%s' "$feature_title" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9' '-')"
  feature_slug="${feature_slug#-}"
  feature_slug="${feature_slug%-}"
  feature_slug="${feature_slug:0:48}"
  feature_slug="${feature_slug%-}"

  if [[ -z "$feature_slug" ]]; then
    feature_slug="feature"
  fi

  resolve_existing_feature_id "$feature_slug"

  if [[ -n "$resolved_existing_feature_id" ]]; then
    feature_id="$resolved_existing_feature_id"
    request_path="$coordinate_root/requests/$feature_id.md"
    task_directory="$coordinate_root/tasks/$feature_id"
    reuse_existing_feature=true
  else
    while true; do
      identifier_reservation="$(mktemp -d "$coordinate_root/.repomux-feature-id.XXXXXX")"
      identifier_suffix="$(basename -- "$identifier_reservation")"
      identifier_suffix="${identifier_suffix##*.}"
      identifier_suffix="$(printf '%s' "$identifier_suffix" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
      feature_id="$feature_slug-$identifier_suffix"
      request_path="$coordinate_root/requests/$feature_id.md"
      task_directory="$coordinate_root/tasks/$feature_id"

      if [[ ! -e "$request_path" && ! -e "$task_directory" ]]; then
        break
      fi

      rm -rf -- "$identifier_reservation"
      identifier_reservation=""
    done
  fi
else
  resolve_existing_feature_id "$feature_id"

  if [[ -n "$resolved_existing_feature_id" ]]; then
    feature_id="$resolved_existing_feature_id"
  fi

  request_path="$coordinate_root/requests/$feature_id.md"
  task_directory="$coordinate_root/tasks/$feature_id"
fi

assignment_path="$task_directory/assignments.txt"

if [[ -e "$request_path" || -e "$task_directory" ]]; then
  reuse_existing_feature=true
fi

repository_keys=()
repository_paths=()

for repository_key in "$@"; do
  if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ]] ||
    ! git check-ref-format "refs/heads/repomux/validation/$repository_key" >/dev/null 2>&1
  then
    echo "Repository key contains unsupported characters: $repository_key" >&2
    exit 2
  fi

  for existing_key in ${repository_keys[@]+"${repository_keys[@]}"}; do
    if [[ "$existing_key" == "$repository_key" ]]; then
      echo "Duplicate repository key: $repository_key" >&2
      exit 2
    fi
  done

  match_count="$(jq --arg key "$repository_key" '[.repositories[] | select(.key == $key)] | length' "$registry_path")"

  if [[ "$match_count" -ne 1 ]]; then
    echo "Repository key is missing or duplicated in the registry: $repository_key" >&2
    exit 2
  fi

  repository_path="$(jq -r --arg key "$repository_key" '.repositories[] | select(.key == $key) | .path' "$registry_path")"

  if [[ ! -d "$repository_path" ]]; then
    echo "Repository directory does not exist: $repository_path" >&2
    exit 2
  fi

  canonical_repository_path="$(cd -- "$repository_path" && pwd -P)"

  if ! repository_root="$(git -C "$canonical_repository_path" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "Path is not inside a Git repository: $repository_path" >&2
    exit 2
  fi

  repository_root="$(cd -- "$repository_root" && pwd -P)"

  if [[ "$canonical_repository_path" != "$repository_root" ]]; then
    echo "Repository path must be the Git repository root: $repository_path" >&2
    exit 2
  fi

  if ! git -C "$canonical_repository_path" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Repository has no initial commit: $repository_path" >&2
    exit 2
  fi

  for existing_path in ${repository_paths[@]+"${repository_paths[@]}"}; do
    if [[ "$existing_path" == "$canonical_repository_path" ]]; then
      echo "Duplicate canonical repository path: $canonical_repository_path" >&2
      exit 2
    fi
  done

  repository_keys+=("$repository_key")
  repository_paths+=("$canonical_repository_path")
done

if [[ "$reuse_existing_feature" == true ]]; then
  if [[ -L "$request_path" || ! -f "$request_path" ]]; then
    echo "Existing feature request is missing or unsafe: $request_path" >&2
    exit 2
  fi

  if [[ -L "$task_directory" || ! -d "$task_directory" ]]; then
    echo "Existing feature task directory is missing or unsafe: $task_directory" >&2
    exit 2
  fi

  if [[ -L "$assignment_path" || ! -f "$assignment_path" ]]; then
    echo "Existing feature assignments are missing or unsafe: $assignment_path" >&2
    exit 2
  fi

  assignment_keys=()

  while IFS='|' read -r assignment_key assignment_repository_path assignment_task_path assignment_extra; do
    if [[ -z "$assignment_key" || \
      -z "$assignment_repository_path" || \
      -z "$assignment_task_path" || \
      -n "$assignment_extra" ]]
    then
      echo "Existing feature assignment is invalid: $assignment_path" >&2
      exit 2
    fi

    repository_index=-1

    for ((index = 0; index < ${#repository_keys[@]}; index++)); do
      if [[ "${repository_keys[$index]}" == "$assignment_key" ]]; then
        repository_index="$index"
        break
      fi
    done

    if [[ "$repository_index" -lt 0 ]]; then
      echo "Existing feature has an unexpected repository assignment: $assignment_key" >&2
      exit 2
    fi

    for existing_key in ${assignment_keys[@]+"${assignment_keys[@]}"}; do
      if [[ "$existing_key" == "$assignment_key" ]]; then
        echo "Existing feature has a duplicate repository assignment: $assignment_key" >&2
        exit 2
      fi
    done

    expected_task_path="$task_directory/$assignment_key.md"

    if [[ "$assignment_repository_path" != "${repository_paths[$repository_index]}" ]]; then
      echo "Existing feature repository path does not match the registry: $assignment_key" >&2
      exit 2
    fi

    if [[ "$assignment_task_path" != "$expected_task_path" || \
      -L "$expected_task_path" || \
      ! -f "$expected_task_path" ]]
    then
      echo "Existing feature task is missing or unsafe: $expected_task_path" >&2
      exit 2
    fi

    assignment_keys+=("$assignment_key")
  done < "$assignment_path"

  if [[ "${#assignment_keys[@]}" -ne "${#repository_keys[@]}" ]]; then
    echo "Existing feature assignments do not match the requested repositories: $feature_id" >&2
    exit 2
  fi

  trap - EXIT
  printf '%s\n' "$request_path"
  printf '%s\n' "$assignment_path"
  exit 0
fi

staging_directory="$(mktemp -d "$coordinate_root/.repomux-feature.${feature_id}.XXXXXX")"

mkdir -p "$staging_directory/requests" "$staging_directory/tasks/$feature_id"

{
  printf '# %s\n\n' "$feature_id"
  printf '## User outcome\n\n'

  if [[ -n "$feature_title" ]]; then
    printf '%s\n\n' "$feature_title"
  else
    printf '<Describe the user-visible or operational outcome.>\n\n'
  fi

  printf '## Repositories\n\n'

  for ((index = 0; index < ${#repository_keys[@]}; index++)); do
    printf -- '- `%s`: `%s`\n' "${repository_keys[$index]}" "${repository_paths[$index]}"
  done

  printf '\n## Shared contract\n\n'
  printf '<Define API, event, schema, version, or file contracts shared by repositories.>\n\n'
  printf '## State transitions and invariants\n\n'
  printf '<Define normal states, failure states, restart behavior, and invariants.>\n\n'
  printf '## Authorization\n\n'
  printf '<Define the identities and permissions required for each operation.>\n\n'
  printf '## Completion rules\n\n'
  printf 'All required repositories must complete their acceptance criteria and focused tests.\n'
  printf 'RepoMux creates local commits after successful repository-agent verification.\n'
  printf 'Repository agents must not stage, commit, push, or merge changes.\n'
} > "$staging_directory/requests/$feature_id.md"

for ((index = 0; index < ${#repository_keys[@]}; index++)); do
  repository_key="${repository_keys[$index]}"
  repository_path="${repository_paths[$index]}"
  task_path="$staging_directory/tasks/$feature_id/$repository_key.md"

  {
    printf '# %s task for %s\n\n' "$feature_id" "$repository_key"
    printf '## Repository\n\n'
    printf 'Repository key: `%s`\n\n' "$repository_key"
    printf 'Repository path: `%s`\n\n' "$repository_path"
    printf '## Goal\n\n'
    printf '<Define the bounded repository outcome.>\n\n'
    printf '## Shared contract\n\n'
    printf '<Copy the exact relevant contract from the feature request.>\n\n'
    printf '## Acceptance criteria\n\n'
    printf -- '- <Add observable acceptance criteria.>\n\n'
    printf '## Required verification\n\n'
    printf '`<Add focused test command.>`\n\n'
    printf '## Commit\n\n'
    printf 'RepoMux creates the commit only after all acceptance criteria and required tests pass.\n\n'
    printf 'Commit message: `<add commit message>`\n\n'
    printf 'Do not stage, commit, push, merge, or rebase.\n'
  } > "$task_path"

  printf '%s|%s|%s\n' \
    "$repository_key" \
    "$repository_path" \
    "$coordinate_root/tasks/$feature_id/$repository_key.md" \
    >> "$staging_directory/tasks/$feature_id/assignments.txt"
done

mkdir -p "$coordinate_root/requests" "$coordinate_root/tasks"
mv -- "$staging_directory/requests/$feature_id.md" "$request_path"
request_installed=true
mv -- "$staging_directory/tasks/$feature_id" "$task_directory"
tasks_installed=true

rm -rf -- "$staging_directory"
staging_directory=""

if [[ -n "$identifier_reservation" ]]; then
  rm -rf -- "$identifier_reservation"
  identifier_reservation=""
fi

trap - EXIT

printf '%s\n' "$request_path"
printf '%s\n' "$assignment_path"
