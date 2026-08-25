#!/bin/bash
set -euo pipefail

# fetch-logs.sh
# Downloads CI artifacts for the current branch's last failed run
# Outputs JSON with paths to test outputs and log dumps

error_exit() {
  echo "{\"error\": \"$1\"}" >&2
  exit 1
}

# Set GITHUB_TOKEN from gh if not already set
if [ -z "${GITHUB_TOKEN:-}" ]; then
  GITHUB_TOKEN=$(gh auth token 2>/dev/null) || error_exit "GITHUB_TOKEN not set and gh auth token failed. Run: gh auth login"
  export GITHUB_TOKEN
fi

# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || error_exit "Not in git repo"

# Get repo owner and name
REPO_JSON=$(gh repo view --json owner,name 2>/dev/null) || error_exit "gh cli failed or not in repo"
OWNER=$(echo "$REPO_JSON" | jq -r '.owner.login')
REPO=$(echo "$REPO_JSON" | jq -r '.name')

# Find PR for this branch (handles fork PRs)
PR_NUM=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
if [ -z "$PR_NUM" ] || [ "$PR_NUM" = "null" ]; then
  error_exit "No PR found for branch $BRANCH"
fi

# Find last failed workflow run
RUN_ID=$(gh api "repos/$OWNER/$REPO/actions/runs?branch=$BRANCH&status=failure&per_page=1" --jq '.workflow_runs[0].id' 2>/dev/null)
if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
  error_exit "No failed workflow runs for branch $BRANCH"
fi

# Check if artifactsdownloader is installed, install if missing
if ! command -v artifactsdownloader &> /dev/null; then
  if ! command -v go &> /dev/null; then
    error_exit "go not found. Install go first"
  fi
  echo "Installing artifactsdownloader..." >&2
  go install github.com/fedepaol/artifactsdownloader@latest || error_exit "Failed to install artifactsdownloader"
fi

# Create logs directory
LOGS_DIR="logs_${RUN_ID}"
mkdir -p "$LOGS_DIR"
cd "$LOGS_DIR"

# Download artifacts
artifactsdownloader "$OWNER" "$REPO" "$RUN_ID" || error_exit "artifactsdownloader failed"

# Find test output files
TEST_OUTPUTS=$(find . -path '*/logs/*e2etests*.txt' -type f 2>/dev/null || echo "")

# Find log dump directories
LOG_DUMPS=$(find . -maxdepth 1 -type d -name 'kind-logs-*' 2>/dev/null || echo "")

# Output JSON
cat <<EOF
{
  "run_id": "$RUN_ID",
  "logs_dir": "$(pwd)",
  "test_outputs": [$(echo "$TEST_OUTPUTS" | sed 's|^|"|; s|$|"|' | paste -sd,)],
  "log_dumps": [$(echo "$LOG_DUMPS" | sed 's|^|"|; s|$|"|' | paste -sd,)],
  "branch": "$BRANCH",
  "pr": $PR_NUM,
  "owner": "$OWNER",
  "repo": "$REPO"
}
EOF
