# RepoChord development and releases

Run the commands in this guide from the RepoChord repository root.

## Generated Bash files

Large Bash programs are assembled from smaller source files under `src/`.
Do not edit generated Bash files directly.

Generate all checked-in Bash artifacts after a source change:

```bash
./scripts/build-installer.sh
./scripts/build-rchord.sh
./scripts/build-skill-scripts.sh
./scripts/build-test-scripts.sh
```

## Verification

Run the project checks after you generate the Bash artifacts:

```bash
bash tests/run.sh
```

This command checks generated-file consistency, behavior, Bash syntax, ShellCheck results, skill structure, release packaging, and the Git diff.
A successful run ends with `All RepoChord tests passed.`

## Versioning

RepoChord uses [Semantic Versioning](https://semver.org/).

- Increase the patch number for a backward-compatible fix, such as `0.1.0` to `0.1.1`.
- Increase the minor number for a backward-compatible feature, such as `0.1.0` to `0.2.0`.
- Increase the major number for an incompatible change after the public interface becomes stable.

The [`VERSION`](../VERSION) file is the single source of truth and contains one stable version in `X.Y.Z` format.
After you change it, run `./scripts/build-rchord.sh` so the generated command reports the same version.
Merge and test the version change before you create its Git tag.

## Manual GitHub releases

Prepare version `0.1.0` by creating and pushing its matching tag:

```bash
git tag -a v0.1.0 -m "RepoChord 0.1.0"
git push origin v0.1.0
```

Pushing the tag does not start a release.

To publish the release:

1. Open the **Release** workflow in GitHub Actions.
2. Select **Run workflow**.
3. Enter the existing version tag, such as `v0.1.0`.
4. Start the workflow.

The workflow checks that the tag matches `VERSION`, runs the project checks, creates an installable archive and SHA-256 checksum, and publishes a GitHub release with generated notes.
If any check fails, the workflow does not publish the release.
If an interrupted run left a draft release, a new run replaces the draft assets and continues.
If the release is already public, a new run does not change it.
Do not move or reuse a published version tag.

RepoChord is available under the [MIT License](../LICENSE).
