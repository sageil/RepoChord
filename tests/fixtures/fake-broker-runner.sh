#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${FAKE_BROKER_RUNNER_CAPTURE:-}" ]]; then
  echo "FAKE_BROKER_RUNNER_CAPTURE is required." >&2
  exit 2
fi

printf 'broker_execution=%s\nregistry=%s\nargument_count=%s\n' \
  "${REPOCHORD_BROKER_EXECUTION:-}" \
  "${REPOCHORD_REGISTRY_PATH:-}" \
  "$#" \
  > "$FAKE_BROKER_RUNNER_CAPTURE"
printf '%s\n' "$@" >> "$FAKE_BROKER_RUNNER_CAPTURE"
echo "broker stdout"
echo "broker stderr" >&2
exit 7
