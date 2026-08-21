# RepoChord troubleshooting and diagnostics

The coordinator normally runs these scripts for you.
Use them directly only for diagnosis or external automation.

## Scaffold a feature packet

Reserve a feature ID and create its assignments metadata:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repochord/scripts/scaffold-feature.sh \
  --title "Invite a friend" \
  api \
  web
```

The script prints the target request-file path followed by the assignments-file path.
It does not create placeholder specification files.

## Validate a feature packet

Write the completed request and repository task files once, then validate them:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repochord/scripts/validate-task-packet.sh \
  /work/acme-commerce-coordinate/tasks/invite-a-friend-78rduu/assignments.txt
```

## Start repository agents directly

Start the repository agents and let RepoChord generate the run ID:

```bash
bash /work/acme-commerce-coordinate/.agents/skills/repochord/scripts/run-repository-agents.sh \
  --reasoning-effort medium \
  /work/acme-commerce-coordinate/tasks/invite-a-friend-78rduu/assignments.txt
```

Pass an explicit run ID before the assignments file only when another system requires that exact ID.
