#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repomux-uninstaller-test.XXXXXX)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

product_repository="$temporary_root/product"
coordinate_repository="$temporary_root/coordinate"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"

git init -q "$product_repository"
git -C "$product_repository" config user.name "Uninstaller Test"
git -C "$product_repository" config user.email "uninstaller-test@example.com"
printf '# product\n' > "$product_repository/README.md"
git -C "$product_repository" add README.md
git -C "$product_repository" commit -m "test: initialize product" >/dev/null
product_commit="$(git -C "$product_repository" rev-parse HEAD)"

mkdir -p "$test_home"
export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOMUX_CONFIG_HOME REPOMUX_DATA_HOME

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

repomux_command="$command_bin/repomux"
installed_data="$test_home/.local/share/repomux"
projects_registry="$test_home/.config/repomux/projects.json"

HOME="$test_home" \
"$repomux_command" init \
  --project uninstall-test \
  --coordinate "$coordinate_repository" \
  --create-coordinate \
  --repository "product=$product_repository" \
  >/dev/null

registry_before_uninstall="$(jq -c . "$projects_registry")"

uninstall_output="$(
  HOME="$test_home" \
  "$repository_directory/uninstall.sh" \
    --bin-dir "$command_bin"
)"

test ! -e "$repomux_command"
test ! -e "$installed_data/skill"
test ! -e "$installed_data/task-skill"
test ! -e "$installed_data"
test -f "$projects_registry"
test "$(jq -c . "$projects_registry")" = "$registry_before_uninstall"
test -d "$coordinate_repository/.agents/skills/repomux"
test -d "$coordinate_repository/.agents/skills/create-repomux-task"
test "$(git -C "$product_repository" rev-parse HEAD)" = "$product_commit"

if [[ "$uninstall_output" != *"Configuration preserved: $projects_registry"* ]]; then
  echo "Uninstaller did not report the preserved configuration." >&2
  exit 1
fi

HOME="$test_home" \
"$repository_directory/uninstall.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

test -f "$projects_registry"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

printf '\nlocal command change\n' >> "$repomux_command"
printf '\nlocal skill change\n' >> "$installed_data/skill/SKILL.md"

HOME="$test_home" \
"$repository_directory/uninstall.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

test ! -e "$repomux_command"
test ! -e "$installed_data/skill"
test ! -e "$installed_data/task-skill"
test -f "$projects_registry"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

rm -f -- "$repomux_command"
ln -s "$repository_directory/payload/repomux" "$repomux_command"
rm -rf -- "$installed_data/skill"
ln -s "$repository_directory/payload/.agents/skills/repomux" "$installed_data/skill"

HOME="$test_home" \
"$repository_directory/uninstall.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

test ! -e "$repomux_command"
test ! -L "$repomux_command"
test ! -e "$installed_data/skill"
test ! -L "$installed_data/skill"
test -f "$repository_directory/payload/repomux"
test -d "$repository_directory/payload/.agents/skills/repomux"
test -f "$projects_registry"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

printf '{"not":"a RepoMux registry"}\n' > "$projects_registry"

purge_output="$(
  HOME="$test_home" \
  "$repository_directory/uninstall.sh" \
    --bin-dir "$command_bin" \
    --purge-config
)"

test ! -e "$repomux_command"
test ! -e "$installed_data"
test ! -e "$projects_registry"
test ! -e "$test_home/.config/repomux"
test -d "$coordinate_repository"
test -d "$product_repository"

if [[ "$purge_output" != *"Configuration removed: $projects_registry"* ]]; then
  echo "Uninstaller did not report the removed configuration." >&2
  exit 1
fi

xdg_home="$temporary_root/xdg-home"
xdg_bin="$temporary_root/xdg-bin"
xdg_data="$temporary_root/xdg-data"
xdg_config="$temporary_root/xdg-config"
mkdir -p "$xdg_home"

HOME="$xdg_home" \
XDG_BIN_HOME="$xdg_bin" \
XDG_DATA_HOME="$xdg_data" \
XDG_CONFIG_HOME="$xdg_config" \
"$repository_directory/install.sh" \
  >/dev/null

HOME="$xdg_home" \
XDG_BIN_HOME="$xdg_bin" \
XDG_DATA_HOME="$xdg_data" \
XDG_CONFIG_HOME="$xdg_config" \
"$repository_directory/uninstall.sh" \
  --purge-config \
  >/dev/null

test ! -e "$xdg_bin/repomux"
test ! -e "$xdg_data/repomux"
test ! -e "$xdg_config/repomux"

echo "Uninstaller tests passed."
