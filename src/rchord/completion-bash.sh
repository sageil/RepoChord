print_bash_completion() {
  cat <<'EOF'
_rchord_selected_project() {
  local index

  for ((index = 1; index < COMP_CWORD; index++)); do
    case "${COMP_WORDS[index]}" in
      -p|--project)
        if [[ $((index + 1)) -lt "$COMP_CWORD" ]]; then
          printf '%s\n' "${COMP_WORDS[index + 1]}"
        fi
        return
        ;;
    esac
  done
}

_rchord_dynamic_candidates() {
  local candidate_type="$1"
  local project_name

  project_name="$(_rchord_selected_project)"

  if [[ -n "$project_name" ]]; then
    command rchord __complete "$candidate_type" "$project_name" 2>/dev/null
  else
    command rchord __complete "$candidate_type" 2>/dev/null
  fi
}

_rchord_complete_words() {
  local words="$1"
  local current_word="$2"
  local candidate

  COMPREPLY=()

  while IFS= read -r candidate; do
    COMPREPLY+=("$candidate")
  done < <(compgen -W "$words" -- "$current_word")
}

_rchord_complete_directories() {
  local current_word="$1"
  local candidate

  COMPREPLY=()

  while IFS= read -r candidate; do
    COMPREPLY+=("$candidate")
  done < <(compgen -d -- "$current_word")
}

_rchord() {
  local current_word="${COMP_WORDS[COMP_CWORD]}"
  local previous_word=""
  local command_name="${COMP_WORDS[1]:-}"
  local action=""
  local setting_name=""
  local index
  local skip_next=false
  local candidates=""
  local commands="start init config list upgrade validate report integrate resume cleanup completion"
  local settings="model coordinator-reasoning-effort repository-agent-reasoning-effort max-parallel max-attempts"
  local efforts="minimal low medium high xhigh"

  if [[ "$COMP_CWORD" -gt 0 ]]; then
    previous_word="${COMP_WORDS[COMP_CWORD - 1]}"
  fi

  if [[ "$COMP_CWORD" -eq 1 ]]; then
    _rchord_complete_words "$commands -p --project -r --repository --model --coordinator-reasoning-effort --repository-agent-reasoning-effort --max-parallel --max-attempts --allow-dirty-source -h --help" "$current_word"
    return
  fi

  if [[ "$command_name" == -* ]]; then
    command_name="start"
  fi

  case "$previous_word" in
    -p|--project)
      candidates="$(command rchord __complete projects 2>/dev/null)"
      _rchord_complete_words "$candidates" "$current_word"
      return
      ;;
    --run)
      candidates="$(_rchord_dynamic_candidates runs)"
      _rchord_complete_words "$candidates" "$current_word"
      return
      ;;
    -r|--repository|--retry-blocked)
      if [[ "$command_name" != "init" ]]; then
        candidates="$(_rchord_dynamic_candidates repositories)"
        _rchord_complete_words "$candidates" "$current_word"
      fi
      return
      ;;
    --coordinator-reasoning-effort|--repository-agent-reasoning-effort)
      _rchord_complete_words "$efforts" "$current_word"
      return
      ;;
    -c|--coordinate)
      _rchord_complete_directories "$current_word"
      return
      ;;
  esac

  if [[ "$command_name" == "completion" ]]; then
    _rchord_complete_words "bash zsh" "$current_word"
    return
  fi

  if [[ "$command_name" == "config" ]]; then
    action="${COMP_WORDS[2]:-}"

    if [[ "$COMP_CWORD" -eq 2 ]]; then
      _rchord_complete_words "get set" "$current_word"
      return
    fi

    for ((index = 3; index < COMP_CWORD; index++)); do
      if [[ "$skip_next" == true ]]; then
        skip_next=false
        continue
      fi

      case "${COMP_WORDS[index]}" in
        -p|--project)
          skip_next=true
          ;;
        -*)
          ;;
        *)
          if [[ -z "$setting_name" ]]; then
            setting_name="${COMP_WORDS[index]}"
          fi
          ;;
      esac
    done

    if [[ -z "$setting_name" ]]; then
      _rchord_complete_words "$settings -p --project -h --help" "$current_word"
      return
    fi

    if [[ "$action" == "set" &&
      ( "$setting_name" == "coordinator-reasoning-effort" ||
        "$setting_name" == "repository-agent-reasoning-effort" ) ]]
    then
      _rchord_complete_words "$efforts" "$current_word"
    fi
    return
  fi

  case "$command_name" in
    start)
      candidates="-p --project -r --repository --model --coordinator-reasoning-effort --repository-agent-reasoning-effort --max-parallel --max-attempts --allow-dirty-source -h --help --"
      ;;
    init)
      candidates="-p --project -c --coordinate --create-coordinate --model --coordinator-reasoning-effort --repository-agent-reasoning-effort --max-parallel -r --repository -h --help"
      ;;
    list)
      candidates="--details -h --help"
      ;;
    upgrade)
      candidates="-h --help"
      ;;
    validate)
      candidates="-p --project -c --coordinate -h --help"
      ;;
    report)
      candidates="-p --project --run -h --help"
      ;;
    integrate)
      candidates="-p --project --run --dry-run --show-diffs -h --help"
      ;;
    resume)
      candidates="-p --project --run --retry-blocked --max-attempts -h --help"
      ;;
    cleanup)
      candidates="-p --project --run --all -r --repository --force -h --help"
      ;;
    *)
      candidates=""
      ;;
  esac

  _rchord_complete_words "$candidates" "$current_word"
}

complete -F _rchord rchord
EOF
}
