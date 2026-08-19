# RepoMux

RepoMux helps you build one feature across several Git repositories.

You describe the feature once to the coordinator.
It works out what each repository needs, sends each task to an isolated repository agent, and checks the results when the agents finish.

| Term | Description |
|---|---|
| Coordinator | The agent you talk to. It plans the work across repositories, sends each task to the right agent, and checks the finished results. |
| Repository agent | An agent that works on one repository in an isolated Git worktree. It makes the change, runs the tests, and reports back to the coordinator. |

![RepoMux coordinator dispatching isolated repository agents](assets/repomux-coordination.png)


## Install RepoMux

### Requirements

You need:

- Bash 3.2 or later.
- Git.
- `jq`.
- Codex CLI 0.147.0 or later.

Each product repository must be a Git repository with at least one commit.

### Default installation

Clone this repository `git clone https://github.com/sageil/repomux.git`, switch directories, then run:

```bash
./install.sh
```

Unless you change them, RepoMux installs with these settings:

| Setting | Default |
|---|---|
| AI model | `gpt-5.6-terra` |
| Coordinator reasoning effort | `medium` |
| Repository-agent reasoning effort | `high` |
| Parallel repository agents | `2` |
| Maximum attempts | `3` |
| Executable script | `~/.local/bin/repomux` |
| Shared skill | `~/.local/share/repomux/skill` |
| Project registry | `~/.config/repomux/projects.json` |

You can use `minimal`, `low`, `medium`, `high`, or `xhigh`.
The selected model must support the effort you choose.


### Custom installation options

You can choose a different model, give the coordinator and repository agents different reasoning efforts, or run more repository agents at the same time:

```bash
./install.sh \
  --default-model openrouter/anthropic/claude-sonnet-4.5 \
  --default-coordinator-reasoning-effort high \
  --default-repository-agent-reasoning-effort medium \
  --default-max-parallel 4
```

### Choose a custom installation directory

If `~/.local/bin` is not in `PATH`, the installer tells you how to add it.
You can also install the command in another directory:

```bash
./install.sh --bin-dir /absolute/command/directory
```

## Set up your first AI workflow

This walkthrough uses an API repository named `acme-orders-api` and a web repository named `acme-storefront`.
RepoMux keeps the workflow files in a separate coordination repository named `acme-commerce-coordinate`.

### 1. Initialize the project

From an existing coordination repository:

```bash
cd /work/acme-commerce-coordinate

repomux init \
  -p acme-commerce \
  -c "$PWD" \
  --model gpt-5.6-luna \
  --max-parallel 4 \
  -r "orders-api=$PWD/../acme-orders-api" \
  -r "storefront=$PWD/../acme-storefront"
```

The short options are:

- `-p` for `--project`.
- `-c` for `--coordinate`.
- `-r` for `--repository`.

If the coordination repository does not exist, let RepoMux create it:

```bash
repomux init \
  -p acme-commerce \
  -c /work/acme-commerce-coordinate \
  --create-coordinate \
  -r orders-api=/work/acme-orders-api \
  -r storefront=/work/acme-storefront
```

`--create-coordinate` accepts an absent directory or an existing empty directory. Initializing a nonempty directory that is not already a Git repository will fail.

Initialization creates the following structure:

```text
acme-commerce-coordinate/
├── .agents/skills/repomux/
├── .repomux/
│   ├── repositories.json
│   ├── results/.gitignore
│   └── worktrees/.gitignore
├── requests/
└── tasks/
```

### 2. Start the AI coordinator

From the coordination repository, run `repomux`.
If you are somewhere else, use the project name when you start it:

```bash
repomux
```

```bash
repomux --project acme-commerce
```

### 3. Request a new feature

Once the coordinator starts, describe the feature and name the repositories that need changes:

```text
$repomux Add customer order cancellation to orders-api and storefront so customers can cancel an eligible order from the order-details page and see the updated status without reloading.
```

Before it creates the feature files, the coordinator shows you the proposed requirements and waits for your approval.

## What RepoMux creates for a feature

After you approve the proposal, RepoMux turns the request into a feature ID, such as `customer-order-cancellation-a31f7c`.
The coordinator then writes one request file and one task for each repository:

```text
requests/customer-order-cancellation-a31f7c.md
tasks/customer-order-cancellation-a31f7c/orders-api.md
tasks/customer-order-cancellation-a31f7c/storefront.md
tasks/customer-order-cancellation-a31f7c/assignments.txt
```

The request file describes the feature as a whole.
Each repository task explains what that repository must change and how its agent must test the result.
The assignments file connects those tasks to the registered repositories.

When implementation starts, RepoMux creates a separate run ID, such as `customer-order-cancellation-a31f7c-run-k82mqp`.
It records the current state of each product repository and gives each repository agent its own branch and worktree:

```text
Branch:   repomux/<run-id>/<repository-key>
Worktree: <coordination-repository>/.repomux/worktrees/<run-id>/<repository-key>
Result:   <coordination-repository>/.repomux/results/<run-id>/<repository-key>.json
```

## Review and integrate the finished feature

When every repository agent has finished and the checks pass, RepoMux reports the run ID.
Run a dry run first to see what RepoMux will change:

```bash
repomux integrate \
  --project acme-commerce \
  --run customer-order-cancellation-a31f7c-run-k82mqp \
  --dry-run
```

If the plan looks correct, run the integration command without `--dry-run`:

```bash
repomux integrate \
  --project acme-commerce \
  --run customer-order-cancellation-a31f7c-run-k82mqp
```

RepoMux asks for confirmation, commits the workflow documents, and fast-forwards each product branch to its completed feature commit.
It keeps the feature branches and worktrees in place and never pushes changes.

## Use an existing requirements file

Start the coordinator, then name the existing feature ID and file in your prompt:

```text
$repomux Implement COMMERCE-2197 in the orders-api and storefront repositories using the requirements in incoming/COMMERCE-2197.md.
```

RepoMux uses the feature ID `COMMERCE-2197` and creates the repository tasks from the existing requirements in `incoming/COMMERCE-2197.md`.

## Start a coordinator session

Select a project and the writable repositories. You can pass extra Codex options after `--`:

```bash
repomux \
  --project acme-commerce \
  --repository orders-api \
  --repository storefront \
  -- \
  --profile acme-team
```

List or validate registered projects:

```bash
repomux list
repomux validate --project acme-commerce
```

## Configure the coordinator and repository agents

Most projects can use the installation defaults.
If one project needs different settings, save them when you initialize it:

```bash
repomux init \
    --project acme-commerce \
    --coordinate /work/acme-commerce-coordinate \
    --model openrouter/anthropic/claude-sonnet-4.5 \
    --coordinator-reasoning-effort high \
    --repository-agent-reasoning-effort medium \
    --max-parallel 4 \
    --repository orders-api=/work/acme-orders-api \
    --repository storefront=/work/acme-storefront
```

If you run `repomux init` again, RepoMux keeps every saved setting that you do not specify.

Change project values later:

```bash
repomux config set --project acme-commerce model gpt-5.6-terra
repomux config set --project acme-commerce coordinator-reasoning-effort high
repomux config set --project acme-commerce repository-agent-reasoning-effort medium
repomux config set --project acme-commerce max-parallel 4
repomux config set --project acme-commerce max-attempts 5
```

Read the effective project values:

```bash
repomux config get --project acme-commerce model
repomux config get --project acme-commerce coordinator-reasoning-effort
repomux config get --project acme-commerce repository-agent-reasoning-effort
repomux config get --project acme-commerce max-parallel
repomux config get --project acme-commerce max-attempts
```

For a one-time change, pass the settings when you start the coordinator:

```bash
repomux \
    --project acme-commerce \
    --model gpt-5.6-terra \
    --coordinator-reasoning-effort high \
    --repository-agent-reasoning-effort medium \
    --max-parallel 2 \
    --max-attempts 5
```

Settings passed at startup apply only to that session and override the saved project settings.
If the project does not have a saved value, RepoMux uses the installation default.

## Resume an incomplete run

If an attempt fails but the repository is still safe to continue, RepoMux tries again in the same worktree and gives the next attempt the previous result.
If the run uses all available attempts, resume it with the same run ID:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repomux/scripts/run-repository-agents.sh \
  --resume customer-order-cancellation-a31f7c-run-k82mqp \
  /work/acme-commerce-coordinate/tasks/customer-order-cancellation-a31f7c/assignments.txt
```

RepoMux skips repositories that already finished.
A blocked repository is different: RepoMux waits for your approval because it found a problem that it must not change automatically.
Retry one blocked repository with:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repomux/scripts/run-repository-agents.sh \
  --resume customer-order-cancellation-a31f7c-run-k82mqp \
  --retry-blocked orders-api \
  /work/acme-commerce-coordinate/tasks/customer-order-cancellation-a31f7c/assignments.txt
```

RepoMux preserves failed and blocked worktrees for review.

## Start another feature before integration

A new feature gets a new feature ID, run ID, RepoMux branch, and worktree for each affected repository to avoid impacting existing features.
The new worktree starts from the current `HEAD` of the normal product repository checkout.
If feature B depends on feature A, integrate feature A before you start feature B. RepoMux does not automatically include changes from an unintegrated feature in a new worktree.

## Clean up worktrees

RepoMux keeps completed, failed, and blocked worktrees until you request cleanup.

After review or integration, remove selected worktrees:

```bash
repomux cleanup \
  --project acme-commerce \
  --run customer-order-cancellation-a31f7c-run-k82mqp \
  --repository orders-api \
  --repository storefront
```

Cleanup preserves the RepoMux branches and commits. It will refuse to remove a dirty worktree.
Use `--force` only when you have reviewed the uncommitted work and explicitly want to remove/abandon it:

```bash
repomux cleanup \
  --project acme-commerce \
  --run customer-order-cancellation-a31f7c-run-k82mqp \
  --repository orders-api \
  --force
```

## Troubleshooting & diagnostics

The coordinator normally runs these scripts for you. Use them directly only for diagnosis or external automation.

Scaffold a new feature to create its requirements and related tasks:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repomux/scripts/scaffold-feature.sh \
  --title "Customer order cancellation" \
  orders-api \
  storefront
```

The script prints the request-file path followed by the assignments-file path.
Complete the generated request and repository task files before starting repository agents.

Start repository agents and generate the run ID:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repomux/scripts/run-repository-agents.sh \
  --reasoning-effort medium \
  /work/acme-commerce-coordinate/tasks/customer-order-cancellation-a31f7c/assignments.txt
```

Pass an explicit run ID before the assignments file only when another system requires that exact ID.

## Workflow Screen Captures

These captures show one complete feature workflow in order.

### 1. Submit the feature request

Start RepoMux for the registered project and describe the cross-repository feature to the coordinator.

![Submit a downloadable order receipt feature to the RepoMux coordinator](assets/workflow-screen-captures/workflow-2026-08-18-213931.png)

### 2. Inspect the repositories and define the requirements

The coordinator verifies both repositories, inspects the existing API and web paths, and defines the shared receipt requirements.

![RepoMux inspecting the API and web repositories and defining the shared requirements](assets/workflow-screen-captures/workflow-2026-08-18-214037.png)

### 3. Prepare the repository tasks

The coordinator writes bounded API and web tasks with acceptance criteria, test commands, and commit messages.

![RepoMux preparing the API and web repository task files](assets/workflow-screen-captures/workflow-2026-08-18-214108.png)

### 4. Approve isolated implementation

RepoMux requests elevated execution for the runner because it must create local Git worktrees and feature commits outside the coordinator sandbox.
The repository agents then run in parallel inside their isolated worktrees.

![Approval of the RepoMux runner followed by parallel repository-agent execution](assets/workflow-screen-captures/workflow-2026-08-18-214227.png)

### 5. Validate the repository results

After both repository agents finish, the coordinator checks their structured results, worktree branches, commits, clean state, and required tests.

![RepoMux validating completed API and web repository results](assets/workflow-screen-captures/workflow-2026-08-18-214320.png)

### 6. Review the completion report

The completion report shows each repository status, test result, commit, worktree, branch, attempt count, and token usage.
It also provides the dry-run and integration commands.
See [Understand token usage](TOKEN-USAGE.md) for details about token isolation and repository-agent usage data.

![RepoMux completion report for the API and web repositories](assets/workflow-screen-captures/workflow-2026-08-18-214407.png)

### 7. Review the integration preflight

The integration command verifies the feature documents and repository commits, then shows the planned local fast-forwards before it asks for confirmation.

![RepoMux integration preflight showing documents, commits, tests, and change summaries](assets/workflow-screen-captures/workflow-2026-08-18-214437.png)

### 8. Confirm local integration

After confirmation, RepoMux commits the feature documents and fast-forwards the product repository branches.
It preserves the feature worktrees and does not push changes.

![Completed RepoMux integration with preserved worktrees and no pushed changes](assets/workflow-screen-captures/workflow-2026-08-18-214445.png)
