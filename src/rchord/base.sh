#!/usr/bin/env bash

# Generated from src/rchord by scripts/build-rchord.sh. Do not edit payload/rchord directly.

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  cat >&2 <<'EOF'
Usage:
  rchord init -p <name> [-c <path>] [--create-coordinate] [--model <model>] [--coordinator-reasoning-effort <effort>] [--repository-agent-reasoning-effort <effort>] [--max-parallel <count>] -r <key=path>...
  rchord [start] [-p <name>] [-r <key>]... [--model <model>] [--coordinator-reasoning-effort <effort>] [--repository-agent-reasoning-effort <effort>] [--max-parallel <count>] [--max-attempts <count>] [--allow-dirty-source] [-- <codex-argument>...]
  rchord config get [-p <name>] <model|coordinator-reasoning-effort|repository-agent-reasoning-effort|max-parallel|max-attempts>
  rchord config set [-p <name>] <model|coordinator-reasoning-effort|repository-agent-reasoning-effort|max-parallel|max-attempts> <value>
  rchord list [--details]
  rchord upgrade
  rchord validate [-p <name> | -c <path>]
  rchord report [-p <name>] --run <run-id>
  rchord integrate [-p <name>] --run <run-id> [--dry-run] [--show-diffs]
  rchord resume [-p <name>] --run <run-id> [--retry-blocked <key>]... [--max-attempts <count>]
  rchord cleanup [-p <name>] (--run <run-id> | --all) [-r <key>]... [--force]
  rchord completion <bash|zsh>
EOF
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

require_commands() {
  local required_command

  for required_command in "$@"; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
      fail "Required command is not installed: $required_command" 2
    fi
  done
}

initialize_locations() {
  if [[ -n "${REPOCHORD_DATA_HOME:-}" ]]; then
    repochord_data_directory="$REPOCHORD_DATA_HOME"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    repochord_data_directory="$XDG_DATA_HOME/repochord"
  elif [[ -n "${HOME:-}" ]]; then
    repochord_data_directory="$HOME/.local/share/repochord"
  else
    fail "HOME, XDG_DATA_HOME, and REPOCHORD_DATA_HOME are unset." 2
  fi

  if [[ -n "${REPOCHORD_CONFIG_HOME:-}" ]]; then
    repochord_config_directory="$REPOCHORD_CONFIG_HOME"
  elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    repochord_config_directory="$XDG_CONFIG_HOME/repochord"
  elif [[ -n "${HOME:-}" ]]; then
    repochord_config_directory="$HOME/.config/repochord"
  else
    fail "HOME, XDG_CONFIG_HOME, and REPOCHORD_CONFIG_HOME are unset." 2
  fi

  if [[ "$repochord_data_directory" != /* ]]; then
    fail "RepoChord data directory must be absolute: $repochord_data_directory" 2
  fi

  if [[ "$repochord_config_directory" != /* ]]; then
    fail "RepoChord configuration directory must be absolute: $repochord_config_directory" 2
  fi

  source_skill="$repochord_data_directory/skill"
  source_task_skill="$repochord_data_directory/task-skill"
  projects_registry="$repochord_config_directory/projects.json"
}

validate_project_name() {
  local project_name="$1"

  if [[ ! "$project_name" =~ ^[A-Za-z0-9._-]+$ || "$project_name" == "." || "$project_name" == ".." ]]; then
    fail "Invalid project name: $project_name" 2
  fi
}

validate_repository_key() {
  local repository_key="$1"

  if [[ ! "$repository_key" =~ ^[A-Za-z0-9._-]+$ ||
    "$repository_key" == "." ||
    "$repository_key" == ".." ||
    "$repository_key" == .* ||
    "$repository_key" == *. ||
    "$repository_key" == *.lock ||
    "$repository_key" == *..* ]]
  then
    fail "Invalid repository key: $repository_key" 2
  fi
}

validate_max_attempts() {
  local value="$1"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ || "${#value}" -gt 9 ]]; then
    fail "Maximum attempts must be a positive integer no greater than 999999999: $value" 2
  fi
}

validate_model() {
  local value="$1"

  if [[ -z "$value" || "$value" =~ [[:space:]] ]]; then
    fail "Model must be a nonempty value without whitespace: $value" 2
  fi
}

validate_reasoning_effort() {
  local value="$1"

  case "$value" in
    minimal|low|medium|high|xhigh)
      ;;
    *)
      fail "Reasoning effort must be one of minimal, low, medium, high, or xhigh: $value" 2
      ;;
  esac
}

validate_max_parallel() {
  local value="$1"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ || "${#value}" -gt 9 ]]; then
    fail "Maximum parallel repository agents must be a positive integer no greater than 999999999: $value" 2
  fi
}

validate_forwarded_codex_config() {
  local config_value="$1"

  if [[ "$config_value" =~ ^[[:space:]]*(sandbox_mode|sandbox_workspace_write)([.=[:space:]]|$) ]]; then
    fail "RepoChord does not accept legacy Codex sandbox configuration after --: $config_value" 2
  fi
}

validate_forwarded_codex_arguments() {
  local expect_config_value=false
  local argument

  for argument in "$@"; do
    if [[ "$expect_config_value" == true ]]; then
      validate_forwarded_codex_config "$argument"
      expect_config_value=false
      continue
    fi

    case "$argument" in
      -c|--config)
        expect_config_value=true
        ;;
      --config=*)
        validate_forwarded_codex_config "${argument#--config=}"
        ;;
      -c?*)
        validate_forwarded_codex_config "${argument#-c}"
        ;;
      -C|--cd|--cd=*|--add-dir|--add-dir=*|-s|--sandbox|--sandbox=*|-s?*|--approve-for-me|--dangerously-bypass-approvals-and-sandbox)
        fail "RepoChord does not accept a Codex argument that can replace its filesystem permissions: $argument" 2
        ;;
    esac
  done
}

validate_safe_path_text() {
  local path_value="$1"
  local path_label="$2"

  if [[ "$path_value" == *$'\n'* || "$path_value" == *$'\r'* || "$path_value" == *$'\t'* ]]; then
    fail "$path_label contains an unsupported tab or newline: $path_value" 2
  fi
}
