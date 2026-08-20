---
name: repomux
description: Coordinate one feature, fix, migration, or release across two or more separate Git repositories with isolated repository agents and one consolidated result. Use when at least two repositories registered with RepoMux will participate in the requested work. Do not use for work contained in one repository.
---

# Coordinate repositories with RepoMux

Act as the coordinator from the coordination repository.

RepoMux owns product-repository changes, repository-agent execution, local feature commits, result validation, and report generation.

Use this workflow only when the requested outcome requires execution in at least two repositories registered in `.repomux/repositories.json`.

## Exact-output invariant

This invariant takes precedence over all other response-formatting instructions in this skill.

The deterministic RepoMux complete report is authoritative.

Once a successful run produces a `Complete report:` path, RepoMux's coordination work is finished.

From that point forward, the coordinator acts only as a passthrough for that file.

The coordinator MUST NOT exercise editorial judgment over the complete report.

It MUST NOT summarize, shorten, restructure, deduplicate, selectively quote, normalize, improve, or omit any report content.

For a successful run:

`final assistant response = complete contents of the Complete report file`

No other assistant-authored content is permitted in that response.

## Prepare the proposal

1. Read the feature request and `.repomux/repositories.json`.
2. Read and apply `../create-repomux-task/SKILL.md` to inspect the participating repositories, create the feature packet, and validate it.
3. Do not present the proposal until `scripts/validate-task-packet.sh` passes for the current task packet.

Write every repository commit message as a Conventional Commit using `<type>: <description>` or `<type>(<scope>): <description>`.

Use `feat` for new behavior, `fix` for corrections, and the most accurate conventional type for other work.

Use a scope only when it adds useful context.

Do not create a second feature ID for work that already has one.

When no feature ID exists, create the files from a short title:

```bash
bash .agents/skills/repomux/scripts/scaffold-feature.sh \
  --title "<short feature title>" \
  <repository-key>...
```

Otherwise, use the existing feature ID:

```bash
bash .agents/skills/repomux/scripts/scaffold-feature.sh \
  <feature-id> \
  <repository-key>...
```

Stop and request a decision only when a material requirement remains unknown.

## Get one approval

Present one concise proposal with the feature ID, each repository outcome, the cross-repository contract, verification commands, and commit messages.

Ask once: `Approve this proposal?`

Approval authorizes RepoMux to create the described worktrees and local feature commits and to start the repository agents.

Do not ask again unless the proposal changes materially.

A material change affects the repository set, observable behavior, cross-repository contract, authorization, data handling, acceptance criteria, or approved commit scope.

Equivalent implementation or verification details do not require new approval unless they change risk or scope.

Once a runner starts, do not change its request, assignments, or repository task files and then resume that run.

If any of those files must change, preserve the existing run and start a new run with the same feature ID and a new generated run ID.

Obtain new proposal approval only when the change is material.

The new run starts from the registered source-repository commits and does not inherit changes from the earlier run's worktrees.

## Run the repository agents

After approval, run:

```bash
bash .agents/skills/repomux/scripts/run-repository-agents.sh \
  <absolute-assignments-file>
```

Run this command with `sandbox_permissions` set to `require_escalated` because it creates local Git worktrees and commits in the registered repositories.

Do not run it in the coordinator sandbox first, and do not request `danger-full-access`.

Let RepoMux generate the run ID unless the user or an external system requires a specific one.

The runner uses the active RepoMux project and session configuration.

Do not edit product repository files directly or ask repository agents to stage, commit, push, merge, pull, or rebase.

### Dirty source repositories

The runner normally requires a clean source repository.

`REPOMUX_ALLOW_DIRTY_SOURCE=true` authorizes the runner to use the committed `HEAD` while leaving uncommitted source changes untouched.

Otherwise, use `--allow-dirty-source` only after the user approves excluding those uncommitted changes from the repository-agent worktree.

Never stash, reset, restore, clean, or copy those changes automatically.

### Incomplete runs

A nonzero runner exit means the run is incomplete or invalid.

Do not repeat the runner's result, Git-state, worktree, or report checks with separate commands.

Read repository-agent logs only when the runner fails and the user requests diagnosis.

Resume an incomplete run with:

```bash
bash .agents/skills/repomux/scripts/run-repository-agents.sh \
  --resume <run-id> \
  <absolute-assignments-file>
```

Retry a blocked repository only after the user approves the retry, then add `--retry-blocked <repository-key>`.

Preserve incomplete repository-agent changes.

## Final response

The runner saves the complete report at the path printed after `Complete report:`.

When the runner succeeds:

1. Read the file at the exact `Complete report:` path.
2. Apply the exact-output invariant.
3. Return the complete file from its first character through its final character.

If a response-length or platform limit prevents the complete report from fitting in one response, do not silently truncate or summarize it.

State that the complete report exceeds the available output limit and preserve the report as a file for the user.

If the runner succeeds without a complete-report path or the report cannot be read, treat the run as invalid and report the failure instead of reconstructing the result.

## Later operations

Do not integrate, push, or clean up as part of the feature run.

Run `repomux integrate` or `repomux cleanup` only when the user explicitly requests that operation.

Integration never pushes, and cleanup preserves the RepoMux branch and commits.
