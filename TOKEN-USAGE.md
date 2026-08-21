# Understand token usage

RepoChord keeps repository work out of the coordinator's conversation, so the coordinator does not spend tokens reading every agent's detailed output.
When RepoChord assigns work, it starts a separate ephemeral `codex exec` session for each repository.
Each repository agent receives only its own task and repository context, not the coordinator conversation or another agent's implementation details.

While the agents work, their events, command logs, source excerpts, diffs, and intermediate output stay out of the coordinator context.
When they finish, the coordinator reads their compact result files and checks the recorded repository state.
Because the coordinator does not read the full agent output, this design can also reduce the total token use for the workflow.

RepoChord adds together the usage reported by every attempt and saves the total under `execution.usage` in the repository result.
To see the usage for one repository, run:

```bash
jq '.execution.usage' \
  /work/acme-commerce-coordinate/.repochord/results/customer-order-cancellation-a31f7c-run-k82mqp/orders-api.json
```

The result shows `input_tokens`, `cached_input_tokens`, `output_tokens`, and `reasoning_output_tokens`.
If no repository-agent attempt completed far enough to report usage, the value is `null`.
