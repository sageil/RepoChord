---
name: repomux
description: Coordinate implementation across two or more separate Git repositories with one coordinator, isolated repository agents, automatic repair attempts, schema-validated results, and consolidated completion reporting. Use for features, fixes, migrations, or releases that require coordinated changes in multiple repositories. Do not use for work contained in one repository or when a shared contract is still materially undefined.
---

# Coordinate repositories with RepoMux

Act as the coordinator from the coordination repository.

Do not edit product repository source files directly.

## Establish the contract

1. Read the feature request and `.repomux/repositories.json`.
2. Inspect enough of each affected repository to verify its execution path and focused test commands.
3. Define shared contracts, state transitions, invariants, authorization, failure behavior, restart behavior, acceptance criteria, and required tests before implementation.
4. Stop and request a decision when a material contract or requirement is unknown.
5. Present the complete contract to the user and ask the user to approve it.
6. Stop and wait for explicit user approval.
7. Do not run `scaffold-feature.sh`, create or edit feature files, or start repository agents until the user approves the contract.

Contract approval does not replace the later approval required to start repository agents.

## Resolve the feature ID

Use a feature ID supplied by the user or an existing requirements file.

When no feature ID exists, create a short feature title and use the scaffold's `--title` form.

Do not ask the user to invent an ID only for this workflow.

Read the generated feature ID from the returned request-file path and include it in the final report.

## Create feature files

Use `scripts/scaffold-feature.sh` when the feature files do not exist:

```bash
bash .agents/skills/repomux/scripts/scaffold-feature.sh \
  <feature-id> \
  <repository-key>...
```

When the request has no feature ID, run:

```bash
bash .agents/skills/repomux/scripts/scaffold-feature.sh \
  --title "<short feature title>" \
  <repository-key>...
```

Complete the generated request and repository task files before repository agents start.

Keep one bounded task per affected repository.

Include the repository path, task, shared contract, acceptance criteria, commit message, and required tests in each task file.

## Run repository agents

Require no uncommitted changes in affected source repositories.

Run without an explicit run ID to generate one from the feature ID:

```bash
bash .agents/skills/repomux/scripts/run-repository-agents.sh \
  <absolute-assignments-file>
```

Execute this command with an explicit approval request on the first attempt.
Set `sandbox_permissions` to `require_escalated` and explain that RepoMux will create isolated local Git worktrees and feature commits in the registered repositories, then run the repository agents.
Do not run the command inside the coordinator sandbox first.
Do not request `danger-full-access` for the coordinator.

Pass `<run-id>` before `<absolute-assignments-file>` only when the user or an external system requires a specific run ID.

Read the generated run ID from the result-directory path and include it in the final report.

Use `--profile <profile>` only when repository agents require a named Codex configuration profile.

The repository-agent launcher reads the effective model, reasoning effort, and maximum concurrency from the RepoMux session or stored project configuration.

An explicit `--model`, `--reasoning-effort`, or `--max-parallel` value on `run-repository-agents.sh` takes precedence over the session and stored values.

When no configured value exists, the model fallback is `gpt-5.6-terra`, the repository-agent reasoning-effort fallback is `high`, and the maximum concurrency fallback is two repository agents.

The repository-agent script reads the stored project maximum when `REPOMUX_MAX_ATTEMPTS` is absent.

An explicit `--max-attempts` value takes precedence over the environment and stored project value.

Use `--max-attempts <count>` on `run-repository-agents.sh` only when the current run needs an explicit script-level override.

`run-repository-agents.sh` starts one isolated `codex exec` process for each repository, applies the concurrency limit, and waits for every repository result.

For each repository, RepoMux records the source branch and commit, creates `repomux/<run-id>/<repository-key>`, and checks out that branch in `.repomux/worktrees/<run-id>/<repository-key>`.

All repository-agent attempts run in that dedicated worktree.

Repository-agent commands use the network policy from the active Codex configuration and profile.

Repository agents cannot write the linked Git metadata.

The repository-agent Git command permits only read-only Git subcommands.

Never ask a repository agent to stage, commit, push, merge, pull, or rebase.

After a repository agent reports successful verification, `run-repository-agent.sh` validates the response and creates the local commit.

Each repository agent can make several attempts within the same run.

A failed or invalid attempt supplies its result to the next attempt when the RepoMux worktree `HEAD` and branch remain unchanged.

The next attempt can continue uncommitted changes from the previous attempt.

An unexpected commit, branch change, explicit blocker, or exhausted attempt limit stops automatic repair for that repository.

A nonzero `run-repository-agents.sh` exit means one or more repositories are incomplete.

Resume an existing run with:

```bash
bash .agents/skills/repomux/scripts/run-repository-agents.sh \
  --resume <run-id> \
  <absolute-assignments-file>
```

The script verifies and skips every completed repository.

The script resumes failed repositories when the configured maximum allows another attempt.

Retry a blocked repository only after the user approves it, then pass `--retry-blocked <repository-key>` with `--resume`.

Do not reset, restore, delete, or rewrite incomplete repository-agent changes automatically.

## Verify results

Read each JSON result under `.repomux/results/<run-id>/`.

Do not read repository-agent logs unless the user explicitly requests failure diagnosis.

Do not copy source files, diffs, command output, or exploration notes into the coordinator response.

For each completed result, verify:

- The result commit matches the RepoMux worktree `HEAD`.
- The result commit is on `repomux/<run-id>/<repository-key>`.
- The result records the source repository path, base branch, base commit, worktree path, and worktree branch.
- The worktree is clean.
- At least one test is reported.
- Every reported test passed.
- The reported test commands cover the required verification in the repository task.
- No blockers remain.

Report overall completion only when every required repository result passes these checks.

Treat `failed` with `execution.retry_safe` set to `true` as unchanged and clean after all configured attempts.

Treat `blocked` as requiring explicit user approval before retry in the same run.

A blocked result must include at least one nonempty blocker.

## Present the integration commands

When every required repository is complete, include these exact next actions with the generated run ID:

```bash
repomux integrate --run <run-id> --dry-run
repomux integrate --run <run-id>
```

The dry run is read-only and requires no confirmation.
The integration command validates the run again and asks the user once before it commits feature documents or fast-forwards product base branches.
Do not run the integration command for the user unless the user explicitly requests that operation.
The integration command never pushes changes and preserves RepoMux feature worktrees.

## Clean up worktrees

Preserve every completed, failed, or blocked worktree until the user explicitly requests cleanup.

Use this command only after the user requests cleanup:

```bash
repomux cleanup \
  --run <run-id> \
  --repository <repository-key>
```

Use `--force` only when the user explicitly requests removal of a dirty worktree.

Cleanup removes the worktree and preserves its RepoMux branch and commits.

## Report

Report each repository with:

- Feature ID and run ID.
- Status.
- Summary.
- Commit.
- Tests.
- Risks.
- Blockers.
- Model and reasoning effort.
- Attempt count and maximum attempts.
- Token usage.
- Retry safety.
- Source repository path and base branch.
- Base commit and final commit.
- RepoMux worktree path and branch.

Also report the overall status, incomplete repositories, and whether any work was pushed or merged.

For a completed run, end the report with the exact dry-run and integration commands for that run ID.

Do not push, merge, pull, rebase, delete branches, or remove worktrees unless the user explicitly requests that exact operation.

Repository-agent scripts never perform push, merge, pull, or rebase operations, even when a repository task requests one.
