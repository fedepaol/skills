---
name: check-comments
description: Check whether actionable comments on a GitHub pull request are addressed in its current code, including resolved review threads and comments from every author. Use for PR comment resolution checks.
---

# Check PR comments

Run `bash <skill-directory>/fetch-comments.sh [PR number or URL]` from the relevant checkout. The bundled read-only helper follows the `gh` based PR lookup used by `analyze-test-failures/fetch-logs.sh`, accepts the current checkout or an explicit PR, uses the active `gh` token, and returns JSON with PR metadata, the token's GitHub login (`viewer`), paginated review threads, inline comments, review bodies, and PR conversation comments. If it fails, report the error; do not claim all comments are resolved from partial data.

Check **every author's** comments, including `viewer` (often `fedepaol`), other users, and bots. Do not filter out the token owner. Join `reviewThreads[].comments.nodes[0].databaseId` to `inlineComments[].id`; use `in_reply_to_id` to attach replies, and inspect any inline comments that cannot be matched to a thread. Review bodies and PR conversation comments are separate from inline threads. Exclude empty review bodies and ordinary acknowledgements from the actionable count, but read replies before deciding whether a request was withdrawn, superseded, or answered.

For each actionable request or GitHub `suggestion` block:

1. Record its author, URL, requested change, and thread's `isResolved`/`isOutdated` state when applicable. An outdated thread can still contain an unmet request.
2. Inspect the **current PR head** (`pr.headRefOid`), the relevant files, and the PR diff (`gh pr diff <PR URL>`). If local `git rev-parse HEAD` matches the PR head, read local files; otherwise fetch the head's files through `gh api` or a read-only `git fetch`/`git show`. Do not judge from a stale local checkout or the original comment diff alone.
3. Determine whether the requested behavior or exact suggestion is present. Equivalent implementations count if the request's intent is met. Replies that merely say “done” and a resolved thread are supporting context, not proof. A superseded or explicitly withdrawn request is closed only when the follow-up makes that clear.
4. Mark each request **applied**, **not applied**, or **unclear**, independently of GitHub's resolved state. If unclear, state what evidence is missing. A thread with multiple independent requests needs a result for each one.

Report a concise summary with totals by author and status, then list every not applied or unclear request with a comment link and specific code evidence. Also call out resolved threads whose request is not applied and unresolved threads whose request is applied. Say “all comments addressed” only when every actionable request is applied or explicitly withdrawn and no review thread remains unresolved; otherwise state what remains. This is a read-only check: do not resolve threads or change PR code unless the user asks.

Before reporting, recheck `headRefOid` with `gh pr view <PR URL> --json headRefOid`. If it changed during the check, refresh the evidence against the new head.
