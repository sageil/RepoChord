#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repomux-task-packet-test.XXXXXX)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_repository() {
  local repository_path="$1"
  local repository_name="$2"

  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Task Packet Test"
  git -C "$repository_path" config user.email "task-packet-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null
}

write_task() {
  local task_path="$1"
  local repository_key="$2"
  local repository_path="$3"
  local commit_scope="$4"

  cat > "$task_path" <<'EOF'
# FEATURE-1 task for @KEY@

## Repository

Repository key: `@KEY@`

Repository path: `@PATH@`

## Mission

Implement the assigned repository outcome so both repositories expose the same behavior.

## Dependencies

- None.

## Context to read first

- `README.md` - Repository entry point.

## Environment

- Required services: None.
- Required tools: Bash.

## File scope

- `README.md` - modified.

## Shared contract

Both repositories use the same enabled state.

## Steps

### Step 1: Implement the outcome

- [ ] Update the repository behavior.
- [ ] Run targeted verification: `bash -n test.sh`.

## Failure and restart behavior

A failed update preserves the previous enabled state and a retry repeats the update.

## Authorization and data handling

No authorization or protected data is involved.

## Acceptance criteria

- [ ] The repository exposes the enabled state.

## Required verification

- `bash -n test.sh` - Verifies the repository script syntax.

## Documentation requirements

### Must update

- `README.md` - Document the enabled state.

### Check if affected

- None.

## Completion criteria

- [ ] All acceptance criteria are satisfied.
- [ ] All required verification passes.
- [ ] Required documentation is updated.

## Commit

RepoMux creates the commit only after all acceptance criteria and required verification pass.

Commit message: `feat(@SCOPE@): expose enabled state`

## Do not

- Expand the requested scope.
- Stage, commit, push, merge, pull, or rebase.
EOF

  sed -i.bak \
    -e "s|@KEY@|$repository_key|g" \
    -e "s|@PATH@|$repository_path|g" \
    -e "s|@SCOPE@|$commit_scope|g" \
    "$task_path"
  rm -f -- "$task_path.bak"
}

api_repository="$temporary_root/api"
web_repository="$temporary_root/web"
coordinate_repository="$temporary_root/control"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"

initialize_repository "$api_repository" api
initialize_repository "$web_repository" web
mkdir -p "$test_home"

HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
"$command_bin/repomux" init \
  --project task-packet-test \
  --coordinate "$coordinate_repository" \
  --create-coordinate \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

scaffolder="$coordinate_repository/.agents/skills/repomux/scripts/scaffold-feature.sh"
validator="$coordinate_repository/.agents/skills/repomux/scripts/validate-task-packet.sh"

"$scaffolder" FEATURE-1 api web >/dev/null

request_file="$coordinate_repository/requests/FEATURE-1.md"
assignments_file="$coordinate_repository/tasks/FEATURE-1/assignments.txt"
api_task="$coordinate_repository/tasks/FEATURE-1/api.md"
web_task="$coordinate_repository/tasks/FEATURE-1/web.md"

cat > "$request_file" <<EOF
# FEATURE-1

## User outcome

Users see one enabled state across the API and web repositories.

## Repositories

- \`api\`: \`$api_repository\`
- \`web\`: \`$web_repository\`

## Shared contract

Both repositories use the same enabled state.

## State transitions and invariants

The state changes from disabled to enabled and remains unchanged after failure.

## Authorization

No authorization or protected data is involved.

## Completion rules

Both repositories expose the enabled state and pass focused verification.
EOF

write_task "$api_task" api "$api_repository" api
write_task "$web_task" web "$web_repository" web

"$validator" "$assignments_file" >/dev/null

cp "$api_task" "$temporary_root/api-task.valid.md"
sed -i.bak 's/^## Mission$/## Mission removed/' "$api_task"
rm -f -- "$api_task.bak"

if "$validator" "$assignments_file" >/dev/null 2>&1; then
  echo "Task packet validator accepted a missing required section." >&2
  exit 1
fi

cp "$temporary_root/api-task.valid.md" "$api_task"
printf '\n<Add unfinished value.>\n' >> "$api_task"

if "$validator" "$assignments_file" >/dev/null 2>&1; then
  echo "Task packet validator accepted an unfinished placeholder." >&2
  exit 1
fi

cp "$temporary_root/api-task.valid.md" "$api_task"
sed -i.bak 's/^Commit message: `feat(api):/Commit message: `not conventional/' "$api_task"
rm -f -- "$api_task.bak"

if "$validator" "$assignments_file" >/dev/null 2>&1; then
  echo "Task packet validator accepted an invalid commit message." >&2
  exit 1
fi

echo "Task packet tests passed."
