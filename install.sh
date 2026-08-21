#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: install.sh [--upgrade] [--bin-dir <absolute-directory>] [--default-model <model>] [--default-coordinator-reasoning-effort <effort>] [--default-repository-agent-reasoning-effort <effort>] [--default-max-parallel <count>]" >&2
}

is_rchord_command() {
  local path="$1"

  [[ -f "$path" ]] &&
    grep -Fq 'rchord init -p <name>' "$path" &&
    grep -Fq 'source_skill="$repochord_data_directory/skill"' "$path"
}

is_repochord_skill() {
  local path="$1"

  [[ -d "$path" && -f "$path/SKILL.md" ]] && grep -Fq 'name: repochord' "$path/SKILL.md"
}

is_repochord_task_skill() {
  local path="$1"

  [[ -d "$path" && -f "$path/SKILL.md" ]] && grep -Fq 'name: create-repochord-task' "$path/SKILL.md"
}

replace_managed_directory() {
  local source_directory="$1"
  local destination_directory="$2"
  local validator="$3"
  local make_scripts_executable="$4"
  local parent_directory
  local replacement_directory
  local previous_directory=""

  parent_directory="$(dirname -- "$destination_directory")"
  replacement_directory="$(mktemp -d "$parent_directory/.repochord-replacement.XXXXXX")"

  if ! cp -R "$source_directory/." "$replacement_directory/"; then
    rm -rf -- "$replacement_directory"
    return 1
  fi

  if [[ "$make_scripts_executable" == true ]] &&
    ! chmod +x "$replacement_directory"/scripts/*.sh
  then
    rm -rf -- "$replacement_directory"
    return 1
  fi

  if ! "$validator" "$replacement_directory" >/dev/null; then
    rm -rf -- "$replacement_directory"
    return 1
  fi

  if [[ -d "$destination_directory" ]]; then
    previous_directory="$(mktemp -d "$parent_directory/.repochord-previous.XXXXXX")"
    rmdir "$previous_directory"

    if ! mv -- "$destination_directory" "$previous_directory"; then
      rm -rf -- "$replacement_directory"
      return 1
    fi
  fi

  if ! mv -- "$replacement_directory" "$destination_directory"; then
    if [[ -n "$previous_directory" ]]; then
      if ! mv -- "$previous_directory" "$destination_directory"; then
        echo "Could not restore the previous RepoChord directory. Recovery copy: $previous_directory" >&2
      fi
    fi
    rm -rf -- "$replacement_directory"
    return 1
  fi

  if ! "$validator" "$destination_directory" >/dev/null ||
    ! diff -qr "$source_directory" "$destination_directory" >/dev/null
  then
    rm -rf -- "$destination_directory"
    if [[ -n "$previous_directory" ]]; then
      if ! mv -- "$previous_directory" "$destination_directory"; then
        echo "Could not restore the previous RepoChord directory. Recovery copy: $previous_directory" >&2
      fi
    fi
    return 1
  fi

  if [[ -n "$previous_directory" ]]; then
    rm -rf -- "$previous_directory"
  fi
}

validate_reasoning_effort() {
  local value="$1"

  case "$value" in
    minimal|low|medium|high|xhigh)
      ;;
    *)
      echo "Reasoning effort must be one of minimal, low, medium, high, or xhigh: $value" >&2
      exit 2
      ;;
  esac
}

validate_projects_registry_file() {
  local registry_path="$1"

  jq -e '
    def valid_reasoning_effort:
      . == "minimal" or . == "low" or . == "medium" or . == "high" or . == "xhigh";

    .version == 1 and
    ((.defaults // {}) | type == "object") and
    ((.defaults.maxAttempts // 3) | type == "number") and
    ((.defaults.maxAttempts // 3) | floor == .) and
    ((.defaults.maxAttempts // 3) >= 1) and
    ((.defaults.maxAttempts // 3) <= 999999999) and
    ((.defaults.model // "gpt-5.6-terra") | type == "string") and
    ((.defaults.model // "gpt-5.6-terra") | length > 0) and
    ((.defaults.model // "gpt-5.6-terra") | test("[[:space:]]") | not) and
    ((.defaults.coordinatorReasoningEffort // "medium") | valid_reasoning_effort) and
    ((.defaults.repositoryAgentReasoningEffort // "high") | valid_reasoning_effort) and
    ((.defaults.maxParallel // 2) | type == "number") and
    ((.defaults.maxParallel // 2) | floor == .) and
    ((.defaults.maxParallel // 2) >= 1) and
    ((.defaults.maxParallel // 2) <= 999999999) and
    (.projects | type == "array") and
    ([.projects[].name] | length == (unique | length)) and
    ([.projects[].coordinate] | length == (unique | length)) and
    all(.projects[];
      (.name | type == "string") and
      (.name | test("^[A-Za-z0-9._-]+$")) and
      (.coordinate | type == "string") and
      (.coordinate | startswith("/")) and
      (.coordinate | test("[\\t\\r\\n]") | not) and
      ((has("maxAttempts") | not) or
        ((.maxAttempts | type == "number") and
         (.maxAttempts | floor == .) and
         (.maxAttempts >= 1) and
         (.maxAttempts <= 999999999))) and
      ((has("model") | not) or
        ((.model | type == "string") and
         (.model | length > 0) and
         (.model | test("[[:space:]]") | not))) and
      ((has("coordinatorReasoningEffort") | not) or
        (.coordinatorReasoningEffort | valid_reasoning_effort)) and
      ((has("repositoryAgentReasoningEffort") | not) or
        (.repositoryAgentReasoningEffort | valid_reasoning_effort)) and
      ((has("maxParallel") | not) or
        ((.maxParallel | type == "number") and
         (.maxParallel | floor == .) and
         (.maxParallel >= 1) and
         (.maxParallel <= 999999999)))
    )
  ' "$registry_path" >/dev/null
}

bin_directory=""
upgrade_install=false
default_model="gpt-5.6-terra"
default_model_explicit=false
default_coordinator_reasoning_effort="medium"
default_coordinator_reasoning_effort_explicit=false
default_repository_agent_reasoning_effort="high"
default_repository_agent_reasoning_effort_explicit=false
default_max_parallel="2"
default_max_parallel_explicit=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --upgrade)
      upgrade_install=true
      shift
      ;;
    --bin-dir)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      bin_directory="$2"
      shift 2
      ;;
    --default-model)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      default_model="$2"
      default_model_explicit=true
      shift 2
      ;;
    --default-coordinator-reasoning-effort)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      default_coordinator_reasoning_effort="$2"
      default_coordinator_reasoning_effort_explicit=true
      shift 2
      ;;
    --default-repository-agent-reasoning-effort)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      default_repository_agent_reasoning_effort="$2"
      default_repository_agent_reasoning_effort_explicit=true
      shift 2
      ;;
    --default-max-parallel)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      default_max_parallel="$2"
      default_max_parallel_explicit=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$default_model" =~ [[:space:]] ]]; then
  echo "Default model must not contain whitespace: $default_model" >&2
  exit 2
fi

validate_reasoning_effort "$default_coordinator_reasoning_effort"
validate_reasoning_effort "$default_repository_agent_reasoning_effort"

if [[ ! "$default_max_parallel" =~ ^[1-9][0-9]*$ || "${#default_max_parallel}" -gt 9 ]]; then
  echo "Default maximum parallel repository agents must be a positive integer no greater than 999999999: $default_max_parallel" >&2
  exit 2
fi

if [[ -z "${HOME:-}" && -z "${XDG_DATA_HOME:-}" && -z "${REPOCHORD_DATA_HOME:-}" ]]; then
  echo "HOME, XDG_DATA_HOME, and REPOCHORD_DATA_HOME are unset." >&2
  exit 2
fi

if [[ -z "$bin_directory" ]]; then
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    bin_directory="$XDG_BIN_HOME"
  elif [[ -n "${HOME:-}" ]]; then
    bin_directory="$HOME/.local/bin"
  else
    echo "HOME and XDG_BIN_HOME are both unset. Use --bin-dir." >&2
    exit 2
  fi
fi

if [[ "$bin_directory" != /* ]]; then
  echo "Command directory must be an absolute path: $bin_directory" >&2
  exit 2
fi

if [[ -n "${REPOCHORD_DATA_HOME:-}" ]]; then
  data_directory="$REPOCHORD_DATA_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  data_directory="$XDG_DATA_HOME/repochord"
else
  data_directory="$HOME/.local/share/repochord"
fi

if [[ "$data_directory" != /* ]]; then
  echo "RepoChord data directory must be an absolute path: $data_directory" >&2
  exit 2
fi

if [[ -n "${REPOCHORD_CONFIG_HOME:-}" ]]; then
  config_directory="$REPOCHORD_CONFIG_HOME"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  config_directory="$XDG_CONFIG_HOME/repochord"
elif [[ -n "${HOME:-}" ]]; then
  config_directory="$HOME/.config/repochord"
else
  echo "HOME, XDG_CONFIG_HOME, and REPOCHORD_CONFIG_HOME are unset." >&2
  exit 2
fi

if [[ "$config_directory" != /* ]]; then
  echo "RepoChord configuration directory must be an absolute path: $config_directory" >&2
  exit 2
fi

for required_command in cp diff grep jq mktemp mv; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

installer_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_command="$installer_directory/payload/rchord"
source_skill="$installer_directory/payload/.agents/skills/repochord"
source_task_skill="$installer_directory/payload/.agents/skills/create-repochord-task"
skill_validator="$installer_directory/scripts/validate-skill.sh"
task_skill_validator="$installer_directory/scripts/validate-task-skill.sh"

if [[ ! -f "$source_command" ]]; then
  echo "RepoChord command payload is missing: $source_command" >&2
  exit 1
fi

if [[ ! -d "$source_skill" ]]; then
  echo "RepoChord skill payload is missing: $source_skill" >&2
  exit 1
fi

if [[ ! -d "$source_task_skill" ]]; then
  echo "RepoChord task-authoring skill payload is missing: $source_task_skill" >&2
  exit 1
fi

if [[ ! -x "$skill_validator" ]]; then
  echo "RepoChord skill validator is missing or not executable: $skill_validator" >&2
  exit 1
fi

if [[ ! -x "$task_skill_validator" ]]; then
  echo "RepoChord task-authoring skill validator is missing or not executable: $task_skill_validator" >&2
  exit 1
fi

if [[ ! -x "$source_command" ]]; then
  echo "RepoChord command payload is not executable: $source_command" >&2
  exit 1
fi

"$skill_validator" "$source_skill" >/dev/null
"$task_skill_validator" "$source_task_skill" >/dev/null

if [[ -e "$bin_directory" && ! -d "$bin_directory" ]]; then
  echo "Command directory is not a directory: $bin_directory" >&2
  exit 2
fi

if [[ -e "$data_directory" && ! -d "$data_directory" ]]; then
  echo "RepoChord data path is not a directory: $data_directory" >&2
  exit 2
fi

if [[ -L "$config_directory" ]]; then
  echo "Refusing to use a symbolic link as the RepoChord configuration directory: $config_directory" >&2
  exit 1
fi

if [[ -e "$config_directory" && ! -d "$config_directory" ]]; then
  echo "RepoChord configuration path is not a directory: $config_directory" >&2
  exit 2
fi

command_path="$bin_directory/rchord"
installed_skill="$data_directory/skill"
installed_task_skill="$data_directory/task-skill"
projects_registry="$config_directory/projects.json"

if [[ -L "$command_path" ]]; then
  echo "Refusing to use a symbolic link as the RepoChord command: $command_path" >&2
  exit 1
fi

if [[ -L "$installed_skill" ]]; then
  echo "Refusing to use a symbolic link as the RepoChord skill: $installed_skill" >&2
  exit 1
fi

if [[ -L "$installed_task_skill" ]]; then
  echo "Refusing to use a symbolic link as the RepoChord task-authoring skill: $installed_task_skill" >&2
  exit 1
fi

if [[ -L "$projects_registry" ]]; then
  echo "Refusing to use a symbolic link as the RepoChord project registry: $projects_registry" >&2
  exit 1
fi

if [[ -e "$projects_registry" && ! -f "$projects_registry" ]]; then
  echo "RepoChord project registry is not a regular file: $projects_registry" >&2
  exit 2
fi

if [[ -f "$projects_registry" ]] && ! validate_projects_registry_file "$projects_registry"; then
  echo "RepoChord project registry is invalid: $projects_registry" >&2
  exit 1
fi

if [[ -e "$command_path" ]] && ! diff -q "$source_command" "$command_path" >/dev/null; then
  if [[ "$upgrade_install" != true ]]; then
    echo "Command path already contains a different file: $command_path" >&2
    echo "Use --upgrade to replace an existing RepoChord installation." >&2
    exit 1
  fi

  if ! is_rchord_command "$command_path"; then
    echo "Refusing to replace a command that is not an identifiable RepoChord command: $command_path" >&2
    exit 1
  fi
fi

if [[ -e "$installed_skill" ]] && ! diff -qr "$source_skill" "$installed_skill" >/dev/null; then
  if [[ "$upgrade_install" != true ]]; then
    echo "Installed RepoChord skill differs from this package: $installed_skill" >&2
    echo "Use --upgrade to replace an existing RepoChord installation." >&2
    exit 1
  fi

  if ! is_repochord_skill "$installed_skill"; then
    echo "Refusing to replace a directory that is not an identifiable RepoChord skill: $installed_skill" >&2
    exit 1
  fi
fi

if [[ -e "$installed_task_skill" ]] && ! diff -qr "$source_task_skill" "$installed_task_skill" >/dev/null; then
  if [[ "$upgrade_install" != true ]]; then
    echo "Installed RepoChord task-authoring skill differs from this package: $installed_task_skill" >&2
    echo "Use --upgrade to replace an existing RepoChord installation." >&2
    exit 1
  fi

  if ! is_repochord_task_skill "$installed_task_skill"; then
    echo "Refusing to replace a directory that is not an identifiable RepoChord task-authoring skill: $installed_task_skill" >&2
    exit 1
  fi
fi

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
