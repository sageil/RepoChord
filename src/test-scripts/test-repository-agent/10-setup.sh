#!/usr/bin/env bash

# Generated from src/test-scripts by scripts/build-test-scripts.sh.
# Do not edit this test in tests directly.

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/repochord-repository-agent-test.XXXXXX")"
temporary_root="$(cd -- "$temporary_root" && pwd -P)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_product_repository() {
  local repository_path="$1"
  local repository_name="$2"

  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Repository Agent Test"
  git -C "$repository_path" config user.email "repository-agent-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null

  if [[ "$repository_name" == "api" ]]; then
    git -C "$repository_path" branch -M main
  else
    git -C "$repository_path" branch -M master
  fi
}

api_repository="$temporary_root/api"
web_repository="$temporary_root/web"
empty_repository="$temporary_root/empty"
coordinate_repository="$temporary_root/control"
fake_bin="$temporary_root/bin"
capture_directory="$temporary_root/captures"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"

initialize_product_repository "$api_repository" api
initialize_product_repository "$web_repository" web
git init -q "$empty_repository"

mkdir -p "$test_home"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOCHORD_CONFIG_HOME REPOCHORD_DATA_HOME

git config --global user.name "Global Repository User"
git config --global user.email "global-repository-user@example.com"

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

HOME="$test_home" \
"$command_bin/rchord" init \
  -p repository-agent-test \
  -c "$coordinate_repository" \
  --create-coordinate \
  -r "api=$api_repository" \
  -r "web=$web_repository" \
  >/dev/null

scaffolder="$coordinate_repository/.agents/skills/repochord/scripts/scaffold-feature.sh"
runner="$coordinate_repository/.agents/skills/repochord/scripts/run-repository-agents.sh"
repository_agent="$coordinate_repository/.agents/skills/repochord/scripts/run-repository-agent.sh"
packet_fixture="$test_directory/fixtures/complete-scaffolded-packet.sh"

api_base_commit="$(git -C "$api_repository" rev-parse HEAD)"
web_base_commit="$(git -C "$web_repository" rev-parse HEAD)"
api_base_branch="$(git -C "$api_repository" symbolic-ref --short HEAD)"
web_base_branch="$(git -C "$web_repository" symbolic-ref --short HEAD)"
post_commit_marker="$temporary_root/post-commit-hook-ran"

for product_repository in "$api_repository" "$web_repository"; do
  for hook_name in post-checkout post-commit reference-transaction; do
    printf '#!/bin/sh\n: > "%s"\n' "$post_commit_marker" > "$product_repository/.git/hooks/$hook_name"
    chmod +x "$product_repository/.git/hooks/$hook_name"
  done
done

"$scaffolder" PROJECT-123 api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-123

assignments_file="$coordinate_repository/tasks/PROJECT-123/assignments.txt"
api_assignment="$temporary_root/api-assignment.txt"
web_assignment="$temporary_root/web-assignment.txt"

sed -n '1p' "$assignments_file" > "$api_assignment"
sed -n '2p' "$assignments_file" > "$web_assignment"

mkdir -p "$fake_bin" "$capture_directory"
cp "$test_directory/fixtures/fake-codex.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"
export FAKE_ABSOLUTE_GIT
FAKE_ABSOLUTE_GIT="$(command -v git)"
