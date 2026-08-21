#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "RepoChord release tests require Bash 5.2 or later." >&2
  exit 2
fi

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/repochord-release-test.XXXXXX")"
temporary_root="$(cd -- "$temporary_root" && pwd -P)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

mapfile -t version_lines < "$repository_directory/VERSION"
test "${#version_lines[@]}" -eq 1
repochord_version="${version_lines[0]}"
archive_name="repochord-$repochord_version.tar.gz"

"$repository_directory/scripts/package-release.sh" \
  --tag "v$repochord_version" \
  --output "$temporary_root/dist" \
  >/dev/null

test -f "$temporary_root/dist/$archive_name"
test -f "$temporary_root/dist/$archive_name.sha256"

(
  cd -- "$temporary_root/dist"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check "$archive_name.sha256" >/dev/null
  else
    shasum -a 256 --check "$archive_name.sha256" >/dev/null
  fi
)

tar -xzf "$temporary_root/dist/$archive_name" -C "$temporary_root"
package_root="$temporary_root/repochord-$repochord_version"

test -f "$package_root/LICENSE"
test -f "$package_root/README.md"
test -f "$package_root/TOKEN-USAGE.md"
test -f "$package_root/VERSION"
test -f "$package_root/assets/repochord-coordination.png"
test -f "$package_root/docs/development.md"
test -f "$package_root/docs/troubleshooting.md"
test -f "$package_root/examples/README.md"
test -x "$package_root/install.sh"
test -x "$package_root/uninstall.sh"
test -x "$package_root/payload/rchord"
test "$("$package_root/payload/rchord" --version)" = "RepoChord $repochord_version"

if "$repository_directory/scripts/package-release.sh" \
  --tag "v999.0.0" \
  --output "$temporary_root/mismatch" \
  >/dev/null 2>&1
then
  echo "Release packaging accepted a tag that does not match VERSION." >&2
  exit 1
fi
