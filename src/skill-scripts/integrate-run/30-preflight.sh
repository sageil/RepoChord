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
private_repository_paths=()
artifact_repository_paths=()
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
  local expected_private_repository_path
  local private_repository_path
  local artifact_repository_path
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
  private_repository_paths=()
  artifact_repository_paths=()
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
    expected_private_repository_path="$coordinate_root/.repochord/repositories/$run_id/$repository_key.git"
    expected_worktree_path="$coordinate_root/.repochord/worktrees/$run_id/$repository_key"
    expected_worktree_branch="repochord/$run_id/$repository_key"

    if [[ -L "$result_path" || ! -f "$result_path" ]]; then
      fail "Repository result does not exist or is not a regular file: $result_path"
    fi

    if ! jq -e \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      --arg source_repository_path "$repository_path" \
      --arg private_repository_path "$expected_private_repository_path" \
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
        ((.execution.private_repository_path // null) == null or
          .execution.private_repository_path == $private_repository_path) and
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
    private_repository_path="$(jq -r '.execution.private_repository_path // empty' "$result_path")"
    artifact_repository_path="$repository_path"

    if [[ -n "$private_repository_path" ]]; then
      if [[ "$private_repository_path" != "$expected_private_repository_path" || \
        -L "$private_repository_path" || \
        ! -d "$private_repository_path" || \
        "$(git -C "$private_repository_path" rev-parse --is-bare-repository 2>/dev/null || true)" != true ]]
      then
        fail "Private repository is unavailable or invalid in $repository_key: $expected_private_repository_path"
      fi

      artifact_repository_path="$private_repository_path"
    fi

    if ! git check-ref-format "refs/heads/$base_branch" >/dev/null 2>&1; then
      fail "Repository result contains an invalid base branch: $base_branch" 2
    fi

    if ! git -C "$repository_path" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
      fail "Recorded base commit does not exist in $repository_key: $base_commit"
    fi

    if ! git -C "$artifact_repository_path" cat-file -e "$final_commit^{commit}" 2>/dev/null; then
      fail "Recorded final commit does not exist in $repository_key: $final_commit"
    fi

    if ! branch_commit="$(git -C "$artifact_repository_path" rev-parse --verify "refs/heads/$expected_worktree_branch^{commit}" 2>/dev/null)"; then
      fail "RepoChord branch does not exist in $repository_key: $expected_worktree_branch"
    fi

    if [[ "$branch_commit" != "$final_commit" ]]; then
      fail "RepoChord branch changed after completion in $repository_key: $expected_worktree_branch"
    fi

    if ! current_base_commit="$(git -C "$repository_path" rev-parse --verify "refs/heads/$base_branch^{commit}" 2>/dev/null)"; then
      fail "Recorded base branch does not exist in $repository_key: $base_branch"
    fi

    if ! git -C "$artifact_repository_path" merge-base --is-ancestor "$base_commit" "$final_commit"; then
      fail "Final commit does not contain the recorded base commit in $repository_key."
    fi

    if [[ -n "$(git -C "$artifact_repository_path" rev-list --merges "$base_commit..$final_commit")" ]]; then
      fail "Final commit history contains a merge commit in $repository_key."
    fi

    if git -C "$repository_path" cat-file -e "$final_commit^{commit}" 2>/dev/null &&
      git -C "$repository_path" merge-base --is-ancestor "$final_commit" "$current_base_commit"
    then
      integration_state="integrated"
    elif git -C "$artifact_repository_path" cat-file -e "$current_base_commit^{commit}" 2>/dev/null &&
      git -C "$artifact_repository_path" merge-base --is-ancestor "$base_commit" "$current_base_commit" &&
      git -C "$artifact_repository_path" merge-base --is-ancestor "$current_base_commit" "$final_commit"
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

      validate_checkout_collisions "$base_checkout_path" "$artifact_repository_path" "$current_base_commit" "$final_commit"
    fi

    if [[ -e "$expected_worktree_path" ]]; then
      if [[ -L "$expected_worktree_path" || ! -d "$expected_worktree_path" ||
        "$(git -C "$expected_worktree_path" rev-parse --show-toplevel 2>/dev/null || true)" != "$expected_worktree_path" ||
        "$(git -C "$expected_worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$expected_worktree_branch" ||
        "$(git -C "$expected_worktree_path" rev-parse --verify HEAD 2>/dev/null || true)" != "$final_commit" ||
        -n "$(git -c core.fsmonitor=false \
          -C "$expected_worktree_path" status --porcelain --untracked-files=all 2>/dev/null || true)" ]]
      then
        fail "RepoChord worktree no longer matches its completed result: $expected_worktree_path"
      fi
    fi

    result_paths+=("$result_path")
    result_hashes+=("$(git -C "$coordinate_root" hash-object -- "$result_path")")
    base_branches+=("$base_branch")
    base_commits+=("$base_commit")
    final_commits+=("$final_commit")
    worktree_branches+=("$expected_worktree_branch")
    private_repository_paths+=("$private_repository_path")
    artifact_repository_paths+=("$artifact_repository_path")
    base_current_commits+=("$current_base_commit")
    base_checkout_paths+=("$base_checkout_path")
    integration_states+=("$integration_state")
  done
}
