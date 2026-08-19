#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: cleanup-worktrees.sh [--force] <run-id> [repository-key...]" >&2
}

force=false

if [[ "${1:-}" == "--force" ]]; then
  force=true
  shift
fi

if [[ "$#" -lt 1 ]]; then
  usage
  exit 2
fi

run_id="$1"
shift

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Run ID contains unsupported characters: $run_id" >&2
  exit 2
fi

for required_command in git jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
registry_path="$coordinate_root/.repomux/repositories.json"
result_directory="$coordinate_root/.repomux/results/$run_id"
expected_worktree_root="$coordinate_root/.repomux/worktrees/$run_id"

if [[ ! -d "$result_directory" ]]; then
  echo "Result directory does not exist: $result_directory" >&2
  exit 2
fi

if [[ ! -f "$registry_path" ]]; then
  echo "Repository registry does not exist: $registry_path" >&2
  exit 2
fi

repository_keys=()

if [[ "$#" -gt 0 ]]; then
  for repository_key in "$@"; do
    if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "Repository key contains unsupported characters: $repository_key" >&2
      exit 2
    fi

    for existing_key in ${repository_keys[@]+"${repository_keys[@]}"}; do
      if [[ "$existing_key" == "$repository_key" ]]; then
        echo "Duplicate repository key: $repository_key" >&2
        exit 2
      fi
    done

    repository_keys+=("$repository_key")
  done
else
  while IFS= read -r result_path; do
    repository_keys+=("$(basename -- "$result_path" .json)")
  done < <(find "$result_directory" \
    -mindepth 1 \
    -maxdepth 1 \
    -type f \
    -name '*.json' \
    ! -name '.manifest.json' \
    -print | sort)
fi

if [[ "${#repository_keys[@]}" -eq 0 ]]; then
  echo "The run has no repository results: $run_id" >&2
  exit 2
fi

for repository_key in "${repository_keys[@]}"; do
  result_path="$result_directory/$repository_key.json"

  if [[ ! -f "$result_path" ]]; then
    echo "Repository result does not exist: $result_path" >&2
    exit 2
  fi

  source_repository_path="$(jq -r '.execution.source_repository_path // empty' "$result_path")"
  worktree_path="$(jq -r '.execution.worktree_path // empty' "$result_path")"
  worktree_branch="$(jq -r '.execution.worktree_branch // empty' "$result_path")"

  if [[ -z "$source_repository_path" || -z "$worktree_path" || -z "$worktree_branch" ]]; then
    echo "Repository result has no worktree to clean: $result_path" >&2
    exit 2
  fi

  expected_worktree_path="$expected_worktree_root/$repository_key"

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

  if [[ ! -e "$worktree_path" ]]; then
    echo "RepoMux worktree is already absent: $worktree_path"
    continue
  fi

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

  remove_arguments=(worktree remove)

  if [[ "$force" == true ]]; then
    remove_arguments+=(--force)
  fi

  remove_arguments+=("$worktree_path")
  git -C "$source_repository_path" "${remove_arguments[@]}"
  echo "Removed RepoMux worktree: $worktree_path"
  echo "Preserved RepoMux branch: $worktree_branch"
done

if [[ -d "$expected_worktree_root" ]]; then
  rmdir "$expected_worktree_root" 2>/dev/null || true
fi
