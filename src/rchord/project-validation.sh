canonical_git_root() {
  local input_path="$1"
  local path_label="$2"
  local canonical_path
  local git_root

  validate_safe_path_text "$input_path" "$path_label"

  if [[ ! -d "$input_path" ]]; then
    fail "$path_label does not exist: $input_path" 2
  fi

  canonical_path="$(cd -- "$input_path" && pwd -P)"

  if ! git_root="$(git -C "$canonical_path" rev-parse --show-toplevel 2>/dev/null)"; then
    fail "$path_label is not inside a Git repository: $input_path" 2
  fi

  git_root="$(cd -- "$git_root" && pwd -P)"

  if [[ "$canonical_path" != "$git_root" ]]; then
    fail "$path_label must be the Git repository root: $input_path" 2
  fi

  printf '%s\n' "$git_root"
}

validate_product_repository() {
  local repository_path="$1"
  local repository_root

  repository_root="$(canonical_git_root "$repository_path" "Product repository path")"

  if ! git -C "$repository_root" rev-parse --verify HEAD >/dev/null 2>&1; then
    fail "Product repository has no initial commit: $repository_root" 2
  fi

  printf '%s\n' "$repository_root"
}

validate_project_data() {
  local coordinate_path="$1"
  local coordinate_root
  local registry_path
  local repository_path
  local canonical_repository_path

  coordinate_root="$(canonical_git_root "$coordinate_path" "Coordination repository")"
  registry_path="$coordinate_root/.repochord/repositories.json"

  validate_repository_registry "$registry_path"

  while IFS= read -r repository_path; do
    canonical_repository_path="$(validate_product_repository "$repository_path")"

    if [[ "$repository_path" != "$canonical_repository_path" ]]; then
      fail "Registered repository path is not canonical: $repository_path"
    fi

    if [[ "$canonical_repository_path" == "$coordinate_root" ]]; then
      fail "A product repository cannot be the coordination repository: $repository_path"
    fi
  done < <(jq -r '.repositories[].path' "$registry_path")

  validated_coordinate_root="$coordinate_root"
  validated_repository_registry="$registry_path"
}

validate_project_files() {
  local coordinate_path="$1"
  local coordinate_root
  local installed_skill
  local installed_task_skill

  coordinate_root="$(canonical_git_root "$coordinate_path" "Coordination repository")"
  installed_skill="$coordinate_root/.agents/skills/repochord"
  installed_task_skill="$coordinate_root/.agents/skills/create-repochord-task"

  validate_skill_directory "$source_skill"
  validate_task_skill_directory "$source_task_skill"

  if [[ -L "$installed_skill" ]]; then
    fail "Refusing to use a symbolic link as a RepoChord skill: $installed_skill"
  fi

  if [[ ! -d "$installed_skill" ]] || ! diff -qr "$source_skill" "$installed_skill" >/dev/null; then
    fail "Installed project skill differs from RepoChord: $installed_skill. Run rchord upgrade."
  fi

  validate_skill_directory "$installed_skill"

  if [[ -L "$installed_task_skill" ]]; then
    fail "Refusing to use a symbolic link as a RepoChord task-authoring skill: $installed_task_skill"
  fi

  if [[ ! -d "$installed_task_skill" ]] || ! diff -qr "$source_task_skill" "$installed_task_skill" >/dev/null; then
    fail "Installed project task-authoring skill differs from RepoChord: $installed_task_skill. Run rchord upgrade."
  fi

  validate_task_skill_directory "$installed_task_skill"
  validate_project_data "$coordinate_root"
}
