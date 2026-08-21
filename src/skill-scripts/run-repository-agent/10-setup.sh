#!/usr/bin/env bash

# Generated from src/skill-scripts by scripts/build-skill-scripts.sh.
# Do not edit this script in the payload directly.

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

export GIT_OPTIONAL_LOCKS=0

usage() {
  echo "Usage: run-repository-agent.sh [--model <model>] [--reasoning-effort <effort>] [--profile <profile>] [--max-attempts <count>] [--resume] [--allow-blocked-resume] <repository-key> <repository-path> <run-id> <task-file>" >&2
}

model="gpt-5.6-terra"
reasoning_effort="${REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT:-high}"
profile=""
max_attempts="${REPOCHORD_MAX_ATTEMPTS:-3}"
resume=false
allow_blocked_resume=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --model)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      model="$2"
      shift 2
      ;;
    --reasoning-effort)
      if [[ "$#" -lt 2 ]]; then
        usage
        exit 2
      fi

      reasoning_effort="$2"
      shift 2
      ;;
    --profile)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      profile="$2"
      shift 2
      ;;
    --max-attempts)
      if [[ "$#" -lt 2 ]]; then
        usage
        exit 2
      fi

      max_attempts="$2"
      shift 2
      ;;
    --resume)
      resume=true
      shift
      ;;
    --allow-blocked-resume)
      allow_blocked_resume=true
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$#" -ne 4 ]]; then
  usage
  exit 2
fi

repository_key="$1"
source_repository_path="$2"
run_id="$3"
task_file="$4"

if [[ "$allow_blocked_resume" == true && "$resume" != true ]]; then
  echo "--allow-blocked-resume requires --resume." >&2
  exit 2
fi

if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Repository key contains unsupported characters: $repository_key" >&2
  exit 2
fi

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Run ID contains unsupported characters: $run_id" >&2
  exit 2
fi

if [[ -n "$profile" && ! "$profile" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Profile contains unsupported characters: $profile" >&2
  exit 2
fi

case "$reasoning_effort" in
  minimal|low|medium|high|xhigh)
    ;;
  *)
    echo "Unsupported reasoning effort: $reasoning_effort" >&2
    exit 2
    ;;
esac

if [[ ! "$max_attempts" =~ ^[1-9][0-9]*$ || "${#max_attempts}" -gt 9 ]]; then
  echo "Maximum attempts must be a positive integer no greater than 999999999: $max_attempts" >&2
  exit 2
fi

for required_command in codex cp git jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"

response_schema_path="$skill_directory/assets/repository-agent-response.schema.json"
result_schema_path="$skill_directory/assets/repository-agent-result.schema.json"
git_guard_source="$script_directory/git-guard.sh"
registry_path="${REPOCHORD_REGISTRY_PATH:-$coordinate_root/.repochord/repositories.json}"
result_directory="$coordinate_root/.repochord/results/$run_id"
result_path="$result_directory/$repository_key.json"
private_repository_path="$coordinate_root/.repochord/repositories/$run_id/$repository_key.git"
worktree_path="$coordinate_root/.repochord/worktrees/$run_id/$repository_key"
worktree_branch="repochord/$run_id/$repository_key"
guard_directory="$result_directory/.git-guard-$repository_key"
empty_hooks_directory="$guard_directory/empty-hooks"

if ! git check-ref-format "refs/heads/$worktree_branch" >/dev/null 2>&1; then
  echo "Run ID and repository key produce an invalid RepoChord branch: $worktree_branch" >&2
  exit 2
fi

mkdir -p "$result_directory"
mkdir -p "$empty_hooks_directory"

temporary_response="$(mktemp "$result_directory/.${repository_key}.response.XXXXXX")"
last_valid_response="$(mktemp "$result_directory/.${repository_key}.last-response.XXXXXX")"
temporary_result="$(mktemp "$result_directory/.${repository_key}.result.XXXXXX")"
scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/repochord-${run_id}-${repository_key}.XXXXXX")"
codex_sqlite_directory="$scratch_directory/codex-sqlite"
mkdir -p "$codex_sqlite_directory"

base_commit=""
base_branch=""
observed_head=""
observed_branch=""
head_changed=false
worktree_clean=false
repository_state_available=false
attempt_count=0
last_response_valid=false
previous_attempt_context="No previous attempt."
cumulative_usage="null"
created_logs=()
created_events=()

# shellcheck disable=SC2329
