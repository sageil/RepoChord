HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  model project-model-2 \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  coordinator-reasoning-effort xhigh \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  repository-agent-reasoning-effort low \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  max-parallel 5 \
  >/dev/null

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  max-attempts 5 \
  >/dev/null

configured_max_attempts="$(
  HOME="$test_home" \
  "$rchord_command" config get \
    --project acme-commerce \
    max-attempts
)"

test "$configured_max_attempts" = "5"

(
  cd "$coordinate_repository"
  HOME="$test_home" \
  "$rchord_command" config set max-attempts 6 \
    >/dev/null

  test "$(HOME="$test_home" "$rchord_command" config get max-attempts)" = "6"
)

HOME="$test_home" \
"$rchord_command" config set \
  --project acme-commerce \
  max-attempts 5 \
  >/dev/null

HOME="$test_home" \
"$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

jq -e \
  '.projects[] |
   select(.name == "acme-commerce") |
   .maxAttempts == 5 and
   .model == "project-model-2" and
   .coordinatorReasoningEffort == "xhigh" and
   .repositoryAgentReasoningEffort == "low" and
   .maxParallel == 5' \
  "$projects_registry" \
  >/dev/null

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  max-attempts 0 \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid maximum attempt count." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  max-parallel 0 \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid concurrency limit." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  model "invalid model" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted a model containing whitespace." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" config set \
  --project acme-commerce \
  coordinator-reasoning-effort impossible \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid coordinator reasoning effort." >&2
  exit 1
fi

if HOME="$test_home" "$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository-agent-reasoning-effort impossible \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null 2>&1
then
  echo "RepoChord unexpectedly accepted an invalid repository-agent reasoning effort." >&2
  exit 1
fi

mkdir -p "$fake_bin"
cp "$test_directory/fixtures/fake-codex-start.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"
