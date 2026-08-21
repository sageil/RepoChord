#!/usr/bin/env bash

# Generated from src/skill-scripts by scripts/build-skill-scripts.sh.
# Do not edit this script in the payload directly.

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

export GIT_OPTIONAL_LOCKS=0

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -n "${REPOCHORD_BROKER_DIRECTORY:-}" && "${REPOCHORD_BROKER_EXECUTION:-false}" != true ]]; then
  exec bash "$script_directory/request-repository-agent-run.sh" \
    "$REPOCHORD_BROKER_DIRECTORY" \
    "$@"
fi

usage() {
  echo "Usage: run-repository-agents.sh [--model <model>] [--reasoning-effort <effort>] [--profile <profile>] [--max-parallel <count>] [--max-attempts <count>] [--allow-dirty-source] [--resume <run-id>] [--retry-blocked <repository-key>]... [<run-id>] <assignments-file>" >&2
}

model=""
model_explicit=false
reasoning_effort=""
reasoning_effort_explicit=false
profile=""
max_parallel=""
max_parallel_explicit=false
max_attempts=""
max_attempts_explicit=false
allow_dirty_source="${REPOCHORD_ALLOW_DIRTY_SOURCE:-false}"
resume=false
run_id=""
retry_blocked_keys=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --model)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      model="$2"
      model_explicit=true
      shift 2
      ;;
    --reasoning-effort)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      reasoning_effort="$2"
      reasoning_effort_explicit=true
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
    --max-parallel)
      if [[ "$#" -lt 2 ]]; then
        usage
        exit 2
      fi

      max_parallel="$2"
      max_parallel_explicit=true
      shift 2
      ;;
    --max-attempts)
      if [[ "$#" -lt 2 ]]; then
        usage
        exit 2
      fi

      max_attempts="$2"
      max_attempts_explicit=true
      shift 2
      ;;
    --allow-dirty-source)
      allow_dirty_source=true
      shift
      ;;
    --resume)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      resume=true
      run_id="$2"
      shift 2
      ;;
    --retry-blocked)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      retry_blocked_keys+=("$2")
      shift 2
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

if [[ "$resume" == true && "$#" -eq 1 ]]; then
  assignments_file="$1"
elif [[ "$resume" == true ]]; then
  usage
  exit 2
elif [[ "$#" -eq 1 ]]; then
  assignments_file="$1"
elif [[ "$#" -eq 2 ]]; then
  run_id="$1"
  assignments_file="$2"
else
  usage
  exit 2
fi

if [[ "${#retry_blocked_keys[@]}" -gt 0 && "$resume" != true ]]; then
  echo "--retry-blocked requires --resume." >&2
  exit 2
fi

if [[ -n "$run_id" && ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Run ID contains unsupported characters: $run_id" >&2
  exit 2
fi

if [[ -n "$profile" && ! "$profile" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Profile contains unsupported characters: $profile" >&2
  exit 2
fi

case "$allow_dirty_source" in
  true|false)
    ;;
  *)
    echo "REPOCHORD_ALLOW_DIRTY_SOURCE must be true or false: $allow_dirty_source" >&2
    exit 2
    ;;
esac

for required_command in codex cp git jq mktemp mv sed; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

if [[ ! -f "$assignments_file" ]]; then
  echo "Assignments file does not exist: $assignments_file" >&2
  exit 2
fi

skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
repository_agent_script="$script_directory/run-repository-agent.sh"
report_script="$script_directory/report-run.sh"
task_progress_script="$script_directory/task-progress.sh"
registry_path="${REPOCHORD_REGISTRY_PATH:-$coordinate_root/.repochord/repositories.json}"
results_root="$coordinate_root/.repochord/results"
result_directory=""
run_id_reservation=""
run_manifest_stage=""

if [[ -n "${REPOCHORD_CONFIG_HOME:-}" ]]; then
  repochord_config_directory="$REPOCHORD_CONFIG_HOME"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  repochord_config_directory="$XDG_CONFIG_HOME/repochord"
elif [[ -n "${HOME:-}" ]]; then
  repochord_config_directory="$HOME/.config/repochord"
else
  repochord_config_directory=""
fi

projects_registry=""

if [[ ! -f "$task_progress_script" ]]; then
  echo "Task progress helper does not exist: $task_progress_script" >&2
  exit 2
fi

# shellcheck source-path=SCRIPTDIR
# shellcheck source=task-progress.sh
source "$task_progress_script"

if [[ -n "$repochord_config_directory" ]]; then
  projects_registry="$repochord_config_directory/projects.json"
fi

if [[ "$reasoning_effort_explicit" != true ]]; then
  if [[ -n "${REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT:-}" ]]; then
    reasoning_effort="$REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT"
  else
    reasoning_effort="high"

    if [[ -n "$projects_registry" && -f "$projects_registry" ]]; then
      reasoning_effort="$(jq -er \
        --arg coordinate "$coordinate_root" \
        '
          (.defaults.repositoryAgentReasoningEffort // "high") as $default |
          [.projects[] | select(.coordinate == $coordinate)] |
          if length == 1 then (.[0].repositoryAgentReasoningEffort // $default) else $default end
        ' \
        "$projects_registry")"
    fi
  fi
fi

case "$reasoning_effort" in
  minimal|low|medium|high|xhigh)
    ;;
  *)
    echo "Unsupported repository-agent reasoning effort: $reasoning_effort" >&2
    exit 2
    ;;
esac

if [[ "$model_explicit" != true ]]; then
  if [[ -n "${REPOCHORD_MODEL:-}" ]]; then
    model="$REPOCHORD_MODEL"
  else
    model="gpt-5.6-terra"

    if [[ -n "$projects_registry" && -f "$projects_registry" ]]; then
      model="$(jq -er \
        --arg coordinate "$coordinate_root" \
        '
          (.defaults.model // "gpt-5.6-terra") as $default |
          [.projects[] | select(.coordinate == $coordinate)] |
          if length == 1 then (.[0].model // $default) else $default end
        ' \
        "$projects_registry")"
    fi
  fi
fi

if [[ -z "$model" || "$model" =~ [[:space:]] ]]; then
  echo "Model must be a nonempty value without whitespace: $model" >&2
  exit 2
fi

if [[ "$max_parallel_explicit" != true ]]; then
  if [[ -n "${REPOCHORD_MAX_PARALLEL:-}" ]]; then
    max_parallel="$REPOCHORD_MAX_PARALLEL"
  else
    max_parallel="2"

    if [[ -n "$projects_registry" && -f "$projects_registry" ]]; then
      max_parallel="$(jq -er \
        --arg coordinate "$coordinate_root" \
        '
          (.defaults.maxParallel // 2) as $default |
          [.projects[] | select(.coordinate == $coordinate)] |
          if length == 1 then (.[0].maxParallel // $default) else $default end
        ' \
        "$projects_registry")"
    fi
  fi
fi

if [[ ! "$max_parallel" =~ ^[1-9][0-9]*$ || "${#max_parallel}" -gt 9 ]]; then
  echo "Maximum parallel repository agents must be a positive integer no greater than 999999999: $max_parallel" >&2
  exit 2
fi

if [[ "$max_attempts_explicit" != true ]]; then
  if [[ -n "${REPOCHORD_MAX_ATTEMPTS:-}" ]]; then
    max_attempts="$REPOCHORD_MAX_ATTEMPTS"
  else
    max_attempts="3"

    if [[ -n "$projects_registry" && -f "$projects_registry" ]]; then
      configured_max_attempts="$(jq -r \
        --arg coordinate "$coordinate_root" \
        '
          (.defaults.maxAttempts // 3) as $default |
          [.projects[] | select(.coordinate == $coordinate)] |
          if length == 1 then (.[0].maxAttempts // $default) else 3 end
        ' \
        "$projects_registry")"
      max_attempts="$configured_max_attempts"
    fi
  fi
fi

if [[ ! "$max_attempts" =~ ^[1-9][0-9]*$ || "${#max_attempts}" -gt 9 ]]; then
  echo "Maximum attempts must be a positive integer no greater than 999999999: $max_attempts" >&2
  exit 2
fi

# shellcheck disable=SC2329
