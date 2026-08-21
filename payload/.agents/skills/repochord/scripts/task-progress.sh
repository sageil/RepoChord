#!/usr/bin/env bash

repochord_task_snapshot_path() {
  local result_directory="$1"
  local repository_key="$2"

  printf '%s/tasks/%s.source.md' "$result_directory" "$repository_key"
}

repochord_completed_task_path() {
  local result_directory="$1"
  local repository_key="$2"

  printf '%s/tasks/%s.completed.md' "$result_directory" "$repository_key"
}

repochord_prepare_task_directory() {
  local result_directory="$1"
  local task_directory="$result_directory/tasks"

  if [[ -L "$task_directory" ]]; then
    echo "Run task directory must not be a symbolic link: $task_directory" >&2
    return 1
  fi

  if [[ -e "$task_directory" && ! -d "$task_directory" ]]; then
    echo "Run task path is not a directory: $task_directory" >&2
    return 1
  fi

  if ! mkdir -p "$task_directory"; then
    echo "Could not create the run task directory: $task_directory" >&2
    return 1
  fi
}

repochord_ensure_task_snapshot() {
  local coordinate_root="$1"
  local result_directory="$2"
  local repository_key="$3"
  local task_file="$4"
  local expected_task_hash="$5"
  local snapshot_path
  local snapshot_stage
  local snapshot_hash

  if ! repochord_prepare_task_directory "$result_directory"; then
    return 1
  fi

  snapshot_path="$(repochord_task_snapshot_path "$result_directory" "$repository_key")"

  if [[ -L "$snapshot_path" ]]; then
    echo "Run task snapshot must not be a symbolic link: $snapshot_path" >&2
    return 1
  fi

  if [[ -e "$snapshot_path" ]]; then
    if [[ ! -f "$snapshot_path" ]]; then
      echo "Run task snapshot is not a regular file: $snapshot_path" >&2
      return 1
    fi

    snapshot_hash="$(git -C "$coordinate_root" hash-object -- "$snapshot_path")"

    if [[ "$snapshot_hash" != "$expected_task_hash" ]]; then
      echo "Run task snapshot does not match the recorded task: $snapshot_path" >&2
      return 1
    fi

    printf '%s\n' "$snapshot_path"
    return 0
  fi

  if [[ -L "$task_file" || ! -f "$task_file" ]]; then
    echo "Repository task is unavailable for snapshot creation: $task_file" >&2
    return 1
  fi

  if [[ "$(git -C "$coordinate_root" hash-object -- "$task_file")" != "$expected_task_hash" ]]; then
    echo "Repository task changed before its run snapshot was created: $task_file" >&2
    return 1
  fi

  snapshot_stage="$(mktemp "$result_directory/tasks/.${repository_key}.source.XXXXXX")"

  if ! cp "$task_file" "$snapshot_stage"; then
    rm -f -- "$snapshot_stage"
    echo "Could not stage the run task snapshot: $snapshot_path" >&2
    return 1
  fi

  snapshot_hash="$(git -C "$coordinate_root" hash-object -- "$snapshot_stage")"

  if [[ "$snapshot_hash" != "$expected_task_hash" ]]; then
    rm -f -- "$snapshot_stage"
    echo "Staged run task snapshot does not match the recorded task: $task_file" >&2
    return 1
  fi

  if ! mv -- "$snapshot_stage" "$snapshot_path"; then
    rm -f -- "$snapshot_stage"
    echo "Could not publish the run task snapshot: $snapshot_path" >&2
    return 1
  fi

  printf '%s\n' "$snapshot_path"
}

repochord_render_completed_task() {
  local coordinate_root="$1"
  local result_directory="$2"
  local repository_key="$3"
  local task_file="$4"
  local expected_task_hash="$5"
  local snapshot_path
  local completed_path
  local completed_stage
  local expected_completed_hash
  local observed_completed_hash

  if ! snapshot_path="$(repochord_ensure_task_snapshot \
    "$coordinate_root" \
    "$result_directory" \
    "$repository_key" \
    "$task_file" \
    "$expected_task_hash")"
  then
    return 1
  fi

  completed_path="$(repochord_completed_task_path "$result_directory" "$repository_key")"

  if [[ -L "$completed_path" ]]; then
    echo "Completed task view must not be a symbolic link: $completed_path" >&2
    return 1
  fi

  if [[ -e "$completed_path" && ! -f "$completed_path" ]]; then
    echo "Completed task view is not a regular file: $completed_path" >&2
    return 1
  fi

  completed_stage="$(mktemp "$result_directory/tasks/.${repository_key}.completed.XXXXXX")"

  if ! LC_ALL=C sed 's/^\([[:space:]]*-\) \[ \] /\1 [x] /' \
    "$snapshot_path" \
    > "$completed_stage"
  then
    rm -f -- "$completed_stage"
    echo "Could not render the completed task view: $completed_path" >&2
    return 1
  fi

  expected_completed_hash="$(git -C "$coordinate_root" hash-object -- "$completed_stage")"

  if [[ -f "$completed_path" ]]; then
    observed_completed_hash="$(git -C "$coordinate_root" hash-object -- "$completed_path")"

    if [[ "$observed_completed_hash" == "$expected_completed_hash" ]]; then
      rm -f -- "$completed_stage"
      printf '%s\n' "$completed_path"
      return 0
    fi
  fi

  if ! mv -- "$completed_stage" "$completed_path"; then
    rm -f -- "$completed_stage"
    echo "Could not publish the completed task view: $completed_path" >&2
    return 1
  fi

  printf '%s\n' "$completed_path"
}
