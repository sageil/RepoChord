#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: uninstall.sh [--bin-dir <absolute-directory>] [--purge-config]" >&2
}

bin_directory=""
purge_config=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --bin-dir)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        usage
        exit 2
      fi

      bin_directory="$2"
      shift 2
      ;;
    --purge-config)
      purge_config=true
      shift
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

if [[ -n "${REPOMUX_DATA_HOME:-}" ]]; then
  data_directory="$REPOMUX_DATA_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  data_directory="$XDG_DATA_HOME/repomux"
elif [[ -n "${HOME:-}" ]]; then
  data_directory="$HOME/.local/share/repomux"
else
  echo "HOME, XDG_DATA_HOME, and REPOMUX_DATA_HOME are unset." >&2
  exit 2
fi

if [[ "$data_directory" != /* ]]; then
  echo "RepoMux data directory must be an absolute path: $data_directory" >&2
  exit 2
fi

if [[ -n "${REPOMUX_CONFIG_HOME:-}" ]]; then
  config_directory="$REPOMUX_CONFIG_HOME"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  config_directory="$XDG_CONFIG_HOME/repomux"
elif [[ -n "${HOME:-}" ]]; then
  config_directory="$HOME/.config/repomux"
else
  echo "HOME, XDG_CONFIG_HOME, and REPOMUX_CONFIG_HOME are unset." >&2
  exit 2
fi

if [[ "$config_directory" != /* ]]; then
  echo "RepoMux configuration directory must be an absolute path: $config_directory" >&2
  exit 2
fi

for required_command in rm rmdir; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

if [[ -e "$bin_directory" && ! -d "$bin_directory" ]]; then
  echo "Command directory is not a directory: $bin_directory" >&2
  exit 2
fi

if [[ -e "$data_directory" && ! -d "$data_directory" ]]; then
  echo "RepoMux data path is not a directory: $data_directory" >&2
  exit 2
fi

if [[ -e "$config_directory" && ! -d "$config_directory" ]]; then
  echo "RepoMux configuration path is not a directory: $config_directory" >&2
  exit 2
fi

if [[ -d "$bin_directory" ]]; then
  bin_directory="$(cd -- "$bin_directory" && pwd -P)"
fi

if [[ -d "$data_directory" ]]; then
  data_directory="$(cd -- "$data_directory" && pwd -P)"
fi

if [[ -d "$config_directory" ]]; then
  config_directory="$(cd -- "$config_directory" && pwd -P)"
fi

command_path="$bin_directory/repomux"
installed_skill="$data_directory/skill"
projects_registry="$config_directory/projects.json"

if [[ -d "$command_path" && ! -L "$command_path" ]]; then
  echo "Refusing to recursively remove a directory as the RepoMux command: $command_path" >&2
  exit 1
fi

if [[ "$purge_config" == true && -d "$projects_registry" && ! -L "$projects_registry" ]]; then
  echo "Refusing to recursively remove a directory as the RepoMux project registry: $projects_registry" >&2
  exit 1
fi

command_removed=false
skill_removed=false
config_removed=false

if [[ -e "$command_path" || -L "$command_path" ]]; then
  rm -f -- "$command_path"
  command_removed=true
fi

if [[ -L "$installed_skill" ]]; then
  rm -f -- "$installed_skill"
  skill_removed=true
elif [[ -d "$installed_skill" ]]; then
  rm -rf -- "$installed_skill"
  skill_removed=true
elif [[ -e "$installed_skill" ]]; then
  rm -f -- "$installed_skill"
  skill_removed=true
fi

if [[ "$purge_config" == true ]]; then
  if [[ -L "$projects_registry" ]]; then
    rm -f -- "$projects_registry"
    config_removed=true
  elif [[ -e "$projects_registry" ]]; then
    rm -f -- "$projects_registry"
    config_removed=true
  fi
fi

rmdir "$data_directory" >/dev/null 2>&1 || true

if [[ "$purge_config" == true ]]; then
  rmdir "$config_directory" >/dev/null 2>&1 || true
fi

echo "RepoMux uninstalled."

if [[ "$command_removed" == true ]]; then
  echo "Command removed: $command_path"
else
  echo "Command was not installed: $command_path"
fi

if [[ "$skill_removed" == true ]]; then
  echo "Shared skill removed: $installed_skill"
else
  echo "Shared skill was not installed: $installed_skill"
fi

if [[ "$purge_config" == true ]]; then
  if [[ "$config_removed" == true ]]; then
    echo "Configuration removed: $projects_registry"
  else
    echo "Configuration was not installed: $projects_registry"
  fi
elif [[ -e "$projects_registry" || -L "$projects_registry" ]]; then
  echo "Configuration preserved: $projects_registry"
else
  echo "Configuration was not installed: $projects_registry"
fi

echo "Coordination repositories, product repositories, worktrees, branches, commits, and results were preserved."
