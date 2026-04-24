---
name: collectforlater
description: Scan all comments on a PR for deferral language ("let's do this later", "follow up", "defer", etc.) and produce a markdown file with proposed issue titles and bodies. Run file-deferred-issues.py to actually file the ones you approve.
argument-hint: <PR number or URL> (optional — auto-detects from current branch if omitted)
---

# Collect For Later

This skill scans all comments on a GitHub PR — inline review comments, review body text, and issue-style comments — for deferral language. It writes a markdown file with one entry per deferred item, including a proposed issue title and body. You approve items by changing `[ ]` to `[x]`, then run `file-deferred-issues.py` to file those as GitHub issues.

## Inputs

- **Optional argument**: a PR number or full GitHub PR URL. If omitted, the skill auto-detects the PR from the current branch.

## Output

A file named `collect-for-later-PR<number>-YYYY-MM-DD.md` in the current directory. Each deferred item has the format:

```markdown
### Item N: <proposed issue title>

- **File?**: [ ]
- **Comment**: [comment by @commenter](url)
- **Excerpt**: "quoted excerpt from the comment"
- **Assignee**: pr-author-login

**Proposed Issue Body**:

<description of what needs to be done>

#### Context

> "quoted excerpt"

[Original comment in PR #N](url)

---
```

The user changes `[ ]` to `[x]` on the `Approve` line, then runs `file-deferred-issues.py <file>` to file those issues.

---

## Step 0: Resolve the PR

1. If an argument was provided, parse it:
   - If it looks like a URL, extract the PR number from the path.
   - If it's a plain integer, use it directly.

2. If no argument was provided, auto-detect:
   ```bash
   git rev-parse --abbrev-ref HEAD
   gh pr view --json number -q '.number'
   ```
   If this fails (no open PR for the branch), tell the user and stop.

3. Get the repo:
   ```bash
   gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"'
   ```

4. Fetch PR metadata:
   ```bash
   gh pr view <number> --json number,title,author,url \
     -q '{number: .number, title: .title, author: .author.login, url: .url}'
   ```

## Step 1: Collect All Comments

Fetch every comment source for the PR:

**PR body and timeline comments:**
```bash
gh pr view <number> --json body,comments \
  --jq '{body: .body, comments: [.comments[] | {author: .author.login, body: .body, url: .url}]}'
```

**Inline review comments (attached to specific lines of the diff):**
```bash
gh api repos/{owner}/{repo}/pulls/<number>/comments \
  --jq '[.[] | {author: .user.login, body: .body, url: .html_url, path: .path}]'
```

**Review-level comments (top-level body of each review):**
```bash
gh api repos/{owner}/{repo}/pulls/<number>/reviews \
  --jq '[.[] | select(.body != "") | {author: .user.login, body: .body, url: .html_url}]'
```

Merge all sources into a single flat list. Each entry has: `author`, `body`, `url`.
Also include the PR body itself as an entry authored by the PR author.

## Step 2: Identify Deferral Comments

For each comment, scan the body for deferral language. Match on these patterns (case-insensitive):

- `follow.?up` (follow up, followup, follow-up)
- `later`
- `defer`
- `future`
- `TODO` / `FIXME`
- `next (pr|issue|iteration|sprint|release)`
- `do this later` / `address later` / `revisit`
- `out of scope` / `separate (issue|pr|ticket)`
- `not in scope`
- `we can` / `we should` / `we could` — only when paired with a deferral word in the same sentence

For each matching comment, extract:
- The **deferred action**: the thing the comment says should be done later (one sentence, paraphrase if needed)
- The **relevant excerpt**: 1-3 sentences from the comment body that best capture the deferral

Skip comments where the deferral language is purely historical ("this was deferred last sprint") or referring to something already done.

If zero deferral comments are found, tell the user and stop.

## Step 3: Generate Issue Proposals

For each deferral comment, generate:
- **Title**: a concise imperative sentence (≤ 72 chars) describing the deferred work, e.g. "Add retry logic to the HTTP client"
- **Body**: a well-formed GitHub issue body with:
  - A one-paragraph description of what needs to be done
  - A `#### Context` section with a blockquote of the original excerpt and a link back: `[Original comment in PR #N](url)`

## Step 4: Write the Tracker File

Write `collect-for-later-PR<number>-YYYY-MM-DD.md` to the current directory:

```markdown
# Collect For Later: PR #<number> — <title>

- **Repo**: <owner>/<repo>
- **PR URL**: <pr-url>
- **PR Author**: @<author>
- **Generated**: <YYYY-MM-DD>

To file issues: mark items with `[x]` in the `File?` field, then run:
`python3 file-deferred-issues.py collect-for-later-PR<number>-YYYY-MM-DD.md`

---

### Item 1: <proposed issue title>

- **File?**: [ ]
- **Comment**: [comment by @<commenter>](<comment-url>)
- **Excerpt**: "<relevant excerpt, truncated at ~150 chars with … if longer>"
- **Assignee**: <pr-author-login>

**Proposed Issue Body**:

<issue body paragraph>

#### Context

> "<relevant excerpt>"

[Original comment in PR #<number>](<comment-url>)

---

### Item 2: ...
```

After writing the file, print the path and a count of deferred items found.
