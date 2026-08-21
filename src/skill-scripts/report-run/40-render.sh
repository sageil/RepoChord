write_complete_report() {
  echo "RepoChord run report"
  echo "Feature: $feature_id"
  echo "Run: $(markdown_code "$run_id")"
  echo "Overall status: $(markdown_code "$overall_status")"
  echo "Pushed by RepoChord: no"
  echo "Incomplete repositories: $incomplete_list"

  for ((index = 0; index < repository_count; index++)); do
    repository_key="${repository_keys[$index]}"
    result_path="${result_paths[$index]}"
    repository_status="${repository_statuses[$index]}"

    echo
    echo "Repository: $repository_key"
    echo "  Status: $(markdown_code "$repository_status")"

    if [[ "$repository_status" == "missing" ]]; then
      echo "  Result: missing"
      continue
    fi

    echo "  Summary: $(single_line "$result_path" '.summary')"
    echo "  Commit: $(markdown_code "$(jq -r '.commit // "unavailable"' "$result_path")")"
    echo "  Tests:"

    if [[ "$(jq '.tests | length' "$result_path")" -eq 0 ]]; then
      echo "    none"
    else
      while IFS=$'\t' read -r test_command test_status test_summary; do
        printf '    - %s: %s - %s\n' "$test_command" "$test_status" "$test_summary"
      done < <(jq -r '
        .tests[] |
        [
          (.command | gsub("[\u0000-\u001F\u007F]"; " ")),
          .status,
          (.summary | gsub("[\u0000-\u001F\u007F]"; " "))
        ] |
        @tsv
      ' "$result_path")
    fi

    echo "  Risks:"
    display_string_list "$result_path" '.risks' "none"
    echo "  Blockers:"
    display_string_list "$result_path" '.blockers' "none"
    echo "  Model: $(markdown_code "$(single_line "$result_path" '.execution.model')")"
    echo "  Reasoning effort: $(markdown_code "$(jq -r '.execution.reasoning_effort // "unavailable"' "$result_path")")"
    echo "  Attempt: $(markdown_code "$(jq -r '.execution.attempt_count' "$result_path")") of $(markdown_code "$(jq -r '.execution.max_attempts' "$result_path")")"

    if jq -e '.execution.usage == null' "$result_path" >/dev/null; then
      echo "  Token usage: unavailable"
    else
      echo "  Token usage:"
      echo "    Input: $(markdown_code "$(jq -r '.execution.usage.input_tokens' "$result_path")")"
      echo "    Cached input: $(markdown_code "$(jq -r '.execution.usage.cached_input_tokens' "$result_path")")"
      echo "    Output: $(markdown_code "$(jq -r '.execution.usage.output_tokens' "$result_path")")"
      echo "    Reasoning output: $(markdown_code "$(jq -r '.execution.usage.reasoning_output_tokens' "$result_path")")"
    fi

    echo "  Retry safe: $(jq -r 'if .execution.retry_safe then "yes" else "no" end' "$result_path")"
    echo "  Source repository: $(single_line "$result_path" '.execution.source_repository_path // "unavailable"')"
    echo "  Private repository: $(markdown_code "$(single_line "$result_path" '.execution.private_repository_path // "legacy source repository"')")"
    echo "  Base branch: $(single_line "$result_path" '.execution.base_branch // "unavailable"')"
    echo "  Base commit: $(markdown_code "$(single_line "$result_path" '.execution.base_commit // "unavailable"')")"
    echo "  Final commit: $(markdown_code "$(single_line "$result_path" '.commit // "unavailable"')")"
    echo "  Worktree: $(markdown_code "$(single_line "$result_path" '.execution.worktree_path // "unavailable"')")"
    echo "  Worktree branch: $(markdown_code "$(single_line "$result_path" '.execution.worktree_branch // "unavailable"')")"

    if [[ "$repository_status" == "completed" ]]; then
      echo "  Completed task: $(markdown_code "${completed_task_paths[$index]}")"
      echo "  Completed task hash: $(markdown_code "${completed_task_hashes[$index]}")"
      echo "  Worktree present: $(markdown_code "${worktree_presence[$index]}")"
      echo "  Integration: $(markdown_code "${integration_states[$index]}")"
    fi
  done

  if [[ "$overall_status" == "completed" ]]; then
    echo
    echo "Next actions:"
    echo "  $(markdown_code "rchord integrate --run $run_id --dry-run")"
    echo "  $(markdown_code "rchord integrate --run $run_id")"
  fi
}
