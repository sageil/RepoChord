command_stage=""
projects_stage=""

cleanup() {
  if [[ -n "$command_stage" ]]; then
    rm -f -- "$command_stage"
  fi

  if [[ -n "$projects_stage" ]]; then
    rm -f -- "$projects_stage"
  fi
}

trap cleanup EXIT

mkdir -p "$bin_directory" "$data_directory" "$config_directory"
bin_directory="$(cd -- "$bin_directory" && pwd -P)"
data_directory="$(cd -- "$data_directory" && pwd -P)"
config_directory="$(cd -- "$config_directory" && pwd -P)"
command_path="$bin_directory/rchord"
installed_skill="$data_directory/skill"
installed_task_skill="$data_directory/task-skill"
projects_registry="$config_directory/projects.json"

projects_stage="$(mktemp "$config_directory/.projects.XXXXXX")"

if [[ -f "$projects_registry" ]]; then
  jq \
    --arg default_model "$default_model" \
    --arg default_model_explicit "$default_model_explicit" \
    --arg default_coordinator_reasoning_effort "$default_coordinator_reasoning_effort" \
    --arg default_coordinator_reasoning_effort_explicit "$default_coordinator_reasoning_effort_explicit" \
    --arg default_repository_agent_reasoning_effort "$default_repository_agent_reasoning_effort" \
    --arg default_repository_agent_reasoning_effort_explicit "$default_repository_agent_reasoning_effort_explicit" \
    --arg default_max_parallel "$default_max_parallel" \
    --arg default_max_parallel_explicit "$default_max_parallel_explicit" \
    '
      .defaults //= {} |
      .defaults.maxAttempts //= 3 |
      del(.defaults.agentOutput) |
      .projects |= map(del(.agentOutput)) |
      if $default_model_explicit == "true" then
        .defaults.model = $default_model
      else
        .defaults.model //= $default_model
      end |
      if $default_coordinator_reasoning_effort_explicit == "true" then
        .defaults.coordinatorReasoningEffort = $default_coordinator_reasoning_effort
      else
        .defaults.coordinatorReasoningEffort //= $default_coordinator_reasoning_effort
      end |
      if $default_repository_agent_reasoning_effort_explicit == "true" then
        .defaults.repositoryAgentReasoningEffort = $default_repository_agent_reasoning_effort
      else
        .defaults.repositoryAgentReasoningEffort //= $default_repository_agent_reasoning_effort
      end |
      if $default_max_parallel_explicit == "true" then
        .defaults.maxParallel = ($default_max_parallel | tonumber)
      else
        .defaults.maxParallel //= ($default_max_parallel | tonumber)
      end
    ' \
    "$projects_registry" > "$projects_stage"
else
  jq -n \
    --arg default_model "$default_model" \
    --arg default_coordinator_reasoning_effort "$default_coordinator_reasoning_effort" \
    --arg default_repository_agent_reasoning_effort "$default_repository_agent_reasoning_effort" \
    --argjson default_max_parallel "$default_max_parallel" \
    '{
      version: 1,
      defaults: {
        maxAttempts: 3,
        model: $default_model,
        coordinatorReasoningEffort: $default_coordinator_reasoning_effort,
        repositoryAgentReasoningEffort: $default_repository_agent_reasoning_effort,
        maxParallel: $default_max_parallel
      },
      projects: []
    }' \
    > "$projects_stage"
fi

if ! validate_projects_registry_file "$projects_stage"; then
  echo "Generated RepoChord project registry is invalid: $projects_stage" >&2
  exit 1
fi

if [[ ! -e "$command_path" ]] || ! diff -q "$source_command" "$command_path" >/dev/null; then
  command_stage="$(mktemp "$bin_directory/.repochord.XXXXXX")"
  cp "$source_command" "$command_stage"
  chmod +x "$command_stage"
  mv -- "$command_stage" "$command_path"
  command_stage=""
fi

chmod +x "$command_path"

if [[ ! -e "$installed_task_skill" ]] ||
  ! diff -qr "$source_task_skill" "$installed_task_skill" >/dev/null
then
  if ! replace_managed_directory \
    "$source_task_skill" \
    "$installed_task_skill" \
    "$task_skill_validator" \
    false
  then
    echo "Could not install the RepoChord task-authoring skill: $installed_task_skill" >&2
    exit 1
  fi
fi

if [[ ! -e "$installed_skill" ]] || ! diff -qr "$source_skill" "$installed_skill" >/dev/null; then
  if ! replace_managed_directory \
    "$source_skill" \
    "$installed_skill" \
    "$skill_validator" \
    true
  then
    echo "Could not install the RepoChord skill: $installed_skill" >&2
    exit 1
  fi
fi

chmod +x "$installed_skill"/scripts/*.sh

mv -- "$projects_stage" "$projects_registry"
projects_stage=""

echo "RepoChord installed."
echo "Command: $command_path"
echo "Data: $data_directory"
echo "Configuration: $projects_registry"
echo "Default repository-agent model: $(jq -r '.defaults.model' "$projects_registry")"
echo "Default coordinator reasoning effort: $(jq -r '.defaults.coordinatorReasoningEffort' "$projects_registry")"
echo "Default repository-agent reasoning effort: $(jq -r '.defaults.repositoryAgentReasoningEffort' "$projects_registry")"
echo "Default maximum parallel repository agents: $(jq -r '.defaults.maxParallel' "$projects_registry")"

case ":${PATH:-}:" in
  *":$bin_directory:"*)
    ;;
  *)
    echo "Add this command directory to PATH in your shell profile:"
    printf "  export PATH=%q:\$PATH\n" "$bin_directory"
    ;;
esac

echo "Next: rchord init -p <name> -c <path> -r <key=path>"
