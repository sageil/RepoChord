# RepoChord file formats

## Repository registry

Store the registry at `.repochord/repositories.json`.

Use this shape:

```json
{
  "version": 1,
  "repositories": [
    {
      "key": "api",
      "path": "/absolute/path/to/api"
    }
  ]
}
```

Repository keys must contain only letters, digits, periods, underscores, and hyphens.

Repository keys must also form valid Git branch components.

Repository paths must be absolute Git repository roots.

Repository keys and canonical repository paths must both be unique.

Each registered repository must have an initial commit.

## Feature ID

Use a supplied ticket or work-item ID when one exists.

Otherwise, `scaffold-feature.sh --title` normalizes the title to lowercase hyphenated text and appends a unique six-character suffix.

For example, `Customer order cancellation` can become `customer-order-cancellation-a31f7c`.

The generated request path and task directory contain the selected feature ID.

## Assignment file

Use one assignment per line.

Separate fields with `|`:

```text
repository-key|absolute-repository-path|absolute-task-file
```

Paths must not contain `|` or newline characters.

## Result directory

Store one result for each repository at:

```text
.repochord/results/<run-id>/<repository-key>.json
```

Store trusted run metadata at:

```text
.repochord/results/<run-id>/.manifest.json
```

Store the immutable task snapshots and derived completed task views at:

```text
.repochord/results/<run-id>/tasks/<repository-key>.source.md
.repochord/results/<run-id>/tasks/<repository-key>.completed.md
```

The manifest records the feature ID, request file, assignments file, repository task files, and the content hash of each file when the run starts.
It also records each assigned repository key and path.
The runner verifies each task hash and creates its immutable run snapshot before starting a repository agent.
The repository agent reads the run snapshot instead of the shared task file.
After a completed result passes result and Git-state validation, the report command creates a completed task view by changing unchecked Markdown task markers to checked markers.
The report records the Git object hash of each completed task view.
The completed task view is derived output, and the completed result remains the source of truth.
If a completed task view is missing or changed, a later report recreates it from the immutable snapshot.
Resume rejects a changed manifest or changed run document.
`rchord integrate` uses the manifest to select only the documents and repositories that belong to that run.

When the caller omits the run ID, `run-repository-agents.sh` derives the feature ID from the task paths and appends `run-` plus a unique six-character suffix.

For example, `customer-order-cancellation-a31f7c` can produce `customer-order-cancellation-a31f7c-run-k82mqp`.

An explicit run ID remains supported.

A new run uses a new run ID unless the caller supplies one.

A resume command continues the supplied run ID.

Automatic attempts inside one run share that run ID.

The persisted result adds trusted execution metadata after the model response is complete.

Execution metadata includes the requested model, optional reasoning effort, optional profile, total token usage, starting and observed Git state, attempt count, maximum attempts, and retry safety.

Execution metadata also records the source repository path, private repository path, base branch, base commit, RepoChord worktree path, and RepoChord worktree branch.

The top-level `commit` field is the final commit on the RepoChord worktree branch.

A `completed` result has at least one reported test, every reported test passed, no blockers, a new matching commit, and a clean worktree.

A `failed` result has an unchanged clean RepoChord worktree after all configured attempts and is safe to resume when the configured maximum permits another attempt.

A `blocked` result requires explicit user approval before retry in the same run.

A `blocked` result must contain at least one nonempty blocker.

Within one run, a repository agent can continue its uncommitted changes after a failed attempt when the RepoChord worktree branch and `HEAD` remain unchanged.

An unexpected commit or branch change stops automatic repair.

## Private repository and worktree branch

Store the private bare repository at:

```text
.repochord/repositories/<run-id>/<repository-key>.git
```

Copy the recorded base commit from the registered source repository into this private repository without creating refs or worktree metadata in the source repository.

Use this branch name:

```text
repochord/<run-id>/<repository-key>
```

Create the branch from the recorded source commit in the private repository.

Check out the branch at `.repochord/worktrees/<run-id>/<repository-key>` in the coordination repository.

Run every repository-agent attempt in that worktree.

Run repository-agent processes with read-only access to the private Git metadata.

Run repository agents with outbound network access under the RepoChord permission profile and with approval prompts disabled.

Load user configuration and an explicitly selected profile, but override the repository-agent filesystem permissions, network permissions, approval policy, and reasoning settings for each run.

Give each repository-agent run a private scratch directory through `TMPDIR`, and remove it when the runner exits.

Grant write access to that exact scratch directory, not to the complete system temporary directory.

Store each nested Codex process's SQLite runtime state in that scratch directory through `CODEX_SQLITE_HOME`.

Keep the user's normal `CODEX_HOME` active so Codex continues to load the configured auth, profiles, skills, plugins, and rules.

Permit only read-only Git subcommands inside a repository-agent process.

Create the local commit after the repository agent reports successful verification and the response passes validation.

Do not stage, commit, push, merge, pull, or rebase from a repository-agent process.

Do not remove a worktree automatically.

The explicit cleanup command removes only the worktree and preserves its private repository, branch, and commits.

Before integration confirmation, validate results, commits, branches, tests, worktrees, source base branches, and pending diffs from the private repositories without writing to the registered source repositories.

After integration confirmation, import each verified private branch into its registered source repository without creating a source feature ref, then fast-forward its recorded base branch.

Do not push during integration.
