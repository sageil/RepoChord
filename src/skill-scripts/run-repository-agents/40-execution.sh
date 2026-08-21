validate_completed_result() {
  local index="$1"
  local repository_key="${repository_keys[$index]}"
  local repository_path="${repository_paths[$index]}"
  local result_path="$result_directory/$repository_key.json"
  local expected_private_repository_path="$coordinate_root/.repochord/repositories/$run_id/$repository_key.git"
  local expected_worktree_path="$coordinate_root/.repochord/worktrees/$run_id/$repository_key"
  local expected_worktree_branch="repochord/$run_id/$repository_key"
  local recorded_commit
  local recorded_base_commit
  local recorded_branch_commit
  local recorded_private_repository_path
  local recorded_worktree_path

  if ! jq -e \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    --arg source_repository_path "$repository_path" \
    --arg private_repository_path "$expected_private_repository_path" \
    --arg worktree_path "$expected_worktree_path" \
    --arg worktree_branch "$expected_worktree_branch" \
    '
      .run_id == $run_id and
      .repository == $repository and
      .status == "completed" and
      (.summary | type == "string") and
      (.commit | type == "string") and
      (.commit | length > 0) and
      (.tests | type == "array") and
      (.tests | length > 0) and
      all(.tests[];
        type == "object" and
        (.command | type == "string") and
        .status == "passed" and
        (.summary | type == "string")
      ) and
      (.risks | type == "array") and
      all(.risks[]; type == "string") and
      .blockers == [] and
      .execution.source_repository_path == $source_repository_path and
      .execution.private_repository_path == $private_repository_path and
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
  recorded_private_repository_path="$(jq -r '.execution.private_repository_path' "$result_path")"
  recorded_worktree_path="$(jq -r '.execution.worktree_path' "$result_path")"

  if [[ "$recorded_private_repository_path" != "$expected_private_repository_path" || \
    -L "$recorded_private_repository_path" || \
    ! -d "$recorded_private_repository_path" || \
    "$(git --git-dir="$recorded_private_repository_path" rev-parse --is-bare-repository 2>/dev/null || true)" != true ]]
  then
    echo "Completed private repository is unavailable or invalid: $expected_private_repository_path" >&2
    return 1
  fi

  if ! recorded_branch_commit="$(git --git-dir="$recorded_private_repository_path" rev-parse --verify "refs/heads/$expected_worktree_branch" 2>/dev/null)"; then
    echo "Completed RepoChord branch does not exist: $expected_worktree_branch" >&2
    return 1
  fi

  if [[ "$recorded_branch_commit" != "$recorded_commit" ]]; then
    echo "Completed RepoChord branch no longer points to its recorded commit: $expected_worktree_branch" >&2
    return 1
  fi

  recorded_base_commit="$(jq -r '.execution.base_commit' "$result_path")"

  if ! git --git-dir="$recorded_private_repository_path" merge-base --is-ancestor "$recorded_base_commit" "$recorded_commit"; then
    echo "Completed repository commit does not contain its recorded base: $repository_key" >&2
    return 1
  fi

  if [[ -n "$(git --git-dir="$recorded_private_repository_path" rev-list --merges "$recorded_base_commit..$recorded_commit")" ]]; then
    echo "Completed repository branch contains a merge commit: $expected_worktree_branch" >&2
    return 1
  fi

  if [[ -e "$recorded_worktree_path" ]]; then
    if [[ "$(git -C "$recorded_worktree_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$recorded_worktree_path" || \
      "$(git -C "$recorded_worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$expected_worktree_branch" || \
      "$(git -C "$recorded_worktree_path" rev-parse --verify HEAD 2>/dev/null || true)" != "$recorded_commit" || \
      -n "$(git -C "$recorded_worktree_path" status --porcelain 2>/dev/null || true)" ]]
    then
      echo "Completed RepoChord worktree no longer matches its result: $recorded_worktree_path" >&2
      return 1
    fi
  fi

  if git -C "$repository_path" show-ref --verify --quiet "refs/heads/$expected_worktree_branch"; then
    echo "Completed RepoChord branch was written into the source repository: $expected_worktree_branch" >&2
    return 1
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
      "${task_snapshot_files[$index]}" \
      > /dev/null \
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
