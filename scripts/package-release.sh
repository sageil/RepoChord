#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord release packaging requires Bash 5.2 or later." >&2
  exit 2
fi

usage() {
  echo "Usage: package-release.sh --output <directory> [--tag <vX.Y.Z>]" >&2
}

output_directory=""
release_tag=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output)
      [[ "$#" -ge 2 ]] || {
        usage
        exit 2
      }
      output_directory="$2"
      shift 2
      ;;
    --tag)
      [[ "$#" -ge 2 ]] || {
        usage
        exit 2
      }
      release_tag="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$output_directory" ]]; then
  usage
  exit 2
fi

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$script_directory/.." && pwd -P)"
version_path="$repository_directory/VERSION"
mapfile -t version_lines < "$version_path"

if [[ "${#version_lines[@]}" -ne 1 || ! "${version_lines[0]}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "VERSION must contain one stable semantic version in X.Y.Z format." >&2
  exit 2
fi

repochord_version="${version_lines[0]}"
expected_tag="v$repochord_version"

if [[ -n "$release_tag" && "$release_tag" != "$expected_tag" ]]; then
  echo "Release tag $release_tag does not match VERSION $repochord_version." >&2
  exit 2
fi

if [[ "$output_directory" != /* ]]; then
  output_directory="$PWD/$output_directory"
fi

package_stage="$(mktemp -d "${TMPDIR:-/tmp}/repochord-release.XXXXXX")"

cleanup() {
  rm -rf -- "$package_stage"
}

trap cleanup EXIT

package_name="repochord-$repochord_version"
package_root="$package_stage/$package_name"
archive_name="$package_name.tar.gz"
archive_stage="$package_stage/$archive_name"
checksum_stage="$package_stage/$archive_name.sha256"

mkdir -p "$package_root" "$output_directory"
cp -- \
  "$repository_directory/LICENSE" \
  "$repository_directory/README.md" \
  "$repository_directory/TOKEN-USAGE.md" \
  "$repository_directory/VERSION" \
  "$repository_directory/install.sh" \
  "$repository_directory/uninstall.sh" \
  "$package_root/"
mkdir -p "$package_root/docs"
cp -- \
  "$repository_directory/docs/development.md" \
  "$repository_directory/docs/troubleshooting.md" \
  "$package_root/docs/"
cp -R -- "$repository_directory/assets" "$package_root/assets"
cp -R -- "$repository_directory/examples" "$package_root/examples"
cp -R -- "$repository_directory/payload" "$package_root/payload"

tar -czf "$archive_stage" -C "$package_stage" "$package_name"

if command -v sha256sum >/dev/null 2>&1; then
  archive_checksum="$(sha256sum "$archive_stage")"
elif command -v shasum >/dev/null 2>&1; then
  archive_checksum="$(shasum -a 256 "$archive_stage")"
else
  echo "A SHA-256 checksum command is required: sha256sum or shasum." >&2
  exit 2
fi

printf '%s  %s\n' "${archive_checksum%% *}" "$archive_name" > "$checksum_stage"
mv -- "$archive_stage" "$output_directory/$archive_name"
mv -- "$checksum_stage" "$output_directory/$archive_name.sha256"

printf '%s\n' "$output_directory/$archive_name"
printf '%s\n' "$output_directory/$archive_name.sha256"
