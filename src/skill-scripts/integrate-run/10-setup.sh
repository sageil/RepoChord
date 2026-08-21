#!/usr/bin/env bash

# Generated from src/skill-scripts by scripts/build-skill-scripts.sh.
# Do not edit this script in the payload directly.

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  echo "Usage: integrate-run.sh [--dry-run] [--show-diffs] <run-id>" >&2
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

validate_safe_text() {
  local value="$1"
  local label="$2"

  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" == *$'\t'* ]]; then
    fail "$label contains an unsupported tab or newline: $value" 2
  fi
}

operation_in_progress() {
  local repository_path="$1"
  local operation_path
  local operation_name

  for operation_name in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-apply rebase-merge; do
    operation_path="$(git -C "$repository_path" rev-parse --git-path "$operation_name")"

    if [[ -e "$operation_path" ]]; then
      return 0
    fi
  done

  return 1
}

find_branch_worktree() {
  local repository_path="$1"
  local branch_name="$2"
  local current_worktree=""
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "worktree "*)
        current_worktree="${line#worktree }"
        ;;
      "branch refs/heads/$branch_name")
        printf '%s\n' "$current_worktree"
        return 0
        ;;
      "")
        current_worktree=""
        ;;
    esac
  done < <(git -C "$repository_path" worktree list --porcelain)

  return 1
}

validate_checkout_collisions() {
  local checkout_path="$1"
  local artifact_repository_path="$2"
  local current_commit="$3"
  local final_commit="$4"
  local changed_path

  while IFS= read -r -d '' changed_path; do
    if [[ -e "$checkout_path/$changed_path" || -L "$checkout_path/$changed_path" ]] &&
      ! git -C "$checkout_path" ls-files --error-unmatch -- "$changed_path" >/dev/null 2>&1
    then
      fail "An untracked or ignored path would be overwritten during integration: $checkout_path/$changed_path"
    fi
  done < <(git -C "$artifact_repository_path" diff \
    --no-ext-diff \
    --no-textconv \
    --name-only \
    -z \
    "$current_commit..$final_commit")
}

dry_run=false
show_diffs=false
run_id=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --show-diffs)
      show_diffs=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "Unknown integration argument: $1" 2
      ;;
    *)
      if [[ -n "$run_id" ]]; then
        usage
        exit 2
      fi

      run_id="$1"
      shift
      ;;
  esac
done

if [[ -z "$run_id" || \
  ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || \
  "$run_id" == "." || \
  "$run_id" == ".." ]]
then
  fail "Integration requires a valid run ID." 2
fi

for required_command in git jq mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    fail "Required command is not installed: $required_command" 2
  fi
done

export GIT_OPTIONAL_LOCKS=0

empty_hooks_directory=""
