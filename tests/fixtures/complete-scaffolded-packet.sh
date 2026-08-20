#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: complete-scaffolded-packet.sh <coordinate-root> <feature-id>" >&2
  exit 2
fi

coordinate_root="$1"
feature_id="$2"
request_file="$coordinate_root/requests/$feature_id.md"
assignments_file="$coordinate_root/tasks/$feature_id/assignments.txt"

printf '# %s test request\n' "$feature_id" > "$request_file"

while IFS='|' read -r repository_key repository_path task_file extra_field || [[ -n "$repository_key$repository_path$task_file$extra_field" ]]; do
  if [[ -n "$extra_field" || -z "$repository_key" || -z "$repository_path" || -z "$task_file" ]]; then
    echo "Invalid test assignment: $assignments_file" >&2
    exit 1
  fi

  printf '# %s test task for %s\n' "$feature_id" "$repository_key" > "$task_file"
done < "$assignments_file"
