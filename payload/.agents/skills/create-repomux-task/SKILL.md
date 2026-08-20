---
name: create-repomux-task
description: Create structured RepoMux feature requests and repository task files for autonomous repository-agent execution. Use from the RepoMux coordination workflow after participating repositories are selected and before the proposal is presented.
---

# Create RepoMux tasks

Create one feature request and one bounded task for each participating repository.

The existing `repomux` skill owns user interaction, approval, and execution.
This skill only prepares and validates the task packet.

## Prerequisites

Read `.repomux/repositories.json` first.
Stop if it does not exist or if fewer than two registered repositories participate in the requested outcome.

## Task creation workflow

### Step 1: Determine the participating repositories

Match the requested outcome to the responsibilities and current code in the registered repositories.
Do not include a repository only because it is registered.

### Step 2: Inspect the current implementation

For each participating repository:

1. Read its applicable `AGENTS.md` files.
2. Identify the current execution path for the requested behavior.
3. Identify the source files, tests, configuration, and documentation that the task is expected to affect.
4. Identify focused verification commands from repository scripts, configuration, or existing tests.
5. Record only paths and commands confirmed by the repository.

### Step 3: Resolve and scaffold the feature

Use an explicit feature ID when one exists.
Otherwise, let `scaffold-feature.sh --title` create the ID.

Use the existing feature packet when the feature ID already exists.
The scaffolder creates only the task directory and `assignments.txt`.
It returns the request path and assignments path without creating request or repository task files.

### Step 4: Write the feature request

Use [references/request-template.md](references/request-template.md).

Define the requested outcome and the exact contract shared by the participating repositories.
Record normal state, failure state, restart behavior, invariants, authorization, and completion rules when they apply to the requested behavior.
Write the completed request directly to the request path returned by the scaffolder.

### Step 5: Write each repository task

Use [references/repository-task-template.md](references/repository-task-template.md).

Read each repository task path from `assignments.txt` and write the completed task directly to that path.
Do not create placeholder request or task files.

Each task must be executable by a fresh repository agent that has the feature request, its repository task, and its assigned repository.
Do not rely on the conversation that created the task.

Write outcome-level steps.
Name confirmed files or directories when the current code makes them knowable.
If a file will be new, mark it as new instead of claiming that it already exists.

Use targeted verification that exercises the assigned outcome.
Do not require a full test suite or a new test file unless the requested change needs it.

### Step 6: Validate the task packet

Run:

```bash
bash .agents/skills/repomux/scripts/validate-task-packet.sh \
  <absolute-assignments-file>
```

If validation reports structural defects, correct the task packet and run the same command again.
Do not present the proposal until validation passes.
If a reported defect cannot be corrected without a material product decision, return that decision to the `repomux` skill.

### Step 7: Return control to RepoMux

Return the feature ID, each repository outcome, shared contract, verification commands, and commit messages to the `repomux` skill.
Do not ask for approval and do not start repository agents.

## Context discipline

List only context that the repository agent needs to begin the task.

- Put confirmed source, test, configuration, and documentation paths in `Context to read first`.
- Put expected change locations in `File scope`.
- Do not list broad documentation sets or unrelated repository areas.
- Do not list a path as existing unless inspection confirmed it.

## Step discipline

Steps must describe distinct, verifiable outcomes.
They must not prescribe every import, local variable, or assertion before the repository agent reads the source.

Use concrete deliverables when they are confirmed by inspection.
For example, prefer `Update the existing order update handler to persist delivery instructions` to `Add backend support`.

If the requested behavior might already exist, direct the repository agent to verify the behavior and close only the confirmed gap.
Do not create work only to force a code change.

## Cross-repository contract

Copy the exact relevant shared contract into every repository task.
Do not paraphrase the contract differently for different repositories.

Order repository outcomes so that producers and consumers agree on:

- Names and data shapes.
- Required and optional values.
- Validation and error behavior.
- Authorization.
- State changes and failure behavior.

RepoMux repository agents can run in parallel.
Do not write a task that requires another repository agent's uncommitted worktree output.

## Definition of ready

Before returning control to RepoMux, confirm:

- The feature request states the user-visible or operational outcome.
- Every participating repository has one task and one assignment.
- Every task has a mission that states what changes and why.
- Dependencies and external prerequisites are explicit.
- Context paths and file scope come from repository inspection.
- Steps describe bounded outcomes in execution order.
- The shared contract is identical where repositories interact.
- Failure, restart, authorization, and data-handling requirements are present when applicable.
- Acceptance criteria are observable.
- Verification commands are confirmed by the repository and exercise the stated outcome.
- Documentation impact is explicit.
- The commit message is a Conventional Commit.
- Guardrails prevent scope expansion and Git operations owned by RepoMux.
- `validate-task-packet.sh` passes.

## Prevent empty completion

Tasks must state the observable gap and expected result clearly enough that an agent cannot complete the task by checking boxes without evidence.

Do not require a code diff when the repository already satisfies the requested outcome.
In that case, require verification evidence and report the task as blocked by an incorrect premise instead of inventing a change.

## Git ownership

RepoMux creates one repository commit after the repository agent completes the task and passes verification.
Repository tasks must not instruct agents to stage, commit, push, merge, pull, or rebase.
