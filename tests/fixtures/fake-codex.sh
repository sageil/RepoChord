#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" != "exec" ]]; then
  echo "Unsupported fake Codex command." >&2
  exit 2
fi

shift

if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' \
    '--cd' \
    '--sandbox' \
    '--ephemeral' \
    '--json' \
    '--model' \
    '--profile' \
    '--config' \
    '--output-schema' \
    '--output-last-message'
  exit 0
fi

repository_path=""
result_path=""
model=""
profile=""
reasoning_effort=""
network_access_disabled=false
prompt=""
ephemeral=false
json_output=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --cd)
      repository_path="$2"
      shift 2
      ;;
    --output-last-message)
      result_path="$2"
      shift 2
      ;;
    --model)
      model="$2"
      shift 2
      ;;
    --profile)
      profile="$2"
      shift 2
      ;;
    --config)
      config_value="$2"

      if [[ "$config_value" == model_reasoning_effort=* ]]; then
        reasoning_effort="${config_value#model_reasoning_effort=\"}"
        reasoning_effort="${reasoning_effort%\"}"
      elif [[ "$config_value" == "sandbox_workspace_write.network_access=false" ]]; then
        network_access_disabled=true
      fi

      shift 2
      ;;
    --sandbox|--color|--output-schema)
      shift 2
      ;;
    --ephemeral)
      ephemeral=true
      shift
      ;;
    --json)
      json_output=true
      shift
      ;;
    *)
      prompt="$1"
      shift
      ;;
  esac
done

run_id=""
repository_key=""
attempt_number=1
maximum_attempts=1

while IFS= read -r prompt_line; do
  case "$prompt_line" in
    "Run ID: "*)
      run_id="${prompt_line#Run ID: }"
      ;;
    "Repository key: "*)
      repository_key="${prompt_line#Repository key: }"
      ;;
    "Attempt: "*)
      attempt_text="${prompt_line#Attempt: }"
      attempt_number="${attempt_text%% of *}"
      maximum_attempts="${attempt_text##* of }"
      ;;
  esac
done <<< "$prompt"

if [[ -z "$repository_path" || -z "$result_path" || -z "$run_id" || -z "$repository_key" ]]; then
  echo "The fake Codex command received incomplete arguments." >&2
  exit 2
fi

if [[ -n "${FAKE_CODEX_CAPTURE_DIRECTORY:-}" ]]; then
  mkdir -p "$FAKE_CODEX_CAPTURE_DIRECTORY"
  jq -n \
    --arg model "$model" \
    --arg profile "$profile" \
    --arg reasoning_effort "$reasoning_effort" \
    --arg bash_version "$BASH_VERSION" \
    --argjson ephemeral "$ephemeral" \
    --argjson json_output "$json_output" \
    --argjson network_access_disabled "$network_access_disabled" \
    --argjson attempt "$attempt_number" \
    --argjson max_attempts "$maximum_attempts" \
    '{
      model: $model,
      profile: (if $profile == "" then null else $profile end),
      reasoning_effort: (if $reasoning_effort == "" then null else $reasoning_effort end),
      bash_version: $bash_version,
      ephemeral: $ephemeral,
      json_output: $json_output,
      network_access_disabled: $network_access_disabled,
      attempt: $attempt,
      max_attempts: $max_attempts
    }' > "$FAKE_CODEX_CAPTURE_DIRECTORY/$repository_key.json"

  cp \
    "$FAKE_CODEX_CAPTURE_DIRECTORY/$repository_key.json" \
    "$FAKE_CODEX_CAPTURE_DIRECTORY/$repository_key-attempt-$attempt_number.json"
fi

emit_usage() {
  jq -nc '{
    type: "turn.completed",
    usage: {
      input_tokens: 100,
      cached_input_tokens: 40,
      output_tokens: 20,
      reasoning_output_tokens: 5
    }
  }'
}

create_change() {
  change_file="fake-$run_id.txt"
  printf 'fake repository-agent change\n' > "$repository_path/$change_file"
}

write_failed_dirty_result() {
  change_file="fake-$run_id.txt"
  printf 'incomplete repository-agent change from attempt %s\n' "$attempt_number" > "$repository_path/$change_file"

  jq -n \
    --arg run_id "$run_id" \
    --arg repository "$repository_key" \
    '{
      run_id: $run_id,
      repository: $repository,
      status: "failed",
      summary: "One required test failed.",
      commit: null,
      commit_message: null,
      tests: [
        {command: "test one", status: "passed", summary: "Passed."},
        {command: "test two", status: "passed", summary: "Passed."},
        {command: "test three", status: "passed", summary: "Passed."},
        {command: "test four", status: "passed", summary: "Passed."},
        {command: "test five", status: "failed", summary: "Failed."}
      ],
      risks: [],
      blockers: []
    }' > "$result_path"
}

mode="${FAKE_CODEX_MODE:-completed}"

case "$mode" in
  completed)
    create_change
    jq -n \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      --arg commit_message "test: fake repository agent $run_id" \
      '{
        run_id: $run_id,
        repository: $repository,
        status: "completed",
        summary: "The fake repository agent completed the task.",
        commit: null,
        commit_message: $commit_message,
        tests: [{command: "fake test", status: "passed", summary: "Passed."}],
        risks: [],
        blockers: []
      }' > "$result_path"
    emit_usage
    ;;
  completed_failed_test)
    create_change
    jq -n \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      --arg commit_message "test: fake repository agent $run_id" \
      '{
        run_id: $run_id,
        repository: $repository,
        status: "completed",
        summary: "The fake repository agent incorrectly reported completion.",
        commit: null,
        commit_message: $commit_message,
        tests: [{command: "fake test", status: "failed", summary: "Failed."}],
        risks: [],
        blockers: ["Verification failed."]
      }' > "$result_path"
    emit_usage
    ;;
  blocked_without_blocker)
    jq -n \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      '{
        run_id: $run_id,
        repository: $repository,
        status: "blocked",
        summary: "",
        commit: null,
        commit_message: null,
        tests: [],
        risks: [],
        blockers: []
      }' > "$result_path"
    emit_usage
    ;;
  fail_after_commit)
    create_change
    "$FAKE_ABSOLUTE_GIT" -C "$repository_path" add "fake-$run_id.txt"
    "$FAKE_ABSOLUTE_GIT" -C "$repository_path" commit -m "test: unauthorized repository-agent commit $run_id" >/dev/null
    jq -nc '{type: "turn.failed", error: {message: "Intentional failure."}}'
    exit 1
    ;;
  fail_unchanged)
    jq -n \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      '{
        run_id: $run_id,
        repository: $repository,
        status: "failed",
        summary: "The fake repository agent failed without changes.",
        commit: null,
        commit_message: null,
        tests: [{command: "fake test", status: "not_run", summary: "Not run."}],
        risks: [],
        blockers: ["Intentional failure."]
      }' > "$result_path"
    emit_usage
    ;;
  guarded_git_operations)
    set +e
    git -C "$repository_path" status --short >/dev/null 2>&1
    status_exit_code=$?
    git -C "$repository_path" add -A >/dev/null 2>&1
    add_exit_code=$?
    git -C "$repository_path" merge --ff-only HEAD >/dev/null 2>&1
    merge_exit_code=$?
    git -C "$repository_path" push >/dev/null 2>&1
    push_exit_code=$?
    git -C "$repository_path" -c alias.publish=push publish >/dev/null 2>&1
    alias_exit_code=$?
    set -e

    if [[ "$status_exit_code" -ne 0 ||
      "$add_exit_code" -ne 126 ||
      "$merge_exit_code" -ne 126 ||
      "$push_exit_code" -ne 126 ||
      "$alias_exit_code" -ne 126 ]]
    then
      echo "RepoMux did not enforce read-only Git access." >&2
      exit 1
    fi

    jq -n \
      --arg run_id "$run_id" \
      --arg repository "$repository_key" \
      '{
        run_id: $run_id,
        repository: $repository,
        status: "failed",
        summary: "RepoMux allowed read-only Git and blocked Git changes.",
        commit: null,
        commit_message: null,
        tests: [{command: "guarded Git operations", status: "not_run", summary: "Read-only access enforced."}],
        risks: [],
        blockers: ["Git integration commands are disabled for repository agents."]
      }' > "$result_path"
    emit_usage
    ;;
  fail_dirty_then_complete)
    if [[ "$attempt_number" -eq 1 ]]; then
      write_failed_dirty_result
    else
      create_change
      jq -n \
        --arg run_id "$run_id" \
        --arg repository "$repository_key" \
        --arg commit_message "test: fake repository agent $run_id" \
        '{
          run_id: $run_id,
          repository: $repository,
          status: "completed",
          summary: "The repair attempt completed the task.",
          commit: null,
          commit_message: $commit_message,
          tests: [{command: "fake test", status: "passed", summary: "Passed after repair."}],
          risks: [],
          blockers: []
        }' > "$result_path"
    fi
    emit_usage
    ;;
  always_fail_dirty)
    write_failed_dirty_result
    emit_usage
    ;;
  *)
    echo "Unsupported fake Codex mode: $mode" >&2
    exit 2
    ;;
esac
