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
