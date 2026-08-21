#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: cleanup-worktrees.sh [--force] (--all | <run-id>) [repository-key...]" >&2
}

validate_run_id() {
  local value="$1"

  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ || "$value" == "." || "$value" == ".." ]]; then
    echo "Run ID contains unsupported characters: $value" >&2
    exit 2
  fi
}

validate_repository_key() {
  local value="$1"

  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ||
    "$value" == "." ||
    "$value" == ".." ||
    "$value" == .* ||
    "$value" == *. ||
    "$value" == *.lock ||
    "$value" == *..* ]]
  then
    echo "Repository key contains unsupported characters: $value" >&2
    exit 2
  fi
}

repository_is_selected() {
  local candidate="$1"
  local selected_key

  if [[ "${#requested_repository_keys[@]}" -eq 0 ]]; then
    return 0
  fi

  for selected_key in "${requested_repository_keys[@]}"; do
    if [[ "$selected_key" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

add_target() {
  target_run_ids+=("$1")
  target_repository_keys+=("$2")
}

force=false
all_runs=false
run_id=""

if [[ "${1:-}" == "--force" ]]; then
  force=true
  shift
fi

if [[ "${1:-}" == "--all" ]]; then
  all_runs=true
  shift
elif [[ "$#" -gt 0 ]]; then
  run_id="$1"
  shift
else
  usage
  exit 2
fi

if [[ "$all_runs" != true ]]; then
  validate_run_id "$run_id"
fi

for required_command in find git jq sort; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
registry_path="$coordinate_root/.repochord/repositories.json"
worktree_runs_root="$coordinate_root/.repochord/worktrees"
private_repository_runs_root="$coordinate_root/.repochord/repositories"

if [[ ! -f "$registry_path" ]]; then
  echo "Repository registry does not exist: $registry_path" >&2
  exit 2
fi

requested_repository_keys=()

for repository_key in "$@"; do
  validate_repository_key "$repository_key"

  for existing_key in ${requested_repository_keys[@]+"${requested_repository_keys[@]}"}; do
    if [[ "$existing_key" == "$repository_key" ]]; then
      echo "Duplicate repository key: $repository_key" >&2
      exit 2
    fi
  done

  registered_path="$(jq -r \
    --arg key "$repository_key" \
    '[.repositories[] | select(.key == $key)] | if length == 1 then .[0].path else "" end' \
    "$registry_path")"

  if [[ -z "$registered_path" ]]; then
    echo "Repository key is not registered: $repository_key" >&2
    exit 2
  fi

  requested_repository_keys+=("$repository_key")
done

target_run_ids=()
target_repository_keys=()

if [[ "$all_runs" == true ]]; then
  if [[ -d "$worktree_runs_root" ]]; then
    while IFS= read -r run_path; do
      run_name="$(basename -- "$run_path")"

      if [[ "$run_name" == ".gitignore" ]]; then
        continue
      fi

      if [[ -L "$run_path" || ! -d "$run_path" ]]; then
        echo "Unexpected path in the RepoChord worktree directory: $run_path" >&2
        exit 1
      fi

      validate_run_id "$run_name"

      while IFS= read -r candidate_worktree; do
        repository_key="$(basename -- "$candidate_worktree")"

        if ! repository_is_selected "$repository_key"; then
          continue
        fi

        validate_repository_key "$repository_key"
        add_target "$run_name" "$repository_key"
      done < <(find "$run_path" -mindepth 1 -maxdepth 1 -print | sort)
    done < <(find "$worktree_runs_root" -mindepth 1 -maxdepth 1 -print | sort)
  fi
else
  result_directory="$coordinate_root/.repochord/results/$run_id"

  if [[ ! -d "$result_directory" ]]; then
    echo "Result directory does not exist: $result_directory" >&2
    exit 2
  fi

  if [[ "${#requested_repository_keys[@]}" -gt 0 ]]; then
    for repository_key in "${requested_repository_keys[@]}"; do
      add_target "$run_id" "$repository_key"
    done
  else
    while IFS= read -r result_path; do
      repository_key="$(basename -- "$result_path" .json)"
      validate_repository_key "$repository_key"
      add_target "$run_id" "$repository_key"
    done < <(find "$result_directory" \
      -mindepth 1 \
      -maxdepth 1 \
      -type f \
      -name '*.json' \
      ! -name '.manifest.json' \
      -print | sort)
  fi
fi

if [[ "${#target_run_ids[@]}" -eq 0 ]]; then
  if [[ "$all_runs" == true ]]; then
    echo "No matching RepoChord worktrees were found."
    exit 0
  fi

  echo "The run has no repository results: $run_id" >&2
  exit 2
fi

private_repository_paths=()
artifact_repository_paths=()
worktree_paths=()
worktree_branches=()
worktree_presence=()

for ((target_index = 0; target_index < ${#target_run_ids[@]}; target_index++)); do
  target_run_id="${target_run_ids[$target_index]}"
  repository_key="${target_repository_keys[$target_index]}"
  result_path="$coordinate_root/.repochord/results/$target_run_id/$repository_key.json"

  if [[ -L "$result_path" || ! -f "$result_path" ]]; then
    echo "Repository result does not exist: $result_path" >&2
    exit 2
  fi

  source_repository_path="$(jq -r '.execution.source_repository_path // empty' "$result_path")"
  private_repository_path="$(jq -r '.execution.private_repository_path // empty' "$result_path")"
  worktree_path="$(jq -r '.execution.worktree_path // empty' "$result_path")"
  worktree_branch="$(jq -r '.execution.worktree_branch // empty' "$result_path")"

  if [[ -z "$source_repository_path" || -z "$worktree_path" || -z "$worktree_branch" ]]; then
    echo "Repository result has no worktree to clean: $result_path" >&2
    exit 2
  fi

  expected_worktree_path="$worktree_runs_root/$target_run_id/$repository_key"
  expected_private_repository_path="$private_repository_runs_root/$target_run_id/$repository_key.git"

  if [[ "$worktree_path" != "$expected_worktree_path" ]]; then
    echo "Repository result contains an unexpected worktree path: $worktree_path" >&2
    exit 2
  fi

  registered_path="$(jq -r \
    --arg key "$repository_key" \
    '[.repositories[] | select(.key == $key)] | if length == 1 then .[0].path else "" end' \
    "$registry_path")"

  if [[ -z "$registered_path" || "$registered_path" != "$source_repository_path" ]]; then
    echo "Repository result does not match the repository registry: $repository_key" >&2
    exit 2
  fi

  private_repository_paths+=("$private_repository_path")
  artifact_repository_path="$source_repository_path"

  if [[ -n "$private_repository_path" ]]; then
    if [[ "$private_repository_path" != "$expected_private_repository_path" || \
      -L "$private_repository_path" || \
      ! -d "$private_repository_path" || \
      "$(git -C "$private_repository_path" rev-parse --is-bare-repository 2>/dev/null || true)" != true ]]
    then
      echo "Repository result contains an invalid private repository: $private_repository_path" >&2
      exit 2
    fi

    artifact_repository_path="$private_repository_path"
  fi

  if ! git -C "$artifact_repository_path" show-ref --verify --quiet "refs/heads/$worktree_branch"; then
    echo "Repository result branch does not exist in its preserved repository: $worktree_branch" >&2
    exit 2
  fi

  artifact_repository_paths+=("$artifact_repository_path")
  worktree_paths+=("$worktree_path")
  worktree_branches+=("$worktree_branch")

  if [[ -L "$worktree_path" ]]; then
    echo "Refusing to remove a symbolic link as a RepoChord worktree: $worktree_path" >&2
    exit 1
  fi

  if [[ ! -e "$worktree_path" ]]; then
    worktree_presence+=(false)
    continue
  fi

  worktree_presence+=(true)
  worktree_root="$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null || true)"

  if [[ "$worktree_root" != "$worktree_path" ]]; then
    echo "Refusing to remove a path that is not the expected Git worktree: $worktree_path" >&2
    exit 1
  fi

  observed_branch="$(git -C "$worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

  if [[ "$observed_branch" != "$worktree_branch" ]]; then
    echo "Refusing to remove a worktree on an unexpected branch: $worktree_path" >&2
    exit 1
  fi

  if [[ "$force" != true && -n "$(git -C "$worktree_path" status --porcelain)" ]]; then
    echo "Refusing to remove a dirty RepoChord worktree without --force: $worktree_path" >&2
    exit 1
  fi
done

for ((target_index = 0; target_index < ${#target_run_ids[@]}; target_index++)); do
  worktree_path="${worktree_paths[$target_index]}"
  worktree_branch="${worktree_branches[$target_index]}"

  if [[ "${worktree_presence[$target_index]}" != true ]]; then
    echo "RepoChord worktree is already absent: $worktree_path"
    continue
  fi

  remove_arguments=(worktree remove)

  if [[ "$force" == true ]]; then
    remove_arguments+=(--force)
  fi

  remove_arguments+=("$worktree_path")
  git -C "${artifact_repository_paths[$target_index]}" "${remove_arguments[@]}"
  echo "Removed RepoChord worktree: $worktree_path"

  if [[ -n "${private_repository_paths[$target_index]}" ]]; then
    echo "Preserved private RepoChord repository: ${private_repository_paths[$target_index]}"
  else
    echo "Preserved legacy RepoChord branch: $worktree_branch"
  fi

  rmdir "$(dirname -- "$worktree_path")" 2>/dev/null || true
done
