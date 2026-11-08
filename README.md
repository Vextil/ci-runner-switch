# ci-runner-switch

Moves private repos from GitHub-hosted runners to [Blacksmith](https://blacksmith.sh) when their org's free GitHub Actions minutes run low, and back again when the quota resets on the 1st.

Every hour, a workflow reads each org's Actions minutes for the current month from the billing API and sets the repo variable `CI_RUNNER`:

- at or above the threshold (default 1,900 of the 2,000 free minutes): `blacksmith`
- below it: `github`

Workflows in the target repos pick their runner with:

```yaml
runs-on: ${{ vars.CI_RUNNER == 'blacksmith' && 'blacksmith-2vcpu-ubuntu-2404' || 'ubuntu-24.04' }}
```

This repo is public so the switcher's own runs are free and keep working after an org runs out of minutes.

## Setup

1. Create a classic personal access token with the `repo` and `read:org` scopes. The account must be an admin of each org.
2. Add it as the `SWITCHER_TOKEN` Actions secret in this repo.

## Configure

Edit `config.json`. Add repos to `repos`, and give one its own `threshold_minutes` if needed:

```json
{ "repo": "org/name", "threshold_minutes": 1500 }
```

## Run it by hand

Actions → Switch CI runners → Run workflow. Tick *dry run* to only see what it would do.

To force a runner for the rest of the month, remove the repo from `config.json` and set `CI_RUNNER` yourself.

`STATE.md` shows the current runner per repo. It's committed when a runner flips or the month changes, which also stops GitHub from disabling the schedule after 60 days without activity.
