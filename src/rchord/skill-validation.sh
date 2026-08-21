validate_skill_directory() {
  local skill_directory="$1"
  local relative_path
  local script_path
  local schema_path
  local required_files=(
    "SKILL.md"
    "agents/openai.yaml"
    "assets/repository-agent-response.schema.json"
    "assets/repository-agent-result.schema.json"
    "references/file-formats.md"
    "scripts/run-repository-agent.sh"
    "scripts/run-repository-agents.sh"
    "scripts/request-repository-agent-run.sh"
    "scripts/repository-agent-broker.sh"
    "scripts/task-progress.sh"
    "scripts/scaffold-feature.sh"
    "scripts/validate-task-packet.sh"
    "scripts/report-run.sh"
    "scripts/integrate-run.sh"
    "scripts/cleanup-worktrees.sh"
    "scripts/git-guard.sh"
  )

  if [[ -L "$skill_directory" ]]; then
    fail "Refusing to use a symbolic link as a RepoChord skill: $skill_directory"
  fi

  if [[ ! -d "$skill_directory" ]]; then
    fail "RepoChord skill directory does not exist: $skill_directory"
  fi

  for relative_path in "${required_files[@]}"; do
    if [[ ! -f "$skill_directory/$relative_path" ]]; then
      fail "Required RepoChord skill file is missing: $relative_path"
    fi
  done

  if ! grep -q '^name: repochord$' "$skill_directory/SKILL.md"; then
    fail "RepoChord SKILL.md has the wrong skill name."
  fi

  for script_path in "$skill_directory"/scripts/*.sh; do
    bash -n "$script_path"

    if [[ ! -x "$script_path" ]]; then
      fail "RepoChord skill script is not executable: $script_path"
    fi
  done

  for schema_path in "$skill_directory"/assets/*.schema.json; do
    jq empty "$schema_path"
  done
}

validate_task_skill_directory() {
  local skill_directory="$1"
  local relative_path
  local required_files=(
    "SKILL.md"
    "references/request-template.md"
    "references/repository-task-template.md"
  )

  if [[ -L "$skill_directory" ]]; then
    fail "Refusing to use a symbolic link as a RepoChord task-authoring skill: $skill_directory"
  fi

  if [[ ! -d "$skill_directory" ]]; then
    fail "RepoChord task-authoring skill directory does not exist: $skill_directory"
  fi

  for relative_path in "${required_files[@]}"; do
    if [[ ! -f "$skill_directory/$relative_path" ]]; then
      fail "Required RepoChord task-authoring skill file is missing: $relative_path"
    fi
  done

  if ! grep -q '^name: create-repochord-task$' "$skill_directory/SKILL.md"; then
    fail "RepoChord task-authoring SKILL.md has the wrong skill name."
  fi
}

validate_projects_registry() {
  if [[ -L "$projects_registry" ]]; then
    fail "Refusing to use a symbolic link as the RepoChord project registry: $projects_registry"
  fi

  if [[ ! -f "$projects_registry" ]]; then
    fail "No RepoChord projects are registered. Run rchord init first." 2
  fi

  if ! jq -e '
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
  ' "$projects_registry" >/dev/null; then
    fail "RepoChord project registry is invalid: $projects_registry"
  fi
}

validate_repository_registry() {
  local registry_path="$1"

  if [[ -L "$registry_path" ]]; then
    fail "Refusing to use a symbolic link as the repository registry: $registry_path"
  fi

  if [[ ! -f "$registry_path" ]]; then
    fail "Repository registry does not exist: $registry_path"
  fi

  if ! jq -e '
    .version == 1 and
    (.repositories | type == "array") and
    (.repositories | length > 0) and
    ([.repositories[].key] | length == (unique | length)) and
    ([.repositories[].path] | length == (unique | length)) and
    all(.repositories[];
      (.key | type == "string") and
      (.key | test("^[A-Za-z0-9._-]+$")) and
      (.path | type == "string") and
      (.path | startswith("/")) and
      (.path | test("[\\t\\r\\n]") | not)
    )
  ' "$registry_path" >/dev/null; then
    fail "Repository registry is invalid: $registry_path"
  fi
}
