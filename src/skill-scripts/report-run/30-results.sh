for ((index = 0; index < repository_count; index++)); do
  repository_key="${repository_keys[$index]}"
  repository_path="${repository_paths[$index]}"
  result_path="$result_directory/$repository_key.json"
  expected_worktree_path="$coordinate_root/.repochord/worktrees/$run_id/$repository_key"
  expected_worktree_branch="repochord/$run_id/$repository_key"
  expected_private_repository_path="$coordinate_root/.repochord/repositories/$run_id/$repository_key.git"

  result_paths+=("$result_path")

  if [[ -L "$result_path" ]]; then
    fail "Repository result must not be a symbolic link: $result_path" 2
  fi

  if [[ ! -e "$result_path" ]]; then
    repository_statuses+=("missing")
    worktree_presence+=("unknown")
    integration_states+=("unavailable")
    completed_task_paths+=("unavailable")
    completed_task_hashes+=("unavailable")
    incomplete_repositories+=("$repository_key")
    continue
  fi

  if [[ ! -f "$result_path" ]]; then
    fail "Repository result is not a regular file: $result_path" 2
  fi

  if ! jq -e \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    '
      type == "object" and
      (keys | sort) == [
        "blockers",
        "commit",
        "execution",
        "repository",
        "risks",
        "run_id",
        "status",
        "summary",
        "tests"
      ] and
      .run_id == $run_id and
      .repository == $repository and
      (.status == "completed" or .status == "blocked" or .status == "failed") and
      (.summary | type == "string") and
      (.commit == null or (.commit | type == "string")) and
      (.tests | type == "array") and
      all(.tests[];
        type == "object" and
        (keys | sort) == ["command", "status", "summary"] and
        (.command | type == "string") and
        (.status == "passed" or .status == "failed" or .status == "not_run") and
        (.summary | type == "string")
      ) and
      (.risks | type == "array") and
      all(.risks[]; type == "string") and
      (.blockers | type == "array") and
      all(.blockers[]; type == "string" and length > 0) and
      (.execution | type == "object") and
      ((.execution | keys | sort) == [
        "attempt_count",
        "base_branch",
        "base_commit",
        "head_changed",
        "max_attempts",
        "model",
        "observed_branch",
        "observed_head",
        "profile",
        "reasoning_effort",
        "retry_safe",
        "source_repository_path",
        "starting_branch",
        "starting_commit",
        "usage",
        "worktree_branch",
        "worktree_clean",
        "worktree_path"
      ] or (.execution | keys | sort) == [
        "attempt_count",
        "base_branch",
        "base_commit",

        "head_changed",
        "max_attempts",
        "model",
        "observed_branch",
        "observed_head",
        "private_repository_path",
        "profile",
        "reasoning_effort",
        "retry_safe",
        "source_repository_path",
        "starting_branch",
        "starting_commit",
        "usage",
        "worktree_branch",
        "worktree_clean",
        "worktree_path"
      ]) and
      (.execution.model | type == "string") and
      (.execution.reasoning_effort == null or
        .execution.reasoning_effort == "minimal" or
        .execution.reasoning_effort == "low" or
        .execution.reasoning_effort == "medium" or
        .execution.reasoning_effort == "high" or
        .execution.reasoning_effort == "xhigh") and
      (.execution.profile == null or (.execution.profile | type == "string")) and
      (.execution.source_repository_path == null or (.execution.source_repository_path | type == "string")) and
      (.execution.private_repository_path == null or (.execution.private_repository_path | type == "string")) and
      (.execution.base_branch == null or (.execution.base_branch | type == "string")) and
      (.execution.base_commit == null or (.execution.base_commit | type == "string")) and
      (.execution.worktree_path == null or (.execution.worktree_path | type == "string")) and
      (.execution.worktree_branch == null or (.execution.worktree_branch | type == "string")) and
      (.execution.usage == null or
        ((.execution.usage | type == "object") and
         (.execution.usage | keys | sort) == [
           "cached_input_tokens",
           "input_tokens",
           "output_tokens",
           "reasoning_output_tokens"
         ] and
         all(.execution.usage[]; type == "number" and floor == . and . >= 0))) and
      (.execution.starting_commit == null or (.execution.starting_commit | type == "string")) and
      (.execution.observed_head == null or (.execution.observed_head | type == "string")) and
      (.execution.starting_branch == null or (.execution.starting_branch | type == "string")) and
      (.execution.observed_branch == null or (.execution.observed_branch | type == "string")) and
      (.execution.head_changed | type == "boolean") and
      (.execution.worktree_clean | type == "boolean") and
      (.execution.retry_safe | type == "boolean") and
      (.execution.attempt_count | type == "number") and
      (.execution.attempt_count | floor == .) and
      .execution.attempt_count >= 0 and
      (.execution.max_attempts | type == "number") and
      (.execution.max_attempts | floor == .) and
      .execution.max_attempts >= 1 and
      .execution.attempt_count <= .execution.max_attempts and
      (if .status == "completed" then
        (.commit | type == "string") and
        (.commit | length > 0) and
        (.tests | length > 0) and
        all(.tests[]; .status == "passed") and
        .blockers == [] and
        .execution.head_changed == true and
        .execution.worktree_clean == true
      elif .status == "blocked" then
        .commit == null and
        (.blockers | length > 0)
      else
        .commit == null
      end)
    ' \
    "$result_path" \
    >/dev/null
  then
    fail "Repository result is invalid: $result_path" 2
  fi

  repository_status="$(jq -r '.status' "$result_path")"
  repository_statuses+=("$repository_status")

  if [[ "$repository_status" != "completed" ]]; then
    worktree_presence+=("unknown")
    integration_states+=("unavailable")
    completed_task_paths+=("unavailable")
    completed_task_hashes+=("unavailable")
    incomplete_repositories+=("$repository_key")
    continue
  fi

  if ! jq -e \
    --arg source_repository_path "$repository_path" \
    --arg private_repository_path "$expected_private_repository_path" \
    --arg worktree_path "$expected_worktree_path" \
    --arg worktree_branch "$expected_worktree_branch" \
    '
      .execution.source_repository_path == $source_repository_path and
      ((.execution.private_repository_path // null) == null or
        .execution.private_repository_path == $private_repository_path) and
      (.execution.base_branch | type == "string" and length > 0) and
      (.execution.base_commit | type == "string" and length > 0) and
      .execution.worktree_path == $worktree_path and
      .execution.worktree_branch == $worktree_branch and
      .execution.observed_head == .commit and
      .execution.observed_branch == $worktree_branch
    ' \
    "$result_path" \
    >/dev/null
  then
    fail "Completed repository result is inconsistent: $result_path" 2
  fi

  if [[ ! -d "$repository_path" ||
    "$(git -C "$repository_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$repository_path" ]]
  then
    fail "Completed result repository is unavailable: $repository_path" 2
  fi

  final_commit="$(jq -r '.commit' "$result_path")"
  base_branch="$(jq -r '.execution.base_branch' "$result_path")"
  base_commit="$(jq -r '.execution.base_commit' "$result_path")"
  private_repository_path="$(jq -r '.execution.private_repository_path // empty' "$result_path")"
  artifact_repository_path="$repository_path"

  if [[ -n "$private_repository_path" ]]; then
    if [[ "$private_repository_path" != "$expected_private_repository_path" || \
      -L "$private_repository_path" || \
      ! -d "$private_repository_path" || \
      "$(git -C "$private_repository_path" rev-parse --is-bare-repository 2>/dev/null || true)" != true ]]
    then
      fail "Completed private repository is unavailable: $expected_private_repository_path" 2
    fi

    artifact_repository_path="$private_repository_path"
  fi

  if ! git check-ref-format "refs/heads/$base_branch" >/dev/null 2>&1; then
    fail "Completed result contains an invalid base branch: $base_branch" 2
  fi

  if ! git -C "$repository_path" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    fail "Completed result base commit does not exist in $repository_key: $base_commit" 2
  fi

  if ! git -C "$artifact_repository_path" merge-base --is-ancestor "$base_commit" "$final_commit"; then
    fail "Completed result final commit does not contain its base in $repository_key." 2
  fi

  if [[ -n "$(git -C "$artifact_repository_path" rev-list --merges "$base_commit..$final_commit")" ]]; then
    fail "Completed result contains a merge commit in $repository_key." 2
  fi

  branch_commit="$(git -C "$artifact_repository_path" rev-parse --verify "refs/heads/$expected_worktree_branch^{commit}" 2>/dev/null || true)"

  if [[ "$branch_commit" != "$final_commit" ]]; then
    fail "Completed RepoChord branch no longer matches its result: $expected_worktree_branch" 2
  fi

  current_base_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$base_branch^{commit}" 2>/dev/null || true)"

  if [[ -z "$current_base_commit" ]]; then
    fail "Completed result base branch does not exist in $repository_key: $base_branch" 2
  fi

  if git -C "$repository_path" cat-file -e "$final_commit^{commit}" 2>/dev/null &&
    git -C "$repository_path" merge-base --is-ancestor "$final_commit" "$current_base_commit"
  then
    integration_states+=("integrated")
    integrated_repositories+=("$repository_key")
  elif git -C "$artifact_repository_path" cat-file -e "$current_base_commit^{commit}" 2>/dev/null &&
    git -C "$artifact_repository_path" merge-base --is-ancestor "$base_commit" "$current_base_commit" &&
    git -C "$artifact_repository_path" merge-base --is-ancestor "$current_base_commit" "$final_commit"
  then
    integration_states+=("pending")
  else
    integration_states+=("diverged")
  fi

  if [[ -L "$expected_worktree_path" ]]; then
    fail "Completed RepoChord worktree must not be a symbolic link: $expected_worktree_path" 2
  fi

  if [[ -e "$expected_worktree_path" ]]; then
    if [[ ! -d "$expected_worktree_path" ||
      "$(git -C "$expected_worktree_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$expected_worktree_path" ||
      "$(git -C "$expected_worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$expected_worktree_branch" ||
      "$(git -C "$expected_worktree_path" rev-parse --verify HEAD 2>/dev/null || true)" != "$final_commit" ||
      -n "$(git -c core.fsmonitor=false -C "$expected_worktree_path" status --porcelain --untracked-files=all 2>/dev/null || true)" ]]
    then
      fail "Completed RepoChord worktree no longer matches its result: $expected_worktree_path" 2
    fi

    worktree_presence+=("yes")
  else
    worktree_presence+=("no")
  fi

  if ! completed_task_path="$(repochord_render_completed_task \
    "$coordinate_root" \
    "$result_directory" \
    "$repository_key" \
    "${task_files[$index]}" \
    "${task_hashes[$index]}")"
  then
    fail "Could not create the completed task view for $repository_key." 2
  fi

  completed_task_paths+=("$completed_task_path")
  completed_task_hashes+=("$(git -C "$coordinate_root" hash-object -- "$completed_task_path")")
done
