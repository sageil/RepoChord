#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: install.sh [--bin-dir <absolute-directory>]" >&2
}

bin_directory=""

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

if [[ -z "${HOME:-}" && -z "${XDG_DATA_HOME:-}" && -z "${REPOMUX_DATA_HOME:-}" ]]; then
  echo "HOME, XDG_DATA_HOME, and REPOMUX_DATA_HOME are unset." >&2
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

if [[ -n "${REPOMUX_DATA_HOME:-}" ]]; then
  data_directory="$REPOMUX_DATA_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  data_directory="$XDG_DATA_HOME/repomux"
else
  data_directory="$HOME/.local/share/repomux"
fi

if [[ "$data_directory" != /* ]]; then
  echo "RepoMux data directory must be an absolute path: $data_directory" >&2
  exit 2
fi

for required_command in cp diff jq mktemp mv; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command is not installed: $required_command" >&2
    exit 2
  fi
done

installer_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_command="$installer_directory/payload/repomux"
source_skill="$installer_directory/payload/.agents/skills/repomux"
skill_validator="$installer_directory/scripts/validate-skill.sh"

if [[ ! -f "$source_command" ]]; then
  echo "RepoMux command payload is missing: $source_command" >&2
  exit 1
fi

if [[ ! -d "$source_skill" ]]; then
  echo "RepoMux skill payload is missing: $source_skill" >&2
  exit 1
fi

if [[ ! -x "$skill_validator" ]]; then
  echo "RepoMux skill validator is missing or not executable: $skill_validator" >&2
  exit 1
fi

if [[ ! -x "$source_command" ]]; then
  echo "RepoMux command payload is not executable: $source_command" >&2
  exit 1
fi

"$skill_validator" "$source_skill" >/dev/null

if [[ -e "$bin_directory" && ! -d "$bin_directory" ]]; then
  echo "Command directory is not a directory: $bin_directory" >&2
  exit 2
fi

if [[ -e "$data_directory" && ! -d "$data_directory" ]]; then
  echo "RepoMux data path is not a directory: $data_directory" >&2
  exit 2
fi

command_path="$bin_directory/repomux"
installed_skill="$data_directory/skill"

if [[ -L "$command_path" ]]; then
  echo "Refusing to use a symbolic link as the RepoMux command: $command_path" >&2
  exit 1
fi

if [[ -L "$installed_skill" ]]; then
  echo "Refusing to use a symbolic link as the RepoMux skill: $installed_skill" >&2
  exit 1
fi

if [[ -e "$command_path" ]] && ! diff -q "$source_command" "$command_path" >/dev/null; then
  echo "Command path already contains a different file: $command_path" >&2
  exit 1
fi

if [[ -e "$installed_skill" ]] && ! diff -qr "$source_skill" "$installed_skill" >/dev/null; then
  echo "Installed RepoMux skill differs from this package: $installed_skill" >&2
  exit 1
fi

command_stage=""
skill_stage=""

cleanup() {
  if [[ -n "$command_stage" ]]; then
    rm -f -- "$command_stage"
  fi

  if [[ -n "$skill_stage" ]]; then
    rm -rf -- "$skill_stage"
  fi
}

trap cleanup EXIT

mkdir -p "$bin_directory" "$data_directory"
bin_directory="$(cd -- "$bin_directory" && pwd -P)"
data_directory="$(cd -- "$data_directory" && pwd -P)"
command_path="$bin_directory/repomux"
installed_skill="$data_directory/skill"

if [[ ! -e "$installed_skill" ]]; then
  skill_stage="$(mktemp -d "$data_directory/.skill.XXXXXX")"
  cp -R "$source_skill/." "$skill_stage/"
  chmod +x "$skill_stage"/scripts/*.sh
  "$skill_validator" "$skill_stage" >/dev/null
  mv -- "$skill_stage" "$installed_skill"
  skill_stage=""
fi

chmod +x "$installed_skill"/scripts/*.sh

if [[ ! -e "$command_path" ]]; then
  command_stage="$(mktemp "$bin_directory/.repomux.XXXXXX")"
  cp "$source_command" "$command_stage"
  chmod +x "$command_stage"
  mv -- "$command_stage" "$command_path"
  command_stage=""
fi

chmod +x "$command_path"

echo "RepoMux installed."
echo "Command: $command_path"
echo "Data: $data_directory"

case ":${PATH:-}:" in
  *":$bin_directory:"*)
    ;;
  *)
    echo "Add this command directory to PATH in your shell profile:"
    printf "  export PATH=%q:\$PATH\n" "$bin_directory"
    ;;
esac

echo "Next: repomux init -p <name> -c <path> -r <key=path>"
