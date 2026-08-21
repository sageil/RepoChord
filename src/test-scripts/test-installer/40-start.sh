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
