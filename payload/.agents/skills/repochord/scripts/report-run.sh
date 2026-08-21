#!/usr/bin/env bash

set -euo pipefail

export GIT_OPTIONAL_LOCKS=0

usage() {
  echo "Usage: report-run.sh <run-id>" >&2
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

single_line() {
  local result_path="$1"
  local filter="$2"

  jq -r "$filter | gsub(\"[\\u0000-\\u001F\\u007F]\"; \" \")" "$result_path"
}

markdown_code() {
  local value="$1"
  local delimiter='`'

  while [[ "$value" == *"$delimiter"* ]]; do
    delimiter="${delimiter}"'`'
  done

  printf '%s%s%s' "$delimiter" "$value" "$delimiter"
}

display_string_list() {
  local result_path="$1"
  local filter="$2"
  local empty_text="$3"
  local item_count
  local item

  item_count="$(jq "$filter | length" "$result_path")"

  if [[ "$item_count" -eq 0 ]]; then
    printf '    %s\n' "$(markdown_code "$empty_text")"
    return
  fi

  while IFS= read -r item; do
    printf '    - %s\n' "$(markdown_code "$item")"
  done < <(jq -r "${filter}[] | gsub(\"[\\u0000-\\u001F\\u007F]\"; \" \")" "$result_path")
}

inline_string_list() {
  local result_path="$1"
  local filter="$2"
  local empty_text="$3"

  jq -r \
    --arg empty_text "$empty_text" \
    "$filter | if length == 0 then \$empty_text else map(gsub(\"[\\u0000-\\u001F\\u007F]\"; \" \")) | join(\"; \") end" \
    "$result_path"
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

run_id="$1"

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  fail "Report requires a valid run ID." 2
fi

for required_command in cp git jq mktemp mv sed; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    fail "Required command is not installed: $required_command" 2
  fi
done

export GIT_OPTIONAL_LOCKS=0

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
coordinate_root="$(cd -- "$coordinate_root" && pwd -P)"
result_directory="$coordinate_root/.repochord/results/$run_id"
run_manifest="$result_directory/.manifest.json"
task_progress_script="$script_directory/task-progress.sh"

if [[ ! -f "$task_progress_script" ]]; then
  fail "Task progress helper does not exist: $task_progress_script" 2
fi

# shellcheck source-path=SCRIPTDIR
# shellcheck source=task-progress.sh
source "$task_progress_script"

if [[ -L "$result_directory" || ! -d "$result_directory" ]]; then
  fail "Run result directory does not exist or is not a directory: $result_directory" 2
fi

if [[ -L "$run_manifest" || ! -f "$run_manifest" ]]; then
  fail "Run manifest does not exist or is not a regular file: $run_manifest" 2
fi

if ! jq -e \
  --arg run_id "$run_id" \
  '
    type == "object" and
    (keys | sort) == [
      "assignments_file",
      "assignments_hash",
      "feature_id",
      "repositories",
      "request_file",
      "request_hash",
      "run_id",
      "version"
    ] and
    .version == 1 and
    .run_id == $run_id and
    (.feature_id | type == "string") and
    (.feature_id | test("^[A-Za-z0-9._-]+$")) and
    .feature_id != "." and
    .feature_id != ".." and
    (.assignments_file | type == "string") and
    (.assignments_file | startswith("/")) and
    (.assignments_hash | type == "string") and
    (.assignments_hash | test("^[0-9a-f]+$")) and
    (.request_file | type == "string") and
    (.request_file | startswith("/")) and
    (.request_hash | type == "string") and
    (.request_hash | test("^[0-9a-f]+$")) and
    (.repositories | type == "array") and
    (.repositories | length > 0) and
    ([.repositories[].key] | length == (unique | length)) and
    ([.repositories[].path] | length == (unique | length)) and
    all(.repositories[];
      type == "object" and
      (keys | sort) == ["key", "path", "task_file", "task_hash"] and
      (.key | type == "string") and
      (.key | test("^[A-Za-z0-9._-]+$")) and
      .key != "." and
      .key != ".." and
      (.path | type == "string") and
      (.path | startswith("/")) and
      (.path | test("[\\t\\r\\n]") | not) and
      (.task_file | type == "string") and
      (.task_file | startswith("/")) and
      (.task_hash | type == "string") and
      (.task_hash | test("^[0-9a-f]+$"))
    )
  ' \
  "$run_manifest" \
  >/dev/null
then
  fail "Run manifest is invalid: $run_manifest" 2
fi

feature_id="$(jq -r '.feature_id' "$run_manifest")"
repository_keys=()
repository_paths=()
task_files=()
task_hashes=()
result_paths=()
repository_statuses=()
worktree_presence=()
integration_states=()
completed_task_paths=()
completed_task_hashes=()
incomplete_repositories=()
integrated_repositories=()

while IFS=$'\t' read -r repository_key repository_path task_file task_hash; do
  repository_keys+=("$repository_key")
  repository_paths+=("$repository_path")
  task_files+=("$task_file")
  task_hashes+=("$task_hash")
done < <(jq -r '.repositories[] | [.key, .path, .task_file, .task_hash] | @tsv' "$run_manifest")

repository_count="${#repository_keys[@]}"
result_file_count=0

for result_candidate in "$result_directory"/*.json; do
  if [[ ! -e "$result_candidate" ]]; then
    continue
  fi

  result_file_count=$((result_file_count + 1))
  result_key="$(basename -- "$result_candidate")"
  result_key="${result_key%.json}"
  result_is_expected=false

  for repository_key in "${repository_keys[@]}"; do
    if [[ "$result_key" == "$repository_key" ]]; then
      result_is_expected=true
      break
    fi
  done

  if [[ "$result_is_expected" != true ]]; then
    fail "Run result has no matching manifest repository: $result_candidate" 2
  fi
done

if [[ "$result_file_count" -gt "$repository_count" ]]; then
  fail "Run contains more repository results than its manifest: $result_directory" 2
fi

for ((index = 0; index < repository_count; index++)); do
  repository_key="${repository_keys[$index]}"
  repository_path="${repository_paths[$index]}"
  result_path="$result_directory/$repository_key.json"
  expected_worktree_path="$coordinate_root/.repochord/worktrees/$run_id/$repository_key"
  expected_worktree_branch="repochord/$run_id/$repository_key"
  expected_private_repository_path="$coordinate_root/.repochord/repositories/$run_id/$repository_key.git"

  result_paths+=("$result_path")

  if [[ -L "$result_path" ]]; then
    fail "Repository result must not be a symbolic link: $result_path" 2
  fi

  if [[ ! -e "$result_path" ]]; then
    repository_statuses+=("missing")
    worktree_presence+=("unknown")
    integration_states+=("unavailable")
    completed_task_paths+=("unavailable")
    completed_task_hashes+=("unavailable")
    incomplete_repositories+=("$repository_key")
    continue
  fi

  if [[ ! -f "$result_path" ]]; then
    fail "Repository result is not a regular file: $result_path" 2
  fi

  if ! jq -e \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    '
      type == "object" and
      (keys | sort) == [
        "blockers",
        "commit",
        "execution",
        "repository",
        "risks",
        "run_id",
        "status",
        "summary",
        "tests"
      ] and
      .run_id == $run_id and
      .repository == $repository and
      (.status == "completed" or .status == "blocked" or .status == "failed") and
      (.summary | type == "string") and
      (.commit == null or (.commit | type == "string")) and
      (.tests | type == "array") and
      all(.tests[];
        type == "object" and
        (keys | sort) == ["command", "status", "summary"] and
        (.command | type == "string") and
        (.status == "passed" or .status == "failed" or .status == "not_run") and
        (.summary | type == "string")
      ) and
      (.risks | type == "array") and
      all(.risks[]; type == "string") and
      (.blockers | type == "array") and
      all(.blockers[]; type == "string" and length > 0) and
      (.execution | type == "object") and
      ((.execution | keys | sort) == [
        "attempt_count",
        "base_branch",
        "base_commit",
        "head_changed",
        "max_attempts",
        "model",
        "observed_branch",
        "observed_head",
        "profile",
        "reasoning_effort",
        "retry_safe",
        "source_repository_path",
        "starting_branch",
        "starting_commit",
        "usage",
        "worktree_branch",
        "worktree_clean",
        "worktree_path"
      ] or (.execution | keys | sort) == [
        "attempt_count",
        "base_branch",
        "base_commit",
        "head_changed",
        "max_attempts",
        "model",
        "observed_branch",
        "observed_head",
        "private_repository_path",
        "profile",
        "reasoning_effort",
        "retry_safe",
        "source_repository_path",
        "starting_branch",
        "starting_commit",
        "usage",
        "worktree_branch",
        "worktree_clean",
        "worktree_path"
      ]) and
      (.execution.model | type == "string") and
      (.execution.reasoning_effort == null or
        .execution.reasoning_effort == "minimal" or
        .execution.reasoning_effort == "low" or
        .execution.reasoning_effort == "medium" or
        .execution.reasoning_effort == "high" or
        .execution.reasoning_effort == "xhigh") and
      (.execution.profile == null or (.execution.profile | type == "string")) and
      (.execution.source_repository_path == null or (.execution.source_repository_path | type == "string")) and
      (.execution.private_repository_path == null or (.execution.private_repository_path | type == "string")) and
      (.execution.base_branch == null or (.execution.base_branch | type == "string")) and
      (.execution.base_commit == null or (.execution.base_commit | type == "string")) and
      (.execution.worktree_path == null or (.execution.worktree_path | type == "string")) and
      (.execution.worktree_branch == null or (.execution.worktree_branch | type == "string")) and
      (.execution.usage == null or
        ((.execution.usage | type == "object") and
         (.execution.usage | keys | sort) == [
           "cached_input_tokens",
           "input_tokens",
           "output_tokens",
           "reasoning_output_tokens"
         ] and
         all(.execution.usage[]; type == "number" and floor == . and . >= 0))) and
      (.execution.starting_commit == null or (.execution.starting_commit | type == "string")) and
      (.execution.observed_head == null or (.execution.observed_head | type == "string")) and
      (.execution.starting_branch == null or (.execution.starting_branch | type == "string")) and
      (.execution.observed_branch == null or (.execution.observed_branch | type == "string")) and
      (.execution.head_changed | type == "boolean") and
      (.execution.worktree_clean | type == "boolean") and
      (.execution.retry_safe | type == "boolean") and
      (.execution.attempt_count | type == "number") and
      (.execution.attempt_count | floor == .) and
      .execution.attempt_count >= 0 and
      (.execution.max_attempts | type == "number") and
      (.execution.max_attempts | floor == .) and
      .execution.max_attempts >= 1 and
      .execution.attempt_count <= .execution.max_attempts and
      (if .status == "completed" then
        (.commit | type == "string") and
        (.commit | length > 0) and
        (.tests | length > 0) and
        all(.tests[]; .status == "passed") and
        .blockers == [] and
        .execution.head_changed == true and
        .execution.worktree_clean == true
      elif .status == "blocked" then
        .commit == null and
        (.blockers | length > 0)
      else
        .commit == null
      end)
    ' \
    "$result_path" \
    >/dev/null
  then
    fail "Repository result is invalid: $result_path" 2
  fi

  repository_status="$(jq -r '.status' "$result_path")"
  repository_statuses+=("$repository_status")

  if [[ "$repository_status" != "completed" ]]; then
    worktree_presence+=("unknown")
    integration_states+=("unavailable")
    completed_task_paths+=("unavailable")
    completed_task_hashes+=("unavailable")
    incomplete_repositories+=("$repository_key")
    continue
  fi

  if ! jq -e \
    --arg source_repository_path "$repository_path" \
    --arg private_repository_path "$expected_private_repository_path" \
    --arg worktree_path "$expected_worktree_path" \
    --arg worktree_branch "$expected_worktree_branch" \
    '
      .execution.source_repository_path == $source_repository_path and
      ((.execution.private_repository_path // null) == null or
        .execution.private_repository_path == $private_repository_path) and
      (.execution.base_branch | type == "string" and length > 0) and
      (.execution.base_commit | type == "string" and length > 0) and
      .execution.worktree_path == $worktree_path and
      .execution.worktree_branch == $worktree_branch and
      .execution.observed_head == .commit and
      .execution.observed_branch == $worktree_branch
    ' \
    "$result_path" \
    >/dev/null
  then
    fail "Completed repository result is inconsistent: $result_path" 2
  fi

  if [[ ! -d "$repository_path" ||
    "$(git -C "$repository_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$repository_path" ]]
  then
    fail "Completed result repository is unavailable: $repository_path" 2
  fi

  final_commit="$(jq -r '.commit' "$result_path")"
  base_branch="$(jq -r '.execution.base_branch' "$result_path")"
  base_commit="$(jq -r '.execution.base_commit' "$result_path")"
  private_repository_path="$(jq -r '.execution.private_repository_path // empty' "$result_path")"
  artifact_repository_path="$repository_path"

  if [[ -n "$private_repository_path" ]]; then
    if [[ "$private_repository_path" != "$expected_private_repository_path" || \
      -L "$private_repository_path" || \
      ! -d "$private_repository_path" || \
      "$(git -C "$private_repository_path" rev-parse --is-bare-repository 2>/dev/null || true)" != true ]]
    then
      fail "Completed private repository is unavailable: $expected_private_repository_path" 2
    fi

    artifact_repository_path="$private_repository_path"
  fi

  if ! git check-ref-format "refs/heads/$base_branch" >/dev/null 2>&1; then
    fail "Completed result contains an invalid base branch: $base_branch" 2
  fi

  if ! git -C "$repository_path" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    fail "Completed result base commit does not exist in $repository_key: $base_commit" 2
  fi

  if ! git -C "$artifact_repository_path" merge-base --is-ancestor "$base_commit" "$final_commit"; then
    fail "Completed result final commit does not contain its base in $repository_key." 2
  fi

  if [[ -n "$(git -C "$artifact_repository_path" rev-list --merges "$base_commit..$final_commit")" ]]; then
    fail "Completed result contains a merge commit in $repository_key." 2
  fi

  branch_commit="$(git -C "$artifact_repository_path" rev-parse --verify "refs/heads/$expected_worktree_branch^{commit}" 2>/dev/null || true)"

  if [[ "$branch_commit" != "$final_commit" ]]; then
    fail "Completed RepoChord branch no longer matches its result: $expected_worktree_branch" 2
  fi

  current_base_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$base_branch^{commit}" 2>/dev/null || true)"

  if [[ -z "$current_base_commit" ]]; then
    fail "Completed result base branch does not exist in $repository_key: $base_branch" 2
  fi

  if git -C "$repository_path" cat-file -e "$final_commit^{commit}" 2>/dev/null &&
    git -C "$repository_path" merge-base --is-ancestor "$final_commit" "$current_base_commit"
  then
    integration_states+=("integrated")
    integrated_repositories+=("$repository_key")
  elif git -C "$artifact_repository_path" cat-file -e "$current_base_commit^{commit}" 2>/dev/null &&
    git -C "$artifact_repository_path" merge-base --is-ancestor "$base_commit" "$current_base_commit" &&
    git -C "$artifact_repository_path" merge-base --is-ancestor "$current_base_commit" "$final_commit"
  then
    integration_states+=("pending")
  else
    integration_states+=("diverged")
  fi

  if [[ -L "$expected_worktree_path" ]]; then
    fail "Completed RepoChord worktree must not be a symbolic link: $expected_worktree_path" 2
  fi

  if [[ -e "$expected_worktree_path" ]]; then
    if [[ ! -d "$expected_worktree_path" ||
      "$(git -C "$expected_worktree_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$expected_worktree_path" ||
      "$(git -C "$expected_worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$expected_worktree_branch" ||
      "$(git -C "$expected_worktree_path" rev-parse --verify HEAD 2>/dev/null || true)" != "$final_commit" ||
      -n "$(git -c core.fsmonitor=false -C "$expected_worktree_path" status --porcelain --untracked-files=all 2>/dev/null || true)" ]]
    then
      fail "Completed RepoChord worktree no longer matches its result: $expected_worktree_path" 2
    fi

    worktree_presence+=("yes")
  else
    worktree_presence+=("no")
  fi

  if ! completed_task_path="$(repochord_render_completed_task \
    "$coordinate_root" \
    "$result_directory" \
    "$repository_key" \
    "${task_files[$index]}" \
    "${task_hashes[$index]}")"
  then
    fail "Could not create the completed task view for $repository_key." 2
  fi

  completed_task_paths+=("$completed_task_path")
  completed_task_hashes+=("$(git -C "$coordinate_root" hash-object -- "$completed_task_path")")
done

if [[ "${#incomplete_repositories[@]}" -eq 0 ]]; then
  overall_status="completed"
else
  overall_status="incomplete"
fi

if [[ "${#integrated_repositories[@]}" -eq 0 ]]; then
  integrated_list="none"
else
  integrated_list=""

  for repository_key in "${integrated_repositories[@]}"; do
    if [[ -n "$integrated_list" ]]; then
      integrated_list+=", "
    fi

    integrated_list+="$repository_key"
  done
fi

if [[ "$overall_status" == "completed" ]]; then
  incomplete_list="none"
else
  incomplete_list=""

  for repository_key in "${incomplete_repositories[@]}"; do
    if [[ -n "$incomplete_list" ]]; then
      incomplete_list+=", "
    fi

    incomplete_list+="$repository_key"
  done
fi

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

report_path="$result_directory/report.md"

if [[ -L "$report_path" || ( -e "$report_path" && ! -f "$report_path" ) ]]; then
  fail "Complete report path is not a regular file: $report_path" 2
fi

report_stage="$(mktemp "$result_directory/.report.XXXXXX")"

# shellcheck disable=SC2329
cleanup_report_stage() {
  if [[ -n "$report_stage" && -e "$report_stage" ]]; then
    rm -f "$report_stage"
  fi
}

trap cleanup_report_stage EXIT
write_complete_report >"$report_stage"
mv "$report_stage" "$report_path"
report_stage=""

echo "RepoChord run: $overall_status"
echo "Feature: $feature_id"
echo "Run: $run_id"
echo "Pushed: no | Incomplete: $incomplete_list"

for ((index = 0; index < repository_count; index++)); do
  repository_key="${repository_keys[$index]}"
  result_path="${result_paths[$index]}"
  repository_status="${repository_statuses[$index]}"

  if [[ "$repository_status" == "missing" ]]; then
    echo "$repository_key: missing | commit unavailable | blockers result missing"
    echo "  Tokens: unavailable"
    continue
  fi

  commit="$(jq -r '.commit // "unavailable"' "$result_path")"
  integration_state="${integration_states[$index]}"
  blockers="$(inline_string_list "$result_path" '.blockers' 'none')"
  echo "$repository_key: $repository_status | commit $commit | integration $integration_state | blockers $blockers"

  if jq -e '.execution.usage == null' "$result_path" >/dev/null; then
    echo "  Tokens: unavailable"
  else
    input_tokens="$(jq -r '.execution.usage.input_tokens' "$result_path")"
    cached_input_tokens="$(jq -r '.execution.usage.cached_input_tokens' "$result_path")"
    output_tokens="$(jq -r '.execution.usage.output_tokens' "$result_path")"
    reasoning_output_tokens="$(jq -r '.execution.usage.reasoning_output_tokens' "$result_path")"
    echo "  Tokens: input $input_tokens | cached input $cached_input_tokens | output $output_tokens | reasoning output $reasoning_output_tokens"
  fi
done

echo "Complete report: $report_path"

if [[ "$overall_status" == "completed" ]]; then
  echo "Next: rchord integrate --run $run_id --dry-run"
  echo "Then: rchord integrate --run $run_id"
  exit 0
fi

exit 1
