#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: repository-agent-broker.sh <broker-directory> <coordinate-root> <runner-script> <registry-snapshot>" >&2
}

if [[ "$#" -ne 4 ]]; then
  usage
  exit 2
fi

broker_directory="$1"
coordinate_root="$2"
runner_script="$3"
registry_snapshot="$4"
requests_directory="$broker_directory/requests"
responses_directory="$broker_directory/responses"
stopped_path="$broker_directory/stopped"

for required_command in bash cat jq mkdir mv sleep; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required broker command is not installed: $required_command" >&2
    exit 2
  fi
done

if [[ "$broker_directory" != /* || -L "$broker_directory" || ! -d "$broker_directory" || \
  "$coordinate_root" != /* || -L "$coordinate_root" || ! -d "$coordinate_root" || \
  "$runner_script" != /* || -L "$runner_script" || ! -f "$runner_script" || \
  "$registry_snapshot" != /* || -L "$registry_snapshot" || ! -f "$registry_snapshot" ]]
then
  echo "RepoChord broker received an invalid startup path." >&2
  exit 2
fi

canonical_coordinate_root="$(cd -- "$coordinate_root" && pwd -P)"
canonical_runner_script="$(cd -- "$(dirname -- "$runner_script")" && pwd -P)/$(basename -- "$runner_script")"
canonical_registry_snapshot="$(cd -- "$(dirname -- "$registry_snapshot")" && pwd -P)/$(basename -- "$registry_snapshot")"

if [[ "$canonical_coordinate_root" != "$coordinate_root" || \
  "$canonical_runner_script" != "$runner_script" || \
  "$canonical_registry_snapshot" != "$registry_snapshot" ]]
then
  echo "RepoChord broker startup paths must be canonical." >&2
  exit 2
fi

if [[ -L "$requests_directory" || ! -d "$requests_directory" || \
  -L "$responses_directory" || ! -d "$responses_directory" ]]
then
  echo "RepoChord broker endpoint directories are invalid." >&2
  exit 2
fi

mark_broker_stopped() {
  : > "$stopped_path"
}

terminate_broker() {
  exit 0
}

trap mark_broker_stopped EXIT
trap terminate_broker INT TERM
: > "$broker_directory/ready"

write_rejection() {
  local response_directory="$1"
  local message="$2"

  printf '%s\n' "$message" > "$response_directory/stderr"
  : > "$response_directory/stdout"
  printf '2\n' > "$response_directory/status"
}

process_request() {
  local request_directory="$1"
  local request_id
  local request_path
  local response_stage
  local response_directory
  local argument_count
  local argument_index
  local argument_value
  local run_id=""
  local assignments_file
  local canonical_assignments_file
  local expected_tasks_prefix="$coordinate_root/tasks/"
  local runner_status=0
  local runner_arguments=()

  request_id="$(basename -- "$request_directory")"
  request_path="$request_directory/request.json"
  response_stage="$responses_directory/.${request_id}.stage"
  response_directory="$responses_directory/$request_id"

  if [[ -e "$response_directory" || -e "$response_stage" ]]; then
    return
  fi

  mkdir "$response_stage"

  if [[ ! "$request_id" =~ ^request\.[A-Za-z0-9]+$ || \
    -L "$request_directory" || \
    -L "$request_path" || \
    ! -f "$request_path" ]]
  then
    write_rejection "$response_stage" "RepoChord broker rejected an invalid request path."
  elif ! jq -e '
    .version == 1 and
    (.arguments | type == "array") and
    ((.arguments | length) >= 1 and (.arguments | length) <= 34) and
    all(.arguments[]; type == "string" and length > 0)
  ' "$request_path" >/dev/null
  then
    write_rejection "$response_stage" "RepoChord broker rejected an invalid request document."
  else
    argument_count="$(jq -r '.arguments | length' "$request_path")"

    if [[ "$(jq -r '.arguments[0]' "$request_path")" == "--resume" ]]; then
      if [[ "$argument_count" -lt 3 ]]; then
        write_rejection "$response_stage" "RepoChord broker rejected an incomplete resume request."
        argument_count=0
      else
        run_id="$(jq -r '.arguments[1]' "$request_path")"
        runner_arguments=(--resume "$run_id")
        argument_index=2

        while [[ "$argument_index" -lt $((argument_count - 1)) ]]; do
          argument_value="$(jq -r --argjson index "$argument_index" '.arguments[$index]' "$request_path")"

          if [[ "$argument_value" != "--retry-blocked" || "$argument_index" -ge $((argument_count - 2)) ]]; then
            write_rejection "$response_stage" "RepoChord broker rejected an unsupported resume argument."
            argument_count=0
            break
          fi

          argument_index=$((argument_index + 1))
          argument_value="$(jq -r --argjson index "$argument_index" '.arguments[$index]' "$request_path")"

          if [[ ! "$argument_value" =~ ^[A-Za-z0-9._-]+$ ]]; then
            write_rejection "$response_stage" "RepoChord broker rejected an invalid retry repository key."
            argument_count=0
            break
          fi

          runner_arguments+=(--retry-blocked "$argument_value")
          argument_index=$((argument_index + 1))
        done

        if [[ "$argument_count" -gt 0 ]]; then
          assignments_file="$(jq -r --argjson index "$((argument_count - 1))" '.arguments[$index]' "$request_path")"
        fi
      fi
    elif [[ "$argument_count" -eq 2 ]]; then
      run_id="$(jq -r '.arguments[0]' "$request_path")"
      assignments_file="$(jq -r '.arguments[1]' "$request_path")"
      runner_arguments=("$run_id")
    else
      assignments_file="$(jq -r '.arguments[0]' "$request_path")"
    fi

    if [[ "$argument_count" -eq 0 ]]; then
      :
    elif [[ -n "$run_id" && ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
      write_rejection "$response_stage" "RepoChord broker rejected an invalid run ID."
    elif [[ "$assignments_file" != /* || \
      "$assignments_file" == *$'\n'* || \
      "$assignments_file" == *$'\r'* || \
      "$assignments_file" == *$'\t'* || \
      -L "$assignments_file" || \
      ! -f "$assignments_file" ]]
    then
      write_rejection "$response_stage" "RepoChord broker rejected an invalid assignments file."
    else
      canonical_assignments_file="$(cd -- "$(dirname -- "$assignments_file")" && pwd -P)/$(basename -- "$assignments_file")"

      if [[ "$canonical_assignments_file" != "$assignments_file" || \
        "$canonical_assignments_file" != "$expected_tasks_prefix"*/assignments.txt ]]
      then
        write_rejection "$response_stage" "RepoChord broker rejected an assignments file outside the task packet."
      else
        runner_arguments+=("$assignments_file")
        REPOCHORD_BROKER_EXECUTION=true \
        REPOCHORD_REGISTRY_PATH="$registry_snapshot" \
        bash "$runner_script" "${runner_arguments[@]}" \
          > "$response_stage/stdout" \
          2> "$response_stage/stderr" || runner_status="$?"

        printf '%s\n' "$runner_status" > "$response_stage/status"
      fi
    fi
  fi

  mv -- "$response_stage" "$response_directory"
  : > "$response_directory/done"
}

while true; do
  for request_directory in "$requests_directory"/request.*; do
    if [[ ! -d "$request_directory" || ! -f "$request_directory/ready" ]]; then
      continue
    fi

    process_request "$request_directory"
  done

  sleep 0.1
done
