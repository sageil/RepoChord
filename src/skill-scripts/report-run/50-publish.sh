report_path="$result_directory/report.md"

if [[ -L "$report_path" || ( -e "$report_path" && ! -f "$report_path" ) ]]; then
  fail "Complete report path is not a regular file: $report_path" 2
fi

report_stage="$(mktemp "$result_directory/.report.XXXXXX")"

# shellcheck disable=SC2329
cleanup_report_stage() {
  if [[ -n "$report_stage" && -e "$report_stage" ]]; then
    rm -f "$report_stage"
  fi
}

trap cleanup_report_stage EXIT
write_complete_report >"$report_stage"
mv "$report_stage" "$report_path"
report_stage=""

echo "RepoChord run: $overall_status"
echo "Feature: $feature_id"
echo "Run: $run_id"
echo "Pushed: no | Incomplete: $incomplete_list"

for ((index = 0; index < repository_count; index++)); do
  repository_key="${repository_keys[$index]}"
  result_path="${result_paths[$index]}"
  repository_status="${repository_statuses[$index]}"

  if [[ "$repository_status" == "missing" ]]; then
    echo "$repository_key: missing | commit unavailable | blockers result missing"
    echo "  Tokens: unavailable"
    continue
  fi

  commit="$(jq -r '.commit // "unavailable"' "$result_path")"
  integration_state="${integration_states[$index]}"
  blockers="$(inline_string_list "$result_path" '.blockers' 'none')"
  echo "$repository_key: $repository_status | commit $commit | integration $integration_state | blockers $blockers"

  if jq -e '.execution.usage == null' "$result_path" >/dev/null; then
    echo "  Tokens: unavailable"
  else
    input_tokens="$(jq -r '.execution.usage.input_tokens' "$result_path")"
    cached_input_tokens="$(jq -r '.execution.usage.cached_input_tokens' "$result_path")"
    output_tokens="$(jq -r '.execution.usage.output_tokens' "$result_path")"
    reasoning_output_tokens="$(jq -r '.execution.usage.reasoning_output_tokens' "$result_path")"
    echo "  Tokens: input $input_tokens | cached input $cached_input_tokens | output $output_tokens | reasoning output $reasoning_output_tokens"
  fi
done

echo "Complete report: $report_path"

if [[ "$overall_status" == "completed" ]]; then
  echo "Next: rchord integrate --run $run_id --dry-run"
  echo "Then: rchord integrate --run $run_id"
  exit 0
fi

exit 1
