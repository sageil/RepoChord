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
    echo "  RepoChord branch: ${worktree_branches[$index]}"
    echo "  Final commit: ${final_commits[$index]}"
    echo "  Integration: ${integration_states[$index]}"
    result_summary="$(jq -c '{summary, tests, risks}' "${result_paths[$index]}")"
    echo "  Result: $result_summary"
    echo "  Change summary:"
    pending_base_commit="${base_commits[$index]}"

    if [[ "${integration_states[$index]}" == "pending" ]]; then
      pending_base_commit="${base_current_commits[$index]}"
    fi

    git -C "${artifact_repository_paths[$index]}" diff --no-ext-diff --no-textconv --stat \
      "$pending_base_commit..${final_commits[$index]}"

    if [[ "$show_diffs" == true ]]; then
      if [[ "${integration_states[$index]}" == "pending" ]]; then
        echo
        echo "  Diff:"
        git -C "${artifact_repository_paths[$index]}" diff \
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
printf 'Import verified commits, commit the feature documents, and fast-forward %s repository branch(es)? [y/N] ' "$pending_repository_count"
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
