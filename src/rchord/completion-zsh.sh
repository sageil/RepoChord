print_zsh_completion() {
  cat <<'EOF'
_rchord_selected_project() {
  local index

  for ((index = 2; index < CURRENT; index++)); do
    case "${words[index]}" in
      -p|--project)
        if (( index + 1 < CURRENT )); then
          print -r -- "${words[index + 1]}"
        fi
        return
        ;;
    esac
  done
}

_rchord_projects() {
  local -a candidates
  candidates=("${(@f)$(command rchord __complete projects 2>/dev/null)}")
  compadd -- "${candidates[@]}"
}

_rchord_dynamic_candidates() {
  local candidate_type="$1"
  local project_name
  local -a candidates

  project_name="$(_rchord_selected_project)"

  if [[ -n "$project_name" ]]; then
    candidates=("${(@f)$(command rchord __complete "$candidate_type" "$project_name" 2>/dev/null)}")
  else
    candidates=("${(@f)$(command rchord __complete "$candidate_type" 2>/dev/null)}")
  fi

  compadd -- "${candidates[@]}"
}

_rchord_repositories() {
  _rchord_dynamic_candidates repositories
}

_rchord_runs() {
  _rchord_dynamic_candidates runs
}

_rchord() {
  local current_word="${words[CURRENT]}"
  local previous_word=""
  local command_name="${words[2]:-}"
  local action=""
  local setting_name=""
  local index
  local skip_next=false
  local -a candidates
  local -a commands
  local -a settings
  local -a efforts

  commands=(start init config list upgrade validate report integrate resume cleanup completion)
  settings=(model coordinator-reasoning-effort repository-agent-reasoning-effort max-parallel max-attempts)
  efforts=(minimal low medium high xhigh)

  if (( CURRENT > 1 )); then
    previous_word="${words[CURRENT - 1]}"
  fi

  if (( CURRENT == 2 )); then
    candidates=("${commands[@]}" -p --project -r --repository --model --coordinator-reasoning-effort --repository-agent-reasoning-effort --max-parallel --max-attempts --allow-dirty-source -h --help)
    compadd -- "${candidates[@]}"
    return
  fi

  if [[ "$command_name" == -* ]]; then
    command_name="start"
  fi

  case "$previous_word" in
    -p|--project)
      _rchord_projects
      return
      ;;
    --run)
      _rchord_runs
      return
      ;;
    -r|--repository|--retry-blocked)
      if [[ "$command_name" == "init" ]]; then
        _message 'repository key=absolute-path'
      else
        _rchord_repositories
      fi
      return
      ;;
    --coordinator-reasoning-effort|--repository-agent-reasoning-effort)
      compadd -- "${efforts[@]}"
      return
      ;;
    -c|--coordinate)
      _directories
      return
      ;;
  esac

  if [[ "$command_name" == "completion" ]]; then
    compadd -- bash zsh
    return
  fi

  if [[ "$command_name" == "config" ]]; then
    action="${words[3]:-}"

    if (( CURRENT == 3 )); then
      compadd -- get set
      return
    fi

    for ((index = 4; index < CURRENT; index++)); do
      if [[ "$skip_next" == true ]]; then
        skip_next=false
        continue
      fi

      case "${words[index]}" in
        -p|--project)
          skip_next=true
          ;;
        -*)
          ;;
        *)
          if [[ -z "$setting_name" ]]; then
            setting_name="${words[index]}"
          fi
          ;;
      esac
    done

    if [[ -z "$setting_name" ]]; then
      candidates=("${settings[@]}" -p --project -h --help)
      compadd -- "${candidates[@]}"
      return
    fi

    if [[ "$action" == "set" &&
      ( "$setting_name" == "coordinator-reasoning-effort" ||
        "$setting_name" == "repository-agent-reasoning-effort" ) ]]
    then
      compadd -- "${efforts[@]}"
    fi
    return
  fi

  case "$command_name" in
    start)
      candidates=(-p --project -r --repository --model --coordinator-reasoning-effort --repository-agent-reasoning-effort --max-parallel --max-attempts --allow-dirty-source -h --help --)
      ;;
    init)
      candidates=(-p --project -c --coordinate --create-coordinate --model --coordinator-reasoning-effort --repository-agent-reasoning-effort --max-parallel -r --repository -h --help)
      ;;
    list)
      candidates=(--details -h --help)
      ;;
    upgrade)
      candidates=(-h --help)
      ;;
    validate)
      candidates=(-p --project -c --coordinate -h --help)
      ;;
    report)
      candidates=(-p --project --run -h --help)
      ;;
    integrate)
      candidates=(-p --project --run --dry-run --show-diffs -h --help)
      ;;
    resume)
      candidates=(-p --project --run --retry-blocked --max-attempts -h --help)
      ;;
    cleanup)
      candidates=(-p --project --run --all -r --repository --force -h --help)
      ;;
    *)
      candidates=()
      ;;
  esac

  compadd -- "${candidates[@]}"
}

if (( ! $+functions[compdef] )); then
  autoload -Uz compinit
  compinit
fi

compdef _rchord rchord
EOF
}
