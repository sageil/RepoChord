#!/usr/bin/env bash

set -euo pipefail

guard_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
filtered_path=""
saved_ifs="$IFS"
IFS=:

for path_entry in $PATH; do
  if [[ "$path_entry" == "$guard_directory" ]]; then
    continue
  fi

  if [[ -z "$filtered_path" ]]; then
    filtered_path="$path_entry"
  else
    filtered_path="$filtered_path:$path_entry"
  fi
done

IFS="$saved_ifs"

if [[ -z "$filtered_path" ]]; then
  echo "RepoChord cannot locate the real Git command." >&2
  exit 126
fi

PATH="$filtered_path"
export PATH
real_git="$(command -v git || true)"

if [[ -z "$real_git" ]]; then
  echo "RepoChord cannot locate the real Git command." >&2
  exit 126
fi

arguments=("$@")
argument_count="${#arguments[@]}"
argument_index=0
subcommand=""

while [[ "$argument_index" -lt "$argument_count" ]]; do
  argument="${arguments[$argument_index]}"

  case "$argument" in
    --)
      argument_index=$((argument_index + 1))

      if [[ "$argument_index" -lt "$argument_count" ]]; then
        subcommand="${arguments[$argument_index]}"
      fi

      break
      ;;
    -C|-c|--config-env|--exec-path|--git-dir|--work-tree|--namespace|--super-prefix)
      argument_index=$((argument_index + 2))
      ;;
    -C*|--config-env=*|--exec-path=*|--git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*)
      argument_index=$((argument_index + 1))
      ;;
    --version)
      subcommand="version"
      break
      ;;
    -* )
      argument_index=$((argument_index + 1))
      ;;
    *)
      subcommand="$argument"
      break
      ;;
  esac
done

case "$subcommand" in
  blame|cat-file|check-attr|check-ignore|check-ref-format|describe|diff|diff-files|diff-index|diff-tree|for-each-ref|grep|log|ls-files|ls-tree|merge-base|name-rev|rev-list|rev-parse|show|show-ref|status|version)
    ;;
  "")
    echo "RepoChord repository agents must specify a read-only Git command." >&2
    exit 126
    ;;
  *)
    echo "RepoChord repository agents cannot run the Git '$subcommand' command." >&2
    echo "RepoChord creates the local commit after it validates the repository-agent result." >&2
    exit 126
    ;;
esac

exec "$real_git" "$@"
