cleanup() {
  if [[ -n "$run_id_reservation" ]]; then
    rm -rf -- "$run_id_reservation"
  fi

  if [[ -n "$run_manifest_stage" ]]; then
    rm -f -- "$run_manifest_stage"
  fi
}

trap cleanup EXIT

if [[ ! -d "$results_root" ]]; then
  echo "Result root does not exist: $results_root" >&2
  exit 2
fi

if [[ ! -f "$registry_path" ]]; then
  echo "Repository registry does not exist: $registry_path" >&2
  exit 2
fi

if ! jq -e '
  .version == 1 and
  (.repositories | type == "array") and
  ([.repositories[].key] | length == (unique | length)) and
  ([.repositories[].path] | length == (unique | length)) and
  all(.repositories[];
    (.key | type == "string") and
    (.key | test("^[A-Za-z0-9._-]+$")) and
    (.path | type == "string") and
    (.path | startswith("/"))
  )
' "$registry_path" >/dev/null; then
  echo "Repository registry is invalid: $registry_path" >&2
  exit 2
fi

while IFS= read -r registered_repository_path; do
  if [[ ! -d "$registered_repository_path" ]]; then
    echo "Registered repository does not exist: $registered_repository_path" >&2
    exit 2
  fi

  canonical_registered_path="$(cd -- "$registered_repository_path" && pwd -P)"

  if [[ "$registered_repository_path" != "$canonical_registered_path" ]]; then
    echo "Registered repository path is not canonical: $registered_repository_path" >&2
    exit 2
  fi
done < <(jq -r '.repositories[].path' "$registry_path")

if [[ "$resume" == true ]]; then
  result_directory="$results_root/$run_id"

  if [[ ! -d "$result_directory" ]]; then
    echo "Result directory does not exist for resume: $result_directory" >&2
    exit 2
  fi
elif [[ -n "$run_id" ]]; then
  result_directory="$results_root/$run_id"

  if [[ -e "$result_directory" ]]; then
    echo "Result directory already exists: $result_directory" >&2
    echo "Use a new run ID." >&2
    exit 2
  fi
fi

repository_keys=()
repository_paths=()
task_files=()

line_number=0

while IFS='|' read -r repository_key repository_path task_file extra || \
  [[ -n "${repository_key}${repository_path}${task_file}${extra}" ]]
do
  line_number=$((line_number + 1))

  if [[ -z "${repository_key}${repository_path}${task_file}${extra}" ]]; then
    continue
  fi

  if [[ "$repository_key" == \#* ]]; then
    continue
  fi

  if [[ -z "$repository_key" || -z "$repository_path" || -z "$task_file" || -n "$extra" ]]; then
    echo "Invalid assignment at line $line_number." >&2
    echo "Expected: repository-key|absolute-repository-path|absolute-task-file" >&2
    exit 2
  fi

  if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ]] ||
    ! git check-ref-format "refs/heads/repochord/validation/$repository_key" >/dev/null 2>&1
  then
    echo "Invalid repository key at line $line_number: $repository_key" >&2
    exit 2
  fi

  if [[ "$repository_path" != /* || "$task_file" != /* ]]; then
    echo "Repository and task paths must be absolute at line $line_number." >&2
    exit 2
  fi

  for existing_key in ${repository_keys[@]+"${repository_keys[@]}"}; do
    if [[ "$existing_key" == "$repository_key" ]]; then
      echo "Duplicate repository key: $repository_key" >&2
      exit 2
    fi
  done

  repository_keys+=("$repository_key")
  repository_paths+=("$repository_path")
  task_files+=("$task_file")
done < "$assignments_file"

repository_agent_count="${#repository_keys[@]}"

if [[ "$repository_agent_count" -eq 0 ]]; then
  echo "The assignments file contains no repository agents." >&2
  exit 2
fi

validated_retry_blocked_keys=()

for retry_blocked_key in ${retry_blocked_keys[@]+"${retry_blocked_keys[@]}"}; do
  if [[ ! "$retry_blocked_key" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Invalid repository key for --retry-blocked: $retry_blocked_key" >&2
    exit 2
  fi

  retry_key_found=false

  for repository_key in "${repository_keys[@]}"; do
    if [[ "$repository_key" == "$retry_blocked_key" ]]; then
      retry_key_found=true
      break
    fi
  done

  if [[ "$retry_key_found" != true ]]; then
    echo "Blocked retry key is not present in the assignments: $retry_blocked_key" >&2
    exit 2
  fi

  for existing_key in ${validated_retry_blocked_keys[@]+"${validated_retry_blocked_keys[@]}"}; do
    if [[ "$existing_key" == "$retry_blocked_key" ]]; then
      echo "Duplicate --retry-blocked repository key: $retry_blocked_key" >&2
      exit 2
    fi
  done

  validated_retry_blocked_keys+=("$retry_blocked_key")
done

canonical_repository_paths=()

if ! global_user_name="$(git config --global --get user.name)" || [[ -z "$global_user_name" ]]; then
  echo "Global Git user.name is not configured." >&2
  exit 2
fi

if ! global_user_email="$(git config --global --get user.email)" || [[ -z "$global_user_email" ]]; then
  echo "Global Git user.email is not configured." >&2
  exit 2
fi

for ((index = 0; index < repository_agent_count; index++)); do
  repository_key="${repository_keys[$index]}"
  repository_path="${repository_paths[$index]}"
  task_file="${task_files[$index]}"

  if [[ ! -d "$repository_path" ]]; then
    echo "Repository directory does not exist: $repository_path" >&2
    exit 2
  fi

  if [[ ! -f "$task_file" ]]; then
    echo "Task file does not exist: $task_file" >&2
    exit 2
  fi

  canonical_repository_path="$(cd -- "$repository_path" && pwd -P)"

  if ! repository_root="$(git -C "$canonical_repository_path" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "Path is not inside a Git repository: $repository_path" >&2
    exit 2
  fi

  repository_root="$(cd -- "$repository_root" && pwd -P)"

  if [[ "$canonical_repository_path" != "$repository_root" ]]; then
    echo "Repository path must be the Git repository root: $repository_path" >&2
    exit 2
  fi

  for existing_path in ${canonical_repository_paths[@]+"${canonical_repository_paths[@]}"}; do
    if [[ "$existing_path" == "$canonical_repository_path" ]]; then
      echo "Duplicate canonical repository path: $canonical_repository_path" >&2
      exit 2
    fi
  done

  canonical_repository_paths+=("$canonical_repository_path")

  registered_path="$(jq -r \
    --arg key "$repository_key" \
    '[.repositories[] | select(.key == $key)] | if length == 1 then .[0].path else "" end' \
    "$registry_path")"

  if [[ -z "$registered_path" || ! -d "$registered_path" ]]; then
    echo "Repository key is not uniquely registered: $repository_key" >&2
    exit 2
  fi

  registered_path="$(cd -- "$registered_path" && pwd -P)"

  if [[ "$registered_path" != "$canonical_repository_path" ]]; then
    echo "Assignment path does not match the registry for: $repository_key" >&2
    exit 2
  fi

  if ! git -C "$canonical_repository_path" symbolic-ref --quiet --short HEAD >/dev/null; then
    echo "Repository has a detached HEAD: $repository_path" >&2
    exit 2
  fi

  if ! git -C "$canonical_repository_path" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Repository has no initial commit: $repository_path" >&2
    exit 2
  fi

  source_repository_status="$(git -c core.fsmonitor=false \
    -C "$canonical_repository_path" status --porcelain=v1 --untracked-files=all)"

  if [[ -n "$source_repository_status" ]]; then
    if [[ "$allow_dirty_source" == true ]]; then
      echo "Warning: uncommitted changes are excluded from this run: $repository_path" >&2
    else
      echo "Repository worktree is not clean: $repository_path" >&2
      exit 2
    fi
  fi


  repository_paths[index]="$canonical_repository_path"
  task_files[index]="$(cd -- "$(dirname -- "$task_file")" && pwd -P)/$(basename -- "$task_file")"
done
