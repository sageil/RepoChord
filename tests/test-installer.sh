#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repomux-installer-test.XXXXXX)"

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
bash32_coordinate_repository="$temporary_root/bash32-control"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
conflict_bin="$temporary_root/conflict-commands"
link_bin="$temporary_root/link-commands"
fake_bin="$temporary_root/fake-bin"
launcher_capture="$temporary_root/launcher-arguments.txt"
attempts_capture="$temporary_root/max-attempts.txt"

initialize_product_repository "$api_repository" api
initialize_product_repository "$web_repository" web
initialize_product_repository "$admin_repository" admin
git init -q "$empty_repository"
mkdir -p "$test_home" "$conflict_bin" "$link_bin"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOMUX_CONFIG_HOME REPOMUX_DATA_HOME

install_output="$(
  HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$command_bin"
)"

repomux_command="$command_bin/repomux"
installed_data="$test_home/.local/share/repomux"
projects_registry="$test_home/.config/repomux/projects.json"

test -f "$repomux_command"
test -x "$repomux_command"
test ! -L "$repomux_command"
test -d "$installed_data/skill"
test ! -L "$installed_data/skill"

env \
  -u HOME \
  -u XDG_CONFIG_HOME \
  -u XDG_DATA_HOME \
  -u REPOMUX_CONFIG_HOME \
  -u REPOMUX_DATA_HOME \
  "$repomux_command" --help \
  >/dev/null 2>&1

expected_path_instruction="export PATH=$command_bin:\$PATH"

if [[ "$install_output" != *"$expected_path_instruction"* ]]; then
  echo "Installer did not print the expected PATH instruction." >&2
  exit 1
fi

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

printf 'preserve this command\n' > "$conflict_bin/repomux"

if HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$conflict_bin" \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly overwrote an existing command." >&2
  exit 1
fi

grep -Fqx "preserve this command" "$conflict_bin/repomux"

ln -s "$repository_directory/payload/repomux" "$link_bin/repomux"

if HOME="$test_home" \
  "$repository_directory/install.sh" \
    --bin-dir "$link_bin" \
    >/dev/null 2>&1
then
  echo "Installer unexpectedly accepted a symbolic link as the command." >&2
  exit 1
fi

test -L "$link_bin/repomux"

if HOME="$test_home" "$repomux_command" init \
  --project duplicate-project \
  --coordinate "$duplicate_coordinate_repository" \
  --create-coordinate \
  --repository "api=$api_repository" \
  --repository "api-alias=$api_repository" \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly accepted a duplicate canonical repository path." >&2
  exit 1
fi

test ! -e "$duplicate_coordinate_repository"

if HOME="$test_home" "$repomux_command" init \
  --project empty-project \
  --coordinate "$empty_coordinate_repository" \
  --create-coordinate \
  --repository "empty=$empty_repository" \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly accepted a repository without an initial commit." >&2
  exit 1
fi

test ! -e "$empty_coordinate_repository"

if HOME="$test_home" "$repomux_command" init \
  --project invalid-ref-project \
  --coordinate "$invalid_ref_coordinate_repository" \
  --create-coordinate \
  --repository "api.lock=$api_repository" \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly accepted a repository key that cannot form a Git branch." >&2
  exit 1
fi

test ! -e "$invalid_ref_coordinate_repository"

HOME="$test_home" "$repomux_command" init \
  -p acme-commerce \
  -c "$coordinate_repository" \
  --create-coordinate \
  -r "api=$api_repository" \
  -r "web=$web_repository"

(
  cd "$coordinate_repository"
  HOME="$test_home" "$repomux_command" init \
    --project acme-commerce \
    --coordinate "$(pwd)" \
    --repository "api=$(pwd)/../api" \
    --repository "web=$(pwd)/../web" \
    >/dev/null
)

test -d "$coordinate_repository/.agents/skills/repomux"
test ! -L "$coordinate_repository/.agents/skills/repomux"
test -f "$coordinate_repository/.repomux/repositories.json"
test -f "$coordinate_repository/.repomux/results/.gitignore"
test ! -e "$coordinate_repository/start-coordinator.sh"

jq -e \
  --arg coordinate "$coordinate_repository" \
  '.version == 1 and
   .defaults == {maxAttempts: 3} and
   .projects == [{name: "acme-commerce", coordinate: $coordinate}]' \
  "$projects_registry" \
  >/dev/null

default_max_attempts="$(
  HOME="$test_home" \
  "$repomux_command" config get \
    --project acme-commerce \
    max-attempts
)"

test "$default_max_attempts" = "3"

HOME="$test_home" \
"$repomux_command" config set \
  --project acme-commerce \
  max-attempts 5 \
  >/dev/null

configured_max_attempts="$(
  HOME="$test_home" \
  "$repomux_command" config get \
    --project acme-commerce \
    max-attempts
)"

test "$configured_max_attempts" = "5"

(
  cd "$coordinate_repository"
  HOME="$test_home" \
  "$repomux_command" config set max-attempts 6 \
    >/dev/null

  test "$(HOME="$test_home" "$repomux_command" config get max-attempts)" = "6"
)

HOME="$test_home" \
"$repomux_command" config set \
  --project acme-commerce \
  max-attempts 5 \
  >/dev/null

HOME="$test_home" \
"$repomux_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

jq -e \
  '.projects[] | select(.name == "acme-commerce") | .maxAttempts == 5' \
  "$projects_registry" \
  >/dev/null

if HOME="$test_home" "$repomux_command" config set \
  --project acme-commerce \
  max-attempts 0 \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly accepted an invalid maximum attempt count." >&2
  exit 1
fi

mkdir -p "$fake_bin"
cp "$test_directory/fixtures/fake-codex-start.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
FAKE_CODEX_START_CAPTURE="$launcher_capture" \
FAKE_REPOMUX_ATTEMPTS_CAPTURE="$attempts_capture" \
"$repomux_command" \
  -- \
  --profile test-profile

diff -u \
  <(printf '%s\n' \
    -C \
    "$coordinate_repository" \
    --sandbox \
    workspace-write \
    --add-dir \
    "$api_repository" \
    --add-dir \
    "$web_repository" \
    --profile \
    test-profile) \
  "$launcher_capture"

grep -Fqx "5" "$attempts_capture"

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
FAKE_CODEX_START_CAPTURE="$launcher_capture" \
FAKE_REPOMUX_ATTEMPTS_CAPTURE="$attempts_capture" \
"$repomux_command" \
  --project acme-commerce \
  --max-attempts 7

grep -Fqx "7" "$attempts_capture"

test "$(
  HOME="$test_home" \
  "$repomux_command" config get \
    --project acme-commerce \
    max-attempts
)" = "5"

(
  cd "$api_repository"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$repomux_command" \
    --repository web \
    -- \
    --model test-model
)

diff -u \
  <(printf '%s\n' \
    -C \
    "$coordinate_repository" \
    --sandbox \
    workspace-write \
    --add-dir \
    "$web_repository" \
    --model \
    test-model) \
  "$launcher_capture"

(
  cd "$temporary_root"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$repomux_command" \
    --repository api
)

diff -u \
  <(printf '%s\n' \
    -C \
    "$coordinate_repository" \
    --sandbox \
    workspace-write \
    --add-dir \
    "$api_repository") \
  "$launcher_capture"

if HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$repomux_command" \
    --repository missing \
    >/dev/null 2>&1
then
  echo "RepoMux unexpectedly accepted an unregistered repository key." >&2
  exit 1
fi

HOME="$test_home" \
PATH="$fake_bin:$PATH" \
"$repomux_command" validate --project acme-commerce \
  >/dev/null

list_output="$(HOME="$test_home" "$repomux_command" list)"

if [[ "$list_output" != *$'acme-commerce\t'"$coordinate_repository"* ]]; then
  echo "RepoMux list did not include the initialized project." >&2
  exit 1
fi

HOME="$test_home" "$repomux_command" init \
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
  "$repomux_command" \
    >/dev/null 2>&1
)
then
  echo "RepoMux unexpectedly selected one of several projects from an unrelated directory." >&2
  exit 1
fi

(
  cd "$temporary_root"
  HOME="$test_home" \
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_START_CAPTURE="$launcher_capture" \
  "$repomux_command" \
    --project back-office
)

diff -u \
  <(printf '%s\n' \
    -C \
    "$second_coordinate_repository" \
    --sandbox \
    workspace-write \
    --add-dir \
    "$admin_repository") \
  "$launcher_capture"

HOME="$test_home" \
/bin/bash "$repomux_command" init \
  --project bash32-project \
  --coordinate "$bash32_coordinate_repository" \
  --create-coordinate \
  --repository "api=$api_repository" \
  >/dev/null

test -f "$bash32_coordinate_repository/.repomux/repositories.json"

if HOME="$test_home" "$repomux_command" init \
  --project acme-commerce \
  --coordinate "$name_collision_coordinate" \
  --create-coordinate \
  --repository "admin=$admin_repository" \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly reused a project name for another coordination repository." >&2
  exit 1
fi

test ! -e "$name_collision_coordinate"

mkdir -p "$conflict_coordinate_repository/.repomux"
git -C "$conflict_coordinate_repository" init -q

jq -n \
  --arg path "$api_repository" \
  '{version: 1, repositories: [{key: "different", path: $path}]}' \
  > "$conflict_coordinate_repository/.repomux/repositories.json"

if HOME="$test_home" "$repomux_command" init \
  --project conflict-project \
  --coordinate "$conflict_coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly overwrote a different repository registry." >&2
  exit 1
fi

test ! -e "$conflict_coordinate_repository/.agents/skills/repomux"

scaffolder="$coordinate_repository/.agents/skills/repomux/scripts/scaffold-feature.sh"

"$scaffolder" PROJECT-123 api web >/dev/null

test -f "$coordinate_repository/requests/PROJECT-123.md"
test -f "$coordinate_repository/tasks/PROJECT-123/api.md"
test -f "$coordinate_repository/tasks/PROJECT-123/web.md"
test -f "$coordinate_repository/tasks/PROJECT-123/assignments.txt"

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
grep -Fqx "Customer order cancellation" "$generated_request_path"
test -f "$coordinate_repository/tasks/$generated_feature_id/api.md"
test -f "$coordinate_repository/tasks/$generated_feature_id/web.md"

second_generated_output="$("$scaffolder" --title "Customer order cancellation" api web)"
second_generated_request_path="${second_generated_output%%$'\n'*}"
second_generated_feature_filename="$(basename -- "$second_generated_request_path")"
second_generated_feature_id="${second_generated_feature_filename%.md}"

if [[ "$second_generated_feature_id" == "$generated_feature_id" ]]; then
  echo "Scaffolder generated a duplicate feature ID." >&2
  exit 1
fi

if [[ -n "$(find "$coordinate_repository" -maxdepth 1 -name '.repomux-feature-id.*' -print -quit)" ]]; then
  echo "Scaffolder left an identifier reservation behind." >&2
  exit 1
fi

touch "$api_repository/preflight-dirty.tmp"
runner="$coordinate_repository/.agents/skills/repomux/scripts/run-repository-agents.sh"

if "$runner" \
  PROJECT-123-preflight \
  "$coordinate_repository/tasks/PROJECT-123/assignments.txt" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a dirty product repository." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repomux/results/PROJECT-123-preflight"
rm -f -- "$api_repository/preflight-dirty.tmp"

if "$scaffolder" PROJECT-123 api web >/dev/null 2>&1; then
  echo "Scaffolder unexpectedly overwrote an existing feature." >&2
  exit 1
fi

printf '\nlocal change\n' >> "$coordinate_repository/.agents/skills/repomux/SKILL.md"

if HOME="$test_home" "$repomux_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null 2>&1
then
  echo "RepoMux unexpectedly overwrote a changed project skill." >&2
  exit 1
fi

echo "Installer tests passed."
