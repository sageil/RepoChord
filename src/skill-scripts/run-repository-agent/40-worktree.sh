
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

if ! global_user_name="$(git config --global --get user.name)" || [[ -z "$global_user_name" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "Global Git user.name is not configured." false
  exit 1
fi

if ! global_user_email="$(git config --global --get user.email)" || [[ -z "$global_user_email" ]]; then
  persist_system_result "blocked" "RepoChord cannot start the repository agent." "Global Git user.email is not configured." false
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
