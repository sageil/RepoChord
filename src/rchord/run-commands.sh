run_resume() {
  local requested_project=""
  local run_id=""
  local requested_max_attempts=""
  local retry_blocked_keys=()
  local retry_blocked_key
  local existing_key
  local run_manifest
  local assignments_file
  local runner_script
  local runner_arguments=()

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
      --run)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        run_id="$2"
        shift 2
        ;;
      --retry-blocked)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        validate_repository_key "$2"

        for existing_key in ${retry_blocked_keys[@]+"${retry_blocked_keys[@]}"}; do
          if [[ "$existing_key" == "$2" ]]; then
            fail "Duplicate --retry-blocked repository key: $2" 2
          fi
        done

        retry_blocked_keys+=("$2")
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
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown resume argument: $1" 2
        ;;
    esac
  done

  if [[ -z "$run_id" ||
    ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ||
    "$run_id" == "." ||
    "$run_id" == ".." ]]
  then
    fail "RepoChord resume requires a valid --run <run-id>." 2
  fi

  if [[ -n "$requested_max_attempts" ]]; then
    validate_max_attempts "$requested_max_attempts"
  fi

  require_commands bash git jq
  resolve_project "$requested_project"
  validate_project_files "$selected_coordinate"

  run_manifest="$validated_coordinate_root/.repochord/results/$run_id/.manifest.json"

  if [[ -L "$run_manifest" || ! -f "$run_manifest" ]]; then
    fail "RepoChord run manifest does not exist or is not a regular file: $run_manifest" 2
  fi

  if ! assignments_file="$(jq -er \
    --arg run_id "$run_id" \
    'select(.version == 1 and .run_id == $run_id) | .assignments_file | select(type == "string" and startswith("/"))' \
    "$run_manifest")"
  then
    fail "RepoChord run manifest has no valid assignments path: $run_manifest" 2
  fi

  if [[ -L "$assignments_file" || ! -f "$assignments_file" ]]; then
    fail "RepoChord assignments file does not exist or is not a regular file: $assignments_file" 2
  fi

  assignments_file="$(cd -- "$(dirname -- "$assignments_file")" && pwd -P)/$(basename -- "$assignments_file")"

  runner_script="$validated_coordinate_root/.agents/skills/repochord/scripts/run-repository-agents.sh"
  runner_arguments=(--resume "$run_id")

  if [[ -n "$requested_max_attempts" ]]; then
    runner_arguments+=(--max-attempts "$requested_max_attempts")
  fi

  for retry_blocked_key in ${retry_blocked_keys[@]+"${retry_blocked_keys[@]}"}; do
    runner_arguments+=(--retry-blocked "$retry_blocked_key")
  done

  runner_arguments+=("$assignments_file")
  exec bash "$runner_script" "${runner_arguments[@]}"
}

run_cleanup() {
  local requested_project=""
  local run_id=""
  local all_runs=false
  local force=false
  local repository_keys=()
  local cleanup_script
  local cleanup_arguments=()

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
      --run)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        run_id="$2"
        shift 2
        ;;
      --all)
        all_runs=true
        shift
        ;;
      -r|--repository)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        validate_repository_key "$2"
        repository_keys+=("$2")
        shift 2
        ;;
      --force)
        force=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown cleanup argument: $1" 2
        ;;
    esac
  done

  if [[ "$all_runs" == true && -n "$run_id" ]]; then
    fail "Use either --run <run-id> or --all with cleanup, not both." 2
  fi

  if [[ "$all_runs" != true && ( -z "$run_id" || ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ) ]]; then
    fail "RepoChord cleanup requires a valid --run <run-id> or --all." 2
  fi

  require_commands bash git jq
  resolve_project "$requested_project"
  validate_project_files "$selected_coordinate"
  cleanup_script="$validated_coordinate_root/.agents/skills/repochord/scripts/cleanup-worktrees.sh"

  if [[ "$force" == true ]]; then
    cleanup_arguments+=(--force)
  fi

  if [[ "$all_runs" == true ]]; then
    cleanup_arguments+=(--all)
  else
    cleanup_arguments+=("$run_id")
  fi
  if [[ "${#repository_keys[@]}" -gt 0 ]]; then
    cleanup_arguments+=("${repository_keys[@]}")
  fi
  exec bash "$cleanup_script" "${cleanup_arguments[@]}"
}

run_integrate() {
  local requested_project=""
  local run_id=""
  local dry_run=false
  local show_diffs=false
  local integration_script
  local integration_arguments=()

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
      --run)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        run_id="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --show-diffs)
        show_diffs=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown integrate argument: $1" 2
        ;;
    esac
  done

  if [[ -z "$run_id" || \
    ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || \
    "$run_id" == "." || \
    "$run_id" == ".." ]]
  then
    fail "RepoChord integrate requires a valid --run <run-id>." 2
  fi

  require_commands bash diff git grep jq
  resolve_project "$requested_project"
  validate_project_files "$selected_coordinate"
  integration_script="$validated_coordinate_root/.agents/skills/repochord/scripts/integrate-run.sh"

  if [[ "$dry_run" == true ]]; then
    integration_arguments+=(--dry-run)
  fi

  if [[ "$show_diffs" == true ]]; then
    integration_arguments+=(--show-diffs)
  fi

  integration_arguments+=("$run_id")
  exec bash "$integration_script" "${integration_arguments[@]}"
}

run_report() {
  local requested_project=""
  local run_id=""
  local report_script

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
      --run)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          usage
          exit 2
        fi

        run_id="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown report argument: $1" 2
        ;;
    esac
  done

  if [[ -z "$run_id" || \
    ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || \
    "$run_id" == "." || \
    "$run_id" == ".." ]]
  then
    fail "RepoChord report requires a valid --run <run-id>." 2
  fi

  require_commands bash git jq
  resolve_project "$requested_project"
  validate_project_files "$selected_coordinate"
  report_script="$validated_coordinate_root/.agents/skills/repochord/scripts/report-run.sh"
  exec bash "$report_script" "$run_id"
}
