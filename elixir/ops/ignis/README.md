# Ignis Symphony deployment

This directory contains Ignis-specific deployment assets for the `symphony-01` worker.

## PR publishing hook

`scripts/publish-pr.sh` is designed to run as a Symphony `hooks.after_run` command, outside the Codex sandbox.

Why this exists:

- Codex app-server runs with `workspaceWrite` sandboxing.
- In that sandbox, the working tree is writable but `.git` ref mutation can be blocked.
- That means an agent can complete code changes and move a Linear issue to `Human Review`, while branch/commit/push/PR creation fails or never happens.
- The host-side hook owns the git side effects after the agent run completes.

Install on `symphony-01`:

```bash
sudo install -m 0755 ops/ignis/scripts/publish-pr.sh /opt/symphony/bin/publish-pr.sh
```

The service environment must provide credentials through `/etc/symphony/symphony.env`:

- `GITHUB_TOKEN` or an authenticated `gh` CLI for the `symphony` user
- `LINEAR_API_KEY`

Recommended workflow hook:

```yaml
hooks:
  timeout_ms: 300000
  after_run: |
    /opt/symphony/bin/publish-pr.sh
```

Deployment-specific optional environment variables:

- `SYMPHONY_BASE_BRANCH`, default `develop`
- `SYMPHONY_GITHUB_REPO`, default `ignislabsio/mycards-api`
- `SYMPHONY_GIT_AUTHOR_NAME`, default `Byron Rode`
- `SYMPHONY_GIT_AUTHOR_EMAIL`, default `byron@ignislabs.io`

The hook only publishes when the Linear issue state is exactly `Human Review`, so active or max-turn interrupted work is not pushed prematurely.
