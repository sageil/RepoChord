
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
