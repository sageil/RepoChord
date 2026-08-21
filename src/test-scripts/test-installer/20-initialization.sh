
if HOME="$test_home" "$rchord_command" init \
  --project duplicate-project \
  --coordinate "$duplicate_coordinate_repository" \
  --create-coordinate \
  --repository "api=$api_repository" \
  --repository "api-alias=$api_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted a duplicate canonical repository path." >&2
  exit 1
fi

test ! -e "$duplicate_coordinate_repository"

if HOME="$test_home" "$rchord_command" init \
  --project empty-project \
  --coordinate "$empty_coordinate_repository" \
  --create-coordinate \
  --repository "empty=$empty_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted a repository without an initial commit." >&2
  exit 1
fi

test ! -e "$empty_coordinate_repository"

if HOME="$test_home" "$rchord_command" init \
  --project invalid-ref-project \
  --coordinate "$invalid_ref_coordinate_repository" \
  --create-coordinate \
  --repository "api.lock=$api_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted a repository key that cannot form a Git branch." >&2
  exit 1
fi

test ! -e "$invalid_ref_coordinate_repository"

HOME="$test_home" "$rchord_command" init \
  -p acme-commerce \
  -c "$coordinate_repository" \
  --create-coordinate \
  --model project-model \
  --coordinator-reasoning-effort high \
  --repository-agent-reasoning-effort medium \
  --max-parallel 3 \
  -r "api=$api_repository" \
  -r "web=$web_repository"

(
  cd "$coordinate_repository"
  HOME="$test_home" "$rchord_command" init \
    --project acme-commerce \
    --coordinate "$(pwd)" \
    --repository "api=$(pwd)/../api" \
    --repository "web=$(pwd)/../web" \
    >/dev/null
)

test -d "$coordinate_repository/.agents/skills/repochord"
test ! -L "$coordinate_repository/.agents/skills/repochord"
test -d "$coordinate_repository/.agents/skills/create-repochord-task"
test ! -L "$coordinate_repository/.agents/skills/create-repochord-task"
test -f "$coordinate_repository/.repochord/repositories.json"
test -f "$coordinate_repository/.repochord/repositories/.gitignore"
test -f "$coordinate_repository/.repochord/results/.gitignore"
test -f "$coordinate_repository/.repochord/worktrees/.gitignore"
test ! -e "$coordinate_repository/start-coordinator.sh"

jq -e \
  --arg coordinate "$coordinate_repository" \
  '.version == 1 and
   .defaults == {
     maxAttempts: 3,
     model: "openrouter/example/model",
     coordinatorReasoningEffort: "low",
     repositoryAgentReasoningEffort: "xhigh",
     maxParallel: 4
   } and
   .projects == [{
     name: "acme-commerce",
     coordinate: $coordinate,
     model: "project-model",
     coordinatorReasoningEffort: "high",
     repositoryAgentReasoningEffort: "medium",
     maxParallel: 3
   }]' \
  "$projects_registry" \
  >/dev/null

default_max_attempts="$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    max-attempts
)"

test "$default_max_attempts" = "3"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    model
)" = "project-model"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    max-parallel
)" = "3"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    coordinator-reasoning-effort
)" = "high"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    repository-agent-reasoning-effort
)" = "medium"
