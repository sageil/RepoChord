run_start() {
  local requested_project=""
  local requested_model=""
  local requested_coordinator_reasoning_effort=""
  local requested_repository_agent_reasoning_effort=""
  local requested_max_parallel=""
  local requested_max_attempts=""
  local allow_dirty_source=false
  local effective_model
  local effective_coordinator_reasoning_effort
  local effective_repository_agent_reasoning_effort
  local effective_max_parallel
  local effective_max_attempts
  local repository_keys=()
  local codex_arguments=()
  local selected_keys=()
  local selected_paths=()
  local repository_key
  local selected_key
  local repository_path
  local canonical_repository_path
  local launch_arguments
  local user_codex_home
  local installation_id_toml_key
  local codex_tmp_toml_key
  local coordinate_scratch_toml_key
  local broker_requests_toml_key
  local coordinator_permissions
  local coordinator_scratch_directory=""
  local broker_directory=""
  local broker_requests_directory
  local broker_responses_directory
  local broker_registry_snapshot
  local broker_script
  local runner_script
  local broker_pid=""
  local codex_status=0
  local index

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
      -r|--repository)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        repository_keys+=("$2")
        shift 2
        ;;
      --max-attempts)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        requested_max_attempts="$2"
        shift 2
        ;;
      --allow-dirty-source)
        allow_dirty_source=true
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
      --)
        shift
        codex_arguments=("$@")
        break
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown start argument: $1. Put Codex arguments after --." 2
        ;;
    esac
  done

  validate_forwarded_codex_arguments "${codex_arguments[@]}"

  require_commands bash codex diff git grep jq mktemp

  if [[ -n "${CODEX_HOME:-}" ]]; then
    user_codex_home="$CODEX_HOME"
  elif [[ -n "${HOME:-}" ]]; then
    user_codex_home="$HOME/.codex"
  else
    fail "HOME and CODEX_HOME are unset." 2
  fi

  if [[ "$user_codex_home" != /* ]]; then
    fail "CODEX_HOME must be absolute: $user_codex_home" 2
  fi

  validate_safe_path_text "$user_codex_home" "CODEX_HOME"

  resolve_project "$requested_project"
  validate_project_files "$selected_coordinate"

  if [[ -n "$requested_model" ]]; then
    validate_model "$requested_model"
    effective_model="$requested_model"
  else
    effective_model="$(resolve_project_model "$selected_project")"
    validate_model "$effective_model"
  fi

  if [[ -n "$requested_coordinator_reasoning_effort" ]]; then
    validate_reasoning_effort "$requested_coordinator_reasoning_effort"
    effective_coordinator_reasoning_effort="$requested_coordinator_reasoning_effort"
  else
    effective_coordinator_reasoning_effort="$(resolve_project_coordinator_reasoning_effort "$selected_project")"
    validate_reasoning_effort "$effective_coordinator_reasoning_effort"
  fi

  if [[ -n "$requested_repository_agent_reasoning_effort" ]]; then
    validate_reasoning_effort "$requested_repository_agent_reasoning_effort"
    effective_repository_agent_reasoning_effort="$requested_repository_agent_reasoning_effort"
  else
    effective_repository_agent_reasoning_effort="$(resolve_project_repository_agent_reasoning_effort "$selected_project")"
    validate_reasoning_effort "$effective_repository_agent_reasoning_effort"
  fi

  if [[ -n "$requested_max_parallel" ]]; then
    validate_max_parallel "$requested_max_parallel"
    effective_max_parallel="$requested_max_parallel"
  else
    effective_max_parallel="$(resolve_project_max_parallel "$selected_project")"
    validate_max_parallel "$effective_max_parallel"
  fi

  if [[ -n "$requested_max_attempts" ]]; then
    validate_max_attempts "$requested_max_attempts"
    effective_max_attempts="$requested_max_attempts"
  else
    effective_max_attempts="$(resolve_project_max_attempts "$selected_project")"
    validate_max_attempts "$effective_max_attempts"
  fi

  if [[ "${#repository_keys[@]}" -eq 0 ]]; then
    while IFS= read -r repository_key; do
      repository_keys+=("$repository_key")
    done < <(jq -r '.repositories[].key' "$validated_repository_registry")
  fi

  for repository_key in "${repository_keys[@]}"; do
    validate_repository_key "$repository_key"

    for selected_key in ${selected_keys[@]+"${selected_keys[@]}"}; do
      if [[ "$selected_key" == "$repository_key" ]]; then
        fail "Duplicate repository key: $repository_key" 2
      fi
    done

    repository_path="$(jq -r --arg key "$repository_key" '
      [.repositories[] | select(.key == $key)] |
      if length == 1 then .[0].path else "" end
    ' "$validated_repository_registry")"

    if [[ -z "$repository_path" ]]; then
      fail "Repository key is not registered: $repository_key" 2
    fi

    canonical_repository_path="$(validate_product_repository "$repository_path")"
    selected_keys+=("$repository_key")
    selected_paths+=("$canonical_repository_path")
  done

  cleanup_start() {
    local cleanup_status="$?"

    if [[ -n "$broker_pid" ]] && kill -0 "$broker_pid" >/dev/null 2>&1; then
      kill "$broker_pid" >/dev/null 2>&1 || true
      wait "$broker_pid" >/dev/null 2>&1 || true
    fi

    if [[ -n "$broker_directory" && -d "$broker_directory" ]]; then
      rm -rf -- "$broker_directory"
    fi

    if [[ -n "$coordinator_scratch_directory" && -d "$coordinator_scratch_directory" ]]; then
      rm -rf -- "$coordinator_scratch_directory"
    fi

    return "$cleanup_status"
  }

  trap cleanup_start EXIT

  coordinator_scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/repochord-coordinator.XXXXXX")"
  broker_directory="$(mktemp -d "${TMPDIR:-/tmp}/repochord-broker.XXXXXX")"
  coordinator_scratch_directory="$(cd -- "$coordinator_scratch_directory" && pwd -P)"
  broker_directory="$(cd -- "$broker_directory" && pwd -P)"
  broker_requests_directory="$broker_directory/requests"
  broker_responses_directory="$broker_directory/responses"
  broker_registry_snapshot="$broker_directory/repositories.json"
  broker_script="$validated_coordinate_root/.agents/skills/repochord/scripts/repository-agent-broker.sh"
  runner_script="$validated_coordinate_root/.agents/skills/repochord/scripts/run-repository-agents.sh"
  mkdir "$broker_requests_directory" "$broker_responses_directory"
  chmod 700 "$coordinator_scratch_directory" "$broker_directory" "$broker_requests_directory" "$broker_responses_directory"

  for ((index = 0; index < ${#selected_keys[@]}; index++)); do
    jq -n \
      --arg key "${selected_keys[$index]}" \
      --arg path "${selected_paths[$index]}" \
      '{key: $key, path: $path}'
  done | jq -s '{version: 1, repositories: .}' > "$broker_registry_snapshot"

  bash "$broker_script" \
    "$broker_directory" \
    "$validated_coordinate_root" \
    "$runner_script" \
    "$broker_registry_snapshot" \
    > "$broker_directory/broker.stdout" \
    2> "$broker_directory/broker.stderr" &
  broker_pid="$!"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -f "$broker_directory/ready" ]]; then
      break
    fi

    if ! kill -0 "$broker_pid" >/dev/null 2>&1; then
      cat "$broker_directory/broker.stderr" >&2
      fail "RepoChord repository-agent broker did not start."
    fi

    sleep 0.1
  done

  if [[ ! -f "$broker_directory/ready" ]]; then
    fail "RepoChord repository-agent broker did not become ready."
  fi

  launch_arguments=(
    -C "$validated_coordinate_root"
  )

  if [[ "${#codex_arguments[@]}" -gt 0 ]]; then
    launch_arguments+=("${codex_arguments[@]}")
  fi

  installation_id_toml_key="$(jq -Rn --arg value "$user_codex_home/installation_id" '$value')"
  codex_tmp_toml_key="$(jq -Rn --arg value "$user_codex_home/tmp" '$value')"
  coordinate_scratch_toml_key="$(jq -Rn --arg value "$coordinator_scratch_directory" '$value')"
  broker_requests_toml_key="$(jq -Rn --arg value "$broker_requests_directory" '$value')"
  coordinator_permissions="permissions.repochord-coordinator={ filesystem = { \":root\" = \"read\", \":workspace_roots\" = { \".\" = \"write\", \".git\" = \"read\", \".agents\" = \"read\", \".codex\" = \"read\" }, $coordinate_scratch_toml_key = \"write\", $broker_requests_toml_key = \"write\", $installation_id_toml_key = \"write\", $codex_tmp_toml_key = \"write\" }, network = { enabled = true, allow_local_binding = true, domains = { \"*\" = \"allow\" } } }"

  launch_arguments+=(
    --config "model_reasoning_effort=\"$effective_coordinator_reasoning_effort\""
    --config 'features.network_proxy=true'
    --config "$coordinator_permissions"
    --config 'default_permissions="repochord-coordinator"'
  )

  export REPOCHORD_MAX_ATTEMPTS="$effective_max_attempts"
  export REPOCHORD_MODEL="$effective_model"
  export REPOCHORD_MAX_PARALLEL="$effective_max_parallel"
  export REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT="$effective_repository_agent_reasoning_effort"
  export REPOCHORD_ALLOW_DIRTY_SOURCE="$allow_dirty_source"
  export REPOCHORD_BROKER_DIRECTORY="$broker_directory"
  export TMPDIR="$coordinator_scratch_directory"

  codex "${launch_arguments[@]}" || codex_status="$?"
  cleanup_start
  trap - EXIT
  return "$codex_status"
}
