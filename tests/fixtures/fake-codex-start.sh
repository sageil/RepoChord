#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
  echo "--cd --profile --config"
  exit 0
fi

if [[ "$#" -eq 2 && "$1" == "exec" && "$2" == "--help" ]]; then
  echo "--cd --ephemeral --json --model --profile --config --output-schema --output-last-message"
  exit 0
fi

if [[ -z "${FAKE_CODEX_START_CAPTURE:-}" ]]; then
  echo "FAKE_CODEX_START_CAPTURE is required." >&2
  exit 2
fi

printf '%s\n' "$@" > "$FAKE_CODEX_START_CAPTURE"

if [[ -n "${FAKE_REPOCHORD_ATTEMPTS_CAPTURE:-}" ]]; then
  printf '%s\n' "${REPOCHORD_MAX_ATTEMPTS:-}" > "$FAKE_REPOCHORD_ATTEMPTS_CAPTURE"
fi

if [[ -n "${FAKE_REPOCHORD_SETTINGS_CAPTURE:-}" ]]; then
  printf 'model=%s\nrepository_agent_reasoning_effort=%s\nmax_parallel=%s\nallow_dirty_source=%s\nbroker_directory=%s\ntmpdir=%s\n' \
    "${REPOCHORD_MODEL:-}" \
    "${REPOCHORD_REPOSITORY_AGENT_REASONING_EFFORT:-}" \
    "${REPOCHORD_MAX_PARALLEL:-}" \
    "${REPOCHORD_ALLOW_DIRTY_SOURCE:-false}" \
    "${REPOCHORD_BROKER_DIRECTORY:-}" \
    "${TMPDIR:-}" \
    > "$FAKE_REPOCHORD_SETTINGS_CAPTURE"
fi

if [[ -n "${FAKE_REPOCHORD_BROKER_REGISTRY_CAPTURE:-}" ]]; then
  cp "$REPOCHORD_BROKER_DIRECTORY/repositories.json" "$FAKE_REPOCHORD_BROKER_REGISTRY_CAPTURE"
fi
