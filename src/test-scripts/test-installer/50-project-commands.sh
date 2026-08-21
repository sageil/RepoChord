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
