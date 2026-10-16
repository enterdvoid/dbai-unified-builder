#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_REPOSITORY:?Run this script from the dedicated GitHub Actions workflow}"
: "${GITHUB_RUN_ID:?Current workflow run ID is required}"
[[ "${CONFIRM_DELETE_HISTORY:-no}" == "yes" ]] || {
  echo "Refusing to delete workflow history without CONFIRM_DELETE_HISTORY=yes." >&2
  exit 2
}
if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then export GH_TOKEN="$GITHUB_TOKEN"; fi
[[ -n "${GH_TOKEN:-}" ]] || { echo "GH_TOKEN/GITHUB_TOKEN is required." >&2; exit 2; }

echo "Repository: $GITHUB_REPOSITORY"
echo "Deleting workflow runs except the current run $GITHUB_RUN_ID."
echo "The current cleanup run cannot reliably delete itself while it is executing."

while true; do
  run_list="$(gh run list --repo "$GITHUB_REPOSITORY" --limit 1000 --json databaseId --jq '.[].databaseId')"
  listed_ids=()
  if [[ -n "$run_list" ]]; then mapfile -t listed_ids <<< "$run_list"; fi
  pending=()
  for run_id in "${listed_ids[@]}"; do
    [[ -n "$run_id" && "$run_id" != "$GITHUB_RUN_ID" ]] && pending+=("$run_id")
  done
  if (("${#pending[@]}" == 0)); then
    echo "No other workflow runs remain."
    exit 0
  fi

  deleted=0
  failed=0
  echo "Found ${#pending[@]} run(s) to delete in this batch."
  for run_id in "${pending[@]}"; do
    if gh run delete "$run_id" --repo "$GITHUB_REPOSITORY" --yes; then
      deleted=$((deleted + 1))
    else
      echo "::warning::Could not delete workflow run $run_id"
      failed=$((failed + 1))
    fi
    sleep 1
  done

  if (( deleted == 0 && failed > 0 )); then
    echo "::error::No workflow runs were deleted in the last batch; stopping to avoid an infinite loop."
    exit 1
  fi
done
