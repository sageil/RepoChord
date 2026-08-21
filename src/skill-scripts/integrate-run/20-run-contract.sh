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
registry_path="$coordinate_root/.repochord/repositories.json"
result_directory="$coordinate_root/.repochord/results/$run_id"
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
    ! git check-ref-format "refs/heads/repochord/validation/$repository_key" >/dev/null 2>&1
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
