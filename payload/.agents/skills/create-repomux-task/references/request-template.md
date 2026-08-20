# RepoMux feature request template

Use this template for `requests/<feature-id>.md`.
Replace every placeholder.

```markdown
# <feature-id>

## User outcome

<State the user-visible or operational result and why it is needed.>

## Repositories

- `<repository-key>`: `<absolute-repository-path>` - <repository outcome>

## Shared contract

<Define the exact API, event, schema, state, or file contract shared by repositories.>

## State transitions and invariants

<Define applicable normal states, failure states, restart behavior, and invariants.>

## Authorization

<Define applicable identities, permissions, and data-handling rules.>

## Completion rules

<Define what must be true across all participating repositories.>
```
