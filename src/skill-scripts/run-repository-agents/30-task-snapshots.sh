assignments_file="$(cd -- "$(dirname -- "$assignments_file")" && pwd -P)/$(basename -- "$assignments_file")"
feature_id=""
tasks_root="$coordinate_root/tasks"

for task_file in "${task_files[@]}"; do
  feature_task_directory="$(dirname -- "$task_file")"
  feature_tasks_parent="$(dirname -- "$feature_task_directory")"
  candidate_feature_id="$(basename -- "$feature_task_directory")"

  if [[ "$feature_tasks_parent" != "$tasks_root" ]]; then
    echo "Repository task files must be under: $tasks_root" >&2
    exit 2
  fi

  if [[ ! "$candidate_feature_id" =~ ^[A-Za-z0-9._-]+$ || \
    "$candidate_feature_id" == "." || \
    "$candidate_feature_id" == ".." ]]
  then
    echo "Cannot derive a valid feature ID from task file: $task_file" >&2
    exit 2
  fi

  if [[ -z "$feature_id" ]]; then
    feature_id="$candidate_feature_id"
  elif [[ "$feature_id" != "$candidate_feature_id" ]]; then
    echo "All repository tasks in one run must belong to one feature." >&2
    exit 2
  fi
done

request_file="$coordinate_root/requests/$feature_id.md"

for run_document in "$request_file" "$assignments_file" "${task_files[@]}"; do
  if [[ -L "$run_document" || ! -f "$run_document" ]]; then
    echo "Run document does not exist or is not a regular file: $run_document" >&2
    exit 2
  fi
done

request_hash="$(git -C "$coordinate_root" hash-object -- "$request_file")"
assignments_hash="$(git -C "$coordinate_root" hash-object -- "$assignments_file")"
task_hashes=()

for task_file in "${task_files[@]}"; do
  task_hashes+=("$(git -C "$coordinate_root" hash-object -- "$task_file")")
done

if [[ -z "$run_id" ]]; then
  while true; do
    run_id_reservation="$(mktemp -d "$results_root/.run-id.XXXXXX")"
    run_id_suffix="$(basename -- "$run_id_reservation")"
    run_id_suffix="${run_id_suffix##*.}"
    run_id="$feature_id-run-$run_id_suffix"
    result_directory="$results_root/$run_id"

    if [[ ! -e "$result_directory" ]]; then
      break
    fi

    rm -rf -- "$run_id_reservation"
    run_id_reservation=""
  done
fi

for repository_key in "${repository_keys[@]}"; do
  worktree_branch="repochord/$run_id/$repository_key"

  if ! git check-ref-format "refs/heads/$worktree_branch" >/dev/null 2>&1; then
    echo "Run ID and repository key produce an invalid RepoChord branch: $worktree_branch" >&2
    exit 2
  fi
done

if [[ "$resume" != true ]]; then
  mkdir "$result_directory"
fi

if [[ -n "$run_id_reservation" ]]; then
  rm -rf -- "$run_id_reservation"
  run_id_reservation=""
fi

run_manifest_path="$result_directory/.manifest.json"

if [[ "$resume" == true ]]; then
  if [[ -L "$run_manifest_path" || ! -f "$run_manifest_path" ]]; then
    echo "Run manifest does not exist or is not a regular file: $run_manifest_path" >&2
    exit 2
  fi

  if ! jq -e \
    --arg run_id "$run_id" \
    --arg feature_id "$feature_id" \
    --arg assignments_file "$assignments_file" \
    --arg assignments_hash "$assignments_hash" \
    --arg request_file "$request_file" \
    --arg request_hash "$request_hash" \
    --argjson repository_count "$repository_agent_count" \
    '
      .version == 1 and
      .run_id == $run_id and
      .feature_id == $feature_id and
      .assignments_file == $assignments_file and
      .assignments_hash == $assignments_hash and
      .request_file == $request_file and
      .request_hash == $request_hash and
      (.repositories | type == "array") and
      (.repositories | length == $repository_count)
    ' \
    "$run_manifest_path" \
    >/dev/null
  then
    echo "Run manifest does not match this resume request: $run_manifest_path" >&2
    exit 2
  fi

  for ((index = 0; index < repository_agent_count; index++)); do
    if ! jq -e \
      --argjson index "$index" \
      --arg key "${repository_keys[$index]}" \
      --arg path "${repository_paths[$index]}" \
      --arg task_file "${task_files[$index]}" \
      --arg task_hash "${task_hashes[$index]}" \
      '
        .repositories[$index] == {
          key: $key,
          path: $path,
          task_file: $task_file,
          task_hash: $task_hash
        }
      ' \
      "$run_manifest_path" \
      >/dev/null
    then
      echo "Run manifest repository assignment changed at index: $index" >&2
      exit 2
    fi
  done
else
  run_manifest_stage="$(mktemp "$result_directory/.manifest.XXXXXX")"

  for ((index = 0; index < repository_agent_count; index++)); do
    jq -n \
      --arg key "${repository_keys[$index]}" \
      --arg path "${repository_paths[$index]}" \
      --arg task_file "${task_files[$index]}" \
      --arg task_hash "${task_hashes[$index]}" \
      '{key: $key, path: $path, task_file: $task_file, task_hash: $task_hash}'
  done | jq -s \
    --arg run_id "$run_id" \
    --arg feature_id "$feature_id" \
    --arg assignments_file "$assignments_file" \
    --arg assignments_hash "$assignments_hash" \
    --arg request_file "$request_file" \
    --arg request_hash "$request_hash" \
    '{
      version: 1,
      run_id: $run_id,
      feature_id: $feature_id,
      assignments_file: $assignments_file,
      assignments_hash: $assignments_hash,
      request_file: $request_file,
      request_hash: $request_hash,
      repositories: .
    }' \
    > "$run_manifest_stage"

  mv -- "$run_manifest_stage" "$run_manifest_path"
  run_manifest_stage=""
fi

task_snapshot_files=()

for ((index = 0; index < repository_agent_count; index++)); do
  if ! task_snapshot_file="$(repochord_ensure_task_snapshot \
    "$coordinate_root" \
    "$result_directory" \
    "${repository_keys[$index]}" \
    "${task_files[$index]}" \
    "${task_hashes[$index]}")"
  then
    exit 1
  fi

  task_snapshot_files+=("$task_snapshot_file")
done

repository_agent_arguments=(
  --model "$model"
  --reasoning-effort "$reasoning_effort"
  --max-attempts "$max_attempts"
)

if [[ -n "$profile" ]]; then
  repository_agent_arguments+=(--profile "$profile")
fi

overall_status=0
launch_indexes=()
resume_repository=()
allow_blocked_resume=()
