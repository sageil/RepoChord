
empty_hooks_directory="$(mktemp -d "${TMPDIR:-/tmp}/repochord-integration-hooks.XXXXXX")"

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
  private_repository_path="${private_repository_paths[$index]}"
  artifact_repository_path="${artifact_repository_paths[$index]}"
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

    validate_checkout_collisions \
      "$base_checkout_path" \
      "$artifact_repository_path" \
      "$current_base_commit" \
      "$final_commit"
  fi

  if [[ -n "$private_repository_path" ]]; then
    if ! git -c core.hooksPath="$empty_hooks_directory" \
      -C "$repository_path" fetch \
      --quiet \
      --no-tags \
      --no-write-fetch-head \
      "$private_repository_path" \
      "refs/heads/${worktree_branches[$index]}"
    then
      fail "Integration stopped after $integrated_repository_count repository branch(es). Verified commit import failed in $repository_key. Re-run the same command after review."
    fi
  fi

  if ! git -C "$repository_path" cat-file -e "$final_commit^{commit}" 2>/dev/null; then
    fail "Integration stopped after $integrated_repository_count repository branch(es). Imported commit verification failed in $repository_key."
  fi

  if [[ -n "$base_checkout_path" ]]; then
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
      -m "repochord: integrate $run_id" \
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
echo "RepoChord feature worktrees were preserved."
