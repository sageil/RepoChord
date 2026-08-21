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
