#!/usr/bin/env bash

# Generated from src/test-scripts by scripts/build-test-scripts.sh.
# Do not edit this test in tests directly.

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/repochord-repository-agent-test.XXXXXX")"
temporary_root="$(cd -- "$temporary_root" && pwd -P)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_product_repository() {
  local repository_path="$1"
  local repository_name="$2"

  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Repository Agent Test"
  git -C "$repository_path" config user.email "repository-agent-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null

  if [[ "$repository_name" == "api" ]]; then
    git -C "$repository_path" branch -M main
  else
    git -C "$repository_path" branch -M master
  fi
}

api_repository="$temporary_root/api"
web_repository="$temporary_root/web"
empty_repository="$temporary_root/empty"
coordinate_repository="$temporary_root/control"
fake_bin="$temporary_root/bin"
capture_directory="$temporary_root/captures"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"

initialize_product_repository "$api_repository" api
initialize_product_repository "$web_repository" web
git init -q "$empty_repository"

mkdir -p "$test_home"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOCHORD_CONFIG_HOME REPOCHORD_DATA_HOME

git config --global user.name "Global Repository User"
git config --global user.email "global-repository-user@example.com"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" init \
  -p repository-agent-test \
  -c "$coordinate_repository" \
  --create-coordinate \
  -r "api=$api_repository" \
  -r "web=$web_repository" \
  >/dev/null

scaffolder="$coordinate_repository/.agents/skills/repochord/scripts/scaffold-feature.sh"
runner="$coordinate_repository/.agents/skills/repochord/scripts/run-repository-agents.sh"
repository_agent="$coordinate_repository/.agents/skills/repochord/scripts/run-repository-agent.sh"
packet_fixture="$test_directory/fixtures/complete-scaffolded-packet.sh"

api_base_commit="$(git -C "$api_repository" rev-parse HEAD)"
web_base_commit="$(git -C "$web_repository" rev-parse HEAD)"
api_base_branch="$(git -C "$api_repository" symbolic-ref --short HEAD)"
web_base_branch="$(git -C "$web_repository" symbolic-ref --short HEAD)"
post_commit_marker="$temporary_root/post-commit-hook-ran"

for product_repository in "$api_repository" "$web_repository"; do
  for hook_name in post-checkout post-commit reference-transaction; do
    printf '#!/bin/sh\n: > "%s"\n' "$post_commit_marker" > "$product_repository/.git/hooks/$hook_name"
    chmod +x "$product_repository/.git/hooks/$hook_name"
  done
done

"$scaffolder" PROJECT-123 api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-123

assignments_file="$coordinate_repository/tasks/PROJECT-123/assignments.txt"
api_assignment="$temporary_root/api-assignment.txt"
web_assignment="$temporary_root/web-assignment.txt"

sed -n '1p' "$assignments_file" > "$api_assignment"
sed -n '2p' "$assignments_file" > "$web_assignment"

mkdir -p "$fake_bin" "$capture_directory"
cp "$test_directory/fixtures/fake-codex.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"
export FAKE_ABSOLUTE_GIT
FAKE_ABSOLUTE_GIT="$(command -v git)"

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

  expected_user_name="Global Repository User"
  expected_user_email="global-repository-user@example.com"

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
  test "$(git -C "$expected_worktree" log -1 --format='%an <%ae>')" = \
    "$expected_user_name <$expected_user_email>"
  test "$(git -C "$expected_worktree" log -1 --format='%cn <%ce>')" = \
    "$expected_user_name <$expected_user_email>"
  if git --git-dir="$expected_private_repository" config --local --get user.name >/dev/null || \
    git --git-dir="$expected_private_repository" config --local --get user.email >/dev/null
  then
    echo "RepoChord wrote identity settings into its private repository." >&2
    exit 1
  fi
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

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$runner" \
  PROJECT-123-stored-settings \
  "$web_assignment" \
  >/dev/null

jq -e '
  .status == "completed" and
  .execution.model == "stored-model" and
  .execution.reasoning_effort == "low"
' "$coordinate_repository/.repochord/results/PROJECT-123-stored-settings/web.json" >/dev/null

printf 'staged source change\n' >> "$web_repository/README.md"
git -C "$web_repository" add README.md
printf 'unstaged source change\n' >> "$web_repository/README.md"
printf 'untracked source change\n' > "$web_repository/local-source-change.txt"
dirty_source_status="$(git -C "$web_repository" status --porcelain=v1 --untracked-files=all)"
dirty_source_index_diff="$(git -C "$web_repository" diff --cached)"
dirty_source_worktree_diff="$(git -C "$web_repository" diff)"
allow_dirty_warning="$temporary_root/allow-dirty-warning.txt"

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$runner" \
  --allow-dirty-source \
  PROJECT-123-allow-dirty-source \
  "$web_assignment" \
  >/dev/null \
  2> "$allow_dirty_warning"

allow_dirty_result="$coordinate_repository/.repochord/results/PROJECT-123-allow-dirty-source/web.json"
allow_dirty_worktree="$(jq -r '.execution.worktree_path' "$allow_dirty_result")"

jq -e \
  --arg base_commit "$web_base_commit" \
  '.status == "completed" and .execution.base_commit == $base_commit' \
  "$allow_dirty_result" \
  >/dev/null
grep -Fqx \
  "Warning: uncommitted changes are excluded from this run: $web_repository" \
  "$allow_dirty_warning"
test "$(git -C "$web_repository" status --porcelain=v1 --untracked-files=all)" = "$dirty_source_status"
test "$(git -C "$web_repository" diff --cached)" = "$dirty_source_index_diff"
test "$(git -C "$web_repository" diff)" = "$dirty_source_worktree_diff"
test "$(git -C "$web_repository" rev-parse HEAD)" = "$web_base_commit"
test "$(git -C "$allow_dirty_worktree" show HEAD:README.md)" = "$(git -C "$web_repository" show "$web_base_commit:README.md")"
test ! -e "$allow_dirty_worktree/local-source-change.txt"

git -C "$web_repository" restore --staged README.md
git -C "$web_repository" restore README.md
rm -f -- "$web_repository/local-source-change.txt"

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT=medium \
"$runner" \
  PROJECT-123-environment-reasoning \
  "$web_assignment" \
  >/dev/null

jq -e '
  .status == "completed" and
  .execution.reasoning_effort == "medium"
' "$coordinate_repository/.repochord/results/PROJECT-123-environment-reasoning/web.json" >/dev/null

if PATH="$fake_bin:$PATH" \
  REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT=impossible \
  "$runner" \
    PROJECT-123-invalid-environment-reasoning \
    "$web_assignment" \
    >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted an invalid environment reasoning effort." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-invalid-environment-reasoning"

if PATH="$fake_bin:$PATH" \
  REPOCHORD_ALLOW_DIRTY_SOURCE=invalid \
  "$runner" \
    PROJECT-123-invalid-allow-dirty-source \
    "$web_assignment" \
    >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted an invalid dirty-source setting." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-invalid-allow-dirty-source"

if PATH="$fake_bin:$PATH" \
  REPOCHORD_MAX_PARALLEL=0 \
  "$runner" \
    PROJECT-123-invalid-environment-parallel \
    "$web_assignment" \
    >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted an invalid environment concurrency limit." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-invalid-environment-parallel"

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  model gpt-5.6-terra \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  repository-agent-reasoning-effort high \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" config set \
  --project repository-agent-test \
  max-parallel 2 \
  >/dev/null

if PATH="$fake_bin:$PATH" FAKE_CODEX_MODE=guarded_git_operations "$runner" \
  --max-attempts 1 \
  PROJECT-123-guarded-git \
  "$web_assignment" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly returned success for guarded Git operations." >&2
  exit 1
fi

jq -e '
  .status == "failed" and
  .execution.attempt_count == 1 and
  .execution.head_changed == false and
  .execution.worktree_clean == true
' "$coordinate_repository/.repochord/results/PROJECT-123-guarded-git/web.json" >/dev/null

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
