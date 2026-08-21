PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=fail_dirty_then_complete \
FAKE_CODEX_CAPTURE_DIRECTORY="$capture_directory" \
"$runner" \
  PROJECT-123-repaired \
  "$web_assignment" \
  >/dev/null

jq -e '
  .status == "completed" and
  .execution.attempt_count == 2 and
  .execution.max_attempts == 3 and
  .execution.usage == {
    input_tokens: 200,
    cached_input_tokens: 80,
    output_tokens: 40,
    reasoning_output_tokens: 10
  } and
  .execution.head_changed == true and
  .execution.worktree_clean == true
' "$coordinate_repository/.repochord/results/PROJECT-123-repaired/web.json" >/dev/null

jq -e '.attempt == 1 and .max_attempts == 3' "$capture_directory/web-attempt-1.json" >/dev/null
jq -e '.attempt == 2 and .max_attempts == 3' "$capture_directory/web-attempt-2.json" >/dev/null

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
FAKE_CODEX_CAPTURE_DIRECTORY="$capture_directory" \
"$runner" \
  PROJECT-123-defaults \
  "$web_assignment" \
  >/dev/null

jq -e '
  .status == "completed" and
  .execution.model == "gpt-5.6-terra" and
  .execution.reasoning_effort == "high" and
  .execution.profile == null
' "$coordinate_repository/.repochord/results/PROJECT-123-defaults/web.json" >/dev/null

jq -e \
  --arg source_repository "$web_repository" \
  --arg private_repository "$coordinate_repository/.repochord/repositories/PROJECT-123-defaults/web.git" \
  '
  .scratch_directory as $scratch_directory |
  .model == "gpt-5.6-terra" and
  .reasoning_effort == "high" and
  .profile == null and
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
  (.scratch_directory | type == "string" and contains("repochord-PROJECT-123-defaults-web")) and
  .scratch_directory_exists == true and
  .scratch_directory_writable == true and
  (.codex_sqlite_directory | type == "string" and startswith($scratch_directory + "/")) and
  .codex_sqlite_directory_exists == true and
  .codex_sqlite_directory_writable == true
' "$capture_directory/web.json" >/dev/null

duplicate_assignments="$temporary_root/duplicate-assignments.txt"

printf 'api|%s|%s\n' \
  "$api_repository" \
  "$coordinate_repository/tasks/PROJECT-123/api.md" \
  > "$duplicate_assignments"
printf 'web|%s|%s\n' \
  "$api_repository" \
  "$coordinate_repository/tasks/PROJECT-123/web.md" \
  >> "$duplicate_assignments"

if PATH="$fake_bin:$PATH" "$runner" \
  PROJECT-123-duplicate-path \
  "$duplicate_assignments" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted duplicate canonical repository paths." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-duplicate-path"

if PATH="$fake_bin:$PATH" "$repository_agent" \
  api \
  "$empty_repository" \
  PROJECT-123-empty \
  "$coordinate_repository/tasks/PROJECT-123/api.md" \
  >/dev/null 2>&1
then
  echo "Repository agent unexpectedly accepted a repository without an initial commit." >&2
  exit 1
fi

jq -e '
  .status == "blocked" and
  .commit == null and
  .execution.starting_commit == null and
  .execution.observed_head == null and
  .execution.retry_safe == false and
  .execution.attempt_count == 0 and
  .execution.max_attempts == 3
' "$coordinate_repository/.repochord/results/PROJECT-123-empty/api.json" >/dev/null

if PATH="$fake_bin:$PATH" \
  REPOCHORD_MAX_ATTEMPTS=4 \
  FAKE_CODEX_MODE=always_fail_dirty \
  "$runner" \
  --max-attempts 2 \
  PROJECT-123-attempt-limit \
  "$api_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly returned success after exhausting repair attempts." >&2
  exit 1
fi

jq -e '
  .status == "blocked" and
  .commit == null and
  (.tests | length == 5) and
  ([.tests[] | select(.status == "passed")] | length == 4) and
  ([.tests[] | select(.status == "failed")] | length == 1) and
  .execution.head_changed == false and
  .execution.worktree_clean == false and
  .execution.retry_safe == false and
  .execution.attempt_count == 2 and
  .execution.max_attempts == 2
' "$coordinate_repository/.repochord/results/PROJECT-123-attempt-limit/api.json" >/dev/null

blocked_worktree="$(jq -r \
  '.execution.worktree_path' \
  "$coordinate_repository/.repochord/results/PROJECT-123-attempt-limit/api.json")"
test -d "$blocked_worktree"
test -n "$(git -C "$blocked_worktree" status --porcelain)"

if HOME="$test_home" PATH="$fake_bin:$PATH" "$command_bin/rchord" cleanup \
  --project repository-agent-test \
  --run PROJECT-123-attempt-limit \
  --repository api \
  >/dev/null 2>&1
then
  echo "Cleanup unexpectedly removed a dirty RepoChord worktree without --force." >&2
  exit 1
fi

test -d "$blocked_worktree"

if PATH="$fake_bin:$PATH" \
  REPOCHORD_MAX_ATTEMPTS=3 \
  FAKE_CODEX_MODE=completed \
  "$runner" \
    --resume PROJECT-123-attempt-limit \
    "$api_assignment" \
    >/dev/null 2>&1
then
  echo "Resume unexpectedly retried a blocked repository without explicit selection." >&2
  exit 1
fi

jq -e '.status == "blocked" and .execution.attempt_count == 2' \
  "$coordinate_repository/.repochord/results/PROJECT-123-attempt-limit/api.json" \
  >/dev/null
