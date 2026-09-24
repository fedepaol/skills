#!/usr/bin/env bash
set -euo pipefail

# Read-only PR discovery and comment collection, using gh as in
# analyze-test-failures/fetch-logs.sh. Output one JSON object on stdout.
error_exit() {
  printf 'check-comments: %s\n' "$1" >&2
  exit 1
}

command -v gh >/dev/null || error_exit 'gh is required'
command -v jq >/dev/null || error_exit 'jq is required'

if (( $# > 1 )); then
  error_exit 'usage: fetch-comments.sh [PR number or URL]'
fi

if (( $# == 0 )); then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || error_exit 'not in a git checkout; pass a PR URL'
  pr_json=$(gh pr view --json number,title,url,headRefOid,baseRefOid,headRefName,baseRefName,author 2>/dev/null) ||
    error_exit 'no PR found for the current checkout (or gh authentication failed)'
else
  pr_json=$(gh pr view "$1" --json number,title,url,headRefOid,baseRefOid,headRefName,baseRefName,author 2>/dev/null) ||
    error_exit "cannot find PR: $1"
fi

read -r host owner repo number < <(
  jq -r '.url | capture("^https?://(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<number>[0-9]+)") | [.host,.owner,.repo,.number] | @tsv' <<<"$pr_json"
) || error_exit 'could not parse PR URL'
[[ -n "$host" && -n "$owner" && -n "$repo" && "$number" =~ ^[0-9]+$ ]] || error_exit 'invalid PR URL'

# gh chooses GH_TOKEN/GITHUB_TOKEN before stored credentials. Query the API
# with the same active credentials used for all subsequent requests.
viewer=$(gh api --hostname "$host" user --jq '.login' 2>/dev/null) ||
  error_exit 'cannot identify the GitHub user for the active token'
[[ -n "$viewer" && "$viewer" != null ]] || error_exit 'active token has no GitHub user'

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
printf '%s\n' "$pr_json" > "$tmp_dir/pr.json"

# GraphQL exposes thread resolution; REST does not. Only the first comment is
# needed here to join each thread to the complete paginated REST comment list.
gh api --hostname "$host" graphql --paginate --slurp \
  -F owner="$owner" -F name="$repo" -F number="$number" \
  -f query='
    query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $endCursor) {
            nodes {
              id isResolved isOutdated path line originalLine
              comments(first: 1) { nodes { databaseId } }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }' > "$tmp_dir/thread_pages.json" || error_exit 'could not fetch review threads'
jq -e 'length > 0 and all(.[];
  .errors == null and
  (.data.repository.pullRequest.reviewThreads.nodes | type == "array") and
  (.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage | type == "boolean") and
  all(.data.repository.pullRequest.reviewThreads.nodes[]; .isResolved != null)
)' \
  "$tmp_dir/thread_pages.json" >/dev/null || error_exit 'review thread response is incomplete'

base="repos/$owner/$repo"
gh api --hostname "$host" --paginate --slurp "$base/pulls/$number/comments?per_page=100" \
  > "$tmp_dir/inline_pages.json" || error_exit 'could not fetch inline comments'
gh api --hostname "$host" --paginate --slurp "$base/pulls/$number/reviews?per_page=100" \
  > "$tmp_dir/review_pages.json" || error_exit 'could not fetch reviews'
gh api --hostname "$host" --paginate --slurp "$base/issues/$number/comments?per_page=100" \
  > "$tmp_dir/issue_pages.json" || error_exit 'could not fetch PR conversation comments'

jq -e 'length > 0 and all(.[]; type == "array")' \
  "$tmp_dir/inline_pages.json" "$tmp_dir/review_pages.json" "$tmp_dir/issue_pages.json" \
  >/dev/null || error_exit 'a paginated comment response is incomplete'

jq -n \
  --slurpfile pr "$tmp_dir/pr.json" \
  --slurpfile threads "$tmp_dir/thread_pages.json" \
  --slurpfile inline "$tmp_dir/inline_pages.json" \
  --slurpfile reviews "$tmp_dir/review_pages.json" \
  --slurpfile issue "$tmp_dir/issue_pages.json" \
  --arg viewer "$viewer" --arg owner "$owner" --arg repo "$repo" \
  '{pr: $pr[0], owner: $owner, repo: $repo, viewer: $viewer,
    reviewThreads: [$threads[0][].data.repository.pullRequest.reviewThreads.nodes[]],
    inlineComments: ($inline[0] | add // []),
    reviews: ($reviews[0] | add // []),
    issueComments: ($issue[0] | add // [])}'
