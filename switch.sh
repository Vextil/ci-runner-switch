#!/usr/bin/env bash
# Sets CI_RUNNER on each configured repo based on its org's GitHub Actions
# minutes used this calendar month:
#   used >= threshold -> CI_RUNNER=blacksmith
#   used <  threshold -> CI_RUNNER=github
# Usage resets on the 1st, so repos flip back to GitHub automatically.
#
# Env: GH_TOKEN (classic PAT: repo, read:org), DRY_RUN=1 to only report.
set -uo pipefail

CONFIG="${CONFIG:-config.json}"
STATE="${STATE:-STATE.md}"
DRY_RUN="${DRY_RUN:-0}"
MONTH="$(date -u +%Y-%m)"
default_threshold="$(jq -r '.default_threshold_minutes' "$CONFIG")"
errors=0
rows=""

# Billable minutes this month. macOS/Windows count against the free quota at
# 10x/2x, so weight them the same way.
used_minutes() {
  gh api "organizations/$1/settings/billing/usage/summary" --jq '
    [.usageItems[]
      | select(.product == "Actions" and .unitType == "minutes")
      | .grossQuantity * (if (.sku | test("macos")) then 10
                          elif (.sku | test("windows")) then 2
                          else 1 end)
    ] | add // 0 | floor'
}

summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; echo "$1"; }

summary "| Repo | Used | Threshold | Was | Now |"
summary "|---|---|---|---|---|"

while read -r entry; do
  repo="$(jq -r '.repo' <<<"$entry")"
  threshold="$(jq -r --arg d "$default_threshold" '.threshold_minutes // ($d | tonumber)' <<<"$entry")"
  org="${repo%%/*}"

  if ! used="$(used_minutes "$org")"; then
    echo "::error::Could not read billing usage for $org"
    errors=$((errors + 1)); continue
  fi

  if [ "$used" -ge "$threshold" ]; then desired=blacksmith; else desired=github; fi
  current="$(gh variable get CI_RUNNER -R "$repo" 2>/dev/null || true)"

  if [ "$current" != "$desired" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry run] would set $repo CI_RUNNER=$desired"
    elif gh variable set CI_RUNNER -b "$desired" -R "$repo"; then
      echo "::notice::$repo: CI_RUNNER ${current:-<unset>} -> $desired ($used/$threshold min)"
    else
      echo "::error::Could not set CI_RUNNER on $repo"
      errors=$((errors + 1)); desired="$current"
    fi
  fi

  summary "| $repo | $used | $threshold | ${current:-unset} | $desired |"
  rows+="| $repo | $desired |"$'\n'
done < <(jq -c '.repos[]' "$CONFIG")

# The state file only changes when a runner flips or the month rolls over.
# Committing it keeps this public repo active, so GitHub never disables the
# schedule for 60 days of inactivity.
if [ "$DRY_RUN" != 1 ] && [ "$errors" -eq 0 ]; then
  {
    echo "# Current runners"
    echo
    echo "Month: $MONTH (UTC). Updated automatically by the switch workflow."
    echo
    echo "| Repo | CI_RUNNER |"
    echo "|---|---|"
    printf '%s' "$rows"
  } > "$STATE"
fi

exit $(( errors > 0 ))
