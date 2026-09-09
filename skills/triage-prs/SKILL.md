---
name: triage-prs
description: Analyze open PRs in the current repo, classify each one into an actionable category (merge, fix-merge, cherry-pick, reject, etc.), and produce a markdown triage report. Can re-evaluate PRs flagged for recheck.
argument-hint: [path/to/existing-triage.md] (optional — pass an existing triage file to recheck flagged PRs and add new ones)
---

# Triage Open PRs

This skill is invoked from within a git repository. It fetches all open PRs, filters out stale and Dependabot PRs, analyzes each one, and classifies it into an actionable category. The output is a markdown triage report.

If an existing triage file is passed as an argument, it re-evaluates PRs marked with `Recheck: true` and adds any new PRs not yet in the file.

## Classifications

Each PR is classified into exactly one of these categories:

| Category | Meaning |
|---|---|
| **Easy win** | Small, clean, ready to merge with minimal review. |
| **Merge** | Well-tested, broadly useful, well-documented, good to go. May be small or big. |
| **Merge-fix** | Mergeable as-is, but has minor issues to fix in a follow-up commit after merging. |
| **Fix-merge** | Has significant issues. Pull locally, make substantial changes, then push with contributor attribution. |
| **Cherry-pick** | Contains M items but we only want N < M. Cherry-pick the good parts locally, close the PR with explanation. |
| **Split-merge** | Contains M items that are separate concerns and should have been separate PRs. Pull locally, split into separate commits, push all with attribution. |
| **Redesign/reimplement** | PR is rejected on design grounds, but the underlying problem is real. We design a better solution and implement it ourselves, then close the PR with thanks and explanation. |
| **Retire** | Obsolete — superseded by another PR or fixed by other means. Close with thank-you. |
| **Reject** | Feature doesn't pay its weight in tech debt, is too niche, or doesn't meet standards. Close with polite note. |
| **Request changes** | Last resort. Ask the contributor to make changes. Use sparingly — can cause contributor starvation. |

## Inputs

- **Optional argument**: path to an existing triage markdown file. If provided, the skill re-evaluates PRs marked `Recheck: true` and appends any new PRs.
- Everything else is derived from the current git repository.

## Output Format

The skill produces a markdown file named `pr-triage-YYYY-MM-DD.md` in the current directory. The format is:

```markdown
# PR Triage: owner/repo

Generated: YYYY-MM-DD

## Summary

| Classification | Count | PRs |
|---|---|---|
| Easy win | 2 | [#12](https://github.com/owner/repo/pull/12), [#45](https://github.com/owner/repo/pull/45) |
| Merge | 1 | [#33](https://github.com/owner/repo/pull/33) |
| Merge-fix | 0 | |
| Fix-merge | 1 | [#7](https://github.com/owner/repo/pull/7) |
| Cherry-pick | 0 | |
| Split-merge | 0 | |
| Redesign/reimplement | 0 | |
| Retire | 1 | [#5](https://github.com/owner/repo/pull/5) |
| Reject | 0 | |
| Request changes | 0 | |
| **Total** | **5** | |

---

### PR #<number>: <title>
- **Link**: <url>
- **Author**: <username>
- **Created**: <date>
- **Description**: <one-paragraph summary of what the PR does>
- **Classification**: <one of the categories above>
- **Reasoning**: <why this classification was chosen — 2-3 sentences>
- **Recheck**: false

---
```

The summary table links use full GitHub PR URLs (`https://github.com/<owner>/<repo>/pull/<number>`) so they are clickable from any context — terminal, editor, or browser.

## Step 0: Determine Repo and Check for Existing Triage

1. Get the repo owner and name:
   ```bash
   gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"'
   ```
   If this fails, tell the user this must be run from within a git repository with a GitHub remote.

2. Check if an existing triage file was passed as an argument.
   - If yes, read it. Parse out:
     - Which PR numbers are already triaged
     - Which PR numbers have `Recheck: true`
   - If no, start fresh.

## Step 1: Fetch Open PRs

1. Fetch all open PRs:
   ```bash
   gh pr list --state open --json number,title,author,createdAt,url,headRefName,isDraft,labels --limit 200
   ```

2. Filter out:
   - **Dependabot PRs**: where `author.login` is `dependabot` or `dependabot[bot]`, or the branch name starts with `dependabot/`.
   - **Stale PRs**: where `createdAt` is more than 365 days ago AND has had no new commits or comments in the last 180 days. To check recent activity:
     ```bash
     gh pr view <number> --json commits,comments --jq '{last_commit: .commits[-1].committedDate, last_comment: .comments[-1].createdAt}'
     ```
   - **Draft PRs**: where `isDraft` is true. Skip these silently.

3. If an existing triage file was provided:
   - Identify **new PRs**: open PRs not already in the triage file.
   - Identify **recheck PRs**: PRs in the triage file with `Recheck: true`.
   - The set of PRs to analyze = new PRs + recheck PRs.
   - PRs already triaged with `Recheck: false` are kept as-is in the output.

4. Report to the user how many PRs will be analyzed (and how many were filtered out).

## Step 2: Analyze Each PR

For each PR to analyze, use an Agent (up to 5 in parallel) to gather information and classify it.

### What to give each agent

Give each agent:
1. The PR number, title, author, and URL
2. The repo owner/name
3. The full list of classification categories and their meanings (copy the table from above)
4. Instructions on what to investigate and how to classify

### What each agent should investigate

Tell each agent to gather the following information about the PR:

**PR metadata and discussion:**
```bash
gh pr view <number> --json title,body,author,createdAt,changedFiles,additions,deletions,reviewDecision,reviews,comments,labels,mergeable,statusCheckRollup
```

**The diff:**
```bash
gh pr diff <number>
```
If the diff is very large (> 2000 lines), the agent should note this and focus on the file list and key changes rather than reading every line.

**Commit history and messages:**
```bash
gh pr view <number> --json commits --jq '.commits[] | "\(.oid[:8]) \(.messageHeadline)\n\(.messageBody)\n---"'
```
Validate the commit history against these rules:
- **Clean history**: There must be no fixup commits — i.e., no commits whose sole purpose is to fix, amend, or correct something introduced by an earlier commit within the same PR (e.g., "fix typo from previous commit", "address review comments", "oops", "fixup"). Each commit should stand on its own as a coherent, correct change.
- **Subject line**: Each commit subject must clearly describe *what* the commit does (e.g., "Add retry logic to HTTP client", not "update" or "changes").
- **Body**: Each commit must have a non-empty body that explains *why* the change is being made — the motivation, context, or problem being solved. A bare subject with no body is insufficient.

If the commit history violates these rules, this is a significant quality signal that should factor into the classification. A PR with sloppy commit history is more likely to be classified as **Fix-merge** or **Request changes** than **Merge** or **Easy win**, unless the code changes themselves are trivial.

**Linked issues and consensus:**
Check whether the PR references an issue (look in the PR body for `Fixes #N`, `Closes #N`, `Resolves #N`, or plain `#N` references):
```bash
gh pr view <number> --json body --jq '.body' | grep -oP '#\d+' | sort -u
```
For each linked issue, fetch the issue discussion:
```bash
gh issue view <issue-number> --json title,body,state,comments,labels --jq '{title, state, comment_count: (.comments | length), labels: [.labels[].name], comments: [.comments[] | {author: .author.login, body: .body}]}'
```
Evaluate whether there is **consensus** on the linked issue:
- **Consensus**: Multiple participants agree on the approach, or a maintainer has endorsed it.
- **Contested**: There is active disagreement about whether the change is needed or how it should be done.
- **No discussion**: The issue exists but has little or no engagement.

If **no issue is linked** and the PR is a **non-trivial feature or refactor** (not a bugfix, not documentation, and more than ~50 lines changed), flag this in the reasoning as: *"Large change with no linked issue or prior discussion."* This is a quality signal — significant changes should generally have been discussed before implementation. This makes the PR more likely to be classified as **Request changes**, **Fix-merge**, or **Redesign/reimplement** depending on the code quality.

**CI status:**
From the `statusCheckRollup` field, determine if CI is passing, failing, or pending.

**Review status:**
From `reviews` and `reviewDecision`, check if there are existing reviews and what they say.

### How each agent should classify

Tell each agent to consider these factors when choosing a classification:

1. **Size and scope**: How many files changed? How many lines? Is it focused or sprawling?
2. **Quality**: Is the code clean? Are there tests? Is there documentation?
3. **CI status**: Are checks passing?
4. **Relevance**: Does this change fit the project's direction and standards?
5. **Separability**: Does the PR mix unrelated concerns?
6. **Completeness**: Is the implementation complete or half-done?
7. **Overlap**: Does this duplicate or conflict with other work?
8. **Commit hygiene**: Is the commit history clean? Are there fixup commits? Does each commit have a meaningful subject describing *what* and a body explaining *why*?
9. **Issue consensus**: If a linked issue exists, is there consensus on the approach? If contested, the PR may need redesign. If there is no linked issue and the change is large and not a bugfix, that is a red flag.

Classification guidance for the agent:
- **Easy win**: < 50 lines changed, single concern, tests pass, obvious improvement.
- **Merge**: Well-scoped, tests included and passing, good description, addresses a real need.
- **Merge-fix**: Good overall but has minor style issues, missing a test case, or small bugs that are easier to fix post-merge.
- **Fix-merge**: Good idea but implementation has significant problems — wrong approach in places, missing error handling, incomplete tests.
- **Cherry-pick**: Multiple features/fixes bundled together and only some are wanted. Look for PRs with "and" in the title or multiple unrelated changes.
- **Split-merge**: Multiple good changes that should be separate PRs. Similar to cherry-pick but all parts are wanted.
- **Redesign/reimplement**: The problem being solved is real but the approach is wrong — wrong abstraction, wrong API, wrong architecture.
- **Retire**: The issue this PR fixes has been resolved by other means, or a newer PR from the same author supersedes it.
- **Reject**: Feature is too niche, adds too much complexity for its value, or doesn't fit the project direction.
- **Request changes**: The PR is close but needs specific, well-defined changes from the contributor. Only use this if the contributor is likely to respond.

### What each agent should return

Each agent must return:
1. A one-paragraph description of what the PR does
2. The chosen classification
3. 2-3 sentences of reasoning for the classification — if a linked issue had no consensus or was contested, or if a large non-bugfix PR has no linked issue, this must be mentioned in the reasoning
4. `Recheck: false` — this skill must **never** set `Recheck: true`. Only a third party (human reviewer or external tool) may flag a PR for recheck by editing the triage file. This skill's job is to re-evaluate entries that already have `Recheck: true` and replace them with an updated classification and `Recheck: false`.

The agent should do research only, NOT make code changes, NOT leave reviews, NOT comment on PRs.

## Step 3: Produce the Triage Report

After all agents complete, assemble the triage report:

1. If this is a recheck of an existing file:
   - Keep all entries with `Recheck: false` unchanged from the original file
   - Replace entries that were rechecked with updated classifications
   - Append new PR entries at the end

2. If this is a fresh triage:
   - Create the full report from scratch

3. Write the output file as `pr-triage-YYYY-MM-DD.md` in the current directory using the format specified above. The summary table must be at the top of the file, before any individual PR entries. Each row in the summary links to the corresponding PR headings within the file using markdown anchor links.

4. Print the summary table to the user (same content as in the file) and tell them the path to the output file.
