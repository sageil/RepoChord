#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: request-repository-agent-run.sh <broker-directory> <runner-arguments>..." >&2
}

if [[ "$#" -lt 2 ]]; then
  usage
  exit 2
fi

broker_directory="$1"
shift

if [[ "$broker_directory" != /* || -L "$broker_directory" || ! -d "$broker_directory" ]]; then
  echo "RepoChord broker directory is invalid: $broker_directory" >&2
  exit 2
fi

requests_directory="$broker_directory/requests"
responses_directory="$broker_directory/responses"

if [[ -L "$requests_directory" || ! -d "$requests_directory" || \
  -L "$responses_directory" || ! -d "$responses_directory" ]]
then
  echo "RepoChord broker endpoints are unavailable: $broker_directory" >&2
  exit 2
fi

request_directory="$(mktemp -d "$requests_directory/request.XXXXXX")"
request_id="$(basename -- "$request_directory")"
request_stage="$request_directory/request.json.stage"
request_path="$request_directory/request.json"
ready_path="$request_directory/ready"
response_directory="$responses_directory/$request_id"

cleanup_request() {
  rm -rf -- "$request_directory"
}

trap cleanup_request EXIT

jq -n --args '$ARGS.positional | {version: 1, arguments: .}' -- "$@" > "$request_stage"
mv -- "$request_stage" "$request_path"
: > "$ready_path"

while [[ ! -f "$response_directory/done" ]]; do
  if [[ -f "$broker_directory/stopped" ]]; then
    echo "RepoChord broker stopped before it completed the repository run." >&2
    exit 1
  fi

  sleep 0.1
done

cat "$response_directory/stdout"
cat "$response_directory/stderr" >&2
response_status="$(cat "$response_directory/status")"

if [[ ! "$response_status" =~ ^[0-9]+$ || "$response_status" -gt 255 ]]; then
  echo "RepoChord broker returned an invalid exit status: $response_status" >&2
  exit 1
fi

exit "$response_status"
