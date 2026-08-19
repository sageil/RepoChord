#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: run-repository-agents.sh [--model <model>] [--reasoning-effort <effort>] [--profile <profile>] [--agent-output <progress|quiet>] [--max-parallel <count>] [--max-attempts <count>] [--allow-dirty-source] [--resume <run-id>] [--retry-blocked <repository-key>]... [<run-id>] <assignments-file>" >&2
}

model=""
model_explicit=false
reasoning_effort=""
reasoning_effort_explicit=false
profile=""
agent_output=""
agent_output_explicit=false
max_parallel=""
max_parallel_explicit=false
max_attempts=""
max_attempts_explicit=false
allow_dirty_source="${REPOMUX_ALLOW_DIRTY_SOURCE:-false}"
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
    --agent-output)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      agent_output="$2"
      agent_output_explicit=true
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
    echo "REPOMUX_ALLOW_DIRTY_SOURCE must be true or false: $allow_dirty_source" >&2
    exit 2
    ;;
esac

for required_command in codex git jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

if [[ ! -f "$assignments_file" ]]; then
  echo "Assignments file does not exist: $assignments_file" >&2
  exit 2
fi

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
repository_agent_script="$script_directory/run-repository-agent.sh"
report_script="$script_directory/report-run.sh"
registry_path="$coordinate_root/.repomux/repositories.json"
results_root="$coordinate_root/.repomux/results"
result_directory=""
run_id_reservation=""
run_manifest_stage=""

if [[ -n "${REPOMUX_CONFIG_HOME:-}" ]]; then
  repomux_config_directory="$REPOMUX_CONFIG_HOME"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  repomux_config_directory="$XDG_CONFIG_HOME/repomux"
elif [[ -n "${HOME:-}" ]]; then
  repomux_config_directory="$HOME/.config/repomux"
else
  repomux_config_directory=""
fi

projects_registry=""

if [[ -n "$repomux_config_directory" ]]; then
  projects_registry="$repomux_config_directory/projects.json"
fi

if [[ "$reasoning_effort_explicit" != true ]]; then
  if [[ -n "${REPOMUX_REPOSITORY_AGENT_REASONING_EFFORT:-}" ]]; then
    reasoning_effort="$REPOMUX_REPOSITORY_AGENT_REASONING_EFFORT"
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
  if [[ -n "${REPOMUX_MODEL:-}" ]]; then
    model="$REPOMUX_MODEL"
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

if [[ "$agent_output_explicit" != true ]]; then
  if [[ -n "${REPOMUX_AGENT_OUTPUT:-}" ]]; then
    agent_output="$REPOMUX_AGENT_OUTPUT"
  else
    agent_output="progress"

    if [[ -n "$projects_registry" && -f "$projects_registry" ]]; then
      agent_output="$(jq -er \
        --arg coordinate "$coordinate_root" \
        '
          (.defaults.agentOutput // "progress") as $default |
          [.projects[] | select(.coordinate == $coordinate)] |
          if length == 1 then (.[0].agentOutput // $default) else $default end
        ' \
        "$projects_registry")"
    fi
  fi
fi

case "$agent_output" in
  progress|quiet)
    ;;
  *)
    echo "Repository-agent output must be progress or quiet: $agent_output" >&2
    exit 2
    ;;
esac

if [[ "$max_parallel_explicit" != true ]]; then
  if [[ -n "${REPOMUX_MAX_PARALLEL:-}" ]]; then
    max_parallel="$REPOMUX_MAX_PARALLEL"
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
  if [[ -n "${REPOMUX_MAX_ATTEMPTS:-}" ]]; then
    max_attempts="$REPOMUX_MAX_ATTEMPTS"
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
cleanup() {
  if [[ -n "$run_id_reservation" ]]; then
    rm -rf -- "$run_id_reservation"
  fi

  if [[ -n "$run_manifest_stage" ]]; then
    rm -f -- "$run_manifest_stage"
  fi
}

trap cleanup EXIT

if [[ ! -d "$results_root" ]]; then
  echo "Result root does not exist: $results_root" >&2
  exit 2
fi

if [[ ! -f "$registry_path" ]]; then
  echo "Repository registry does not exist: $registry_path" >&2
  exit 2
fi

if ! jq -e '
  .version == 1 and
  (.repositories | type == "array") and
  ([.repositories[].key] | length == (unique | length)) and
  ([.repositories[].path] | length == (unique | length)) and
  all(.repositories[];
    (.key | type == "string") and
    (.key | test("^[A-Za-z0-9._-]+$")) and
    (.path | type == "string") and
    (.path | startswith("/"))
  )
' "$registry_path" >/dev/null; then
  echo "Repository registry is invalid: $registry_path" >&2
  exit 2
fi

while IFS= read -r registered_repository_path; do
  if [[ ! -d "$registered_repository_path" ]]; then
    echo "Registered repository does not exist: $registered_repository_path" >&2
    exit 2
  fi

  canonical_registered_path="$(cd -- "$registered_repository_path" && pwd -P)"

  if [[ "$registered_repository_path" != "$canonical_registered_path" ]]; then
    echo "Registered repository path is not canonical: $registered_repository_path" >&2
    exit 2
  fi
done < <(jq -r '.repositories[].path' "$registry_path")

if [[ "$resume" == true ]]; then
  result_directory="$results_root/$run_id"

  if [[ ! -d "$result_directory" ]]; then
    echo "Result directory does not exist for resume: $result_directory" >&2
    exit 2
  fi
elif [[ -n "$run_id" ]]; then
  result_directory="$results_root/$run_id"

  if [[ -e "$result_directory" ]]; then
    echo "Result directory already exists: $result_directory" >&2
    echo "Use a new run ID." >&2
    exit 2
  fi
fi

repository_keys=()
repository_paths=()
task_files=()

line_number=0

while IFS='|' read -r repository_key repository_path task_file extra || \
  [[ -n "${repository_key}${repository_path}${task_file}${extra}" ]]
do
  line_number=$((line_number + 1))

  if [[ -z "${repository_key}${repository_path}${task_file}${extra}" ]]; then
    continue
  fi

  if [[ "$repository_key" == \#* ]]; then
    continue
  fi

  if [[ -z "$repository_key" || -z "$repository_path" || -z "$task_file" || -n "$extra" ]]; then
    echo "Invalid assignment at line $line_number." >&2
    echo "Expected: repository-key|absolute-repository-path|absolute-task-file" >&2
    exit 2
  fi

  if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ]] ||
    ! git check-ref-format "refs/heads/repomux/validation/$repository_key" >/dev/null 2>&1
  then
    echo "Invalid repository key at line $line_number: $repository_key" >&2
    exit 2
  fi

  if [[ "$repository_path" != /* || "$task_file" != /* ]]; then
    echo "Repository and task paths must be absolute at line $line_number." >&2
    exit 2
  fi

  for existing_key in ${repository_keys[@]+"${repository_keys[@]}"}; do
    if [[ "$existing_key" == "$repository_key" ]]; then
      echo "Duplicate repository key: $repository_key" >&2
      exit 2
    fi
  done

  repository_keys+=("$repository_key")
  repository_paths+=("$repository_path")
  task_files+=("$task_file")
done < "$assignments_file"

repository_agent_count="${#repository_keys[@]}"

if [[ "$repository_agent_count" -eq 0 ]]; then
  echo "The assignments file contains no repository agents." >&2
  exit 2
fi

validated_retry_blocked_keys=()

for retry_blocked_key in ${retry_blocked_keys[@]+"${retry_blocked_keys[@]}"}; do
  if [[ ! "$retry_blocked_key" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Invalid repository key for --retry-blocked: $retry_blocked_key" >&2
    exit 2
  fi

  retry_key_found=false

  for repository_key in "${repository_keys[@]}"; do
    if [[ "$repository_key" == "$retry_blocked_key" ]]; then
      retry_key_found=true
      break
    fi
  done

  if [[ "$retry_key_found" != true ]]; then
    echo "Blocked retry key is not present in the assignments: $retry_blocked_key" >&2
    exit 2
  fi

  for existing_key in ${validated_retry_blocked_keys[@]+"${validated_retry_blocked_keys[@]}"}; do
    if [[ "$existing_key" == "$retry_blocked_key" ]]; then
      echo "Duplicate --retry-blocked repository key: $retry_blocked_key" >&2
      exit 2
    fi
  done

  validated_retry_blocked_keys+=("$retry_blocked_key")
done

canonical_repository_paths=()

for ((index = 0; index < repository_agent_count; index++)); do
  repository_key="${repository_keys[$index]}"
  repository_path="${repository_paths[$index]}"
  task_file="${task_files[$index]}"

  if [[ ! -d "$repository_path" ]]; then
    echo "Repository directory does not exist: $repository_path" >&2
    exit 2
  fi

  if [[ ! -f "$task_file" ]]; then
    echo "Task file does not exist: $task_file" >&2
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

  for existing_path in ${canonical_repository_paths[@]+"${canonical_repository_paths[@]}"}; do
    if [[ "$existing_path" == "$canonical_repository_path" ]]; then
      echo "Duplicate canonical repository path: $canonical_repository_path" >&2
      exit 2
    fi
  done

  canonical_repository_paths+=("$canonical_repository_path")

  registered_path="$(jq -r \
    --arg key "$repository_key" \
    '[.repositories[] | select(.key == $key)] | if length == 1 then .[0].path else "" end' \
    "$registry_path")"

  if [[ -z "$registered_path" || ! -d "$registered_path" ]]; then
    echo "Repository key is not uniquely registered: $repository_key" >&2
    exit 2
  fi

  registered_path="$(cd -- "$registered_path" && pwd -P)"

  if [[ "$registered_path" != "$canonical_repository_path" ]]; then
    echo "Assignment path does not match the registry for: $repository_key" >&2
    exit 2
  fi

  if ! git -C "$canonical_repository_path" symbolic-ref --quiet --short HEAD >/dev/null; then
    echo "Repository has a detached HEAD: $repository_path" >&2
    exit 2
  fi

  if ! git -C "$canonical_repository_path" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Repository has no initial commit: $repository_path" >&2
    exit 2
  fi

  source_repository_status="$(git -c core.fsmonitor=false \
    -C "$canonical_repository_path" status --porcelain=v1 --untracked-files=all)"

  if [[ -n "$source_repository_status" ]]; then
    if [[ "$allow_dirty_source" == true ]]; then
      echo "Warning: uncommitted changes are excluded from this run: $repository_path" >&2
    else
      echo "Repository worktree is not clean: $repository_path" >&2
      exit 2
    fi
  fi

  if ! git -C "$canonical_repository_path" config user.name >/dev/null; then
    echo "Git user.name is not configured for: $repository_path" >&2
    exit 2
  fi

  if ! git -C "$canonical_repository_path" config user.email >/dev/null; then
    echo "Git user.email is not configured for: $repository_path" >&2
    exit 2
  fi

  repository_paths[index]="$canonical_repository_path"
  task_files[index]="$(cd -- "$(dirname -- "$task_file")" && pwd -P)/$(basename -- "$task_file")"
done

assignments_file="$(cd -- "$(dirname -- "$assignments_file")" && pwd -P)/$(basename -- "$assignments_file")"
feature_id=""
tasks_root="$coordinate_root/tasks"

for task_file in "${task_files[@]}"; do
  feature_task_directory="$(dirname -- "$task_file")"
  feature_tasks_parent="$(dirname -- "$feature_task_directory")"
  candidate_feature_id="$(basename -- "$feature_task_directory")"

  if [[ "$feature_tasks_parent" != "$tasks_root" ]]; then
    echo "Repository task files must be under: $tasks_root" >&2
    exit 2
  fi

  if [[ ! "$candidate_feature_id" =~ ^[A-Za-z0-9._-]+$ || \
    "$candidate_feature_id" == "." || \
    "$candidate_feature_id" == ".." ]]
  then
    echo "Cannot derive a valid feature ID from task file: $task_file" >&2
    exit 2
  fi

  if [[ -z "$feature_id" ]]; then
    feature_id="$candidate_feature_id"
  elif [[ "$feature_id" != "$candidate_feature_id" ]]; then
    echo "All repository tasks in one run must belong to one feature." >&2
    exit 2
  fi
done

request_file="$coordinate_root/requests/$feature_id.md"

for run_document in "$request_file" "$assignments_file" "${task_files[@]}"; do
  if [[ -L "$run_document" || ! -f "$run_document" ]]; then
    echo "Run document does not exist or is not a regular file: $run_document" >&2
    exit 2
  fi
done

request_hash="$(git -C "$coordinate_root" hash-object -- "$request_file")"
assignments_hash="$(git -C "$coordinate_root" hash-object -- "$assignments_file")"
task_hashes=()

for task_file in "${task_files[@]}"; do
  task_hashes+=("$(git -C "$coordinate_root" hash-object -- "$task_file")")
done

if [[ -z "$run_id" ]]; then
  while true; do
    run_id_reservation="$(mktemp -d "$results_root/.run-id.XXXXXX")"
    run_id_suffix="$(basename -- "$run_id_reservation")"
    run_id_suffix="${run_id_suffix##*.}"
    run_id="$feature_id-run-$run_id_suffix"
    result_directory="$results_root/$run_id"

    if [[ ! -e "$result_directory" ]]; then
      break
    fi

    rm -rf -- "$run_id_reservation"
    run_id_reservation=""
  done
fi

for repository_key in "${repository_keys[@]}"; do
  worktree_branch="repomux/$run_id/$repository_key"

  if ! git check-ref-format "refs/heads/$worktree_branch" >/dev/null 2>&1; then
    echo "Run ID and repository key produce an invalid RepoMux branch: $worktree_branch" >&2
    exit 2
  fi
done

if [[ "$resume" != true ]]; then
  mkdir "$result_directory"
fi

if [[ -n "$run_id_reservation" ]]; then
  rm -rf -- "$run_id_reservation"
  run_id_reservation=""
fi

run_manifest_path="$result_directory/.manifest.json"

if [[ "$resume" == true ]]; then
  if [[ -L "$run_manifest_path" || ! -f "$run_manifest_path" ]]; then
    echo "Run manifest does not exist or is not a regular file: $run_manifest_path" >&2
    exit 2
  fi

  if ! jq -e \
    --arg run_id "$run_id" \
    --arg feature_id "$feature_id" \
    --arg assignments_file "$assignments_file" \
    --arg assignments_hash "$assignments_hash" \
    --arg request_file "$request_file" \
    --arg request_hash "$request_hash" \
    --argjson repository_count "$repository_agent_count" \
    '
      .version == 1 and
      .run_id == $run_id and
      .feature_id == $feature_id and
      .assignments_file == $assignments_file and
      .assignments_hash == $assignments_hash and
      .request_file == $request_file and
      .request_hash == $request_hash and
      (.repositories | type == "array") and
      (.repositories | length == $repository_count)
    ' \
    "$run_manifest_path" \
    >/dev/null
  then
    echo "Run manifest does not match this resume request: $run_manifest_path" >&2
    exit 2
  fi

  for ((index = 0; index < repository_agent_count; index++)); do
    if ! jq -e \
      --argjson index "$index" \
      --arg key "${repository_keys[$index]}" \
      --arg path "${repository_paths[$index]}" \
      --arg task_file "${task_files[$index]}" \
      --arg task_hash "${task_hashes[$index]}" \
      '
        .repositories[$index] == {
          key: $key,
          path: $path,
          task_file: $task_file,
          task_hash: $task_hash
        }
      ' \
      "$run_manifest_path" \
      >/dev/null
    then
      echo "Run manifest repository assignment changed at index: $index" >&2
      exit 2
    fi
  done
else
  run_manifest_stage="$(mktemp "$result_directory/.manifest.XXXXXX")"

  for ((index = 0; index < repository_agent_count; index++)); do
    jq -n \
      --arg key "${repository_keys[$index]}" \
      --arg path "${repository_paths[$index]}" \
      --arg task_file "${task_files[$index]}" \
      --arg task_hash "${task_hashes[$index]}" \
      '{key: $key, path: $path, task_file: $task_file, task_hash: $task_hash}'
  done | jq -s \
    --arg run_id "$run_id" \
    --arg feature_id "$feature_id" \
    --arg assignments_file "$assignments_file" \
    --arg assignments_hash "$assignments_hash" \
    --arg request_file "$request_file" \
    --arg request_hash "$request_hash" \
    '{
      version: 1,
      run_id: $run_id,
      feature_id: $feature_id,
      assignments_file: $assignments_file,
      assignments_hash: $assignments_hash,
      request_file: $request_file,
      request_hash: $request_hash,
      repositories: .
    }' \
    > "$run_manifest_stage"

  mv -- "$run_manifest_stage" "$run_manifest_path"
  run_manifest_stage=""
fi

repository_agent_arguments=(
  --model "$model"
  --reasoning-effort "$reasoning_effort"
  --agent-output "$agent_output"
  --max-attempts "$max_attempts"
)

if [[ -n "$profile" ]]; then
  repository_agent_arguments+=(--profile "$profile")
fi

overall_status=0
launch_indexes=()
resume_repository=()
allow_blocked_resume=()

validate_completed_result() {
  local index="$1"
  local repository_key="${repository_keys[$index]}"
  local repository_path="${repository_paths[$index]}"
  local result_path="$result_directory/$repository_key.json"
  local expected_worktree_path="$coordinate_root/.repomux/worktrees/$run_id/$repository_key"
  local expected_worktree_branch="repomux/$run_id/$repository_key"
  local recorded_commit
  local recorded_branch_commit
  local recorded_worktree_path

  if ! jq -e \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    --arg source_repository_path "$repository_path" \
    --arg worktree_path "$expected_worktree_path" \
    --arg worktree_branch "$expected_worktree_branch" \
    '
      .run_id == $run_id and
      .repository == $repository and
      .status == "completed" and
      (.commit | type == "string") and
      (.commit | length > 0) and
      .execution.source_repository_path == $source_repository_path and
      (.execution.base_branch | type == "string") and
      (.execution.base_commit | type == "string") and
      .execution.worktree_path == $worktree_path and
      .execution.worktree_branch == $worktree_branch and
      .execution.observed_head == .commit and
      .execution.observed_branch == $worktree_branch and
      .execution.head_changed == true and
      .execution.worktree_clean == true
    ' \
    "$result_path" \
    >/dev/null
  then
    echo "Completed repository result is invalid: $result_path" >&2
    return 1
  fi

  recorded_commit="$(jq -r '.commit' "$result_path")"
  recorded_worktree_path="$(jq -r '.execution.worktree_path' "$result_path")"

  if ! recorded_branch_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$expected_worktree_branch" 2>/dev/null)"; then
    echo "Completed RepoMux branch does not exist: $expected_worktree_branch" >&2
    return 1
  fi

  if [[ "$recorded_branch_commit" != "$recorded_commit" ]]; then
    echo "Completed RepoMux branch no longer points to its recorded commit: $expected_worktree_branch" >&2
    return 1
  fi

  if [[ -e "$recorded_worktree_path" ]]; then
    if [[ "$(git -C "$recorded_worktree_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$recorded_worktree_path" || \
      "$(git -C "$recorded_worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$expected_worktree_branch" || \
      "$(git -C "$recorded_worktree_path" rev-parse --verify HEAD 2>/dev/null || true)" != "$recorded_commit" || \
      -n "$(git -C "$recorded_worktree_path" status --porcelain 2>/dev/null || true)" ]]
    then
      echo "Completed RepoMux worktree no longer matches its result: $recorded_worktree_path" >&2
      return 1
    fi
  fi
}

for ((index = 0; index < repository_agent_count; index++)); do
  repository_key="${repository_keys[$index]}"
  result_path="$result_directory/$repository_key.json"
  resume_repository[index]=false
  allow_blocked_resume[index]=false

  if [[ "$resume" != true || ! -f "$result_path" ]]; then
    launch_indexes+=("$index")
    continue
  fi

  existing_status="$(jq -r '.status // empty' "$result_path")"

  case "$existing_status" in
    completed)
      if ! validate_completed_result "$index"; then
        exit 1
      fi
      ;;
    failed)
      launch_indexes+=("$index")
      resume_repository[index]=true
      ;;
    blocked)
      retry_blocked=false

      for retry_blocked_key in ${validated_retry_blocked_keys[@]+"${validated_retry_blocked_keys[@]}"}; do
        if [[ "$retry_blocked_key" == "$repository_key" ]]; then
          retry_blocked=true
          break
        fi
      done

      if [[ "$retry_blocked" == true ]]; then
        launch_indexes+=("$index")
        resume_repository[index]=true
        allow_blocked_resume[index]=true
      else
        overall_status=1
      fi
      ;;
    *)
      echo "Existing repository result has an invalid status: $result_path" >&2
      exit 1
      ;;
  esac
done

for retry_blocked_key in ${validated_retry_blocked_keys[@]+"${validated_retry_blocked_keys[@]}"}; do
  retry_result_path="$result_directory/$retry_blocked_key.json"

  if [[ ! -f "$retry_result_path" || "$(jq -r '.status // empty' "$retry_result_path")" != "blocked" ]]; then
    echo "--retry-blocked requires an existing blocked result: $retry_blocked_key" >&2
    exit 2
  fi
done

next_index=0
launch_count="${#launch_indexes[@]}"

while [[ "$next_index" -lt "$launch_count" ]]; do
  batch_end=$((next_index + max_parallel))

  if [[ "$batch_end" -gt "$launch_count" ]]; then
    batch_end="$launch_count"
  fi

  pids=()
  launcher_logs=()

  for ((launch_index = next_index; launch_index < batch_end; launch_index++)); do
    index="${launch_indexes[$launch_index]}"
    repository_key="${repository_keys[$index]}"
    launcher_log="$result_directory/$repository_key.launcher.log"
    current_repository_agent_arguments=("${repository_agent_arguments[@]}")

    if [[ "${resume_repository[$index]}" == true ]]; then
      current_repository_agent_arguments+=(--resume)
    fi

    if [[ "${allow_blocked_resume[$index]}" == true ]]; then
      current_repository_agent_arguments+=(--allow-blocked-resume)
    fi

    bash "$repository_agent_script" \
      "${current_repository_agent_arguments[@]}" \
      "$repository_key" \
      "${repository_paths[$index]}" \
      "$run_id" \
      "${task_files[$index]}" \
      2> "$launcher_log" &

    pids+=("$!")
    launcher_logs+=("$launcher_log")
  done

  for ((batch_index = 0; batch_index < ${#pids[@]}; batch_index++)); do
    if wait "${pids[$batch_index]}"; then
      rm -f -- "${launcher_logs[$batch_index]}"
    else
      overall_status=1
    fi
  done

  next_index="$batch_end"
done

for ((index = 0; index < repository_agent_count; index++)); do
  result_path="$result_directory/${repository_keys[$index]}.json"

  if [[ -f "$result_path" ]]; then
    printf '%s\n' "$result_path"
  else
    echo "Repository agent produced no result: ${repository_keys[$index]}" >&2
    overall_status=1
  fi
done

echo
report_status=0
bash "$report_script" "$run_id" || report_status="$?"

if [[ "$overall_status" -eq 0 && "$report_status" -ne 0 ]]; then
  overall_status="$report_status"
fi

exit "$overall_status"
