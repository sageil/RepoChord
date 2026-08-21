validate_upgrade_target() {
  local coordinate_path="$1"
  local coordinate_root
  local destination_skill
  local destination_task_skill
  local expected_directory

  coordinate_root="$(canonical_git_root "$coordinate_path" "Coordination repository")"

  if [[ "$coordinate_path" != "$coordinate_root" ]]; then
    fail "Registered coordination repository path is not canonical: $coordinate_path"
  fi

  for expected_directory in \
    "$coordinate_root/.agents" \
    "$coordinate_root/.agents/skills" \
    "$coordinate_root/.repochord"
  do
    if [[ -L "$expected_directory" ]]; then
      fail "Refusing to use a symbolic link as a project directory: $expected_directory"
    fi

    if [[ ! -d "$expected_directory" ]]; then
      fail "Required project directory does not exist: $expected_directory"
    fi
  done

  destination_skill="$coordinate_root/.agents/skills/repochord"
  destination_task_skill="$coordinate_root/.agents/skills/create-repochord-task"

  if [[ -L "$destination_skill" ]]; then
    fail "Refusing to use a symbolic link as the project skill: $destination_skill"
  fi

  if [[ -e "$destination_skill" && ! -d "$destination_skill" ]]; then
    fail "Project skill path is not a directory: $destination_skill"
  fi

  if [[ -L "$destination_task_skill" ]]; then
    fail "Refusing to use a symbolic link as the project task-authoring skill: $destination_task_skill"
  fi

  if [[ -e "$destination_task_skill" && ! -d "$destination_task_skill" ]]; then
    fail "Project task-authoring skill path is not a directory: $destination_task_skill"
  fi

  validate_project_data "$coordinate_root"
  validated_upgrade_coordinate="$coordinate_root"
}

upgrade_project_runtime() (
  set -euo pipefail

  local coordinate_path="$1"
  local project_name="$2"
  local coordinate_root
  local skills_directory
  local destination_skill
  local destination_task_skill
  local private_repositories_root
  local upgrade_workspace=""
  local replacement_skill
  local replacement_task_skill
  local previous_skill
  local previous_task_skill
  local failed_skill
  local failed_task_skill
  local destination_existed=false
  local task_destination_existed=false
  local replacement_install_started=false
  local task_replacement_install_started=false

  cleanup_project_upgrade() {
    local status="$?"
    local rollback_failed=false

    trap - EXIT INT TERM

    if [[ "$status" -ne 0 && -n "$upgrade_workspace" ]]; then
      failed_skill="$upgrade_workspace/failed-repochord"
      failed_task_skill="$upgrade_workspace/failed-create-repochord-task"

      if [[ -e "$previous_skill" ]]; then
        if [[ -e "$destination_skill" ]] && ! mv -- "$destination_skill" "$failed_skill"; then
          echo "Could not remove the failed RepoChord skill during rollback: $destination_skill" >&2
          rollback_failed=true
        fi

        if [[ -e "$destination_skill" ]]; then
          echo "Could not restore the previous RepoChord skill because its path is occupied: $destination_skill" >&2
          rollback_failed=true
        elif ! mv -- "$previous_skill" "$destination_skill"; then
          echo "Could not restore the previous RepoChord skill: $previous_skill" >&2
          rollback_failed=true
        fi
      elif [[ "$destination_existed" == false &&
        "$replacement_install_started" == true &&
        -e "$destination_skill" ]]
      then
        if ! mv -- "$destination_skill" "$failed_skill"; then
          echo "Could not remove the failed RepoChord skill during rollback: $destination_skill" >&2
          rollback_failed=true
        fi
      fi

      if [[ -e "$previous_task_skill" ]]; then
        if [[ -e "$destination_task_skill" ]] && ! mv -- "$destination_task_skill" "$failed_task_skill"; then
          echo "Could not remove the failed RepoChord task-authoring skill during rollback: $destination_task_skill" >&2
          rollback_failed=true
        fi

        if [[ -e "$destination_task_skill" ]]; then
          echo "Could not restore the previous RepoChord task-authoring skill because its path is occupied: $destination_task_skill" >&2
          rollback_failed=true
        elif ! mv -- "$previous_task_skill" "$destination_task_skill"; then
          echo "Could not restore the previous RepoChord task-authoring skill: $previous_task_skill" >&2
          rollback_failed=true
        fi
      elif [[ "$task_destination_existed" == false &&
        "$task_replacement_install_started" == true &&
        -e "$destination_task_skill" ]]
      then
        if ! mv -- "$destination_task_skill" "$failed_task_skill"; then
          echo "Could not remove the failed RepoChord task-authoring skill during rollback: $destination_task_skill" >&2
          rollback_failed=true
        fi
      fi
    fi

    if [[ "$rollback_failed" == true ]]; then
      echo "RepoChord kept the upgrade workspace for manual recovery: $upgrade_workspace" >&2
      exit 1
    fi

    if [[ -n "$upgrade_workspace" ]]; then
      rm -rf -- "$upgrade_workspace"
    fi

    exit "$status"
  }

  trap cleanup_project_upgrade EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  validate_upgrade_target "$coordinate_path"
  coordinate_root="$validated_upgrade_coordinate"
  skills_directory="$coordinate_root/.agents/skills"
  destination_skill="$skills_directory/repochord"
  destination_task_skill="$skills_directory/create-repochord-task"
  private_repositories_root="$coordinate_root/.repochord/repositories"

  if [[ -L "$private_repositories_root" || \
    ( -e "$private_repositories_root" && ! -d "$private_repositories_root" ) ]]
  then
    fail "Private repository root is not a directory: $private_repositories_root"
  fi

  mkdir -p "$private_repositories_root"

  if [[ ! -e "$private_repositories_root/.gitignore" ]]; then
    printf '*\n!.gitignore\n' > "$private_repositories_root/.gitignore"
  fi

  if [[ -d "$destination_skill" && -d "$destination_task_skill" ]] &&
    diff -qr "$source_skill" "$destination_skill" >/dev/null &&
    diff -qr "$source_task_skill" "$destination_task_skill" >/dev/null
  then
    validate_skill_directory "$destination_skill"
    validate_task_skill_directory "$destination_task_skill"
    echo "RepoChord project is already current: $project_name"
    exit 0
  fi

  if [[ -d "$destination_skill" ]]; then
    destination_existed=true
  fi

  if [[ -d "$destination_task_skill" ]]; then
    task_destination_existed=true
  fi

  if ! upgrade_workspace="$(mktemp -d "$skills_directory/.repochord-upgrade.XXXXXX")"; then
    fail "Could not create an upgrade workspace for: $project_name"
  fi

  replacement_skill="$upgrade_workspace/replacement-repochord"
  replacement_task_skill="$upgrade_workspace/replacement-create-repochord-task"
  previous_skill="$upgrade_workspace/previous-repochord"
  previous_task_skill="$upgrade_workspace/previous-create-repochord-task"
  mkdir "$replacement_skill" || fail "Could not stage the RepoChord skill for: $project_name"
  mkdir "$replacement_task_skill" || fail "Could not stage the RepoChord task-authoring skill for: $project_name"
  cp -R "$source_skill/." "$replacement_skill/" || fail "Could not copy the RepoChord skill for: $project_name"
  cp -R "$source_task_skill/." "$replacement_task_skill/" || fail "Could not copy the RepoChord task-authoring skill for: $project_name"
  chmod +x "$replacement_skill"/scripts/*.sh || fail "Could not make the staged RepoChord scripts executable for: $project_name"
  validate_skill_directory "$replacement_skill"
  validate_task_skill_directory "$replacement_task_skill"

  if [[ -d "$destination_skill" ]]; then
    mv -- "$destination_skill" "$previous_skill" || fail "Could not preserve the previous RepoChord skill for: $project_name"
  fi

  if [[ -d "$destination_task_skill" ]]; then
    mv -- "$destination_task_skill" "$previous_task_skill" || fail "Could not preserve the previous RepoChord task-authoring skill for: $project_name"
  fi

  replacement_install_started=true
  mv -- "$replacement_skill" "$destination_skill" || fail "Could not install the RepoChord skill for: $project_name"
  task_replacement_install_started=true
  mv -- "$replacement_task_skill" "$destination_task_skill" || fail "Could not install the RepoChord task-authoring skill for: $project_name"

  validate_skill_directory "$destination_skill"
  validate_task_skill_directory "$destination_task_skill"

  if ! diff -qr "$source_skill" "$destination_skill" >/dev/null; then
    fail "Upgraded project skill differs from RepoChord: $destination_skill"
  fi

  if ! diff -qr "$source_task_skill" "$destination_task_skill" >/dev/null; then
    fail "Upgraded project task-authoring skill differs from RepoChord: $destination_task_skill"
  fi

  validate_project_data "$coordinate_root"
  echo "Upgraded RepoChord project: $project_name"
  exit 0
)
