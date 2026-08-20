#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repomux-integration-test.XXXXXX)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_product_repository() {
  local repository_path="$1"
  local repository_name="$2"
  local branch_name="$3"

  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Integration Test"
  git -C "$repository_path" config user.email "integration-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null
  git -C "$repository_path" branch -M "$branch_name"
}

api_repository="$temporary_root/api"
web_repository="$temporary_root/web"
coordinate_repository="$temporary_root/coordinate"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
fake_bin="$temporary_root/fake-bin"

initialize_product_repository "$api_repository" api main
initialize_product_repository "$web_repository" web master
mkdir -p "$test_home" "$fake_bin"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOMUX_CONFIG_HOME REPOMUX_DATA_HOME

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

HOME="$test_home" \
"$command_bin/repomux" init \
  -p integration-test \
  -c "$coordinate_repository" \
  --create-coordinate \
  -r "api=$api_repository" \
  -r "web=$web_repository" \
  >/dev/null

git -C "$coordinate_repository" config user.name "Integration Test"
git -C "$coordinate_repository" config user.email "integration-test@example.com"
printf 'initial coordination state\n' > "$coordinate_repository/README.md"
printf 'preserve this staged change\n' > "$coordinate_repository/notes.txt"
git -C "$coordinate_repository" add .
git -C "$coordinate_repository" commit -m "test: initialize coordination repository" >/dev/null
git -C "$coordinate_repository" config --unset user.email
printf 'staged but unrelated\n' >> "$coordinate_repository/notes.txt"
git -C "$coordinate_repository" add notes.txt

cp "$test_directory/fixtures/fake-codex.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"
export FAKE_ABSOLUTE_GIT
FAKE_ABSOLUTE_GIT="$(command -v git)"

scaffolder="$coordinate_repository/.agents/skills/repomux/scripts/scaffold-feature.sh"
runner="$coordinate_repository/.agents/skills/repomux/scripts/run-repository-agents.sh"
packet_fixture="$test_directory/fixtures/complete-scaffolded-packet.sh"
run_id="PROJECT-INTEGRATE-run-001"

"$scaffolder" PROJECT-INTEGRATE api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-INTEGRATE

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$runner" \
  --max-parallel 2 \
  "$run_id" \
  "$coordinate_repository/tasks/PROJECT-INTEGRATE/assignments.txt" \
  >/dev/null

run_manifest="$coordinate_repository/.repomux/results/$run_id/.manifest.json"

jq -e \
  --arg coordinate "$coordinate_repository" \
  --arg api "$api_repository" \
  --arg web "$web_repository" \
  '
    .version == 1 and
    .run_id == "PROJECT-INTEGRATE-run-001" and
    .feature_id == "PROJECT-INTEGRATE" and
    .assignments_file == ($coordinate + "/tasks/PROJECT-INTEGRATE/assignments.txt") and
    .request_file == ($coordinate + "/requests/PROJECT-INTEGRATE.md") and
    (.assignments_hash | test("^[0-9a-f]+$")) and
    (.request_hash | test("^[0-9a-f]+$")) and
    .repositories[0].key == "api" and
    .repositories[0].path == $api and
    (.repositories[0].task_hash | test("^[0-9a-f]+$")) and
    .repositories[1].key == "web" and
    .repositories[1].path == $web and
    (.repositories[1].task_hash | test("^[0-9a-f]+$"))
  ' \
  "$run_manifest" \
  >/dev/null

api_base_commit="$(git -C "$api_repository" rev-parse main)"
web_base_commit="$(git -C "$web_repository" rev-parse master)"
coordinate_base_commit="$(git -C "$coordinate_repository" rev-parse HEAD)"
api_final_commit="$(jq -r '.commit' "$coordinate_repository/.repomux/results/$run_id/api.json")"
web_final_commit="$(jq -r '.commit' "$coordinate_repository/.repomux/results/$run_id/web.json")"

git -C "$api_repository" switch -q -c user-work
integration_hook_marker="$temporary_root/integration-hook-ran"

for hook_path in \
  "$coordinate_repository/.git/hooks/post-commit" \
  "$api_repository/.git/hooks/reference-transaction" \
  "$web_repository/.git/hooks/post-merge"
do
  printf '#!/bin/sh\n: > "%s"\n' "$integration_hook_marker" > "$hook_path"
  chmod +x "$hook_path"
done

printf 'uncommitted product change\n' >> "$web_repository/README.md"
dirty_checkout_error="$temporary_root/dirty-checkout-error.txt"

if HOME="$test_home" "$command_bin/repomux" integrate \
  --project integration-test \
  --run "$run_id" \
  --dry-run \
  >/dev/null \
  2> "$dirty_checkout_error"
then
  echo "Integration unexpectedly accepted a dirty product checkout." >&2
  exit 1
fi

grep -Fqx \
  "Base branch checkout is not clean in web: $web_repository" \
  "$dirty_checkout_error"
git -C "$web_repository" restore README.md

dry_run_output="$(
  HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$run_id" \
    --dry-run
)"

if git -C "$coordinate_repository" config user.email >/dev/null; then
  echo "Integration test unexpectedly has a configured coordination repository email." >&2
  exit 1
fi

if [[ "$dry_run_output" != *"Dry run complete. No changes were made."* || \
  "$dry_run_output" != *"Integration: pending"* ]]
then
  echo "Integration dry run did not report the expected plan." >&2
  exit 1
fi

if [[ "$dry_run_output" == *"  Diff:"* ]]; then
  echo "Integration displayed full diffs without --show-diffs." >&2
  exit 1
fi

show_diffs_output="$(
  HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$run_id" \
    --dry-run \
    --show-diffs
)"

if [[ "$show_diffs_output" != *"Dry run complete. No changes were made."* || \
  "$show_diffs_output" != *"  Diff:"* || \
  "$show_diffs_output" != *"+fake repository-agent change"* ]]
then
  echo "Integration did not display the requested repository diffs." >&2
  exit 1
fi

show_diff_file_count="$(
  printf '%s\n' "$show_diffs_output" | \
    grep -Fc "diff --git a/fake-$run_id.txt b/fake-$run_id.txt"
)"

if [[ "$show_diff_file_count" -ne 2 ]]; then
  echo "Integration did not display one diff for each pending repository." >&2
  exit 1
fi

test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$coordinate_base_commit"
test "$(git -C "$api_repository" rev-parse main)" = "$api_base_commit"
test "$(git -C "$web_repository" rev-parse master)" = "$web_base_commit"
test "$(git -C "$api_repository" symbolic-ref --short HEAD)" = "user-work"
test "$(git -C "$api_repository" rev-parse HEAD)" = "$api_base_commit"
test -d "$coordinate_repository/.repomux/worktrees/$run_id/api"
test -d "$coordinate_repository/.repomux/worktrees/$run_id/web"

confirmation_fifo="$temporary_root/confirmation.fifo"
confirmation_output="$temporary_root/confirmation-output.txt"
original_coordinate_branch="$(git -C "$coordinate_repository" symbolic-ref --short HEAD)"
confirmation_prompt_seen=false
mkfifo "$confirmation_fifo"
exec 9<>"$confirmation_fifo"

HOME="$test_home" \
"$command_bin/repomux" integrate \
  --project integration-test \
  --run "$run_id" \
  <"$confirmation_fifo" \
  >"$confirmation_output" \
  2>&1 &
confirmation_pid="$!"

for ((prompt_attempt = 0; prompt_attempt < 100; prompt_attempt++)); do
  if grep -Fq "repository branch(es)? [y/N]" "$confirmation_output"; then
    confirmation_prompt_seen=true
    break
  fi

  if ! kill -0 "$confirmation_pid" >/dev/null 2>&1; then
    break
  fi

  sleep 0.05
done

if [[ "$confirmation_prompt_seen" != true ]]; then
  echo "Integration did not present its confirmation prompt." >&2
  exit 1
fi

git -C "$coordinate_repository" switch -q -c changed-during-confirmation
printf 'yes\n' >&9
exec 9>&-

if wait "$confirmation_pid"; then
  echo "Integration unexpectedly accepted a changed confirmation plan." >&2
  exit 1
fi

grep -Fq "The integration plan changed while confirmation was pending." "$confirmation_output"
test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$coordinate_base_commit"
test "$(git -C "$api_repository" rev-parse main)" = "$api_base_commit"
test "$(git -C "$web_repository" rev-parse master)" = "$web_base_commit"
git -C "$coordinate_repository" switch -q "$original_coordinate_branch"

integration_output="$(
  printf 'yes\n' | \
    HOME="$test_home" \
    "$command_bin/repomux" integrate \
      --project integration-test \
      --run "$run_id"
)"

if [[ "$integration_output" != *"Integration complete."* || \
  "$integration_output" != *"No changes were pushed."* ]]
then
  echo "Integration did not report completion." >&2
  exit 1
fi

if [[ "$integration_output" == *"configured automatically"* || \
  "$integration_output" == *"Committer:"* ]]
then
  echo "Integration exposed Git's automatic identity notice." >&2
  exit 1
fi

test "$(git -C "$api_repository" rev-parse main)" = "$api_final_commit"
test "$(git -C "$web_repository" rev-parse master)" = "$web_final_commit"
test "$(git -C "$api_repository" symbolic-ref --short HEAD)" = "user-work"
test "$(git -C "$api_repository" rev-parse HEAD)" = "$api_base_commit"
test "$(git -C "$web_repository" symbolic-ref --short HEAD)" = "master"
test "$(git -C "$web_repository" rev-parse HEAD)" = "$web_final_commit"
test ! -e "$integration_hook_marker"
test -d "$coordinate_repository/.repomux/worktrees/$run_id/api"
test -d "$coordinate_repository/.repomux/worktrees/$run_id/web"

diff -u \
  <(printf '%s\n' \
    requests/PROJECT-INTEGRATE.md \
    tasks/PROJECT-INTEGRATE/api.md \
    tasks/PROJECT-INTEGRATE/assignments.txt \
    tasks/PROJECT-INTEGRATE/web.md) \
  <(git -C "$coordinate_repository" diff-tree --no-commit-id --name-only -r HEAD | sort)

test "$(git -C "$coordinate_repository" status --short notes.txt)" = "M  notes.txt"

integrated_coordinate_commit="$(git -C "$coordinate_repository" rev-parse HEAD)"
printf 'local work after integration\n' > "$web_repository/local-work.txt"
integrated_dry_run_output="$(
  HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$run_id" \
    --dry-run \
    --show-diffs
)"

if [[ "$integrated_dry_run_output" != *"Integration: integrated"* || \
  "$integrated_dry_run_output" != *"  Diff: none - already integrated"* || \
  "$integrated_dry_run_output" == *"diff --git"* ]]
then
  echo "Dry run did not report the already integrated repositories." >&2
  exit 1
fi

HOME="$test_home" \
"$command_bin/repomux" integrate \
  --project integration-test \
  --run "$run_id" \
  </dev/null \
  >/dev/null

test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$integrated_coordinate_commit"
test "$(git -C "$api_repository" rev-parse main)" = "$api_final_commit"
test "$(git -C "$web_repository" rev-parse master)" = "$web_final_commit"
test -f "$web_repository/local-work.txt"
rm -f -- "$web_repository/local-work.txt"

cancel_run_id="PROJECT-CANCEL-run-001"
"$scaffolder" PROJECT-CANCEL api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-CANCEL

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$runner" \
  "$cancel_run_id" \
  "$coordinate_repository/tasks/PROJECT-CANCEL/assignments.txt" \
  >/dev/null

cancel_coordinate_commit="$(git -C "$coordinate_repository" rev-parse HEAD)"
cancel_api_base="$(git -C "$api_repository" rev-parse user-work)"
cancel_web_base="$(git -C "$web_repository" rev-parse master)"

if printf 'no\n' | \
  HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$cancel_run_id" \
    >/dev/null 2>&1
then
  echo "Integration unexpectedly continued without confirmation." >&2
  exit 1
fi

test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$cancel_coordinate_commit"
test "$(git -C "$api_repository" rev-parse user-work)" = "$cancel_api_base"
test "$(git -C "$web_repository" rev-parse master)" = "$cancel_web_base"

printf '\nchanged after run\n' >> "$coordinate_repository/requests/PROJECT-CANCEL.md"

if HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$cancel_run_id" \
    --dry-run \
    >/dev/null 2>&1
then
  echo "Integration unexpectedly accepted changed feature requirements." >&2
  exit 1
fi

incomplete_run_id="PROJECT-INCOMPLETE-run-001"
"$scaffolder" PROJECT-INCOMPLETE api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-INCOMPLETE

if PATH="$fake_bin:$PATH" \
  FAKE_CODEX_MODE=fail_unchanged \
  "$runner" \
    --max-attempts 1 \
    "$incomplete_run_id" \
    "$coordinate_repository/tasks/PROJECT-INCOMPLETE/assignments.txt" \
    >/dev/null 2>&1
then
  echo "Repository runner unexpectedly completed the incomplete test run." >&2
  exit 1
fi

incomplete_coordinate_commit="$(git -C "$coordinate_repository" rev-parse HEAD)"
incomplete_api_base="$(git -C "$api_repository" rev-parse user-work)"
incomplete_web_base="$(git -C "$web_repository" rev-parse master)"

if HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$incomplete_run_id" \
    --dry-run \
    >/dev/null 2>&1
then
  echo "Integration unexpectedly accepted an incomplete run." >&2
  exit 1
fi

test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$incomplete_coordinate_commit"
test "$(git -C "$api_repository" rev-parse user-work)" = "$incomplete_api_base"
test "$(git -C "$web_repository" rev-parse master)" = "$incomplete_web_base"

collision_run_id="PROJECT-COLLISION-run-001"
"$scaffolder" PROJECT-COLLISION api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-COLLISION

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$runner" \
  "$collision_run_id" \
  "$coordinate_repository/tasks/PROJECT-COLLISION/assignments.txt" \
  >/dev/null

collision_coordinate_commit="$(git -C "$coordinate_repository" rev-parse HEAD)"
collision_api_base="$(git -C "$api_repository" rev-parse user-work)"
collision_web_base="$(git -C "$web_repository" rev-parse master)"
collision_file="fake-$collision_run_id.txt"
printf '%s\n' "$collision_file" >> "$api_repository/.git/info/exclude"
printf 'preserve this ignored local file\n' > "$api_repository/$collision_file"

if HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$collision_run_id" \
    --dry-run \
    >/dev/null 2>&1
then
  echo "Integration unexpectedly accepted an ignored path collision." >&2
  exit 1
fi

test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$collision_coordinate_commit"
test "$(git -C "$api_repository" rev-parse user-work)" = "$collision_api_base"
test "$(git -C "$web_repository" rev-parse master)" = "$collision_web_base"
grep -Fqx "preserve this ignored local file" "$api_repository/$collision_file"

diverged_run_id="PROJECT-DIVERGED-run-001"
"$scaffolder" PROJECT-DIVERGED api web >/dev/null
"$packet_fixture" "$coordinate_repository" PROJECT-DIVERGED

PATH="$fake_bin:$PATH" \
FAKE_CODEX_MODE=completed \
"$runner" \
  "$diverged_run_id" \
  "$coordinate_repository/tasks/PROJECT-DIVERGED/assignments.txt" \
  >/dev/null

diverged_coordinate_commit="$(git -C "$coordinate_repository" rev-parse HEAD)"
diverged_web_base="$(git -C "$web_repository" rev-parse master)"
printf 'independent base-branch change\n' > "$api_repository/independent.txt"
git -C "$api_repository" add independent.txt
git -C "$api_repository" commit -m "test: create base branch divergence" >/dev/null
diverged_api_base="$(git -C "$api_repository" rev-parse user-work)"

if HOME="$test_home" \
  "$command_bin/repomux" integrate \
    --project integration-test \
    --run "$diverged_run_id" \
    --dry-run \
    >/dev/null 2>&1
then
  echo "Integration unexpectedly accepted a diverged base branch." >&2
  exit 1
fi

test "$(git -C "$coordinate_repository" rev-parse HEAD)" = "$diverged_coordinate_commit"
test "$(git -C "$api_repository" rev-parse user-work)" = "$diverged_api_base"
test "$(git -C "$web_repository" rev-parse master)" = "$diverged_web_base"

HOME="$test_home" \
"$command_bin/repomux" cleanup \
  --project integration-test \
  --run "$run_id" \
  >/dev/null

test ! -e "$coordinate_repository/.repomux/worktrees/$run_id/api"
test ! -e "$coordinate_repository/.repomux/worktrees/$run_id/web"
test "$(git -C "$api_repository" rev-parse "repomux/$run_id/api")" = "$api_final_commit"
test "$(git -C "$web_repository" rev-parse "repomux/$run_id/web")" = "$web_final_commit"

echo "Integration tests passed."
