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
