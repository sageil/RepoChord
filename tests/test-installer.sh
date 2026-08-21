#!/usr/bin/env bash

# Generated from src/test-scripts by scripts/build-test-scripts.sh.
# Do not edit this test in tests directly.

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repochord-installer-test.XXXXXX)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_product_repository() {
  local repository_path="$1"
  local repository_name="$2"

  mkdir -p "$repository_path"
  git -C "$repository_path" init -q
  git -C "$repository_path" config user.name "Installer Test"
  git -C "$repository_path" config user.email "installer-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null
}

api_repository="$temporary_root/api"
web_repository="$temporary_root/web"
admin_repository="$temporary_root/admin"
empty_repository="$temporary_root/empty-product"
coordinate_repository="$temporary_root/control"
second_coordinate_repository="$temporary_root/second-control"
duplicate_coordinate_repository="$temporary_root/duplicate-control"
empty_coordinate_repository="$temporary_root/empty-control"
invalid_ref_coordinate_repository="$temporary_root/invalid-ref-control"
conflict_coordinate_repository="$temporary_root/conflict-control"
name_collision_coordinate="$temporary_root/name-collision-coordinate"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
conflict_bin="$temporary_root/conflict-commands"
link_bin="$temporary_root/link-commands"
invalid_registry_bin="$temporary_root/invalid-registry-commands"
invalid_registry_home="$temporary_root/invalid-registry-home"
fake_bin="$temporary_root/fake-bin"
launcher_capture="$temporary_root/launcher-arguments.txt"
attempts_capture="$temporary_root/max-attempts.txt"
settings_capture="$temporary_root/repository-agent-settings.txt"
broker_registry_capture="$temporary_root/broker-registry.json"
expected_coordinator_permissions="permissions.repochord-coordinator={ filesystem = { \":root\" = \"read\", \":workspace_roots\" = { \".\" = \"write\", \".git\" = \"read\", \".agents\" = \"read\", \".codex\" = \"read\" }, \"<coordinator-scratch>\" = \"write\", \"<broker-requests>\" = \"write\", \"$test_home/.codex/installation_id\" = \"write\", \"$test_home/.codex/tmp\" = \"write\" }, network = { enabled = true, allow_local_binding = true, domains = { \"*\" = \"allow\" } } }"

normalize_launcher_capture() {
  sed -E \
    -e 's#"/[^"]*/repochord-coordinator\.[A-Za-z0-9]+"#"<coordinator-scratch>"#' \
    -e 's#"/[^"]*/repochord-broker\.[A-Za-z0-9]+/requests"#"<broker-requests>"#' \
    "$launcher_capture"
}

initialize_product_repository "$api_repository" api
initialize_product_repository "$web_repository" web
initialize_product_repository "$admin_repository" admin
git init -q "$empty_repository"
mkdir -p "$test_home" "$conflict_bin" "$link_bin"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOCHORD_CONFIG_HOME REPOCHORD_DATA_HOME

if /bin/bash -c '((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2)))'; then
  if /bin/bash "$repository_directory/install.sh" --help >"$temporary_root/unsupported-installer-bash.out" 2>&1; then
    echo "The installer unexpectedly ran with an unsupported Bash version." >&2
    exit 1
  fi

  grep -Fqx "RepoChord requires Bash 5.2 or later." "$temporary_root/unsupported-installer-bash.out"
fi

install_output="$(
  HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$command_bin"
)"

rchord_command="$command_bin/rchord"
installed_data="$test_home/.local/share/repochord"
projects_registry="$test_home/.config/repochord/projects.json"

test -f "$rchord_command"
test -x "$rchord_command"
test ! -L "$rchord_command"
expected_version="$(<"$repository_directory/VERSION")"
test "$("$rchord_command" --version)" = "RepoChord $expected_version"
test -d "$installed_data/skill"
test ! -L "$installed_data/skill"
test -x "$installed_data/skill/scripts/report-run.sh"
test -x "$installed_data/skill/scripts/task-progress.sh"
test -d "$installed_data/task-skill"
test ! -L "$installed_data/task-skill"

printf '\n# old RepoChord command\n' >> "$rchord_command"
printf '\nOld RepoChord skill content.\n' >> "$installed_data/skill/SKILL.md"
printf '\nOld RepoChord task skill content.\n' >> "$installed_data/task-skill/SKILL.md"

if HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$command_bin" \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly replaced an existing RepoChord installation without --upgrade." >&2
  exit 1
fi

HOME="$test_home" \
"$repository_directory/install.sh" \
  --upgrade \
  --bin-dir "$command_bin" \
  >/dev/null

diff -q "$repository_directory/payload/rchord" "$rchord_command" >/dev/null
diff -qr "$repository_directory/payload/.agents/skills/repochord" "$installed_data/skill" >/dev/null
diff -qr "$repository_directory/payload/.agents/skills/create-repochord-task" "$installed_data/task-skill" >/dev/null

jq -e '
  .version == 1 and
  .defaults == {
    maxAttempts: 3,
    model: "gpt-5.6-terra",
    coordinatorReasoningEffort: "medium",
    repositoryAgentReasoningEffort: "high",
    maxParallel: 2
  } and
  .projects == []
' "$projects_registry" >/dev/null

env \
  -u HOME \
  -u XDG_CONFIG_HOME \
  -u XDG_DATA_HOME \
  -u REPOCHORD_CONFIG_HOME \
  -u REPOCHORD_DATA_HOME \
  "$rchord_command" --help \
  >/dev/null 2>&1

expected_path_instruction="export PATH=$command_bin:\$PATH"

if [[ "$install_output" != *"$expected_path_instruction"* ]]; then
  echo "Installer did not print the expected PATH instruction." >&2
  exit 1
fi

jq '
  del(.defaults.coordinatorReasoningEffort) |
  del(.defaults.repositoryAgentReasoningEffort) |
  .defaults.agentOutput = "progress"
' "$projects_registry" > "$projects_registry.legacy"
mv "$projects_registry.legacy" "$projects_registry"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

jq -e '
  .defaults.coordinatorReasoningEffort == "medium" and
  .defaults.repositoryAgentReasoningEffort == "high" and
  (.defaults | has("agentOutput") | not)
' "$projects_registry" >/dev/null

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  --default-model openrouter/example/model \
  --default-coordinator-reasoning-effort low \
  --default-repository-agent-reasoning-effort xhigh \
  --default-max-parallel 4 \
  >/dev/null

jq -e '
  .defaults.model == "openrouter/example/model" and
  .defaults.coordinatorReasoningEffort == "low" and
  .defaults.repositoryAgentReasoningEffort == "xhigh" and
  .defaults.maxParallel == 4 and
  .projects == []
' "$projects_registry" >/dev/null

if HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$command_bin" \
    --default-repository-agent-reasoning-effort impossible \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly accepted an invalid repository-agent reasoning effort." >&2
  exit 1
fi

test "$(jq -r '.defaults.repositoryAgentReasoningEffort' "$projects_registry")" = "xhigh"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

jq -e '
  .defaults.model == "openrouter/example/model" and
  .defaults.coordinatorReasoningEffort == "low" and
  .defaults.repositoryAgentReasoningEffort == "xhigh" and
  .defaults.maxParallel == 4
' "$projects_registry" >/dev/null

mkdir -p "$invalid_registry_home/.config/repochord"
jq -n '{
  version: 1,
  defaults: {
    maxAttempts: 3,
    model: "gpt-5.6-terra",
    coordinatorReasoningEffort: "medium",
    repositoryAgentReasoningEffort: "high",
    maxParallel: 0
  },
  projects: []
}' > "$invalid_registry_home/.config/repochord/projects.json"

if HOME="$invalid_registry_home" \
  XDG_CONFIG_HOME="$invalid_registry_home/.config" \
  "$repository_directory/install.sh" \
    --bin-dir "$invalid_registry_bin" \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly accepted an invalid existing project registry." >&2
  exit 1
fi

test ! -e "$invalid_registry_bin/rchord"
test "$(jq -r '.defaults.maxParallel' "$invalid_registry_home/.config/repochord/projects.json")" = "0"

printf 'preserve this command\n' > "$conflict_bin/rchord"

if HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$conflict_bin" \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly overwrote an existing command." >&2
  exit 1
fi

grep -Fqx "preserve this command" "$conflict_bin/rchord"

ln -s "$repository_directory/payload/rchord" "$link_bin/rchord"

if HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$link_bin" \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly accepted a symbolic link as the command." >&2
  exit 1
fi

test -L "$link_bin/rchord"


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

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  model project-model-2 \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  coordinator-reasoning-effort xhigh \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  repository-agent-reasoning-effort low \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  max-parallel 5 \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  max-attempts 5 \
  >/dev/null

configured_max_attempts="$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    max-attempts
)"

test "$configured_max_attempts" = "5"

(
  cd "$coordinate_repository"
  HOME="$test_home" \
  "$rchord_command" config set max-attempts 6 \
    >/dev/null

  test "$(HOME="$test_home" "$rchord_command" config get max-attempts)" = "6"
)

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  max-attempts 5 \
  >/dev/null

HOME="$test_home" \
"$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

jq -e \
  '.projects[] |
   select(.name == "acme-commerce") |
   .maxAttempts == 5 and
   .model == "project-model-2" and
   .coordinatorReasoningEffort == "xhigh" and
   .repositoryAgentReasoningEffort == "low" and
   .maxParallel == 5' \
  "$projects_registry" \
  >/dev/null

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  max-attempts 0 \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid maximum attempt count." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  max-parallel 0 \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid concurrency limit." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  model "invalid model" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted a model containing whitespace." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  coordinator-reasoning-effort impossible \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid coordinator reasoning effort." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository-agent-reasoning-effort impossible \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid repository-agent reasoning effort." >&2
  exit 1
fi

mkdir -p "$fake_bin"
cp "$test_directory/fixtures/fake-codex-start.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
FAKE_CODEX_START_CAPTURE="$launcher_capture" \
FAKE_REPOCHORD_ATTEMPTS_CAPTURE="$attempts_capture" \
FAKE_REPOCHORD_SETTINGS_CAPTURE="$settings_capture" \
"$rchord_command" \
  -- \
  --profile test-profile

diff -u \
  <(printf '%s\n' \
    -C \
    "$coordinate_repository" \
    --profile \
    test-profile \
    --config \
    'model_reasoning_effort="xhigh"' \
    --config \
    'features.network_proxy=true' \
    --config \
    "$expected_coordinator_permissions" \
    --config \
    'default_permissions="repochord-coordinator"') \
  <(normalize_launcher_capture)

captured_broker_directory="$(sed -n 's/^broker_directory=//p' "$settings_capture")"
captured_tmpdir="$(sed -n 's/^tmpdir=//p' "$settings_capture")"
[[ "$captured_broker_directory" == /private/*/repochord-broker.* ]]
[[ "$captured_tmpdir" == /private/*/repochord-coordinator.* ]]
test ! -e "$captured_broker_directory"
test ! -e "$captured_tmpdir"

if HOME="$test_home" PATH="$fake_bin:$PATH" "$rchord_command" -- --sandbox workspace-write >/dev/null 2>&1; then
  echo "RepoChord unexpectedly accepted a legacy Codex sandbox argument." >&2
  exit 1
fi

if HOME="$test_home" PATH="$fake_bin:$PATH" "$rchord_command" -- --add-dir "$api_repository" >/dev/null 2>&1; then
  echo "RepoChord unexpectedly accepted an additional writable directory." >&2
  exit 1
fi

if HOME="$test_home" PATH="$fake_bin:$PATH" "$rchord_command" -- --config 'sandbox_mode="workspace-write"' >/dev/null 2>&1; then
  echo "RepoChord unexpectedly accepted legacy Codex sandbox configuration." >&2
  exit 1
fi

if HOME="$test_home" PATH="$fake_bin:$PATH" "$rchord_command" -- --dangerously-bypass-approvals-and-sandbox >/dev/null 2>&1; then
  echo "RepoChord unexpectedly accepted the Codex sandbox bypass argument." >&2
  exit 1
fi

grep -Fqx "5" "$attempts_capture"
grep -Fqx "model=project-model-2" "$settings_capture"
grep -Fqx "repository_agent_reasoning_effort=low" "$settings_capture"
grep -Fqx "max_parallel=5" "$settings_capture"
grep -Fqx "allow_dirty_source=false" "$settings_capture"

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
FAKE_CODEX_START_CAPTURE="$launcher_capture" \
FAKE_REPOCHORD_ATTEMPTS_CAPTURE="$attempts_capture" \
FAKE_REPOCHORD_SETTINGS_CAPTURE="$settings_capture" \
"$rchord_command" \
  --project acme-commerce \
  --model session-model \
  --coordinator-reasoning-effort medium \
  --repository-agent-reasoning-effort xhigh \
  --max-parallel 7 \
  --max-attempts 7 \
  --allow-dirty-source

grep -Fqx "7" "$attempts_capture"
grep -Fqx "model=session-model" "$settings_capture"
grep -Fqx "repository_agent_reasoning_effort=xhigh" "$settings_capture"
grep -Fqx "max_parallel=7" "$settings_capture"
grep -Fqx "allow_dirty_source=true" "$settings_capture"
grep -Fqx 'model_reasoning_effort="medium"' "$launcher_capture"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    max-attempts
)" = "5"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    model
)" = "project-model-2"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    max-parallel
)" = "5"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    coordinator-reasoning-effort
)" = "xhigh"

test "$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    repository-agent-reasoning-effort
)" = "low"

(
  cd "$api_repository"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  FAKE_REPOCHORD_BROKER_REGISTRY_CAPTURE="$broker_registry_capture" \
  "$rchord_command" \
    --repository web \
    -- \
    --model test-model
)

diff -u \
  <(printf '%s\n' \
    -C \
    "$coordinate_repository" \
    --model \
    test-model \
    --config \
    'model_reasoning_effort="xhigh"' \
    --config \
    'features.network_proxy=true' \
    --config \
    "$expected_coordinator_permissions" \
    --config \
    'default_permissions="repochord-coordinator"') \
  <(normalize_launcher_capture)

jq -e \
  --arg path "$web_repository" \
  '. == {version: 1, repositories: [{key: "web", path: $path}]}' \
  "$broker_registry_capture" \
  >/dev/null

(
  cd "$temporary_root"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$rchord_command" \
    --repository api
)

diff -u \
  <(printf '%s\n' \
    -C \
    "$coordinate_repository" \
    --config \
    'model_reasoning_effort="xhigh"' \
    --config \
    'features.network_proxy=true' \
    --config \
    "$expected_coordinator_permissions" \
    --config \
    'default_permissions="repochord-coordinator"') \
  <(normalize_launcher_capture)

if HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$rchord_command" \
    --repository missing \
    >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an unregistered repository key." >&2
  exit 1
fi

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
"$rchord_command" validate --project acme-commerce \
  >/dev/null

list_output="$(HOME="$test_home" "$rchord_command" list)"

expected_list_output="$(printf 'PROJECT\tCOORDINATE\nacme-commerce\t%s\n' "$coordinate_repository")"

if [[ "$list_output" != "$expected_list_output" ]]; then
  echo "RepoChord list did not return the expected project table." >&2
  exit 1
fi

detailed_list_output="$(HOME="$test_home" "$rchord_command" list --details)"
expected_detailed_list_output="$(printf \
  'PROJECT\tCOORDINATE\tREPOSITORY\tPATH\nacme-commerce\t%s\tapi\t%s\nacme-commerce\t%s\tweb\t%s\n' \
  "$coordinate_repository" \
  "$api_repository" \
  "$coordinate_repository" \
  "$web_repository")"

if [[ "$detailed_list_output" != "$expected_detailed_list_output" ]]; then
  echo "RepoChord detailed list did not include the registered repositories." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" list --unknown >/dev/null 2>&1; then
  echo "RepoChord list unexpectedly accepted an unknown option." >&2
  exit 1
fi

HOME="$test_home" "$rchord_command" init \
  --project back-office \
  --coordinate "$second_coordinate_repository" \
  --create-coordinate \
  --repository "admin=$admin_repository" \
  >/dev/null

if (
  cd "$temporary_root"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$rchord_command" \
    >/dev/null 2>&1
)
then
  echo "RepoChord unexpectedly selected one of several projects from an unrelated directory." >&2
  exit 1
fi

(
  cd "$temporary_root"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  FAKE_REPOCHORD_SETTINGS_CAPTURE="$settings_capture" \
  "$rchord_command" \
    --project back-office
)

diff -u \
  <(printf '%s\n' \
    -C \
    "$second_coordinate_repository" \
    --config \
    'model_reasoning_effort="low"' \
    --config \
    'features.network_proxy=true' \
    --config \
    "$expected_coordinator_permissions" \
    --config \
    'default_permissions="repochord-coordinator"') \
  <(normalize_launcher_capture)

grep -Fqx "repository_agent_reasoning_effort=xhigh" "$settings_capture"

if /bin/bash -c '((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2)))'; then
  if /bin/bash "$rchord_command" --help >"$temporary_root/unsupported-bash.out" 2>&1; then
    echo "RepoChord unexpectedly ran with an unsupported Bash version." >&2
    exit 1
  fi

  grep -Fqx "RepoChord requires Bash 5.2 or later." "$temporary_root/unsupported-bash.out"
fi

if HOME="$test_home" "$rchord_command" init \
  --project acme-commerce \
  --coordinate "$name_collision_coordinate" \
  --create-coordinate \
  --repository "admin=$admin_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly reused a project name for another coordination repository." >&2
  exit 1
fi

test ! -e "$name_collision_coordinate"

mkdir -p "$conflict_coordinate_repository/.repochord"
git -C "$conflict_coordinate_repository" init -q

jq -n \
  --arg path "$api_repository" \
  '{version: 1, repositories: [{key: "different", path: $path}]}' \
  > "$conflict_coordinate_repository/.repochord/repositories.json"

if HOME="$test_home" "$rchord_command" init \
  --project conflict-project \
  --coordinate "$conflict_coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly overwrote a different repository registry." >&2
  exit 1
fi

test ! -e "$conflict_coordinate_repository/.agents/skills/repochord"

scaffolder="$coordinate_repository/.agents/skills/repochord/scripts/scaffold-feature.sh"
packet_fixture="$test_directory/fixtures/complete-scaffolded-packet.sh"

"$scaffolder" PROJECT-123 api web >/dev/null

test ! -e "$coordinate_repository/requests/PROJECT-123.md"
test ! -e "$coordinate_repository/tasks/PROJECT-123/api.md"
test ! -e "$coordinate_repository/tasks/PROJECT-123/web.md"
test -f "$coordinate_repository/tasks/PROJECT-123/assignments.txt"

"$scaffolder" editable-shipping-address api web >/dev/null
existing_request="$coordinate_repository/requests/editable-shipping-address.md"
existing_assignments="$coordinate_repository/tasks/editable-shipping-address/assignments.txt"
existing_assignments_hash="$(git hash-object "$existing_assignments")"
resolved_output="$("$scaffolder" --title "Editable shipping address" api web)"
resolved_request_path="${resolved_output%%$'\n'*}"
resolved_assignment_path="${resolved_output#*$'\n'}"
resolved_assignment_path="${resolved_assignment_path%%$'\n'*}"
case_variant_output="$("$scaffolder" EDITABLE-SHIPPING-ADDRESS api web)"
case_variant_request_path="${case_variant_output%%$'\n'*}"
case_variant_assignment_path="${case_variant_output#*$'\n'}"
case_variant_assignment_path="${case_variant_assignment_path%%$'\n'*}"

test "$resolved_request_path" = "$existing_request"
test "$resolved_assignment_path" = "$existing_assignments"
test "$case_variant_request_path" = "$existing_request"
test "$case_variant_assignment_path" = "$existing_assignments"
test ! -e "$existing_request"
test "$existing_assignments_hash" = "$(git hash-object "$existing_assignments")"

if find "$coordinate_repository/tasks" -maxdepth 1 -name 'editable-shipping-address-*' -print -quit | grep -q .; then
  echo "Scaffolder created a duplicate for an existing normalized feature title." >&2
  exit 1
fi

generated_output="$("$scaffolder" --title "Customer order cancellation" api web)"
generated_request_path="${generated_output%%$'\n'*}"
generated_assignment_path="${generated_output#*$'\n'}"
generated_assignment_path="${generated_assignment_path%%$'\n'*}"
generated_feature_filename="$(basename -- "$generated_request_path")"
generated_feature_id="${generated_feature_filename%.md}"
generated_feature_prefix="customer-order-cancellation-"
generated_feature_suffix="${generated_feature_id#"$generated_feature_prefix"}"

if [[ "$generated_feature_id" != "$generated_feature_prefix"* || \
  ! "$generated_feature_suffix" =~ ^[a-z0-9]+$ || \
  "${#generated_feature_suffix}" -ne 6 ]]
then
  echo "Scaffolder returned an invalid generated feature ID: $generated_feature_id" >&2
  exit 1
fi

test "$generated_assignment_path" = "$coordinate_repository/tasks/$generated_feature_id/assignments.txt"
test ! -e "$generated_request_path"
test ! -e "$coordinate_repository/tasks/$generated_feature_id/api.md"
test ! -e "$coordinate_repository/tasks/$generated_feature_id/web.md"

second_generated_output="$("$scaffolder" --title "Customer order cancellation" api web)"
second_generated_request_path="${second_generated_output%%$'\n'*}"
second_generated_feature_filename="$(basename -- "$second_generated_request_path")"
second_generated_feature_id="${second_generated_feature_filename%.md}"

if [[ "$second_generated_feature_id" == "$generated_feature_id" ]]; then
  echo "Scaffolder generated a duplicate feature ID." >&2
  exit 1
fi

if [[ -n "$(find "$coordinate_repository" -maxdepth 1 -name '.repochord-feature-id.*' -print -quit)" ]]; then
  echo "Scaffolder left an identifier reservation behind." >&2
  exit 1
fi

"$packet_fixture" "$coordinate_repository" PROJECT-123

touch "$api_repository/preflight-dirty.tmp"
runner="$coordinate_repository/.agents/skills/repochord/scripts/run-repository-agents.sh"

if "$runner" \
  PROJECT-123-preflight \
  "$coordinate_repository/tasks/PROJECT-123/assignments.txt" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a dirty product repository." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-preflight"
rm -f -- "$api_repository/preflight-dirty.tmp"

existing_explicit_output="$("$scaffolder" PROJECT-123 api web)"
existing_explicit_request="${existing_explicit_output%%$'\n'*}"
existing_explicit_assignments="${existing_explicit_output#*$'\n'}"
existing_explicit_assignments="${existing_explicit_assignments%%$'\n'*}"
test "$existing_explicit_request" = "$coordinate_repository/requests/PROJECT-123.md"
test "$existing_explicit_assignments" = "$coordinate_repository/tasks/PROJECT-123/assignments.txt"

printf '\nlocal change\n' >> "$coordinate_repository/.agents/skills/repochord/SKILL.md"
printf 'obsolete project runtime file\n' > "$coordinate_repository/.agents/skills/repochord/obsolete.txt"

HOME="$test_home" "$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

diff -qr "$installed_data/skill" "$coordinate_repository/.agents/skills/repochord" >/dev/null
diff -qr "$installed_data/task-skill" "$coordinate_repository/.agents/skills/create-repochord-task" >/dev/null
test ! -e "$coordinate_repository/.agents/skills/repochord/obsolete.txt"

echo "Installer tests passed."
