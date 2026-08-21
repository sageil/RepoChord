#!/usr/bin/env bash

set -euo pipefail

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
cleanup() {
  rm -f -- "$temporary_response" "$last_valid_response" "$temporary_result"
  rm -rf -- "$guard_directory"
  rm -rf -- "$scratch_directory"
}

trap cleanup EXIT

capture_repository_state() {
  observed_head=""
  observed_branch=""
  head_changed=false
  worktree_clean=false
  repository_state_available=false

  if [[ ! -d "$worktree_path" ]]; then
    return
  fi

  if ! git -C "$worktree_path" rev-parse --show-toplevel >/dev/null 2>&1; then
    return
  fi

  repository_state_available=true

  if observed_head_value="$(git -C "$worktree_path" rev-parse --verify HEAD 2>/dev/null)"; then
    observed_head="$observed_head_value"
  fi

  if observed_branch_value="$(git -C "$worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    observed_branch="$observed_branch_value"
  fi

  if [[ -z "$(git -C "$worktree_path" status --porcelain 2>/dev/null || true)" ]]; then
    worktree_clean=true
  fi

  if [[ -n "$base_commit" && "$observed_head" != "$base_commit" ]]; then
    head_changed=true
  fi
}

extract_attempt_usage() {
  local events_path="$1"
  local attempt_usage="null"

  if [[ -s "$events_path" ]]; then
    if ! attempt_usage="$(jq -cs '
      [
        .[]
        | select(.type == "turn.completed")
        | .usage
      ]
      | last // null
      | if . == null then
          null
        else
          {
            input_tokens: (.input_tokens // 0),
            cached_input_tokens: (.cached_input_tokens // 0),
            output_tokens: (.output_tokens // 0),
            reasoning_output_tokens: (.reasoning_output_tokens // 0)
          }
        end
    ' "$events_path" 2>/dev/null)"; then
      attempt_usage="null"
    fi
  fi

  if [[ "$attempt_usage" != "null" ]]; then
    cumulative_usage="$(jq -n \
      --argjson current "$cumulative_usage" \
      --argjson addition "$attempt_usage" \
      '
        ($current // {
          input_tokens: 0,
          cached_input_tokens: 0,
          output_tokens: 0,
          reasoning_output_tokens: 0
        }) as $base |
        {
          input_tokens: ($base.input_tokens + $addition.input_tokens),
          cached_input_tokens: ($base.cached_input_tokens + $addition.cached_input_tokens),
          output_tokens: ($base.output_tokens + $addition.output_tokens),
          reasoning_output_tokens: ($base.reasoning_output_tokens + $addition.reasoning_output_tokens)
        }
      ')"
  fi

  attempt_usage_json="$attempt_usage"
}

validate_repository_agent_response() {
  jq -e '
    type == "object" and
    (keys | sort == ["blockers", "commit", "commit_message", "repository", "risks", "run_id", "status", "summary", "tests"]) and
    (.run_id | type == "string") and
    (.repository | type == "string") and
    (.status == "completed" or .status == "blocked" or .status == "failed") and
    (.summary | type == "string") and
    (.commit == null) and
    (.commit_message == null or (.commit_message | type == "string")) and
    (if .status == "completed" then
      (.commit_message | type == "string") and
      (.commit_message | length > 0 and length <= 200) and
      (.commit_message | test("[\\r\\n]") | not)
    else
      .commit_message == null
    end) and
    (.tests | type == "array") and
    all(.tests[];
      type == "object" and
      (keys | sort == ["command", "status", "summary"]) and
      (.command | type == "string") and
      (.status == "passed" or .status == "failed" or .status == "not_run") and
      (.summary | type == "string")
    ) and
    (.risks | type == "array") and
    all(.risks[]; type == "string") and
    (.blockers | type == "array") and
    all(.blockers[]; type == "string" and length > 0) and
    (if .status == "blocked" then
      (.blockers | length) > 0
    else
      true
    end)
  ' "$temporary_response" >/dev/null
}

persist_response_result() {
  local final_status="$1"
  local retry_safe="$2"
  local summary_override="$3"
  local additional_blocker="$4"

  jq \
    --arg status "$final_status" \
    --arg summary_override "$summary_override" \
    --arg additional_blocker "$additional_blocker" \
    --arg model "$model" \
    --arg reasoning_effort "$reasoning_effort" \
    --arg profile "$profile" \
    --arg source_repository_path "$source_repository_path" \
    --arg private_repository_path "$private_repository_path" \
    --arg base_branch "$base_branch" \
    --arg base_commit "$base_commit" \
    --arg worktree_path "$worktree_path" \
    --arg worktree_branch "$worktree_branch" \
    --arg observed_head "$observed_head" \
    --arg observed_branch "$observed_branch" \
    --argjson usage "$cumulative_usage" \
    --argjson head_changed "$head_changed" \
    --argjson worktree_clean "$worktree_clean" \
    --argjson retry_safe "$retry_safe" \
    --argjson attempt_count "$attempt_count" \
    --argjson max_attempts "$max_attempts" \
    '
      .status = $status |
      if $summary_override != "" then .summary = $summary_override else . end |
      if $status == "completed" then .commit = $observed_head else .commit = null end |
      del(.commit_message) |
      if $additional_blocker != "" then
        .blockers = ((.blockers + [$additional_blocker]) | unique)
      else
        .
      end |
      . + {
        execution: {
          model: $model,
          reasoning_effort: (if $reasoning_effort == "" then null else $reasoning_effort end),
          profile: (if $profile == "" then null else $profile end),
          source_repository_path: (if $source_repository_path == "" then null else $source_repository_path end),
          private_repository_path: (if $private_repository_path == "" then null else $private_repository_path end),
          base_branch: (if $base_branch == "" then null else $base_branch end),
          base_commit: (if $base_commit == "" then null else $base_commit end),
          worktree_path: (if $worktree_path == "" then null else $worktree_path end),
          worktree_branch: (if $worktree_branch == "" then null else $worktree_branch end),
          usage: $usage,
          starting_commit: (if $base_commit == "" then null else $base_commit end),
          observed_head: (if $observed_head == "" then null else $observed_head end),
          starting_branch: (if $worktree_branch == "" then null else $worktree_branch end),
          observed_branch: (if $observed_branch == "" then null else $observed_branch end),
          head_changed: $head_changed,
          worktree_clean: $worktree_clean,
          retry_safe: $retry_safe,
          attempt_count: $attempt_count,
          max_attempts: $max_attempts
        }
      }
    ' "$last_valid_response" > "$temporary_result"

  mv -- "$temporary_result" "$result_path"
  printf '%s\n' "$result_path"
}

persist_system_result() {
  local final_status="$1"
  local result_summary="$2"
  local blocker="$3"
  local retry_safe="$4"

  jq -n \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    --arg status "$final_status" \
    --arg summary "$result_summary" \
    --arg blocker "$blocker" \
    --arg model "$model" \
    --arg reasoning_effort "$reasoning_effort" \
    --arg profile "$profile" \
    --arg source_repository_path "$source_repository_path" \
    --arg private_repository_path "$private_repository_path" \
    --arg base_branch "$base_branch" \
    --arg base_commit "$base_commit" \
    --arg worktree_path "$worktree_path" \
    --arg worktree_branch "$worktree_branch" \
    --arg observed_head "$observed_head" \
    --arg observed_branch "$observed_branch" \
    --argjson usage "$cumulative_usage" \
    --argjson head_changed "$head_changed" \
    --argjson worktree_clean "$worktree_clean" \
    --argjson retry_safe "$retry_safe" \
    --argjson attempt_count "$attempt_count" \
    --argjson max_attempts "$max_attempts" \
    '{
      run_id: $run_id,
      repository: $repository,
      status: $status,
      summary: $summary,
      commit: null,
      tests: [],
      risks: [],
      blockers: [$blocker],
      execution: {
        model: $model,
        reasoning_effort: (if $reasoning_effort == "" then null else $reasoning_effort end),
        profile: (if $profile == "" then null else $profile end),
        source_repository_path: (if $source_repository_path == "" then null else $source_repository_path end),
        private_repository_path: (if $private_repository_path == "" then null else $private_repository_path end),
        base_branch: (if $base_branch == "" then null else $base_branch end),
        base_commit: (if $base_commit == "" then null else $base_commit end),
        worktree_path: (if $worktree_path == "" then null else $worktree_path end),
        worktree_branch: (if $worktree_branch == "" then null else $worktree_branch end),
        usage: $usage,
        starting_commit: (if $base_commit == "" then null else $base_commit end),
        observed_head: (if $observed_head == "" then null else $observed_head end),
        starting_branch: (if $worktree_branch == "" then null else $worktree_branch end),
        observed_branch: (if $observed_branch == "" then null else $observed_branch end),
        head_changed: $head_changed,
        worktree_clean: $worktree_clean,
        retry_safe: $retry_safe,
        attempt_count: $attempt_count,
        max_attempts: $max_attempts
      }
    }' > "$temporary_result"

  mv -- "$temporary_result" "$result_path"
  printf '%s\n' "$result_path"
}

finish_incomplete() {
  local blocker="$1"
  local summary="The repository agent stopped in a state that requires review."
  local final_status="blocked"
  local retry_safe=false

  capture_repository_state

  if [[ "$repository_state_available" == true && \
    "$observed_branch" == "$worktree_branch" && \
    "$head_changed" == false && \
    "$worktree_clean" == true ]]
  then
    final_status="failed"
    summary="The repository agent used all available attempts without changing the RepoChord worktree."
    retry_safe=true
  fi

  if [[ "$last_response_valid" == true ]]; then
    persist_response_result "$final_status" "$retry_safe" "$summary" "$blocker"
  else
    persist_system_result "$final_status" "$summary" "$blocker" "$retry_safe"
  fi
}

finish_blocked() {
  local blocker="$1"

  capture_repository_state

  if [[ "$last_response_valid" == true ]]; then
    persist_response_result \
      "blocked" \
      false \
      "The repository agent stopped in a state that requires review." \
      "$blocker"
  else
    persist_system_result \
      "blocked" \
      "The repository agent stopped in a state that requires review." \
      "$blocker" \
      false
  fi
}

if [[ ! -f "$response_schema_path" || ! -f "$result_schema_path" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "A required repository-agent schema does not exist." false
  exit 1
fi

if [[ ! -x "$git_guard_source" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The RepoChord Git command guard is missing or is not executable." false
  exit 1
fi

if [[ ! -d "$source_repository_path" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository directory does not exist: $source_repository_path" false
  exit 1
fi

source_repository_path="$(cd -- "$source_repository_path" && pwd -P)"

if ! repository_root="$(git -C "$source_repository_path" rev-parse --show-toplevel 2>/dev/null)"; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository path is not inside a Git repository." false
  exit 1
fi

repository_root="$(cd -- "$repository_root" && pwd -P)"

if [[ "$source_repository_path" != "$repository_root" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository path must be the Git repository root." false
  exit 1
fi

if [[ ! -f "$task_file" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The task file does not exist: $task_file" false
  exit 1
fi

task_file="$(cd -- "$(dirname -- "$task_file")" && pwd -P)/$(basename -- "$task_file")"

if ! git -C "$source_repository_path" rev-parse --verify HEAD >/dev/null 2>&1; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository has no initial commit." false
  exit 1
fi

if ! git -C "$source_repository_path" config user.name >/dev/null; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "Git user.name is not configured for the repository." false
  exit 1
fi

if ! git -C "$source_repository_path" config user.email >/dev/null; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "Git user.email is not configured for the repository." false
  exit 1
fi

if [[ ! -f "$registry_path" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository registry does not exist." false
  exit 1
fi

registered_path="$(jq -r \
  --arg key "$repository_key" \
  '[.repositories[] | select(.key == $key)] | if length == 1 then .[0].path else "" end' \
  "$registry_path")"

if [[ -z "$registered_path" || ! -d "$registered_path" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository key is not uniquely registered." false
  exit 1
fi

registered_path="$(cd -- "$registered_path" && pwd -P)"

if [[ "$registered_path" != "$source_repository_path" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository path does not match the registered path." false
  exit 1
fi

if [[ "$resume" == true ]]; then
  if [[ ! -f "$result_path" ]]; then
    persist_system_result "blocked" "RepoChord cannot resume the repository agent." "The previous repository result does not exist." false
    exit 1
  fi

  if ! jq -e '
    (.status == "failed" or .status == "blocked") and
    (.execution.source_repository_path | type == "string") and
    (.execution.private_repository_path | type == "string") and
    (.execution.base_branch | type == "string") and
    (.execution.base_commit | type == "string") and
    (.execution.worktree_path | type == "string") and
    (.execution.worktree_branch | type == "string") and
    (.execution.attempt_count | type == "number")
  ' "$result_path" >/dev/null; then
    echo "Existing repository result cannot be resumed: $result_path" >&2
    exit 1
  fi

  previous_status="$(jq -r '.status' "$result_path")"

  if [[ "$previous_status" == "blocked" && "$allow_blocked_resume" != true ]]; then
    echo "Blocked repository requires explicit --allow-blocked-resume: $repository_key" >&2
    exit 1
  fi

  recorded_source_repository_path="$(jq -r '.execution.source_repository_path' "$result_path")"
  recorded_private_repository_path="$(jq -r '.execution.private_repository_path' "$result_path")"
  recorded_worktree_path="$(jq -r '.execution.worktree_path' "$result_path")"
  recorded_worktree_branch="$(jq -r '.execution.worktree_branch' "$result_path")"

  if [[ "$recorded_source_repository_path" != "$source_repository_path" || \
    "$recorded_private_repository_path" != "$private_repository_path" || \
    "$recorded_worktree_path" != "$worktree_path" || \
    "$recorded_worktree_branch" != "$worktree_branch" ]]
  then
    echo "Existing repository result does not match the expected RepoChord worktree." >&2
    exit 1
  fi

  base_branch="$(jq -r '.execution.base_branch' "$result_path")"
  base_commit="$(jq -r '.execution.base_commit' "$result_path")"
  attempt_count="$(jq -r '.execution.attempt_count' "$result_path")"
  cumulative_usage="$(jq -c '.execution.usage' "$result_path")"
  previous_attempt_context="$(jq -c '{status, summary, tests, blockers}' "$result_path")"
  jq 'del(.execution)' "$result_path" > "$last_valid_response"
  last_response_valid=true

  if [[ "$attempt_count" -ge "$max_attempts" ]]; then
    echo "Repository $repository_key already used $attempt_count of $max_attempts configured attempts." >&2
    echo "Increase max-attempts before resuming this run." >&2
    exit 1
  fi

  if [[ -L "$private_repository_path" || ! -d "$private_repository_path" ]] || \
    ! git --git-dir="$private_repository_path" show-ref --verify --quiet "refs/heads/$worktree_branch"
  then
    finish_blocked "The preserved RepoChord branch does not exist: $worktree_branch"
    exit 1
  fi

  if [[ ! -e "$worktree_path" ]]; then
    mkdir -p "$(dirname -- "$worktree_path")"

    if ! git --git-dir="$private_repository_path" \
      -c core.hooksPath="$empty_hooks_directory" \
      worktree add "$worktree_path" "$worktree_branch" \
      >/dev/null
    then
      finish_blocked "RepoChord could not restore the preserved worktree."
      exit 1
    fi
  fi
else
  if ! base_branch="$(git -C "$source_repository_path" symbolic-ref --quiet --short HEAD)"; then
    persist_system_result "blocked" "RepoChord cannot start the repository agent." "The repository has a detached HEAD." false
    exit 1
  fi

  base_commit="$(git -C "$source_repository_path" rev-parse --verify HEAD)"

  if [[ -e "$private_repository_path" ]]; then
    persist_system_result "blocked" "RepoChord cannot create the private repository." "The private repository path already exists: $private_repository_path" false
    exit 1
  fi

  if [[ -e "$worktree_path" ]]; then
    persist_system_result "blocked" "RepoChord cannot create the repository worktree." "The RepoChord worktree path already exists: $worktree_path" false
    exit 1
  fi

  mkdir -p "$(dirname -- "$private_repository_path")" "$(dirname -- "$worktree_path")"

  if ! git init --bare --quiet "$private_repository_path"; then
    persist_system_result "blocked" "RepoChord cannot create the private repository." "Private Git repository creation failed." false
    exit 1
  fi

  if ! git --git-dir="$private_repository_path" \
    fetch --quiet --no-tags --no-write-fetch-head "$source_repository_path" "$base_commit"
  then
    rm -rf -- "$private_repository_path"
    persist_system_result "blocked" "RepoChord cannot create the private repository." "The recorded base commit could not be copied into the private repository." false
    exit 1
  fi

  source_user_name="$(git -C "$source_repository_path" config user.name)"
  source_user_email="$(git -C "$source_repository_path" config user.email)"
  git --git-dir="$private_repository_path" config user.name "$source_user_name"
  git --git-dir="$private_repository_path" config user.email "$source_user_email"

  if ! git --git-dir="$private_repository_path" \
    -c core.hooksPath="$empty_hooks_directory" \
    worktree add \
    -b "$worktree_branch" \
    "$worktree_path" \
    "$base_commit" \
    >/dev/null
  then
    persist_system_result "blocked" "RepoChord cannot create the repository worktree." "Git worktree creation failed." false
    exit 1
  fi
fi

capture_repository_state

if [[ "$repository_state_available" != true ]]; then
  finish_blocked "The RepoChord worktree is unavailable."
  exit 1
fi

if [[ "$observed_branch" != "$worktree_branch" ]]; then
  finish_blocked "The RepoChord worktree is on an unexpected branch."
  exit 1
fi

if [[ "$observed_head" != "$base_commit" ]]; then
  finish_blocked "The RepoChord worktree HEAD does not match the recorded base commit."
  exit 1
fi

if [[ "$resume" == true && "$(jq -r '.status' "$result_path")" == "failed" && "$worktree_clean" != true ]]; then
  finish_blocked "A failed repository result must have a clean worktree before resume."
  exit 1
fi

git_common_directory="$(git -C "$worktree_path" rev-parse --git-common-dir)"

if [[ "$git_common_directory" != /* ]]; then
  git_common_directory="$worktree_path/$git_common_directory"
fi

git_common_directory="$(cd -- "$git_common_directory" && pwd -P)"

if [[ "$git_common_directory" == "$worktree_path" || "$git_common_directory" == "$worktree_path/"* ]]; then
  finish_blocked "The RepoChord worktree Git metadata is inside the repository-agent writable directory."
  exit 1
fi

source_repository_toml_key="$(jq -Rn --arg value "$source_repository_path" '$value')"
private_repository_toml_key="$(jq -Rn --arg value "$private_repository_path" '$value')"
scratch_directory_toml_key="$(jq -Rn --arg value "$scratch_directory" '$value')"
repository_agent_permissions="permissions.repochord-repository-agent={ filesystem = { \":root\" = \"read\", \":workspace_roots\" = { \".\" = \"write\", \".git\" = \"read\" }, $scratch_directory_toml_key = \"write\", $source_repository_toml_key = \"read\", $private_repository_toml_key = \"read\" }, network = { enabled = true, allow_local_binding = true, domains = { \"*\" = \"allow\" } } }"

mkdir -p "$guard_directory"
cp "$git_guard_source" "$guard_directory/git"
chmod +x "$guard_directory/git"

while [[ "$attempt_count" -lt "$max_attempts" ]]; do
  attempt_count=$((attempt_count + 1))
  capture_repository_state

  if [[ "$observed_branch" != "$worktree_branch" ]]; then
    finish_blocked "The RepoChord worktree branch changed during automatic repair."
    exit 1
  fi

  if [[ "$head_changed" == true ]]; then
    finish_blocked "RepoChord worktree HEAD changed without verified completion."
    exit 1
  fi

  log_path="$result_directory/$repository_key.attempt-$attempt_count.agent.log"
  events_path="$result_directory/$repository_key.attempt-$attempt_count.events.jsonl"
  created_logs+=("$log_path")
  created_events+=("$events_path")
  : > "$temporary_response"

  repository_agent_prompt="$(printf '%s\n' \
    "Act as the repository agent for one RepoChord assignment." \
    "Make repository changes only in the current RepoChord worktree." \
    "Scratch pad: $scratch_directory" \
    "Use the scratch pad only for disposable temporary files." \
    "Do not delegate work or start other agents." \
    "Read and obey the repository AGENTS.md files." \
    "Run ID: $run_id" \
    "Repository key: $repository_key" \
    "Source repository: $source_repository_path" \
    "Base branch: $base_branch" \
    "Base commit: $base_commit" \
    "RepoChord worktree: $worktree_path" \
    "Repository branch: $worktree_branch" \
    "Attempt: $attempt_count of $max_attempts" \
    "Previous attempt result: $previous_attempt_context" \
    "The complete task specification is supplied through standard input." \
    "Inspect the existing execution path before editing." \
    "Continue any uncommitted changes created by an earlier attempt in this run." \
    "Do not discard or reset existing changes." \
    "Implement only the supplied repository task." \
    "Run every test required by the task." \
    "When a test fails, diagnose it, repair the implementation, and rerun the required tests before returning." \
    "Review the complete diff before committing." \
    "Report completed only after all acceptance criteria and required tests pass." \
    "A completed response must include at least one reported test, all reported tests must pass, and blockers must be empty." \
    "Do not stage or commit changes. RepoChord creates the commit after it validates your completed response." \
    "Return blocked only for a concrete condition that this repository agent cannot resolve." \
    "Return failed only after you cannot complete this attempt and include the failed or unrun tests." \
    "Do not run Git commands that change the index, worktree, branches, tags, remotes, or repository configuration." \
    "Do not push, merge, pull, rebase, or change the source repository worktree." \
    "Return only a final response that conforms to the supplied JSON Schema." \
    "Set commit to null for every status." \
    "When status is completed, set commit_message to the exact commit message from the repository task." \
    "Set commit_message to null when status is blocked or failed." \
    "Do not include diffs, source files, command logs, or exploration notes.")"

  codex_command=(
    codex exec
    --ephemeral
    --json
    --cd "$worktree_path"
    --color never
    --model "$model"
  )

  if [[ -n "$profile" ]]; then
    codex_command+=(--profile "$profile")
  fi

  codex_command+=(
    --config 'features.network_proxy=true'
    --config "$repository_agent_permissions"
    --config 'default_permissions="repochord-repository-agent"'
    --config 'approval_policy="never"'
    --config "model_reasoning_effort=\"$reasoning_effort\""
  )

  codex_command+=(
    --output-schema "$response_schema_path"
    --output-last-message "$temporary_response"
    "$repository_agent_prompt"
  )

  repository_agent_exit_code=0

  PATH="$guard_directory:$PATH" \
  TMPDIR="$scratch_directory" \
  CODEX_SQLITE_HOME="$codex_sqlite_directory" \
  "${codex_command[@]}" \
    < "$task_file" \
    > "$events_path" \
    2> "$log_path" \
    || repository_agent_exit_code=$?

  extract_attempt_usage "$events_path"
  capture_repository_state
  failure_reason=""

  if [[ "$observed_branch" != "$worktree_branch" ]]; then
    finish_blocked "The RepoChord worktree branch changed during attempt $attempt_count."
    exit 1
  fi

  if [[ "$repository_agent_exit_code" -ne 0 ]]; then
    failure_reason="Repository agent attempt $attempt_count exited with status $repository_agent_exit_code."
  elif [[ ! -s "$temporary_response" ]]; then
    failure_reason="Repository agent attempt $attempt_count returned an empty result."
  elif ! validate_repository_agent_response; then
    failure_reason="Repository agent attempt $attempt_count returned an invalid result."
  elif ! jq -e \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    '.run_id == $run_id and .repository == $repository' \
    "$temporary_response" \
    >/dev/null
  then
    failure_reason="Repository agent attempt $attempt_count returned the wrong run ID or repository key."
  elif [[ "$attempt_usage_json" == "null" ]]; then
    failure_reason="Repository agent attempt $attempt_count did not emit a completed usage event."
  else
    cp "$temporary_response" "$last_valid_response"
    last_response_valid=true
  fi

  if [[ -n "$failure_reason" ]]; then
    previous_attempt_context="$failure_reason"

    if [[ "$head_changed" == true ]]; then
      finish_blocked "$failure_reason RepoChord worktree HEAD changed without verified completion."
      exit 1
    fi

    if [[ "$attempt_count" -lt "$max_attempts" ]]; then
      continue
    fi

    finish_incomplete "$failure_reason Maximum attempts reached."
    exit 1
  fi

  repository_agent_status="$(jq -r '.status' "$last_valid_response")"

  if [[ "$repository_agent_status" == "completed" ]]; then
    commit_message="$(jq -r '.commit_message // empty' "$last_valid_response")"

    if [[ "$head_changed" == true ]]; then
      failure_reason="The repository agent changed RepoChord worktree HEAD."
    elif [[ "$worktree_clean" == true ]]; then
      failure_reason="The repository agent reported completion without making a change."
    elif ! jq -e '
      (.tests | length) > 0 and
      all(.tests[]; .status == "passed") and
      (.blockers | length) == 0
    ' "$last_valid_response" >/dev/null; then
      failure_reason="The repository agent reported completion with missing, failed, or unrun tests, or with blockers."
    elif ! git -C "$worktree_path" add -A; then
      finish_blocked "RepoChord could not stage the completed repository changes."
      exit 1
    elif git -C "$worktree_path" diff --cached --quiet; then
      failure_reason="The repository agent reported completion without a committable change."
    elif ! completed_tree="$(git -C "$worktree_path" write-tree)"; then
      finish_blocked "RepoChord could not create the completed repository tree."
      exit 1
    elif ! completed_commit="$(git -C "$worktree_path" commit-tree "$completed_tree" -p "$base_commit" -m "$commit_message")"; then
      finish_blocked "RepoChord could not create the completed repository commit."
      exit 1
    elif ! git -C "$worktree_path" \
      -c core.hooksPath="$empty_hooks_directory" \
      update-ref \
      "refs/heads/$worktree_branch" \
      "$completed_commit" \
      "$base_commit"
    then
      finish_blocked "RepoChord could not update the RepoChord branch to the completed commit."
      exit 1
    else
      capture_repository_state

      if [[ "$observed_branch" != "$worktree_branch" ]]; then
        finish_blocked "The RepoChord worktree branch changed while RepoChord created the commit."
        exit 1
      fi

      if [[ "$head_changed" != true || "$worktree_clean" != true ]]; then
        finish_blocked "The RepoChord commit did not leave the expected clean worktree state."
        exit 1
      fi

      if ! git -C "$worktree_path" merge-base --is-ancestor "$base_commit" "$observed_head"; then
        finish_blocked "The completed commit is not based on the recorded base commit."
        exit 1
      fi

      if [[ -n "$(git -C "$worktree_path" rev-list --merges "$base_commit..$observed_head")" ]]; then
        finish_blocked "The RepoChord branch contains a merge commit."
        exit 1
      fi

      persist_response_result "completed" false "" ""
      rm -f -- "${created_logs[@]}" "${created_events[@]}"
      exit 0
    fi

    previous_attempt_context="$(jq -c '{status, summary, tests, blockers}' "$last_valid_response") Failure: $failure_reason"

    if [[ "$head_changed" == true ]]; then
      finish_blocked "$failure_reason RepoChord worktree HEAD changed without verified completion."
      exit 1
    fi

    if [[ "$attempt_count" -lt "$max_attempts" ]]; then
      continue
    fi

    finish_incomplete "$failure_reason Maximum attempts reached."
    exit 1
  fi

  if ! jq -e '.commit == null' "$last_valid_response" >/dev/null; then
    failure_reason="A blocked or failed repository-agent result must have a null commit."
    previous_attempt_context="$failure_reason"

    if [[ "$head_changed" == true ]]; then
      finish_blocked "$failure_reason RepoChord worktree HEAD changed without verified completion."
      exit 1
    fi

    if [[ "$attempt_count" -lt "$max_attempts" ]]; then
      continue
    fi

    finish_incomplete "$failure_reason Maximum attempts reached."
    exit 1
  fi

  if [[ "$repository_agent_status" == "blocked" ]]; then
    persist_response_result "blocked" false "" ""
    exit 1
  fi

  previous_attempt_context="$(jq -c '{status, summary, tests, blockers}' "$last_valid_response")"

  if [[ "$head_changed" == true ]]; then
    finish_blocked "RepoChord worktree HEAD changed after an incomplete attempt."
    exit 1
  fi

  if [[ "$attempt_count" -lt "$max_attempts" ]]; then
    continue
  fi

  finish_incomplete "Maximum attempts reached before repository completion."
  exit 1
done

finish_incomplete "Maximum attempts reached before repository completion."
exit 1
