#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: integrate-run.sh [--dry-run] [--show-diffs] <run-id>" >&2
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

validate_safe_text() {
  local value="$1"
  local label="$2"

  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" == *$'\t'* ]]; then
    fail "$label contains an unsupported tab or newline: $value" 2
  fi
}

operation_in_progress() {
  local repository_path="$1"
  local operation_path
  local operation_name

  for operation_name in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-apply rebase-merge; do
    operation_path="$(git -C "$repository_path" rev-parse --git-path "$operation_name")"

    if [[ -e "$operation_path" ]]; then
      return 0
    fi
  done

  return 1
}

find_branch_worktree() {
  local repository_path="$1"
  local branch_name="$2"
  local current_worktree=""
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "worktree "*)
        current_worktree="${line#worktree }"
        ;;
      "branch refs/heads/$branch_name")
        printf '%s\n' "$current_worktree"
        return 0
        ;;
      "")
        current_worktree=""
        ;;
    esac
  done < <(git -C "$repository_path" worktree list --porcelain)

  return 1
}

validate_checkout_collisions() {
  local checkout_path="$1"
  local current_commit="$2"
  local final_commit="$3"
  local changed_path

  while IFS= read -r -d '' changed_path; do
    if [[ -e "$checkout_path/$changed_path" || -L "$checkout_path/$changed_path" ]] &&
      ! git -C "$checkout_path" ls-files --error-unmatch -- "$changed_path" >/dev/null 2>&1
    then
      fail "An untracked or ignored path would be overwritten during integration: $checkout_path/$changed_path"
    fi
  done < <(git -C "$checkout_path" diff \
    --no-ext-diff \
    --no-textconv \
    --name-only \
    -z \
    "$current_commit..$final_commit")
}

dry_run=false
show_diffs=false
run_id=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --show-diffs)
      show_diffs=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "Unknown integration argument: $1" 2
      ;;
    *)
      if [[ -n "$run_id" ]]; then
        usage
        exit 2
      fi

      run_id="$1"
      shift
      ;;
  esac
done

if [[ -z "$run_id" || \
  ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || \
  "$run_id" == "." || \
  "$run_id" == ".." ]]
then
  fail "Integration requires a valid run ID." 2
fi

for required_command in git jq mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    fail "Required command is not installed: $required_command" 2
  fi
done

export GIT_OPTIONAL_LOCKS=0

empty_hooks_directory=""

cleanup() {
  if [[ -n "$empty_hooks_directory" ]]; then
    rm -rf -- "$empty_hooks_directory"
  fi
}

trap cleanup EXIT

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skill_directory="$(cd -- "$script_directory/.." && pwd -P)"
coordinate_root="$(git -C "$skill_directory" rev-parse --show-toplevel)"
coordinate_root="$(cd -- "$coordinate_root" && pwd -P)"
registry_path="$coordinate_root/.repomux/repositories.json"
result_directory="$coordinate_root/.repomux/results/$run_id"
run_manifest="$result_directory/.manifest.json"

if [[ -L "$result_directory" || ! -d "$result_directory" ]]; then
  fail "Run result directory does not exist or is not a directory: $result_directory" 2
fi

if [[ -L "$run_manifest" || ! -f "$run_manifest" ]]; then
  fail "Run manifest does not exist or is not a regular file: $run_manifest" 2
fi

if [[ -L "$registry_path" || ! -f "$registry_path" ]]; then
  fail "Repository registry does not exist or is not a regular file: $registry_path" 2
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
    (.assignments_file | type == "string") and
    (.assignments_file | startswith("/")) and
    (.assignments_file | test("[\\t\\r\\n]") | not) and
    (.assignments_hash | type == "string") and
    (.assignments_hash | test("^[0-9a-f]+$")) and
    (.request_file | type == "string") and
    (.request_file | startswith("/")) and
    (.request_file | test("[\\t\\r\\n]") | not) and
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
      (.path | type == "string") and
      (.path | startswith("/")) and
      (.path | test("[\\t\\r\\n]") | not) and
      (.task_file | type == "string") and
      (.task_file | startswith("/")) and
      (.task_file | test("[\\t\\r\\n]") | not) and
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

if [[ ! "$feature_id" =~ ^[A-Za-z0-9._-]+$ || \
  "$feature_id" == "." || \
  "$feature_id" == ".." ]]
then
  fail "Run manifest contains an invalid feature ID: $feature_id" 2
fi

assignments_file="$(jq -r '.assignments_file' "$run_manifest")"
assignments_hash="$(jq -r '.assignments_hash' "$run_manifest")"
request_file="$(jq -r '.request_file' "$run_manifest")"
request_hash="$(jq -r '.request_hash' "$run_manifest")"
expected_assignments_file="$coordinate_root/tasks/$feature_id/assignments.txt"
expected_request_file="$coordinate_root/requests/$feature_id.md"

if [[ "$assignments_file" != "$expected_assignments_file" ]]; then
  fail "Run did not use the feature assignments file: $expected_assignments_file" 2
fi

if [[ "$request_file" != "$expected_request_file" ]]; then
  fail "Run manifest request path does not match its feature: $request_file" 2
fi

for run_document in "$request_file" "$assignments_file"; do
  if [[ -L "$run_document" || ! -f "$run_document" ]]; then
    fail "Run document does not exist or is not a regular file: $run_document" 2
  fi
done

if [[ "$(git -C "$coordinate_root" hash-object -- "$request_file")" != "$request_hash" ]]; then
  fail "Feature request changed after the run started: $request_file"
fi

if [[ "$(git -C "$coordinate_root" hash-object -- "$assignments_file")" != "$assignments_hash" ]]; then
  fail "Feature assignments changed after the run started: $assignments_file"
fi

if ! jq -e '
  .version == 1 and
  (.repositories | type == "array") and
  (.repositories | length > 0) and
  ([.repositories[].key] | length == (unique | length)) and
  ([.repositories[].path] | length == (unique | length))
' "$registry_path" >/dev/null
then
  fail "Repository registry is invalid: $registry_path" 2
fi

repository_keys=()
repository_paths=()
task_files=()
task_hashes=()

while IFS=$'\t' read -r repository_key repository_path task_file task_hash; do
  validate_safe_text "$repository_key" "Repository key"
  validate_safe_text "$repository_path" "Repository path"
  validate_safe_text "$task_file" "Task file"

  if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ]] ||
    ! git check-ref-format "refs/heads/repomux/validation/$repository_key" >/dev/null 2>&1
  then
    fail "Run manifest contains an invalid repository key: $repository_key" 2
  fi

  expected_task_file="$coordinate_root/tasks/$feature_id/$repository_key.md"

  if [[ "$task_file" != "$expected_task_file" ]]; then
    fail "Run manifest task path does not match its repository: $task_file" 2
  fi

  if [[ -L "$task_file" || ! -f "$task_file" ]]; then
    fail "Repository task does not exist or is not a regular file: $task_file" 2
  fi

  if [[ "$(git -C "$coordinate_root" hash-object -- "$task_file")" != "$task_hash" ]]; then
    fail "Repository task changed after the run started: $task_file"
  fi

  registered_path="$(jq -r --arg key "$repository_key" '
    [.repositories[] | select(.key == $key)] |
    if length == 1 then .[0].path else "" end
  ' "$registry_path")"

  if [[ -z "$registered_path" || "$registered_path" != "$repository_path" ]]; then
    fail "Run repository does not match the project registry: $repository_key" 2
  fi

  if [[ ! -d "$repository_path" ]]; then
    fail "Run repository does not exist: $repository_path" 2
  fi

  canonical_repository_path="$(cd -- "$repository_path" && pwd -P)"

  if [[ "$canonical_repository_path" != "$repository_path" || \
    "$(git -C "$repository_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$repository_path" ]]
  then
    fail "Run repository is not a canonical Git repository root: $repository_path" 2
  fi

  repository_keys+=("$repository_key")
  repository_paths+=("$repository_path")
  task_files+=("$task_file")
  task_hashes+=("$task_hash")
done < <(jq -r '.repositories[] | [.key, .path, .task_file, .task_hash] | @tsv' "$run_manifest")

repository_count="${#repository_keys[@]}"

if [[ "$repository_count" -eq 0 ]]; then
  fail "Run manifest contains no repositories: $run_manifest" 2
fi

assignment_index=0
assignment_line_number=0

while IFS='|' read -r assigned_key assigned_path assigned_task assigned_extra || \
  [[ -n "${assigned_key}${assigned_path}${assigned_task}${assigned_extra}" ]]
do
  assignment_line_number=$((assignment_line_number + 1))

  if [[ -z "${assigned_key}${assigned_path}${assigned_task}${assigned_extra}" || "$assigned_key" == \#* ]]; then
    continue
  fi

  if [[ "$assignment_index" -ge "$repository_count" || \
    -n "$assigned_extra" || \
    "$assigned_key" != "${repository_keys[$assignment_index]}" || \
    "$assigned_path" != "${repository_paths[$assignment_index]}" || \
    "$assigned_task" != "${task_files[$assignment_index]}" ]]
  then
    fail "Feature assignments do not match the run manifest at line: $assignment_line_number" 2
  fi

  assignment_index=$((assignment_index + 1))
done < "$assignments_file"

if [[ "$assignment_index" -ne "$repository_count" ]]; then
  fail "Feature assignments do not contain every run repository: $assignments_file" 2
fi

run_manifest_hash="$(git -C "$coordinate_root" hash-object -- "$run_manifest")"

validate_recorded_run_files() {
  local index
  local run_document

  for run_document in "$run_manifest" "$request_file" "$assignments_file" "${task_files[@]}"; do
    if [[ -L "$run_document" || ! -f "$run_document" ]]; then
      fail "Run file changed or disappeared during integration: $run_document"
    fi
  done

  if [[ "$(git -C "$coordinate_root" hash-object -- "$run_manifest")" != "$run_manifest_hash" ]]; then
    fail "Run manifest changed during integration: $run_manifest"
  fi

  if [[ "$(git -C "$coordinate_root" hash-object -- "$request_file")" != "$request_hash" ]]; then
    fail "Feature request changed after the run started: $request_file"
  fi

  if [[ "$(git -C "$coordinate_root" hash-object -- "$assignments_file")" != "$assignments_hash" ]]; then
    fail "Feature assignments changed after the run started: $assignments_file"
  fi

  for ((index = 0; index < repository_count; index++)); do
    if [[ "$(git -C "$coordinate_root" hash-object -- "${task_files[$index]}")" != "${task_hashes[$index]}" ]]; then
      fail "Repository task changed after the run started: ${task_files[$index]}"
    fi
  done
}

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

if [[ "$result_file_count" -ne "$repository_count" ]]; then
  fail "Run does not contain one result for every repository: $result_directory"
fi

document_relative_paths=(
  "requests/$feature_id.md"
  "tasks/$feature_id/assignments.txt"
)

for task_file in "${task_files[@]}"; do
  document_relative_paths+=("${task_file#"$coordinate_root/"}")
done

result_paths=()
result_hashes=()
base_branches=()
base_commits=()
final_commits=()
worktree_branches=()
base_current_commits=()
base_checkout_paths=()
integration_states=()
documents_pending=false
document_status=""
coordinate_branch=""

preflight_integration() {
  local index
  local repository_key
  local repository_path
  local result_path
  local expected_worktree_path
  local expected_worktree_branch
  local base_branch
  local base_commit
  local final_commit
  local branch_commit
  local current_base_commit
  local base_checkout_path
  local integration_state
  local relative_path

  result_paths=()
  result_hashes=()
  base_branches=()
  base_commits=()
  final_commits=()
  worktree_branches=()
  base_current_commits=()
  base_checkout_paths=()
  integration_states=()
  validate_recorded_run_files
  documents_pending=false
  coordinate_branch=""
  document_status="$(git -c core.fsmonitor=false \
    -C "$coordinate_root" status --short --untracked-files=all -- "${document_relative_paths[@]}")"

  if [[ -n "$document_status" ]]; then
    documents_pending=true

    if operation_in_progress "$coordinate_root"; then
      fail "The coordination repository has a Git operation in progress: $coordinate_root"
    fi

    if ! coordinate_branch="$(git -C "$coordinate_root" symbolic-ref --quiet --short HEAD)"; then
      fail "The coordination repository must be on a branch before feature documents can be committed: $coordinate_root"
    fi

    for relative_path in "${document_relative_paths[@]}"; do
      if ! git -C "$coordinate_root" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1 &&
        git -C "$coordinate_root" check-ignore -q -- "$relative_path"
      then
        fail "Feature document is ignored by Git: $coordinate_root/$relative_path"
      fi
    done
  fi

  for ((index = 0; index < repository_count; index++)); do
    repository_key="${repository_keys[$index]}"
    repository_path="${repository_paths[$index]}"
    result_path="$result_directory/$repository_key.json"
    expected_worktree_path="$coordinate_root/.repomux/worktrees/$run_id/$repository_key"
    expected_worktree_branch="repomux/$run_id/$repository_key"

    if [[ -L "$result_path" || ! -f "$result_path" ]]; then
      fail "Repository result does not exist or is not a regular file: $result_path"
    fi

    if ! jq -e \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      --arg source_repository_path "$repository_path" \
      --arg worktree_path "$expected_worktree_path" \
      --arg worktree_branch "$expected_worktree_branch" \
      '
        type == "object" and
        .run_id == $run_id and
        .repository == $repository and
        .status == "completed" and
        (.summary | type == "string") and
        (.commit | type == "string") and
        (.commit | length > 0) and
        (.tests | type == "array") and
        (.tests | length > 0) and
        all(.tests[];
          type == "object" and
          (.command | type == "string") and
          .status == "passed" and
          (.summary | type == "string")
        ) and
        (.risks | type == "array") and
        all(.risks[]; type == "string") and
        .blockers == [] and
        (.execution | type == "object") and
        .execution.source_repository_path == $source_repository_path and
        (.execution.base_branch | type == "string") and
        (.execution.base_branch | length > 0) and
        (.execution.base_commit | type == "string") and
        (.execution.base_commit | length > 0) and
        .execution.worktree_path == $worktree_path and
        .execution.worktree_branch == $worktree_branch and
        .execution.observed_head == .commit and
        .execution.observed_branch == $worktree_branch and
        .execution.head_changed == true and
        .execution.worktree_clean == true
      ' \
      "$result_path" \
      >/dev/null
    then
      fail "Repository result is incomplete or invalid: $result_path"
    fi

    base_branch="$(jq -r '.execution.base_branch' "$result_path")"
    base_commit="$(jq -r '.execution.base_commit' "$result_path")"
    final_commit="$(jq -r '.commit' "$result_path")"

    if ! git check-ref-format "refs/heads/$base_branch" >/dev/null 2>&1; then
      fail "Repository result contains an invalid base branch: $base_branch" 2
    fi

    if ! git -C "$repository_path" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
      fail "Recorded base commit does not exist in $repository_key: $base_commit"
    fi

    if ! git -C "$repository_path" cat-file -e "$final_commit^{commit}" 2>/dev/null; then
      fail "Recorded final commit does not exist in $repository_key: $final_commit"
    fi

    if ! branch_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$expected_worktree_branch^{commit}" 2>/dev/null)"; then
      fail "RepoMux branch does not exist in $repository_key: $expected_worktree_branch"
    fi

    if [[ "$branch_commit" != "$final_commit" ]]; then
      fail "RepoMux branch changed after completion in $repository_key: $expected_worktree_branch"
    fi

    if ! current_base_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$base_branch^{commit}" 2>/dev/null)"; then
      fail "Recorded base branch does not exist in $repository_key: $base_branch"
    fi

    if ! git -C "$repository_path" merge-base --is-ancestor "$base_commit" "$final_commit"; then
      fail "Final commit does not contain the recorded base commit in $repository_key."
    fi

    if git -C "$repository_path" merge-base --is-ancestor "$final_commit" "$current_base_commit"; then
      integration_state="integrated"
    elif git -C "$repository_path" merge-base --is-ancestor "$base_commit" "$current_base_commit" &&
      git -C "$repository_path" merge-base --is-ancestor "$current_base_commit" "$final_commit"
    then
      integration_state="pending"
    else
      fail "Base branch diverged or moved behind its recorded base in $repository_key: $base_branch"
    fi

    base_checkout_path=""

    if base_checkout_path="$(find_branch_worktree "$repository_path" "$base_branch")" &&
      [[ "$integration_state" == "pending" ]]
    then
      if [[ -z "$base_checkout_path" || ! -d "$base_checkout_path" ]]; then
        fail "Git reported an invalid checkout for $repository_key base branch: $base_branch"
      fi

      if [[ -n "$(git -c core.fsmonitor=false \
        -C "$base_checkout_path" status --porcelain --untracked-files=all)" ]]
      then
        fail "Base branch checkout is not clean in $repository_key: $base_checkout_path"
      fi

      if operation_in_progress "$base_checkout_path"; then
        fail "Base branch checkout has a Git operation in progress: $base_checkout_path"
      fi

      validate_checkout_collisions "$base_checkout_path" "$current_base_commit" "$final_commit"
    fi

    if [[ -e "$expected_worktree_path" ]]; then
      if [[ -L "$expected_worktree_path" || ! -d "$expected_worktree_path" ||
        "$(git -C "$expected_worktree_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$expected_worktree_path" ||
        "$(git -C "$expected_worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$expected_worktree_branch" ||
        "$(git -C "$expected_worktree_path" rev-parse --verify HEAD 2>/dev/null || true)" != "$final_commit" ||
        -n "$(git -c core.fsmonitor=false \
          -C "$expected_worktree_path" status --porcelain --untracked-files=all 2>/dev/null || true)" ]]
      then
        fail "RepoMux worktree no longer matches its completed result: $expected_worktree_path"
      fi
    fi

    result_paths+=("$result_path")
    result_hashes+=("$(git -C "$coordinate_root" hash-object -- "$result_path")")
    base_branches+=("$base_branch")
    base_commits+=("$base_commit")
    final_commits+=("$final_commit")
    worktree_branches+=("$expected_worktree_branch")
    base_current_commits+=("$current_base_commit")
    base_checkout_paths+=("$base_checkout_path")
    integration_states+=("$integration_state")
  done
}

display_plan() {
  local index
  local pending_base_commit
  local result_summary

  echo "Integration preflight passed."
  echo "Run: $run_id"
  echo "Feature: $feature_id"
  echo "Coordination documents:"
  printf '  %s\n' "${document_relative_paths[@]}"

  if [[ "$documents_pending" == true ]]; then
    echo "Coordination document action: will commit"
    echo "Coordination branch: $coordinate_branch"
    printf '%s\n' "$document_status"
  else
    echo "Coordination document action: already committed"
  fi

  for ((index = 0; index < repository_count; index++)); do
    echo
    echo "Repository: ${repository_keys[$index]}"
    echo "  Path: ${repository_paths[$index]}"
    echo "  Base: ${base_branches[$index]} ${base_current_commits[$index]}"
    echo "  RepoMux branch: ${worktree_branches[$index]}"
    echo "  Final commit: ${final_commits[$index]}"
    echo "  Integration: ${integration_states[$index]}"
    result_summary="$(jq -c '{summary, tests, risks}' "${result_paths[$index]}")"
    echo "  Result: $result_summary"
    echo "  Change summary:"
    pending_base_commit="${base_commits[$index]}"

    if [[ "${integration_states[$index]}" == "pending" ]]; then
      pending_base_commit="${base_current_commits[$index]}"
    fi

    git -C "${repository_paths[$index]}" diff --no-ext-diff --no-textconv --stat \
      "$pending_base_commit..${final_commits[$index]}"

    if [[ "$show_diffs" == true ]]; then
      if [[ "${integration_states[$index]}" == "pending" ]]; then
        echo
        echo "  Diff:"
        git -C "${repository_paths[$index]}" diff \
          "${base_current_commits[$index]}..${final_commits[$index]}"
      else
        echo "  Diff: none - already integrated"
      fi
    fi
  done
}

preflight_integration
display_plan

pending_repository_count=0

for integration_state in "${integration_states[@]}"; do
  if [[ "$integration_state" == "pending" ]]; then
    pending_repository_count=$((pending_repository_count + 1))
  fi
done

if [[ "$dry_run" == true ]]; then
  echo
  echo "Dry run complete. No changes were made."
  exit 0
fi

if [[ "$documents_pending" != true && "$pending_repository_count" -eq 0 ]]; then
  echo
  echo "This run is already integrated. No changes were made."
  exit 0
fi

echo
printf 'Commit the feature documents and fast-forward %s repository branch(es)? [y/N] ' "$pending_repository_count"
confirmation=""
IFS= read -r confirmation || true

case "$confirmation" in
  y|Y|yes|YES|Yes)
    ;;
  *)
    echo "Integration cancelled. No changes were made."
    exit 1
    ;;
esac

# State can change while the confirmation prompt is open.
confirmed_documents_pending="$documents_pending"
confirmed_document_status="$document_status"
confirmed_coordinate_branch="$coordinate_branch"
confirmed_result_hashes=("${result_hashes[@]}")
confirmed_base_branches=("${base_branches[@]}")
confirmed_base_current_commits=("${base_current_commits[@]}")
confirmed_final_commits=("${final_commits[@]}")
confirmed_base_checkout_paths=("${base_checkout_paths[@]}")
confirmed_integration_states=("${integration_states[@]}")
preflight_integration

if [[ "$documents_pending" != "$confirmed_documents_pending" || \
  "$document_status" != "$confirmed_document_status" || \
  "$coordinate_branch" != "$confirmed_coordinate_branch" ]]
then
  fail "The integration plan changed while confirmation was pending. No changes were made. Run the command again."
fi

for ((index = 0; index < repository_count; index++)); do
  if [[ "${result_hashes[$index]}" != "${confirmed_result_hashes[$index]}" || \
    "${base_branches[$index]}" != "${confirmed_base_branches[$index]}" || \
    "${base_current_commits[$index]}" != "${confirmed_base_current_commits[$index]}" || \
    "${final_commits[$index]}" != "${confirmed_final_commits[$index]}" || \
    "${base_checkout_paths[$index]}" != "${confirmed_base_checkout_paths[$index]}" || \
    "${integration_states[$index]}" != "${confirmed_integration_states[$index]}" ]]
  then
    fail "The integration plan changed while confirmation was pending. No changes were made. Run the command again."
  fi
done

empty_hooks_directory="$(mktemp -d "${TMPDIR:-/tmp}/repomux-integration-hooks.XXXXXX")"

if [[ "$documents_pending" == true ]]; then
  if ! git -c core.hooksPath="$empty_hooks_directory" \
    -C "$coordinate_root" add -- "${document_relative_paths[@]}"
  then
    fail "Feature documents could not be staged. No product branches were changed."
  fi

  if ! git -c core.hooksPath="$empty_hooks_directory" \
    -C "$coordinate_root" commit \
    --quiet \
    --only \
    -m "docs: record $feature_id" \
    -- \
    "${document_relative_paths[@]}"
  then
    fail "Feature document commit failed. No product branches were changed."
  fi

  if [[ -n "$(git -c core.fsmonitor=false \
    -C "$coordinate_root" status --short --untracked-files=all -- "${document_relative_paths[@]}")" ]]
  then
    fail "Feature documents changed during their commit. No product branches were changed."
  fi

  echo "Committed feature documents: $(git -C "$coordinate_root" rev-parse HEAD)"
fi

integrated_repository_count=0

for ((index = 0; index < repository_count; index++)); do
  if [[ "${integration_states[$index]}" == "integrated" ]]; then
    echo "Already integrated: ${repository_keys[$index]}"
    continue
  fi

  repository_key="${repository_keys[$index]}"
  repository_path="${repository_paths[$index]}"
  base_branch="${base_branches[$index]}"
  expected_current_commit="${base_current_commits[$index]}"
  final_commit="${final_commits[$index]}"
  current_base_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$base_branch^{commit}")"

  if [[ -L "${result_paths[$index]}" || ! -f "${result_paths[$index]}" ]]; then
    fail "Integration stopped after $integrated_repository_count repository branch(es). The result disappeared in $repository_key. Re-run the same command after review."
  fi

  if [[ "$(git -C "$coordinate_root" hash-object -- "${result_paths[$index]}")" != "${result_hashes[$index]}" ]]; then
    fail "Integration stopped after $integrated_repository_count repository branch(es). The result changed in $repository_key. Re-run the same command after review."
  fi

  if [[ "$current_base_commit" != "$expected_current_commit" ]]; then
    fail "Integration stopped after $integrated_repository_count repository branch(es). The base branch changed in $repository_key. Re-run the same command after review."
  fi

  base_checkout_path=""

  if base_checkout_path="$(find_branch_worktree "$repository_path" "$base_branch")"; then
    if operation_in_progress "$base_checkout_path"; then
      fail "Integration stopped after $integrated_repository_count repository branch(es). A Git operation started in $repository_key. Re-run the same command after review."
    fi

    if [[ -n "$(git -c core.fsmonitor=false \
      -C "$base_checkout_path" status --porcelain --untracked-files=all)" ]]
    then
      fail "Integration stopped after $integrated_repository_count repository branch(es). The base checkout became dirty in $repository_key. Re-run the same command after review."
    fi

    validate_checkout_collisions "$base_checkout_path" "$current_base_commit" "$final_commit"

    if ! git -c core.hooksPath="$empty_hooks_directory" \
      -C "$base_checkout_path" merge --ff-only "$final_commit"
    then
      fail "Integration stopped after $integrated_repository_count repository branch(es). Fast-forward failed in $repository_key. Re-run the same command after review."
    fi

    if [[ -n "$(git -c core.fsmonitor=false \
      -C "$base_checkout_path" status --porcelain --untracked-files=all)" ]]
    then
      fail "Integration stopped after $integrated_repository_count repository branch(es). The $repository_key base checkout is dirty after integration."
    fi
  else
    if ! git -c core.hooksPath="$empty_hooks_directory" \
      -C "$repository_path" update-ref \
      -m "repomux: integrate $run_id" \
      "refs/heads/$base_branch" \
      "$final_commit" \
      "$expected_current_commit"
    then
      fail "Integration stopped after $integrated_repository_count repository branch(es). Atomic branch update failed in $repository_key. Re-run the same command after review."
    fi
  fi

  if [[ "$(git -C "$repository_path" rev-parse --verify "refs/heads/$base_branch^{commit}")" != "$final_commit" ]]; then
    fail "Integration stopped after $integrated_repository_count repository branch(es). Final commit verification failed in $repository_key."
  fi

  integrated_repository_count=$((integrated_repository_count + 1))
  echo "Integrated $repository_key: $base_branch -> $final_commit"
done

echo
echo "Integration complete."
echo "No changes were pushed."
echo "RepoMux feature worktrees were preserved."
