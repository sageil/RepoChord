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

## Approve the proposal

After completing the request and repository task files, present one concise proposal that includes the feature ID, each repository outcome, the shared contract, required verification, and commit messages.

Ask once: `Approve this proposal?`

Do not start repository agents before the user approves the current proposal.

The proposal approval authorizes RepoMux to create the described worktrees and feature commits and to start the repository agents for that proposal.

Do not ask for separate approval to start repository agents.

Do not ask again when the user has already approved the current proposal in the conversation.

Request new approval only when the proposal changes materially after approval.

## Run repository agents

By default, require no uncommitted changes in affected source repositories.

The runner can continue with a dirty source repository when `--allow-dirty-source` is passed or `REPOMUX_ALLOW_DIRTY_SOURCE` is `true`.

Treat `REPOMUX_ALLOW_DIRTY_SOURCE=true` as approval supplied when the user started the coordinator session.

Otherwise, use `--allow-dirty-source` only after the user explicitly approves excluding the uncommitted changes from the repository-agent worktree.

The option leaves the normal checkout unchanged and creates the repository-agent worktree from the committed `HEAD`.

Never stash, reset, restore, clean, or copy the uncommitted source changes automatically.

Run without an explicit run ID to generate one from the feature ID:

```bash
bash .agents/skills/repomux/scripts/run-repository-agents.sh \
  <absolute-assignments-file>
```

After proposal approval, execute this command without another conversational approval request.
Set `sandbox_permissions` to `require_escalated` because RepoMux creates isolated local Git worktrees and feature commits in the registered repositories.
Do not run the command inside the coordinator sandbox first.
Do not request `danger-full-access` for the coordinator.

Pass `<run-id>` before `<absolute-assignments-file>` only when the user or an external system requires a specific run ID.

Read the generated run ID from the result-directory path and include it in the final report.

Use `--profile <profile>` only when repository agents require a named Codex configuration profile.

The repository-agent launcher reads the effective model, reasoning effort, output mode, and maximum concurrency from the RepoMux session or stored project configuration.

An explicit `--model`, `--reasoning-effort`, `--agent-output`, or `--max-parallel` value on `run-repository-agents.sh` takes precedence over the session and stored values.

When no configured value exists, the model fallback is `gpt-5.6-terra`, the repository-agent reasoning-effort fallback is `high`, the output-mode fallback is `progress`, and the maximum concurrency fallback is two repository agents.

The repository-agent script reads the stored project maximum when `REPOMUX_MAX_ATTEMPTS` is absent.

An explicit `--max-attempts` value takes precedence over the environment and stored project value.

Use `--max-attempts <count>` on `run-repository-agents.sh` only when the current run needs an explicit script-level override.

`run-repository-agents.sh` starts one isolated `codex exec` process for each repository, applies the concurrency limit, and waits for every repository result.

The runner streams compact repository-prefixed activity while each repository agent works.

Do not start separate monitoring commands while the runner is active.

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

## Accept the runner result

`run-repository-agents.sh` owns repository execution, result validation, Git-state validation, report generation, and the final exit status.

Do not repeat its work with separate `jq`, `git`, result-file, worktree, or report commands.

Do not read repository-agent logs unless the runner fails and the user requests failure diagnosis.

A zero exit means every required repository completed and passed the runner's validation.

A nonzero exit means the run is incomplete or invalid.

Treat a blocked result as requiring explicit user approval before retry in the same run.

## Present the integration commands

The generated report includes these exact next actions when every required repository is complete:

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

`run-repository-agents.sh` runs the reporter as its final workflow action.

Do not run `repomux report` again after the runner finishes.

The runner prints a short receipt and saves the complete deterministic report at the path in that receipt.

Read the complete report file from the exact path printed by the command.

Use the complete contents of that file as the final response.

Do not replace the report with a link, a path, a short receipt, or a sentence that says the report is available elsewhere.

Do not recreate or summarize the report from the result files.

Before sending the final response, confirm that it includes the overall status, every repository, every full commit, every token-usage value, all risks and blockers, every integration state, and the integration commands when the run completed.

The receipt includes the overall status, repository commits, token usage, blockers, integration state, and the complete report path.

The complete report includes the detailed repository result, execution, and worktree information.

A completed report ends with the exact dry-run and integration commands for that run ID.

Do not push, merge, pull, rebase, delete branches, or remove worktrees unless the user explicitly requests that exact operation.

Repository-agent scripts never perform push, merge, pull, or rebase operations, even when a repository task requests one.
