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
    elif ! completed_commit="$(
      GIT_AUTHOR_NAME="$global_user_name" \
      GIT_AUTHOR_EMAIL="$global_user_email" \
      GIT_COMMITTER_NAME="$global_user_name" \
      GIT_COMMITTER_EMAIL="$global_user_email" \
      git -C "$worktree_path" commit-tree "$completed_tree" -p "$base_commit" -m "$commit_message"
    )"; then
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
