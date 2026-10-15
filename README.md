# Ownship Deploy Action

Deploy an [Ownship](https://ownship.dev) project to your own homelab from GitHub Actions.
The action triggers a deployment, waits for it to pass its health check, and fails the
job if it fails.

## Usage

1. In the Ownship dashboard, create an API token under **Keychain → API Tokens** with the
   `deploy` scope.
2. Add it to your repository as a secret named `OWNSHIP_TOKEN`
   (**Settings → Secrets and variables → Actions**).
3. Copy your project id from the project's URL in the dashboard (`/projects/<id>`).

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: ownship-dev/deploy-action@v1
        id: ownship
        with:
          token: ${{ secrets.OWNSHIP_TOKEN }}
          project-id: 550e8400-e29b-41d4-a716-446655440000

      - run: echo "Live at ${{ steps.ownship.outputs.url }}"
```

Run it after your tests (`needs: test`) so only a green build ships.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | yes | | Ownship API token. Use a `deploy`-scope token stored as a secret. |
| `project-id` | yes | | The project to deploy. |
| `wait` | no | `true` | Wait for the deployment to finish and fail the job if it fails. |
| `api-url` | no | `https://api.ownship.dev` | Ownship API base URL. |

## Outputs

| Output | Description |
|--------|-------------|
| `deployment-id` | The id of the created deployment. |
| `url` | The public URL once live (only with `wait: true` and routing configured). |

## Behaviour

- The deployment deploys the project's configured branch, exactly like the **Deploy**
  button in the dashboard.
- With `wait: true` the job polls for up to 20 minutes. It succeeds when the deployment is
  `live` and fails when it ends `failed`, `rolledback` or `superseded`, printing the reason.
  A failed health check auto-rolls back on Ownship's side, so production keeps running.
- API errors are shown with their message (for example a homelab that is offline or
  unpaired). Short network blips while waiting are retried.
- The token is only sent in the `Authorization` header and is never printed.
- Requires `bash`, `curl` and `python3`, all present on GitHub-hosted runners.
