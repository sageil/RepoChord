#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repomux-report-test.XXXXXX)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

initialize_product_repository() {
  local repository_path="$1"
  local repository_name="$2"

  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Report Test"
  git -C "$repository_path" config user.email "report-test@example.com"
  printf '# %s\n' "$repository_name" > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize $repository_name" >/dev/null
  git -C "$repository_path" branch -M main
}

run_report_expect_status() {
  local expected_status="$1"
  local output_path="$2"
  local actual_status

  set +e
  HOME="$test_home" \
  "$repomux_command" report \
    --project report-test \
    --run "$run_id" \
    >"$output_path" \
    2>&1
  actual_status="$?"
  set -e

  if [[ "$actual_status" -ne "$expected_status" ]]; then
    echo "Report returned $actual_status instead of $expected_status." >&2
    cat "$output_path" >&2
    exit 1
  fi
}

api_repository="$temporary_root/api"
web_repository="$temporary_root/web"
coordinate_repository="$temporary_root/coordinate"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
fake_bin="$temporary_root/fake-bin"
run_id="REPORT-123-run-abc123"

initialize_product_repository "$api_repository" api
initialize_product_repository "$web_repository" web
mkdir -p "$test_home" "$fake_bin"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOMUX_CONFIG_HOME REPOMUX_DATA_HOME

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

repomux_command="$command_bin/repomux"

HOME="$test_home" \
"$repomux_command" init \
  --project report-test \
  --coordinate "$coordinate_repository" \
  --create-coordinate \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

cp "$test_directory/fixtures/fake-codex.sh" "$fake_bin/codex"
chmod +x "$fake_bin/codex"
export FAKE_ABSOLUTE_GIT
FAKE_ABSOLUTE_GIT="$(command -v git)"

scaffolder="$coordinate_repository/.agents/skills/repomux/scripts/scaffold-feature.sh"
runner="$coordinate_repository/.agents/skills/repomux/scripts/run-repository-agents.sh"
assignments_file="$coordinate_repository/tasks/REPORT-123/assignments.txt"

"$scaffolder" REPORT-123 api web >/dev/null

runner_output="$(
  PATH="$fake_bin:$PATH" \
  FAKE_CODEX_MODE=completed \
  "$runner" \
    --max-parallel 2 \
    "$run_id" \
    "$assignments_file"
)"

report_output="$temporary_root/report.txt"
run_report_expect_status 0 "$report_output"

runner_report="RepoMux run report${runner_output#*RepoMux run report}"

if [[ "$runner_report" != "$(cat "$report_output")" ]]; then
  echo "Runner output did not contain the deterministic report." >&2
  exit 1
fi

grep -Fqx "Overall status: completed" "$report_output"
grep -Fqx "Incomplete repositories: none" "$report_output"
grep -Fqx "Pushed by RepoMux: no" "$report_output"
grep -Fqx "Integrated repositories: none" "$report_output"
grep -Fqx "Repository: api" "$report_output"
grep -Fqx "Repository: web" "$report_output"
grep -Fqx "    Input: 100" "$report_output"
grep -Fqx "    Cached input: 40" "$report_output"
grep -Fqx "    Output: 20" "$report_output"
grep -Fqx "    Reasoning output: 5" "$report_output"
grep -Fqx "  Retry safe: no" "$report_output"
grep -Fqx "  Source repository: $api_repository" "$report_output"
grep -Fqx "  Worktree present: yes" "$report_output"
grep -Fqx "  Integration: pending" "$report_output"
grep -Fqx "  repomux integrate --run $run_id --dry-run" "$report_output"
grep -Fqx "  repomux integrate --run $run_id" "$report_output"

api_final_commit="$(jq -r '.commit' "$coordinate_repository/.repomux/results/$run_id/api.json")"
git -C "$api_repository" merge --ff-only "$api_final_commit" >/dev/null
run_report_expect_status 0 "$report_output"
grep -Fqx "Integrated repositories: api" "$report_output"
grep -A40 -F "Repository: api" "$report_output" | grep -Fqx "  Integration: integrated"

api_result="$coordinate_repository/.repomux/results/$run_id/api.json"
api_result_backup="$temporary_root/api-result.json"
cp "$api_result" "$api_result_backup"

jq '.execution.usage = null' "$api_result_backup" > "$api_result"
run_report_expect_status 0 "$report_output"
grep -Fqx "  Token usage: unavailable" "$report_output"

jq '.execution.usage.input_tokens = -1' "$api_result_backup" > "$api_result"
run_report_expect_status 2 "$report_output"
grep -Fqx "Repository result is invalid: $api_result" "$report_output"

jq '
  .status = "failed" |
  .summary = "The repository agent did not complete the task." |
  .commit = null |
  .execution.observed_head = .execution.base_commit |
  .execution.head_changed = false |
  .execution.retry_safe = true
' "$api_result_backup" > "$api_result"
run_report_expect_status 1 "$report_output"
grep -Fqx "Overall status: incomplete" "$report_output"
grep -Fqx "Incomplete repositories: api" "$report_output"
grep -A1 -F "Repository: api" "$report_output" | grep -Fqx "  Status: failed"
grep -Fqx "  Retry safe: yes" "$report_output"

jq '
  .status = "blocked" |
  .summary = "The repository agent needs a decision." |
  .commit = null |
  .blockers = ["Approval is required."] |
  .execution.observed_head = .execution.base_commit |
  .execution.head_changed = false |
  .execution.retry_safe = false
' "$api_result_backup" > "$api_result"
run_report_expect_status 1 "$report_output"
grep -A1 -F "Repository: api" "$report_output" | grep -Fqx "  Status: blocked"
grep -Fqx "  - Approval is required." "$report_output"

mv "$api_result" "$temporary_root/missing-api-result.json"
run_report_expect_status 1 "$report_output"
grep -A1 -F "Repository: api" "$report_output" | grep -Fqx "  Status: missing"
grep -Fqx "  Result: missing" "$report_output"
mv "$temporary_root/missing-api-result.json" "$api_result"

printf '{}\n' > "$coordinate_repository/.repomux/results/$run_id/unexpected.json"
run_report_expect_status 2 "$report_output"
grep -Fqx \
  "Run result has no matching manifest repository: $coordinate_repository/.repomux/results/$run_id/unexpected.json" \
  "$report_output"

if HOME="$test_home" "$repomux_command" report --project report-test --run '../bad' >/dev/null 2>&1; then
  echo "Report unexpectedly accepted an invalid run ID." >&2
  exit 1
fi

echo "Report tests passed."
