PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
FAKE_CODEX_CAPTURE_DIRECTORY="$capture_directory" \
"$runner" \
  --model gpt-5.6-terra \
  --reasoning-effort medium \
  --profile test-profile \
  --max-parallel 1 \
  PROJECT-123-good \
  "$assignments_file" \
  >/dev/null

for repository_key in api web; do
  result_path="$coordinate_repository/.repochord/results/PROJECT-123-good/$repository_key.json"
  source_task="$coordinate_repository/.repochord/results/PROJECT-123-good/tasks/$repository_key.source.md"
  completed_task="$coordinate_repository/.repochord/results/PROJECT-123-good/tasks/$repository_key.completed.md"
  canonical_task="$coordinate_repository/tasks/PROJECT-123/$repository_key.md"

  if [[ "$repository_key" == "api" ]]; then
    expected_source_repository="$api_repository"
    expected_base_commit="$api_base_commit"
    expected_base_branch="$api_base_branch"
  else
    expected_source_repository="$web_repository"
    expected_base_commit="$web_base_commit"
    expected_base_branch="$web_base_branch"
  fi

  expected_worktree="$coordinate_repository/.repochord/worktrees/PROJECT-123-good/$repository_key"
  expected_private_repository="$coordinate_repository/.repochord/repositories/PROJECT-123-good/$repository_key.git"
  expected_worktree_branch="repochord/PROJECT-123-good/$repository_key"

  jq -e \
    --arg source_repository "$expected_source_repository" \
    --arg base_commit "$expected_base_commit" \
    --arg base_branch "$expected_base_branch" \
    --arg private_repository "$expected_private_repository" \
    --arg worktree "$expected_worktree" \
    --arg worktree_branch "$expected_worktree_branch" \
    '
    .status == "completed" and
    (.commit | type == "string") and
    (.tests | length == 1) and
    all(.tests[]; .status == "passed") and
    (.blockers | length == 0) and
    .execution.model == "gpt-5.6-terra" and
    .execution.reasoning_effort == "medium" and
    .execution.profile == "test-profile" and
    .execution.usage == {
      input_tokens: 100,
      cached_input_tokens: 40,
      output_tokens: 20,
      reasoning_output_tokens: 5
    } and
    .execution.head_changed == true and
    .execution.worktree_clean == true and
    .execution.retry_safe == false and
    .execution.attempt_count == 1 and
    .execution.max_attempts == 3 and
    .execution.source_repository_path == $source_repository and
    .execution.private_repository_path == $private_repository and
    .execution.base_commit == $base_commit and
    .execution.base_branch == $base_branch and
    .execution.worktree_path == $worktree and
    .execution.worktree_branch == $worktree_branch and
    .execution.starting_commit == $base_commit and
    .execution.starting_branch == $worktree_branch and
    .execution.observed_branch == $worktree_branch
  ' "$result_path" >/dev/null

  test -d "$expected_worktree"
  test "$(git -C "$expected_private_repository" rev-parse --is-bare-repository)" = true
  test "$(git -C "$expected_private_repository" rev-parse "refs/heads/$expected_worktree_branch")" = \
    "$(jq -r '.commit' "$result_path")"
  test "$(git -C "$expected_source_repository" worktree list --porcelain | grep -c '^worktree ')" = 1
  if git -C "$expected_source_repository" show-ref --verify --quiet "refs/heads/$expected_worktree_branch"; then
    echo "Repository-agent run wrote its feature branch into the source repository." >&2
    exit 1
  fi
  test "$(git -C "$expected_worktree" symbolic-ref --short HEAD)" = "$expected_worktree_branch"
  test "$(git -C "$expected_worktree" rev-parse HEAD)" = "$(jq -r '.commit' "$result_path")"
  test "$(git -C "$expected_worktree" log -1 --format=%s)" = "test: fake repository agent PROJECT-123-good"
  jq -e 'has("commit_message") | not' "$result_path" >/dev/null

  jq -e \
    --arg repository_key "$repository_key" \
    --arg source_repository "$expected_source_repository" \
    --arg private_repository "$expected_private_repository" \
    '
    .scratch_directory as $scratch_directory |
    .model == "gpt-5.6-terra" and
    .reasoning_effort == "medium" and
    .profile == "test-profile" and
    .ephemeral == true and
    .json_output == true and
    .approval_policy == "never" and
    .network_access_enabled == true and
    .network_proxy_enabled == true and
    .permission_profile == "repochord-repository-agent" and
    .filesystem_permissions_configured == true and
    (.permission_configuration | contains("\":root\" = \"read\"")) and
    (.permission_configuration | contains(($scratch_directory | @json) + " = \"write\"")) and
    (.permission_configuration | contains(($source_repository | @json) + " = \"read\"")) and
    (.permission_configuration | contains(($private_repository | @json) + " = \"read\"")) and
    (.permission_configuration | contains("\":minimal\"") | not) and
    (.permission_configuration | contains("\":tmpdir\" = \"write\"" ) | not) and
    (.permission_configuration | contains("\":slash_tmp\" = \"write\"" ) | not) and
    .legacy_sandbox_used == false and
    (.scratch_directory | type == "string" and contains("repochord-PROJECT-123-good-" + $repository_key)) and
    .scratch_directory_exists == true and
    .scratch_directory_writable == true and
    (.codex_sqlite_directory | type == "string" and startswith($scratch_directory + "/")) and
    .codex_sqlite_directory_exists == true and
    .codex_sqlite_directory_writable == true and
    .attempt == 1 and
    .max_attempts == 3
    ' "$capture_directory/$repository_key.json" >/dev/null

  test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-good/$repository_key.attempt-1.events.jsonl"
  test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-good/$repository_key.attempt-1.agent.log"
  test ! -e "$(jq -r '.scratch_directory' "$capture_directory/$repository_key.json")"
  cmp "$canonical_task" "$source_task"
  grep -Fqx -- '- [ ] The repository task is complete.' "$source_task"
  grep -Fqx -- '- [x] The repository task is complete.' "$completed_task"
  test "$(git -C "$coordinate_repository" hash-object -- "$canonical_task")" = \
    "$(git -C "$coordinate_repository" hash-object -- "$source_task")"
done

test "$(git -C "$api_repository" rev-parse HEAD)" = "$api_base_commit"
test "$(git -C "$api_repository" symbolic-ref --short HEAD)" = "$api_base_branch"
test "$(git -C "$web_repository" rev-parse HEAD)" = "$web_base_commit"
test "$(git -C "$web_repository" symbolic-ref --short HEAD)" = "$web_base_branch"
test ! -e "$post_commit_marker"

auto_run_output="$(
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_MODE=completed \
  "$runner" \
    "$web_assignment"
)"
auto_result_path="${auto_run_output%%$'\n'*}"
auto_run_directory="$(dirname -- "$auto_result_path")"
auto_run_id="$(basename -- "$auto_run_directory")"
auto_run_prefix="PROJECT-123-run-"
auto_run_suffix="${auto_run_id#"$auto_run_prefix"}"

if [[ "$auto_run_id" != "$auto_run_prefix"* || \
  ! "$auto_run_suffix" =~ ^[A-Za-z0-9]+$ || \
  "${#auto_run_suffix}" -ne 6 ]]
then
  echo "Runner returned an invalid generated run ID: $auto_run_id" >&2
  exit 1
fi

test "$auto_result_path" = "$coordinate_repository/.repochord/results/$auto_run_id/web.json"

jq -e \
  --arg run_id "$auto_run_id" \
  '.run_id == $run_id and .status == "completed"' \
  "$auto_result_path" \
  >/dev/null

if [[ -n "$(find "$coordinate_repository/.repochord/results" -maxdepth 1 -name '.run-id.*' -print -quit)" ]]; then
  echo "Runner left a run ID reservation behind." >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" "$runner" \
  --reasoning-effort impossible \
  PROJECT-123-invalid-reasoning \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted an invalid reasoning effort." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-invalid-reasoning"

if PATH="$fake_bin:$PATH" "$runner" \
  --max-parallel 0 \
  PROJECT-123-invalid-parallel \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted an invalid concurrency limit." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-invalid-parallel"

if PATH="$fake_bin:$PATH" "$runner" \
  --max-attempts 0 \
  PROJECT-123-invalid-attempts \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted an invalid maximum attempt count." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-invalid-attempts"

if PATH="$fake_bin:$PATH" "$runner" \
  PROJECT..123-invalid-ref \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a run ID that cannot form a Git branch." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT..123-invalid-ref"

if PATH="$fake_bin:$PATH" FAKE_CODEX_MODE=completed_failed_test "$runner" \
  PROJECT-123-failed-test \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a completed result with failed verification." >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" FAKE_CODEX_MODE=blocked_without_blocker "$runner" \
  --max-attempts 2 \
  PROJECT-123-empty-blocker \
  "$web_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a blocked result without a blocker." >&2
  exit 1
fi

jq -e '
  .status == "failed" and
  (.blockers | length >= 1) and
  .execution.attempt_count == 2 and
  .execution.max_attempts == 2 and
  .execution.retry_safe == true
' "$coordinate_repository/.repochord/results/PROJECT-123-empty-blocker/web.json" >/dev/null

jq -e '
  .status == "blocked" and
  .commit == null and
  (.blockers | length >= 1) and
  .execution.head_changed == false and
  .execution.worktree_clean == false and
  .execution.retry_safe == false and
  .execution.attempt_count == 3 and
  .execution.max_attempts == 3
' "$coordinate_repository/.repochord/results/PROJECT-123-failed-test/api.json" >/dev/null

if PATH="$fake_bin:$PATH" FAKE_CODEX_MODE=fail_after_commit "$runner" \
  PROJECT-123-fail-after-commit \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a process failure after a commit." >&2
  exit 1
fi

jq -e '
  .status == "blocked" and
  .commit == null and
  (.execution.starting_commit | type == "string") and
  (.execution.observed_head | type == "string") and
  .execution.starting_commit != .execution.observed_head and
  .execution.head_changed == true and
  .execution.worktree_clean == true and
  .execution.retry_safe == false and
  .execution.attempt_count == 1
' "$coordinate_repository/.repochord/results/PROJECT-123-fail-after-commit/api.json" >/dev/null

if PATH="$fake_bin:$PATH" FAKE_CODEX_MODE=fail_unchanged "$runner" \
  PROJECT-123-safe-failure \
  "$web_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly returned success for an incomplete repository agent." >&2
  exit 1
fi

jq -e '
  .status == "failed" and
  .commit == null and
  .execution.starting_commit == .execution.observed_head and
  .execution.head_changed == false and
  .execution.worktree_clean == true and
  .execution.retry_safe == true and
  .execution.attempt_count == 3 and
  .execution.max_attempts == 3 and
  .execution.usage == {
    input_tokens: 300,
    cached_input_tokens: 120,
    output_tokens: 60,
    reasoning_output_tokens: 15
  }
' "$coordinate_repository/.repochord/results/PROJECT-123-safe-failure/web.json" >/dev/null

if PATH="$fake_bin:$PATH" \
  REPOCHORD_MAX_ATTEMPTS=2 \
  FAKE_CODEX_MODE=fail_unchanged \
  "$runner" \
    PROJECT-123-environment-attempts \
    "$web_assignment" \
    >/dev/null 2>&1
then
  echo "Runner unexpectedly returned success for an incomplete repository agent." >&2
  exit 1
fi

jq -e '
  .status == "failed" and
  .execution.attempt_count == 2 and
  .execution.max_attempts == 2
' "$coordinate_repository/.repochord/results/PROJECT-123-environment-attempts/web.json" >/dev/null

failed_resume_worktree="$(jq -r \
  '.execution.worktree_path' \
  "$coordinate_repository/.repochord/results/PROJECT-123-environment-attempts/web.json")"
test -d "$failed_resume_worktree"
