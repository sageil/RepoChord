#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
  echo "--cd --add-dir --sandbox --config"
  exit 0
fi

if [[ "$#" -eq 2 && "$1" == "exec" && "$2" == "--help" ]]; then
  echo "--cd --sandbox --ephemeral --json --model --profile --config --output-schema --output-last-message"
  exit 0
fi

if [[ -z "${FAKE_CODEX_START_CAPTURE:-}" ]]; then
  echo "FAKE_CODEX_START_CAPTURE is required." >&2
  exit 2
fi

printf '%s\n' "$@" > "$FAKE_CODEX_START_CAPTURE"

if [[ -n "${FAKE_REPOMUX_ATTEMPTS_CAPTURE:-}" ]]; then
  printf '%s\n' "${REPOMUX_MAX_ATTEMPTS:-}" > "$FAKE_REPOMUX_ATTEMPTS_CAPTURE"
fi

if [[ -n "${FAKE_REPOMUX_SETTINGS_CAPTURE:-}" ]]; then
  printf 'model=%s\nrepository_agent_reasoning_effort=%s\nagent_output=%s\nmax_parallel=%s\nallow_dirty_source=%s\n' \
    "${REPOMUX_MODEL:-}" \
    "${REPOMUX_REPOSITORY_AGENT_REASONING_EFFORT:-}" \
    "${REPOMUX_AGENT_OUTPUT:-}" \
    "${REPOMUX_MAX_PARALLEL:-}" \
    "${REPOMUX_ALLOW_DIRTY_SOURCE:-false}" \
    > "$FAKE_REPOMUX_SETTINGS_CAPTURE"
fi
