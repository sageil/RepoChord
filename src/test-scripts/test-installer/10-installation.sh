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
