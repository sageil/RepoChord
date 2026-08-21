git config --global user.name "Updated Global User"
git config --global user.email "updated-global-user@example.com"

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$command_bin/rchord" resume \
  --project repository-agent-test \
  --run PROJECT-123-environment-attempts \
  --max-attempts 4 \
  >/dev/null

resumed_result="$coordinate_repository/.repochord/results/PROJECT-123-environment-attempts/web.json"

jq -e '
  .status == "completed" and
  .execution.attempt_count == 3 and
  .execution.max_attempts == 4 and
  .execution.usage == {
    input_tokens: 300,
    cached_input_tokens: 120,
    output_tokens: 60,
    reasoning_output_tokens: 15
  }
' "$resumed_result" >/dev/null

resumed_commit="$(jq -r '.commit' "$resumed_result")"
resumed_private_repository="$(jq -r '.execution.private_repository_path' "$resumed_result")"
test "$(git -C "$resumed_private_repository" log -1 --format='%an <%ae>' "$resumed_commit")" = \
  "Updated Global User <updated-global-user@example.com>"
test "$(git -C "$resumed_private_repository" log -1 --format='%cn <%ce>' "$resumed_commit")" = \
  "Updated Global User <updated-global-user@example.com>"

git config --global user.name "Global Repository User"
git config --global user.email "global-repository-user@example.com"

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=fail_after_commit \
"$runner" \
  --resume PROJECT-123-environment-attempts \
  "$web_assignment" \
  >/dev/null

test "$(jq -r '.commit' "$resumed_result")" = "$resumed_commit"
test "$(jq -r '.execution.attempt_count' "$resumed_result")" = "3"

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
"$command_bin/rchord" cleanup \
  --project repository-agent-test \
  --run PROJECT-123-environment-attempts \
  --repository web \
  >/dev/null

test ! -e "$failed_resume_worktree"
test "$(git -C "$resumed_private_repository" rev-parse "refs/heads/repochord/PROJECT-123-environment-attempts/web")" = "$resumed_commit"
if git -C "$web_repository" show-ref --verify --quiet "refs/heads/repochord/PROJECT-123-environment-attempts/web"; then
  echo "Cleanup test found a RepoChord feature branch in the source repository." >&2
  exit 1
fi

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=fail_after_commit \
"$runner" \
  --resume PROJECT-123-environment-attempts \
  "$web_assignment" \
  >/dev/null

test "$(jq -r '.commit' "$resumed_result")" = "$resumed_commit"

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  max-attempts 5 \
  >/dev/null

if PATH="$fake_bin:$PATH" FAKE_CODEX_MODE=fail_unchanged "$runner" \
  PROJECT-123-stored-attempts \
  "$web_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly returned success for an incomplete repository agent." >&2
  exit 1
fi

jq -e '
  .status == "failed" and
  .execution.attempt_count == 5 and
  .execution.max_attempts == 5
' "$coordinate_repository/.repochord/results/PROJECT-123-stored-attempts/web.json" >/dev/null

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  max-attempts 3 \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  model stored-model \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  repository-agent-reasoning-effort low \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  max-parallel 1 \
  >/dev/null
