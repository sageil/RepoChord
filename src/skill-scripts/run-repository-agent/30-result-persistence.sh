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
