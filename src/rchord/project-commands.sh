run_upgrade() {
  local project_count
  local project_name
  local coordinate_path
  local project_index
  local failure_count=0
  local project_names=()
  local coordinate_paths=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown upgrade argument: $1" 2
        ;;
    esac
  done

  require_commands bash cp diff git jq mktemp mv
  validate_skill_directory "$source_skill"
  validate_task_skill_directory "$source_task_skill"
  validate_projects_registry
  project_count="$(jq '.projects | length' "$projects_registry")"

  if [[ "$project_count" -eq 0 ]]; then
    echo "No registered RepoChord projects to upgrade."
    return
  fi

  while IFS=$'\t' read -r project_name coordinate_path; do
    validate_upgrade_target "$coordinate_path"
    project_names+=("$project_name")
    coordinate_paths+=("$validated_upgrade_coordinate")
  done < <(jq -r '.projects[] | [.name, .coordinate] | @tsv' "$projects_registry")

  for ((project_index = 0; project_index < ${#project_names[@]}; project_index++)); do
    if ! upgrade_project_runtime \
      "${coordinate_paths[$project_index]}" \
      "${project_names[$project_index]}"
    then
      failure_count=$((failure_count + 1))
    fi
  done

  if [[ "$failure_count" -ne 0 ]]; then
    fail "RepoChord could not upgrade $failure_count of $project_count registered projects."
  fi

  echo "RepoChord upgrade complete: $project_count registered projects are current."
}

run_list() {
  local show_details=false
  local project_name
  local coordinate_path
  local registry_path

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --details)
        show_details=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "The list command accepts only --details." 2
        ;;
    esac
  done

  require_commands jq
  validate_projects_registry

  if [[ "$show_details" != true ]]; then
    printf 'PROJECT\tCOORDINATE\n'
    jq -r '.projects[] | [.name, .coordinate] | @tsv' "$projects_registry"
    return
  fi

  while IFS=$'\t' read -r project_name coordinate_path; do
    registry_path="$coordinate_path/.repochord/repositories.json"
    validate_repository_registry "$registry_path"
  done < <(jq -r '.projects[] | [.name, .coordinate] | @tsv' "$projects_registry")

  printf 'PROJECT\tCOORDINATE\tREPOSITORY\tPATH\n'

  while IFS=$'\t' read -r project_name coordinate_path; do
    registry_path="$coordinate_path/.repochord/repositories.json"
    jq -r \
      --arg project "$project_name" \
      --arg coordinate "$coordinate_path" \
      '.repositories[] | [$project, $coordinate, .key, .path] | @tsv' \
      "$registry_path"
  done < <(jq -r '.projects[] | [.name, .coordinate] | @tsv' "$projects_registry")
}

run_config() {
  local action=""
  local requested_project=""
  local setting_name=""
  local setting_value=""
  local configured_value
  local registry_stage=""

  if [[ "$#" -eq 0 ]]; then
    usage
    exit 2
  fi

  action="$1"
  shift

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -p|--project)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_project="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  case "$action" in
    get)
      if [[ "$#" -ne 1 ]]; then
        usage
        exit 2
      fi

      setting_name="$1"
      ;;
    set)
      if [[ "$#" -ne 2 ]]; then
        usage
        exit 2
      fi

      setting_name="$1"
      setting_value="$2"
      ;;
    *)
      fail "Unknown config action: $action" 2
      ;;
  esac

  case "$setting_name" in
    model|coordinator-reasoning-effort|repository-agent-reasoning-effort|max-parallel|max-attempts)
      ;;
    *)
      fail "Unknown RepoChord setting: $setting_name" 2
      ;;
  esac

  require_commands jq mktemp mv
  resolve_project "$requested_project"

  if [[ "$action" == "get" ]]; then
    case "$setting_name" in
      model)
        resolve_project_model "$selected_project"
        ;;
      coordinator-reasoning-effort)
        resolve_project_coordinator_reasoning_effort "$selected_project"
        ;;
      repository-agent-reasoning-effort)
        resolve_project_repository_agent_reasoning_effort "$selected_project"
        ;;
      max-parallel)
        resolve_project_max_parallel "$selected_project"
        ;;
      max-attempts)
        resolve_project_max_attempts "$selected_project"
        ;;
    esac
    return
  fi

  configured_value="$setting_value"

  case "$setting_name" in
    model)
      validate_model "$configured_value"
      ;;
    coordinator-reasoning-effort|repository-agent-reasoning-effort)
      validate_reasoning_effort "$configured_value"
      ;;
    max-parallel)
      validate_max_parallel "$configured_value"
      ;;
    max-attempts)
      validate_max_attempts "$configured_value"
      ;;
  esac

  registry_stage="$(mktemp "$repochord_config_directory/.projects.XXXXXX")"

  cleanup_config() {
    if [[ -n "$registry_stage" ]]; then
      rm -f -- "$registry_stage"
    fi
  }

  trap cleanup_config EXIT

  case "$setting_name" in
    model)
      jq \
        --arg name "$selected_project" \
        --arg model "$configured_value" \
        '.projects |= map(if .name == $name then .model = $model else . end)' \
        "$projects_registry" > "$registry_stage"
      ;;
    coordinator-reasoning-effort)
      jq \
        --arg name "$selected_project" \
        --arg reasoning_effort "$configured_value" \
        '.projects |= map(
          if .name == $name then
            .coordinatorReasoningEffort = $reasoning_effort
          else
            .
          end
        )' \
        "$projects_registry" > "$registry_stage"
      ;;
    repository-agent-reasoning-effort)
      jq \
        --arg name "$selected_project" \
        --arg reasoning_effort "$configured_value" \
        '.projects |= map(
          if .name == $name then
            .repositoryAgentReasoningEffort = $reasoning_effort
          else
            .
          end
        )' \
        "$projects_registry" > "$registry_stage"
      ;;
    max-parallel)
      jq \
        --arg name "$selected_project" \
        --argjson max_parallel "$configured_value" \
        '.projects |= map(if .name == $name then .maxParallel = $max_parallel else . end)' \
        "$projects_registry" > "$registry_stage"
      ;;
    max-attempts)
      jq \
        --arg name "$selected_project" \
        --argjson max_attempts "$configured_value" \
        '.projects |= map(if .name == $name then .maxAttempts = $max_attempts else . end)' \
        "$projects_registry" > "$registry_stage"
      ;;
  esac

  mv -- "$registry_stage" "$projects_registry"
  registry_stage=""
  validate_projects_registry
  echo "RepoChord $setting_name for $selected_project: $configured_value"
  trap - EXIT
}

run_validate() {
  local requested_project=""
  local coordinate_path=""
  local codex_interactive_help
  local codex_exec_help
  local required_flag

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -p|--project)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_project="$2"
        shift 2
        ;;
      -c|--coordinate)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        coordinate_path="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown validate argument: $1" 2
        ;;
    esac
  done

  if [[ -n "$requested_project" && -n "$coordinate_path" ]]; then
    fail "Use either --project or --coordinate with validate, not both." 2
  fi

  require_commands bash codex diff git grep jq

  if [[ -n "$coordinate_path" ]]; then
    selected_project=""
    selected_coordinate="$(canonical_git_root "$coordinate_path" "Coordination repository")"
  else
    resolve_project "$requested_project"
  fi

  validate_project_files "$selected_coordinate"

  codex_interactive_help="$(codex --help 2>&1)"

  for required_flag in --cd --profile --config; do
    if [[ "$codex_interactive_help" != *"$required_flag"* ]]; then
      fail "Installed Codex CLI does not support: $required_flag"
    fi
  done

  codex_exec_help="$(codex exec --help 2>&1)"

  for required_flag in --cd --ephemeral --json --model --profile --config --output-schema --output-last-message; do
    if [[ "$codex_exec_help" != *"$required_flag"* ]]; then
      fail "Installed Codex CLI does not support: $required_flag"
    fi
  done

  if [[ -n "$selected_project" ]]; then
    echo "RepoChord project validation passed: $selected_project"
  else
    echo "RepoChord coordination repository validation passed: $validated_coordinate_root"
  fi
}
