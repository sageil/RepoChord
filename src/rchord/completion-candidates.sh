completion_projects_registry_available() {
  if ! command -v jq >/dev/null 2>&1 ||
    [[ -L "$projects_registry" || ! -f "$projects_registry" ]]
  then
    return 1
  fi

  jq -e '
    .version == 1 and
    (.projects | type == "array") and
    ([.projects[].name] | length == (unique | length)) and
    all(.projects[];
      (.name | type == "string") and
      (.name | test("^[A-Za-z0-9._-]+$")) and
      (.coordinate | type == "string") and
      (.coordinate | startswith("/")) and
      (.coordinate | test("[\\t\\r\\n]") | not)
    )
  ' "$projects_registry" >/dev/null 2>&1
}

completion_project_coordinate() {
  local requested_project="$1"
  local current_directory
  local current_git_root=""
  local git_root_candidate
  local project_name
  local coordinate_path
  local registry_path
  local project_count
  local matching_coordinates=()

  if ! completion_projects_registry_available; then
    return 1
  fi

  if [[ -n "$requested_project" ]]; then
    coordinate_path="$(jq -r --arg name "$requested_project" '
      [.projects[] | select(.name == $name)] |
      if length == 1 then .[0].coordinate else "" end
    ' "$projects_registry")"

    if [[ -z "$coordinate_path" ]]; then
      return 1
    fi

    printf '%s\n' "$coordinate_path"
    return
  fi

  current_directory="$(pwd -P)"

  if git_root_candidate="$(git -C "$current_directory" rev-parse --show-toplevel 2>/dev/null)"; then
    current_git_root="$(cd -- "$git_root_candidate" && pwd -P)"
  fi

  while IFS=$'\t' read -r project_name coordinate_path; do
    if path_is_within "$current_directory" "$coordinate_path"; then
      matching_coordinates+=("$coordinate_path")
      continue
    fi

    registry_path="$coordinate_path/.repochord/repositories.json"

    if [[ -n "$current_git_root" && ! -L "$registry_path" && -f "$registry_path" ]] &&
      jq -e --arg path "$current_git_root" '
        (.repositories | type == "array") and
        any(.repositories[]; .path == $path)
      ' "$registry_path" >/dev/null 2>&1
    then
      matching_coordinates+=("$coordinate_path")
    fi
  done < <(jq -r '.projects[] | [.name, .coordinate] | @tsv' "$projects_registry")

  if [[ "${#matching_coordinates[@]}" -eq 1 ]]; then
    printf '%s\n' "${matching_coordinates[0]}"
    return
  fi

  if [[ "${#matching_coordinates[@]}" -gt 1 ]]; then
    return 1
  fi

  project_count="$(jq '.projects | length' "$projects_registry")"

  if [[ "$project_count" -eq 1 ]]; then
    jq -r '.projects[0].coordinate' "$projects_registry"
    return
  fi

  return 1
}

run_completion_candidates() {
  local candidate_type="${1:-}"
  local requested_project="${2:-}"
  local coordinate_path
  local registry_path
  local results_root
  local run_path
  local run_id

  if [[ "$#" -gt 2 ]]; then
    return 2
  fi

  case "$candidate_type" in
    projects)
      if [[ "$#" -ne 1 ]] || ! completion_projects_registry_available; then
        return 0
      fi

      jq -r '.projects[].name' "$projects_registry"
      ;;
    repositories)
      if ! coordinate_path="$(completion_project_coordinate "$requested_project")"; then
        return 0
      fi

      registry_path="$coordinate_path/.repochord/repositories.json"

      if [[ -L "$registry_path" || ! -f "$registry_path" ]]; then
        return 0
      fi

      jq -r '
        if
          .version == 1 and
          (.repositories | type == "array") and
          ([.repositories[].key] | length == (unique | length)) and
          all(.repositories[];
            (.key | type == "string") and
            (.key | test("^[A-Za-z0-9_-][A-Za-z0-9._-]*$")) and
            (.key | endswith(".") | not) and
            (.key | endswith(".lock") | not) and
            (.key | contains("..") | not)
          )
        then
          .repositories[].key
        else
          empty
        end
      ' "$registry_path" 2>/dev/null || true
      ;;
    runs)
      if ! coordinate_path="$(completion_project_coordinate "$requested_project")"; then
        return 0
      fi

      results_root="$coordinate_path/.repochord/results"

      if [[ -L "$results_root" || ! -d "$results_root" ]]; then
        return 0
      fi

      for run_path in "$results_root"/.* "$results_root"/*; do
        if [[ -L "$run_path" || ! -d "$run_path" ||
          -L "$run_path/.manifest.json" || ! -f "$run_path/.manifest.json" ]]
        then
          continue
        fi

        run_id="$(basename -- "$run_path")"

        if [[ "$run_id" =~ ^[A-Za-z0-9._-]+$ && "$run_id" != "." && "$run_id" != ".." ]]; then
          printf '%s\n' "$run_id"
        fi
      done
      ;;
    *)
      return 2
      ;;
  esac
}
