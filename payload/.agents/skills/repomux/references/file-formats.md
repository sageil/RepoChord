# RepoMux file formats

## Repository registry

Store the registry at `.repomux/repositories.json`.

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
.repomux/results/<run-id>/<repository-key>.json
```

Store trusted run metadata at:

```text
.repomux/results/<run-id>/.manifest.json
```

The manifest records the feature ID, request file, assignments file, repository task files, and the content hash of each file when the run starts.
It also records each assigned repository key and path.
Resume rejects a changed manifest or changed run document.
`repomux integrate` uses the manifest to select only the documents and repositories that belong to that run.

When the caller omits the run ID, `run-repository-agents.sh` derives the feature ID from the task paths and appends `run-` plus a unique six-character suffix.

For example, `customer-order-cancellation-a31f7c` can produce `customer-order-cancellation-a31f7c-run-k82mqp`.

An explicit run ID remains supported.

A new run uses a new run ID unless the caller supplies one.

A resume command continues the supplied run ID.

Automatic attempts inside one run share that run ID.

The persisted result adds trusted execution metadata after the model response is complete.

Execution metadata includes the requested model, optional reasoning effort, optional profile, total token usage, starting and observed Git state, attempt count, maximum attempts, and retry safety.

Execution metadata also records the source repository path, base branch, base commit, RepoMux worktree path, and RepoMux worktree branch.

The top-level `commit` field is the final commit on the RepoMux worktree branch.

A `completed` result has at least one reported test, every reported test passed, no blockers, a new matching commit, and a clean worktree.

A `failed` result has an unchanged clean RepoMux worktree after all configured attempts and is safe to resume when the configured maximum permits another attempt.

A `blocked` result requires explicit user approval before retry in the same run.

A `blocked` result must contain at least one nonempty blocker.

Within one run, a repository agent can continue its uncommitted changes after a failed attempt when the RepoMux worktree branch and `HEAD` remain unchanged.

An unexpected commit or branch change stops automatic repair.

## Worktree branch

Use this branch name:

```text
repomux/<run-id>/<repository-key>
```

Create the branch from the recorded source commit.

Check out the branch at `.repomux/worktrees/<run-id>/<repository-key>` in the coordination repository.

Run every repository-agent attempt in that worktree.

Run repository-agent processes without write access to the linked Git metadata.

Network access follows the active Codex configuration and profile.

Permit only read-only Git subcommands inside a repository-agent process.

Create the local commit after the repository agent reports successful verification and the response passes validation.

Do not stage, commit, push, merge, pull, or rebase from a repository-agent process.

Do not remove a worktree automatically.

The explicit cleanup command removes only the worktree and preserves its branch.
