# Try RepoMux with the Acme example

The `acme-orders-api` and `acme-storefront` directories contain a small API and web application that work together.
The `acme-commerce-coordinate` directory contains the `customer-order-cancellation` feature request and repository tasks.
Use them to try a RepoMux feature across two repositories.

The example directories are part of the RepoMux Git repository, so RepoMux cannot use them in place as separate product repositories.
Copy them to a new directory and initialize each copy as its own Git repository.

From the RepoMux repository root, run:

```bash
example_workspace=/absolute/path/to/repomux-acme-example
mkdir "$example_workspace"

cp -R examples/acme-orders-api "$example_workspace/acme-orders-api"
cp -R examples/acme-storefront "$example_workspace/acme-storefront"
cp -R examples/acme-commerce-coordinate "$example_workspace/acme-commerce-coordinate"

git -C "$example_workspace/acme-orders-api" init
git -C "$example_workspace/acme-orders-api" add .
git -C "$example_workspace/acme-orders-api" commit -m "chore: initialize orders API example"

git -C "$example_workspace/acme-storefront" init
git -C "$example_workspace/acme-storefront" add .
git -C "$example_workspace/acme-storefront" commit -m "chore: initialize storefront example"

git -C "$example_workspace/acme-commerce-coordinate" init
git -C "$example_workspace/acme-commerce-coordinate" add .
git -C "$example_workspace/acme-commerce-coordinate" commit -m "docs: add order cancellation feature specifications"
```

Create and register the coordination repository:

```bash
repomux init \
  --project acme-example \
  --coordinate "$example_workspace/acme-commerce-coordinate" \
  --repository "api=$example_workspace/acme-orders-api" \
  --repository "web=$example_workspace/acme-storefront"

git -C "$example_workspace/acme-commerce-coordinate" add .agents .repomux
git -C "$example_workspace/acme-commerce-coordinate" commit -m "chore: initialize RepoMux coordination"
```

Confirm that RepoMux can find the complete project:

```bash
repomux list --details
repomux validate --project acme-example
```

Start the coordinator from any directory:

```bash
repomux --project acme-example
```

Paste this prompt into Codex:

```text
$repomux Implement the existing customer-order-cancellation feature in the request and task files.
Replace every __EXAMPLE_WORKSPACE__ placeholder with the current example workspace path before running the repository agents.
```

The example API uses `http://localhost:3001`, and the storefront uses `http://localhost:3000`.
Run `npm test` in either product repository to verify its starting state.
