HOME="$test_home" \
PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$command_bin/rchord" resume \
  --project repository-agent-test \
  --run PROJECT-123-attempt-limit \
  --max-attempts 3 \
  --retry-blocked api \
  >/dev/null

jq -e '
  .status == "completed" and
  .execution.attempt_count == 3 and
  .execution.max_attempts == 3
' "$coordinate_repository/.repochord/results/PROJECT-123-attempt-limit/api.json" >/dev/null

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
"$command_bin/rchord" cleanup \
  --project repository-agent-test \
  --run PROJECT-123-attempt-limit \
  --repository api \
  >/dev/null

test ! -e "$blocked_worktree"
test "$(git -C "$api_repository" rev-parse HEAD)" = "$api_base_commit"
test "$(git -C "$api_repository" symbolic-ref --short HEAD)" = "$api_base_branch"

echo "Repository-agent tests passed."
