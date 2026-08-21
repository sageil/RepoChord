path_is_within() {
  local candidate="$1"
  local root="$2"

  [[ "$candidate" == "$root" || "$candidate" == "$root/"* ]]
}

resolve_project() {
  local requested_project="$1"
  local current_directory
  local current_git_root=""
  local project_name
  local coordinate_path
  local registry_path
  local project_count
  local matching_names=()
  local matching_coordinates=()

  validate_projects_registry

  if [[ -n "$requested_project" ]]; then
    validate_project_name "$requested_project"
    selected_coordinate="$(jq -r --arg name "$requested_project" '
      [.projects[] | select(.name == $name)] |
      if length == 1 then .[0].coordinate else "" end
    ' "$projects_registry")"

    if [[ -z "$selected_coordinate" ]]; then
      fail "RepoChord project is not registered: $requested_project" 2
    fi

    selected_project="$requested_project"
    return
  fi

  current_directory="$(pwd -P)"

  if git_root_candidate="$(git -C "$current_directory" rev-parse --show-toplevel 2>/dev/null)"; then
    current_git_root="$(cd -- "$git_root_candidate" && pwd -P)"
  fi

  while IFS=$'\t' read -r project_name coordinate_path; do
    if path_is_within "$current_directory" "$coordinate_path"; then
      matching_names+=("$project_name")
      matching_coordinates+=("$coordinate_path")
      continue
    fi

    registry_path="$coordinate_path/.repochord/repositories.json"

    if [[ -n "$current_git_root" && -f "$registry_path" ]] &&
      jq -e --arg path "$current_git_root" 'any(.repositories[]; .path == $path)' "$registry_path" >/dev/null 2>&1
    then
      matching_names+=("$project_name")
      matching_coordinates+=("$coordinate_path")
    fi
  done < <(jq -r '.projects[] | [.name, .coordinate] | @tsv' "$projects_registry")

  if [[ "${#matching_names[@]}" -eq 1 ]]; then
    selected_project="${matching_names[0]}"
    selected_coordinate="${matching_coordinates[0]}"
    return
  fi

  if [[ "${#matching_names[@]}" -gt 1 ]]; then
    echo "The current repository belongs to more than one RepoChord project." >&2
    printf '  %s\n' "${matching_names[@]}" >&2
    fail "Use --project <name> to select one project." 2
  fi

  project_count="$(jq '.projects | length' "$projects_registry")"

  if [[ "$project_count" -eq 1 ]]; then
    selected_project="$(jq -r '.projects[0].name' "$projects_registry")"
    selected_coordinate="$(jq -r '.projects[0].coordinate' "$projects_registry")"
    return
  fi

  echo "RepoChord cannot select a project from the current directory." >&2
  echo "Registered projects:" >&2
  jq -r '.projects[].name | "  " + .' "$projects_registry" >&2
  fail "Use --project <name> to select one project." 2
}

resolve_project_max_attempts() {
  local project_name="$1"

  jq -r --arg name "$project_name" '
    (.defaults.maxAttempts // 3) as $default |
    ([.projects[] | select(.name == $name)][0].maxAttempts // $default)
  ' "$projects_registry"
}

resolve_project_model() {
  local project_name="$1"

  jq -r --arg name "$project_name" '
    (.defaults.model // "gpt-5.6-terra") as $default |
    ([.projects[] | select(.name == $name)][0].model // $default)
  ' "$projects_registry"
}

resolve_project_coordinator_reasoning_effort() {
  local project_name="$1"

  jq -r --arg name "$project_name" '
    (.defaults.coordinatorReasoningEffort // "medium") as $default |
    ([.projects[] | select(.name == $name)][0].coordinatorReasoningEffort // $default)
  ' "$projects_registry"
}

resolve_project_repository_agent_reasoning_effort() {
  local project_name="$1"

  jq -r --arg name "$project_name" '
    (.defaults.repositoryAgentReasoningEffort // "high") as $default |
    ([.projects[] | select(.name == $name)][0].repositoryAgentReasoningEffort // $default)
  ' "$projects_registry"
}

resolve_project_max_parallel() {
  local project_name="$1"

  jq -r --arg name "$project_name" '
    (.defaults.maxParallel // 2) as $default |
    ([.projects[] | select(.name == $name)][0].maxParallel // $default)
  ' "$projects_registry"
}
