#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/repochord-broker-test.XXXXXX")"
temporary_root="$(cd -- "$temporary_root" && pwd -P)"
broker_pid=""

cleanup() {
  if [[ -n "$broker_pid" ]] && kill -0 "$broker_pid" >/dev/null 2>&1; then
    kill "$broker_pid" >/dev/null 2>&1 || true
    wait "$broker_pid" >/dev/null 2>&1 || true
  fi

  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

coordinate_root="$temporary_root/coordinate"
broker_directory="$temporary_root/broker"
assignments_file="$coordinate_root/tasks/example/assignments.txt"
outside_assignments="$temporary_root/outside-assignments.txt"
runner_script="$test_directory/fixtures/fake-broker-runner.sh"
registry_snapshot="$broker_directory/repositories.json"
runner_capture="$temporary_root/runner-capture.txt"
client_script="$repository_directory/payload/.agents/skills/repochord/scripts/request-repository-agent-run.sh"
broker_script="$repository_directory/payload/.agents/skills/repochord/scripts/repository-agent-broker.sh"

mkdir -p \
  "$coordinate_root/tasks/example" \
  "$broker_directory/requests" \
  "$broker_directory/responses"
printf 'api|/example/api|%s\n' "$coordinate_root/tasks/example/api.md" > "$assignments_file"
cp "$assignments_file" "$outside_assignments"
printf '{"version":1,"repositories":[]}\n' > "$registry_snapshot"

FAKE_BROKER_RUNNER_CAPTURE="$runner_capture" \
bash "$broker_script" \
  "$broker_directory" \
  "$coordinate_root" \
  "$runner_script" \
  "$registry_snapshot" \
  > "$temporary_root/broker.stdout" \
  2> "$temporary_root/broker.stderr" &
broker_pid="$!"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$broker_directory/ready" ]]; then
    break
  fi

  sleep 0.1
done

test -f "$broker_directory/ready"

client_status=0
bash "$client_script" "$broker_directory" test-run "$assignments_file" \
  > "$temporary_root/client.stdout" \
  2> "$temporary_root/client.stderr" || client_status="$?"

test "$client_status" -eq 7
grep -Fqx "broker stdout" "$temporary_root/client.stdout"
grep -Fqx "broker stderr" "$temporary_root/client.stderr"
grep -Fqx "broker_execution=true" "$runner_capture"
grep -Fqx "registry=$registry_snapshot" "$runner_capture"
grep -Fqx "argument_count=2" "$runner_capture"
grep -Fqx "test-run" "$runner_capture"
grep -Fqx "$assignments_file" "$runner_capture"

client_status=0
bash "$client_script" \
  "$broker_directory" \
  --resume test-run \
  --retry-blocked api \
  "$assignments_file" \
  > "$temporary_root/resume.stdout" \
  2> "$temporary_root/resume.stderr" || client_status="$?"

test "$client_status" -eq 7
grep -Fqx "argument_count=5" "$runner_capture"
grep -Fqx -- "--resume" "$runner_capture"
grep -Fqx "test-run" "$runner_capture"
grep -Fqx -- "--retry-blocked" "$runner_capture"
grep -Fqx "api" "$runner_capture"
grep -Fqx "$assignments_file" "$runner_capture"

capture_hash="$(git hash-object "$runner_capture")"
client_status=0
bash "$client_script" "$broker_directory" "$outside_assignments" \
  > "$temporary_root/rejected.stdout" \
  2> "$temporary_root/rejected.stderr" || client_status="$?"

test "$client_status" -eq 2
grep -Fqx "RepoChord broker rejected an assignments file outside the task packet." "$temporary_root/rejected.stderr"
test "$capture_hash" = "$(git hash-object "$runner_capture")"

kill "$broker_pid"
wait "$broker_pid"
broker_pid=""
test -f "$broker_directory/stopped"

echo "Broker tests passed."
