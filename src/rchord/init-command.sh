prepare_coordinate_path() {
  local requested_path="$1"
  local create_coordinate="$2"
  local canonical_path
  local coordinate_parent
  local coordinate_name
  local git_root

  validate_safe_path_text "$requested_path" "Coordination repository path"

  if [[ -e "$requested_path" && ! -d "$requested_path" ]]; then
    fail "Coordination repository path is not a directory: $requested_path" 2
  fi

  if [[ -d "$requested_path" ]]; then
    canonical_path="$(cd -- "$requested_path" && pwd -P)"

    if git_root="$(git -C "$canonical_path" rev-parse --show-toplevel 2>/dev/null)"; then
      git_root="$(cd -- "$git_root" && pwd -P)"

      if [[ "$canonical_path" != "$git_root" ]]; then
        fail "Coordination repository path must be the Git repository root: $requested_path" 2
      fi

      prepared_coordinate_path="$git_root"
      coordinate_requires_git_init=false
      return
    fi

    if [[ "$create_coordinate" != true ]]; then
      fail "Coordination repository path is not a Git repository. Use --create-coordinate: $requested_path" 2
    fi

    if [[ -n "$(find "$canonical_path" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      fail "Refusing to initialize a nonempty coordination repository: $canonical_path" 2
    fi

    prepared_coordinate_path="$canonical_path"
    coordinate_requires_git_init=true
    return
  fi

  if [[ "$create_coordinate" != true ]]; then
    fail "Coordination repository path does not exist. Use --create-coordinate: $requested_path" 2
  fi

  coordinate_parent="$(dirname -- "$requested_path")"
  coordinate_name="$(basename -- "$requested_path")"

  if [[ ! -d "$coordinate_parent" ]]; then
    fail "Coordination repository parent does not exist: $coordinate_parent" 2
  fi

  coordinate_parent="$(cd -- "$coordinate_parent" && pwd -P)"

  if [[ "$coordinate_name" == "." || "$coordinate_name" == ".." || -z "$coordinate_name" ]]; then
    fail "Invalid coordination repository directory name: $coordinate_name" 2
  fi

  prepared_coordinate_path="$coordinate_parent/$coordinate_name"
  coordinate_requires_git_init=true
}

run_init() {
  local project_name=""
  local coordinate_path="$PWD"
  local create_coordinate=false
  local requested_model=""
  local requested_coordinator_reasoning_effort=""
  local requested_repository_agent_reasoning_effort=""
  local requested_max_parallel=""
  local repository_arguments=()
  local repository_keys=()
  local repository_paths=()
  local repository_argument
  local repository_key
  local repository_path
  local canonical_repository_path
  local existing_key
  local existing_path
  local coordinate_root
  local destination_skill
  local destination_task_skill
  local registry_path
  local existing_coordinate
  local existing_project
  temporary_repository_registry=""
  temporary_projects_registry=""
  registry_stage=""
  projects_stage=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -p|--project)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        project_name="$2"
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
      --create-coordinate)
        create_coordinate=true
        shift
        ;;
      --model)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_model="$2"
        shift 2
        ;;
      --coordinator-reasoning-effort)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_coordinator_reasoning_effort="$2"
        shift 2
        ;;
      --repository-agent-reasoning-effort)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_repository_agent_reasoning_effort="$2"
        shift 2
        ;;
      --max-parallel)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_max_parallel="$2"
        shift 2
        ;;
      -r|--repository)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        repository_arguments+=("$2")
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown init argument: $1" 2
        ;;
    esac
  done

  if [[ -z "$project_name" ]]; then
    fail "RepoChord init requires --project <name>." 2
  fi

  validate_project_name "$project_name"

  if [[ -n "$requested_model" ]]; then
    validate_model "$requested_model"
  fi

  if [[ -n "$requested_coordinator_reasoning_effort" ]]; then
    validate_reasoning_effort "$requested_coordinator_reasoning_effort"
  fi

  if [[ -n "$requested_repository_agent_reasoning_effort" ]]; then
    validate_reasoning_effort "$requested_repository_agent_reasoning_effort"
  fi

  if [[ -n "$requested_max_parallel" ]]; then
    validate_max_parallel "$requested_max_parallel"
  fi

  require_commands bash cp diff find git grep jq mktemp mv
  validate_skill_directory "$source_skill"
  validate_task_skill_directory "$source_task_skill"
  prepare_coordinate_path "$coordinate_path" "$create_coordinate"
  coordinate_root="$prepared_coordinate_path"

  for repository_argument in ${repository_arguments[@]+"${repository_arguments[@]}"}; do
    if [[ "$repository_argument" != *=* ]]; then
      fail "Invalid repository argument. Expected key=path: $repository_argument" 2
    fi

    repository_key="${repository_argument%%=*}"
    repository_path="${repository_argument#*=}"
    validate_repository_key "$repository_key"
    canonical_repository_path="$(validate_product_repository "$repository_path")"

    if [[ "$canonical_repository_path" == "$coordinate_root" ]]; then
      fail "A product repository cannot be the coordination repository: $canonical_repository_path" 2
    fi

    for existing_key in ${repository_keys[@]+"${repository_keys[@]}"}; do
      if [[ "$existing_key" == "$repository_key" ]]; then
        fail "Duplicate repository key: $repository_key" 2
      fi
    done

    for existing_path in ${repository_paths[@]+"${repository_paths[@]}"}; do
      if [[ "$existing_path" == "$canonical_repository_path" ]]; then
        fail "Duplicate canonical repository path: $canonical_repository_path" 2
      fi
    done

    repository_keys+=("$repository_key")
    repository_paths+=("$canonical_repository_path")
  done

  destination_skill="$coordinate_root/.agents/skills/repochord"
  destination_task_skill="$coordinate_root/.agents/skills/create-repochord-task"
  registry_path="$coordinate_root/.repochord/repositories.json"

  if [[ -L "$destination_skill" ]]; then
    fail "Refusing to use a symbolic link as the project skill: $destination_skill"
  fi

  if [[ -L "$destination_task_skill" ]]; then
    fail "Refusing to use a symbolic link as the project task-authoring skill: $destination_task_skill"
  fi

  if [[ -L "$registry_path" ]]; then
    fail "Refusing to use a symbolic link as the repository registry: $registry_path"
  fi

  if [[ "${#repository_keys[@]}" -eq 0 && ! -f "$registry_path" ]]; then
    fail "RepoChord init requires at least one --repository option for a new project." 2
  fi

  temporary_repository_registry="$(mktemp "${TMPDIR:-/tmp}/repochord-repositories.XXXXXX")"
  temporary_projects_registry="$(mktemp "${TMPDIR:-/tmp}/repochord-projects.XXXXXX")"

  cleanup_init() {
    rm -f -- "$temporary_repository_registry" "$temporary_projects_registry"

    if [[ -n "$registry_stage" ]]; then
      rm -f -- "$registry_stage"
    fi

    if [[ -n "$projects_stage" ]]; then
      rm -f -- "$projects_stage"
    fi
  }

  trap cleanup_init EXIT

  if [[ "${#repository_keys[@]}" -gt 0 ]]; then
    for ((repository_index = 0; repository_index < ${#repository_keys[@]}; repository_index++)); do
      jq -n \
        --arg key "${repository_keys[$repository_index]}" \
        --arg path "${repository_paths[$repository_index]}" \
        '{key: $key, path: $path}'
    done | jq -s '{version: 1, repositories: .}' > "$temporary_repository_registry"

    if [[ -e "$registry_path" ]] && ! diff -q "$temporary_repository_registry" "$registry_path" >/dev/null; then
      fail "Existing repository registry differs from the requested registry: $registry_path"
    fi
  else
    cp "$registry_path" "$temporary_repository_registry"
  fi

  for expected_directory in \
    "$coordinate_root/.agents" \
    "$coordinate_root/.agents/skills" \
    "$coordinate_root/.repochord" \
    "$coordinate_root/.repochord/repositories" \
    "$coordinate_root/.repochord/results" \
    "$coordinate_root/.repochord/worktrees" \
    "$coordinate_root/requests" \
    "$coordinate_root/tasks"
  do
    if [[ -L "$expected_directory" ]]; then
      fail "Refusing to use a symbolic link as a project directory: $expected_directory"
    fi

    if [[ -e "$expected_directory" && ! -d "$expected_directory" ]]; then
      fail "Project directory path contains a non-directory: $expected_directory"
    fi
  done

  if [[ -e "$repochord_config_directory" && ! -d "$repochord_config_directory" ]]; then
    fail "RepoChord configuration path is not a directory: $repochord_config_directory"
  fi

  if [[ -L "$projects_registry" ]]; then
    fail "Refusing to use a symbolic link as the project registry: $projects_registry"
  fi

  if [[ -e "$projects_registry" && ! -f "$projects_registry" ]]; then
    fail "RepoChord project registry is not a regular file: $projects_registry"
  fi

  if [[ -f "$projects_registry" ]]; then
    validate_projects_registry
    existing_coordinate="$(jq -r --arg name "$project_name" '
      [.projects[] | select(.name == $name)] |
      if length == 1 then .[0].coordinate else "" end
    ' "$projects_registry")"
    existing_project="$(jq -r --arg coordinate "$coordinate_root" '
      [.projects[] | select(.coordinate == $coordinate)] |
      if length == 1 then .[0].name else "" end
    ' "$projects_registry")"

    if [[ -n "$existing_coordinate" && "$existing_coordinate" != "$coordinate_root" ]]; then
      fail "Project name is already registered to another coordination repository: $project_name"
    fi

    if [[ -n "$existing_project" && "$existing_project" != "$project_name" ]]; then
      fail "Coordination repository is already registered as another project: $existing_project"
    fi

    jq \
      --arg name "$project_name" \
      --arg coordinate "$coordinate_root" \
      --arg model "$requested_model" \
      --arg coordinator_reasoning_effort "$requested_coordinator_reasoning_effort" \
      --arg repository_agent_reasoning_effort "$requested_repository_agent_reasoning_effort" \
      --arg max_parallel "$requested_max_parallel" \
      '
        def apply_overrides:
          if $model != "" then .model = $model else . end |
          if $coordinator_reasoning_effort != "" then
            .coordinatorReasoningEffort = $coordinator_reasoning_effort
          else
            .
          end |
          if $repository_agent_reasoning_effort != "" then
            .repositoryAgentReasoningEffort = $repository_agent_reasoning_effort
          else
            .
          end |
          if $max_parallel != "" then .maxParallel = ($max_parallel | tonumber) else . end;

        del(.defaults.agentOutput) |
        .projects |= map(del(.agentOutput)) |
        .defaults //= {} |
        .defaults.maxAttempts //= 3 |
        .defaults.model //= "gpt-5.6-terra" |
        .defaults.coordinatorReasoningEffort //= "medium" |
        .defaults.repositoryAgentReasoningEffort //= "high" |
        .defaults.maxParallel //= 2 |
        if any(.projects[]; .name == $name) then
          .projects |= map(
            if .name == $name then
              apply_overrides
            else
              .
            end
          )
        else
          .projects += [({name: $name, coordinate: $coordinate} | apply_overrides)]
        end |
        .projects |= sort_by(.name)
      ' \
      "$projects_registry" > "$temporary_projects_registry"
  else
    jq -n \
      --arg name "$project_name" \
      --arg coordinate "$coordinate_root" \
      --arg model "$requested_model" \
      --arg coordinator_reasoning_effort "$requested_coordinator_reasoning_effort" \
      --arg repository_agent_reasoning_effort "$requested_repository_agent_reasoning_effort" \
      --arg max_parallel "$requested_max_parallel" \
      '{
        version: 1,
        defaults: {
          maxAttempts: 3,
          model: "gpt-5.6-terra",
          coordinatorReasoningEffort: "medium",
          repositoryAgentReasoningEffort: "high",
          maxParallel: 2
        },
        projects: [{name: $name, coordinate: $coordinate}]
      } |
      if $model != "" then .projects[0].model = $model else . end |
      if $coordinator_reasoning_effort != "" then
        .projects[0].coordinatorReasoningEffort = $coordinator_reasoning_effort
      else
        .
      end |
      if $repository_agent_reasoning_effort != "" then
        .projects[0].repositoryAgentReasoningEffort = $repository_agent_reasoning_effort
      else
        .
      end |
      if $max_parallel != "" then .projects[0].maxParallel = ($max_parallel | tonumber) else . end' \
      > "$temporary_projects_registry"
  fi

  if [[ "$coordinate_requires_git_init" == true ]]; then
    mkdir -p "$coordinate_root"
    git -C "$coordinate_root" init -q
  fi

  mkdir -p \
    "$coordinate_root/.agents/skills" \
    "$coordinate_root/.repochord/repositories" \
    "$coordinate_root/.repochord/results" \
    "$coordinate_root/.repochord/worktrees" \
    "$coordinate_root/requests" \
    "$coordinate_root/tasks"

  if [[ ! -e "$coordinate_root/.repochord/results/.gitignore" ]]; then
    printf '*\n!.gitignore\n' > "$coordinate_root/.repochord/results/.gitignore"
  fi

  if [[ ! -e "$coordinate_root/.repochord/repositories/.gitignore" ]]; then
    printf '*\n!.gitignore\n' > "$coordinate_root/.repochord/repositories/.gitignore"
  fi

  if [[ ! -e "$coordinate_root/.repochord/worktrees/.gitignore" ]]; then
    printf '*\n!.gitignore\n' > "$coordinate_root/.repochord/worktrees/.gitignore"
  fi

  if [[ ! -e "$registry_path" ]]; then
    registry_stage="$(mktemp "$coordinate_root/.repochord/.repositories.XXXXXX")"
    cp "$temporary_repository_registry" "$registry_stage"
    mv -- "$registry_stage" "$registry_path"
    registry_stage=""
  fi

  upgrade_project_runtime "$coordinate_root" "$project_name"

  mkdir -p "$repochord_config_directory"

  if [[ ! -f "$projects_registry" ]] || ! diff -q "$temporary_projects_registry" "$projects_registry" >/dev/null; then
    projects_stage="$(mktemp "$repochord_config_directory/.projects.XXXXXX")"
    cp "$temporary_projects_registry" "$projects_stage"
    mv -- "$projects_stage" "$projects_registry"
    projects_stage=""
  fi

  validate_project_files "$coordinate_root"
  validate_projects_registry

  echo "RepoChord project initialized: $project_name"
  echo "Coordination repository: $coordinate_root"
  echo "Repository registry: $registry_path"
  echo "Skill: $destination_skill"
  echo "Task-authoring skill: $destination_task_skill"
}
