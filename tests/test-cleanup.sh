#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/repochord-cleanup-test.XXXXXX")"
temporary_root="$(cd -- "$temporary_root" && pwd -P)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_product_repository() {
  local repository_path="$1"
  local repository_name="$2"

  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Cleanup Test"
  git -C "$repository_path" config user.email "cleanup-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null
}

create_run_worktree() {
  local run_id="$1"
  local repository_key="$2"
  local source_repository="$3"
  local private_repository="$coordinate_repository/.repochord/repositories/$run_id/$repository_key.git"
  local worktree_path="$coordinate_repository/.repochord/worktrees/$run_id/$repository_key"
  local worktree_branch="repochord/$run_id/$repository_key"
  local result_directory="$coordinate_repository/.repochord/results/$run_id"
  local base_commit

  base_commit="$(git -C "$source_repository" rev-parse HEAD)"

  mkdir -p "$(dirname -- "$private_repository")" "$(dirname -- "$worktree_path")" "$result_directory"
  git init --bare -q "$private_repository"
  git -C "$private_repository" fetch -q --no-tags --no-write-fetch-head "$source_repository" "$base_commit"
  git -C "$private_repository" worktree add -q -b "$worktree_branch" "$worktree_path" "$base_commit"
  jq -n \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    --arg source_repository_path "$source_repository" \
    --arg private_repository_path "$private_repository" \
    --arg worktree_path "$worktree_path" \
    --arg worktree_branch "$worktree_branch" \
    '{
      run_id: $run_id,
      repository: $repository,
      execution: {
        source_repository_path: $source_repository_path,
        private_repository_path: $private_repository_path,
        worktree_path: $worktree_path,
        worktree_branch: $worktree_branch
      }
    }' > "$result_directory/$repository_key.json"
}

test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
coordinate_repository="$temporary_root/coordinate"
api_repository="$temporary_root/api"
web_repository="$temporary_root/web"

initialize_product_repository "$api_repository" api
initialize_product_repository "$web_repository" web
mkdir -p "$test_home"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOCHORD_CONFIG_HOME REPOCHORD_DATA_HOME

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

rchord_command="$command_bin/rchord"

HOME="$test_home" \
"$rchord_command" init \
  --project acme \
  --coordinate "$coordinate_repository" \
  --create-coordinate \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

for run_id in run-one run-two; do
  create_run_worktree "$run_id" api "$api_repository"
  create_run_worktree "$run_id" web "$web_repository"
done

if HOME="$test_home" "$rchord_command" cleanup --project acme >/dev/null 2>&1; then
  echo "Cleanup unexpectedly accepted no run selector." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" cleanup \
  --project acme \
  --run run-one \
  --all \
  >/dev/null 2>&1
then
  echo "Cleanup unexpectedly accepted both --run and --all." >&2
  exit 1
fi

printf 'dirty\n' > "$coordinate_repository/.repochord/worktrees/run-two/api/dirty.txt"

if HOME="$test_home" "$rchord_command" cleanup \
  --project acme \
  --repository api \
  --all \
  >/dev/null 2>&1
then
  echo "Cleanup unexpectedly removed dirty worktrees without --force." >&2
  exit 1
fi

test -d "$coordinate_repository/.repochord/worktrees/run-one/api"
test -d "$coordinate_repository/.repochord/worktrees/run-two/api"

HOME="$test_home" "$rchord_command" cleanup \
  --project acme \
  --repository api \
  --all \
  --force \
  >/dev/null

for run_id in run-one run-two; do
  test ! -e "$coordinate_repository/.repochord/worktrees/$run_id/api"
  test -d "$coordinate_repository/.repochord/worktrees/$run_id/web"
  test -f "$coordinate_repository/.repochord/results/$run_id/api.json"
  test -f "$coordinate_repository/.repochord/results/$run_id/web.json"
  git -C "$coordinate_repository/.repochord/repositories/$run_id/api.git" \
    rev-parse --verify "refs/heads/repochord/$run_id/api" >/dev/null
  git -C "$coordinate_repository/.repochord/repositories/$run_id/web.git" \
    rev-parse --verify "refs/heads/repochord/$run_id/web" >/dev/null
done

HOME="$test_home" "$rchord_command" cleanup \
  --project acme \
  --all \
  --force \
  >/dev/null

for run_id in run-one run-two; do
  test ! -e "$coordinate_repository/.repochord/worktrees/$run_id/web"
  test -f "$coordinate_repository/.repochord/results/$run_id/api.json"
  test -f "$coordinate_repository/.repochord/results/$run_id/web.json"
  git -C "$coordinate_repository/.repochord/repositories/$run_id/api.git" \
    rev-parse --verify "refs/heads/repochord/$run_id/api" >/dev/null
  git -C "$coordinate_repository/.repochord/repositories/$run_id/web.git" \
    rev-parse --verify "refs/heads/repochord/$run_id/web" >/dev/null
done

cleanup_output="$(HOME="$test_home" "$rchord_command" cleanup --project acme --all --force)"
grep -Fqx "No matching RepoChord worktrees were found." <<< "$cleanup_output"

echo "Cleanup tests passed."
