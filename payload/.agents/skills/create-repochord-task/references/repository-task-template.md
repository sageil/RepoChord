# RepoChord repository task template

Use this template for `tasks/<feature-id>/<repository-key>.md`.
Replace every placeholder.

```markdown
# <feature-id> task for <repository-key>

## Repository

Repository key: `<repository-key>`

Repository path: `<absolute-repository-path>`

## Mission

<State the bounded repository outcome and why this repository owns it.>

## Dependencies

- <State another repository outcome or external prerequisite, or state `None`.>

## Context to read first

- `<confirmed-path>` - <why this context is needed>

## Environment

- Required services: <services or `None`>
- Required tools: <tools confirmed by the repository>

## File scope

- `<confirmed-existing-path>` - modified
- `<planned-new-path>` - new

## Shared contract

<Copy the exact relevant contract from the feature request.>

## Steps

### Step 1: <outcome>

- [ ] <Specific, verifiable result>
- [ ] Run targeted verification: `<confirmed command>`

## Failure and restart behavior

<Define the repository behavior after failure and retry, or state why it is not applicable.>

## Authorization and data handling

<Define applicable permissions and protected data behavior, or state why it is not applicable.>

## Acceptance criteria

- [ ] <Observable repository result>

## Required verification

- `<confirmed command>` - <behavior exercised by this command>

## Documentation requirements

### Must update

- `<path>` - <required documentation change>

### Check if affected

- `<path>` - <condition that requires an update>

Use `None` when no documentation is affected.

## Completion criteria

- [ ] All acceptance criteria are satisfied.
- [ ] All required verification passes.
- [ ] Required documentation is updated.

## Commit

RepoChord creates the commit only after all acceptance criteria and required verification pass.

Commit message: `<type>(<optional-scope>): <description>`

## Do not

- Expand the requested scope.
- Stage, commit, push, merge, pull, or rebase.
```
