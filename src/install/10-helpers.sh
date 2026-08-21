#!/usr/bin/env bash

# Generated from src/install by scripts/build-installer.sh.
# Do not edit install.sh directly.

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord requires Bash 5.2 or later." >&2
  exit 2
fi

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
