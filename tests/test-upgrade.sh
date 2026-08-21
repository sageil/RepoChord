#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/repochord-upgrade-test.XXXXXX")"
temporary_root="$(cd -- "$temporary_root" && pwd -P)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_repository() {
  local repository_path="$1"
  local repository_name="$2"

  mkdir -p "$repository_path"
  git -C "$repository_path" init -q
  git -C "$repository_path" config user.name "Upgrade Test"
  git -C "$repository_path" config user.email "upgrade-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null
}

test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
fake_codex_bin="$temporary_root/fake-codex-bin"
first_product="$temporary_root/first-product"
second_product="$temporary_root/second-product"
first_coordinate="$temporary_root/first-coordinate"
second_coordinate="$temporary_root/second-coordinate"
mkdir -p "$test_home" "$fake_codex_bin"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOCHORD_CONFIG_HOME REPOCHORD_DATA_HOME

initialize_repository "$first_product" first-product
initialize_repository "$second_product" second-product

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

rchord_command="$command_bin/rchord"
source_skill="$test_home/.local/share/repochord/skill"
source_task_skill="$test_home/.local/share/repochord/task-skill"
projects_registry="$test_home/.config/repochord/projects.json"

HOME="$test_home" "$rchord_command" init \
  --project first \
  --coordinate "$first_coordinate" \
  --create-coordinate \
  --repository "product=$first_product" \
  >/dev/null

HOME="$test_home" "$rchord_command" init \
  --project second \
  --coordinate "$second_coordinate" \
  --create-coordinate \
  --repository "product=$second_product" \
  >/dev/null

printf 'keep request\n' > "$first_coordinate/requests/keep.md"
printf 'keep task\n' > "$first_coordinate/tasks/keep.md"
printf 'keep result\n' > "$first_coordinate/.repochord/results/keep.json"
printf 'keep worktree metadata\n' > "$first_coordinate/.repochord/worktrees/keep.txt"
rm -rf -- "$first_coordinate/.repochord/repositories"

projects_before="$(git hash-object "$projects_registry")"
first_registry_before="$(git hash-object "$first_coordinate/.repochord/repositories.json")"
second_registry_before="$(git hash-object "$second_coordinate/.repochord/repositories.json")"
first_head_before="$(git -C "$first_product" rev-parse HEAD)"
second_head_before="$(git -C "$second_product" rev-parse HEAD)"

rm -f -- "$first_coordinate/.agents/skills/repochord/scripts/report-run.sh"
printf 'obsolete\n' > "$first_coordinate/.agents/skills/repochord/obsolete.txt"
printf '\nstale project copy\n' >> "$second_coordinate/.agents/skills/repochord/SKILL.md"
cp "$test_directory/fixtures/fake-codex-start.sh" "$fake_codex_bin/codex"
chmod +x "$fake_codex_bin/codex"

if HOME="$test_home" PATH="$fake_codex_bin:$PATH" \
  "$rchord_command" validate --project first >"$temporary_root/validate.out" 2>&1
then
  echo "RepoChord unexpectedly validated a stale project skill." >&2
  exit 1
fi

grep -Fq "Run rchord upgrade." "$temporary_root/validate.out"

upgrade_output="$(HOME="$test_home" "$rchord_command" upgrade)"

grep -Fqx "Upgraded RepoChord project: first" <<< "$upgrade_output"
grep -Fqx "Upgraded RepoChord project: second" <<< "$upgrade_output"
grep -Fqx "RepoChord upgrade complete: 2 registered projects are current." <<< "$upgrade_output"
diff -qr "$source_skill" "$first_coordinate/.agents/skills/repochord" >/dev/null
diff -qr "$source_skill" "$second_coordinate/.agents/skills/repochord" >/dev/null
diff -qr "$source_task_skill" "$first_coordinate/.agents/skills/create-repochord-task" >/dev/null
diff -qr "$source_task_skill" "$second_coordinate/.agents/skills/create-repochord-task" >/dev/null
test ! -e "$first_coordinate/.agents/skills/repochord/obsolete.txt"
grep -Fqx "keep request" "$first_coordinate/requests/keep.md"
grep -Fqx "keep task" "$first_coordinate/tasks/keep.md"
grep -Fqx "keep result" "$first_coordinate/.repochord/results/keep.json"
grep -Fqx "keep worktree metadata" "$first_coordinate/.repochord/worktrees/keep.txt"
test -f "$first_coordinate/.repochord/repositories/.gitignore"
test -f "$second_coordinate/.repochord/repositories/.gitignore"
test "$projects_before" = "$(git hash-object "$projects_registry")"
test "$first_registry_before" = "$(git hash-object "$first_coordinate/.repochord/repositories.json")"
test "$second_registry_before" = "$(git hash-object "$second_coordinate/.repochord/repositories.json")"
test "$first_head_before" = "$(git -C "$first_product" rev-parse HEAD)"
test "$second_head_before" = "$(git -C "$second_product" rev-parse HEAD)"
if compgen -G "$first_coordinate/.agents/skills/.repochord-upgrade.*" >/dev/null; then
  echo "RepoChord left an upgrade workspace in the first project." >&2
  exit 1
fi

if compgen -G "$second_coordinate/.agents/skills/.repochord-upgrade.*" >/dev/null; then
  echo "RepoChord left an upgrade workspace in the second project." >&2
  exit 1
fi

second_upgrade_output="$(HOME="$test_home" "$rchord_command" upgrade)"
grep -Fqx "RepoChord project is already current: first" <<< "$second_upgrade_output"
grep -Fqx "RepoChord project is already current: second" <<< "$second_upgrade_output"
grep -Fqx "RepoChord upgrade complete: 2 registered projects are current." <<< "$second_upgrade_output"

mv "$second_coordinate/.agents/skills/repochord" "$temporary_root/missing-project-skill"
missing_skill_output="$(HOME="$test_home" "$rchord_command" upgrade)"
grep -Fqx "RepoChord project is already current: first" <<< "$missing_skill_output"
grep -Fqx "Upgraded RepoChord project: second" <<< "$missing_skill_output"
diff -qr "$source_skill" "$second_coordinate/.agents/skills/repochord" >/dev/null
diff -qr "$source_task_skill" "$second_coordinate/.agents/skills/create-repochord-task" >/dev/null

printf '\nrollback test\n' >> "$second_coordinate/.agents/skills/repochord/SKILL.md"
printf '\nrollback task skill test\n' >> "$second_coordinate/.agents/skills/create-repochord-task/SKILL.md"
second_stale_hash="$(git hash-object "$second_coordinate/.agents/skills/repochord/SKILL.md")"
second_task_stale_hash="$(git hash-object "$second_coordinate/.agents/skills/create-repochord-task/SKILL.md")"
fake_bin="$temporary_root/fake-bin"
mkdir "$fake_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "$2" == */replacement-repochord && "$3" == */.agents/skills/repochord ]]; then' \
  '  /bin/mv "$@"' \
  '  /bin/rm -f -- "$3/scripts/report-run.sh"' \
  '  exit 0' \
  'fi' \
  'exec /bin/mv "$@"' \
  > "$fake_bin/mv"
chmod +x "$fake_bin/mv"

if HOME="$test_home" PATH="$fake_bin:$PATH" "$rchord_command" upgrade >"$temporary_root/rollback.out" 2>&1; then
  echo "RepoChord upgrade unexpectedly accepted an invalid installed replacement." >&2
  exit 1
fi

grep -Fqx "RepoChord project is already current: first" "$temporary_root/rollback.out"
grep -Fq "RepoChord could not upgrade 1 of 2 registered projects." "$temporary_root/rollback.out"
test "$second_stale_hash" = "$(git hash-object "$second_coordinate/.agents/skills/repochord/SKILL.md")"
test "$second_task_stale_hash" = "$(git hash-object "$second_coordinate/.agents/skills/create-repochord-task/SKILL.md")"

if compgen -G "$second_coordinate/.agents/skills/.repochord-upgrade.*" >/dev/null; then
  echo "RepoChord left an upgrade workspace after rollback." >&2
  exit 1
fi

HOME="$test_home" "$rchord_command" upgrade >/dev/null

if HOME="$test_home" "$rchord_command" upgrade --project first >/dev/null 2>&1; then
  echo "RepoChord upgrade unexpectedly accepted --project." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" upgrade --coordinate "$first_coordinate" >/dev/null 2>&1; then
  echo "RepoChord upgrade unexpectedly accepted --coordinate." >&2
  exit 1
fi

printf '\nfirst remains stale after failed preflight\n' >> "$first_coordinate/.agents/skills/repochord/SKILL.md"
first_stale_hash="$(git hash-object "$first_coordinate/.agents/skills/repochord/SKILL.md")"
cp "$projects_registry" "$temporary_root/projects.valid.json"
jq '.projects |= map(if .name == "second" then .coordinate = "/missing/repochord-upgrade-test" else . end)' \
  "$projects_registry" > "$temporary_root/projects.invalid-target.json"
mv "$temporary_root/projects.invalid-target.json" "$projects_registry"

if HOME="$test_home" "$rchord_command" upgrade >/dev/null 2>&1; then
  echo "RepoChord upgrade unexpectedly accepted a missing registered coordination repository." >&2
  exit 1
fi

test "$first_stale_hash" = "$(git hash-object "$first_coordinate/.agents/skills/repochord/SKILL.md")"
mv "$temporary_root/projects.valid.json" "$projects_registry"

jq '.projects = []' "$projects_registry" > "$temporary_root/projects.empty.json"
mv "$temporary_root/projects.empty.json" "$projects_registry"
test "$(HOME="$test_home" "$rchord_command" upgrade)" = "No registered RepoChord projects to upgrade."

HOME="$test_home" "$rchord_command" init \
  --project first \
  --coordinate "$first_coordinate" \
  --repository "product=$first_product" \
  >/dev/null

diff -qr "$source_skill" "$first_coordinate/.agents/skills/repochord" >/dev/null
diff -qr "$source_task_skill" "$first_coordinate/.agents/skills/create-repochord-task" >/dev/null
test "$(jq -r '.projects | length' "$projects_registry")" = "1"
test "$(jq -r '.projects[0].name' "$projects_registry")" = "first"

echo "Upgrade tests passed."
