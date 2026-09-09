---
name: writecommit
description: Write and create a Git commit with a clear conventional message and required assistance and sign-off trailers.
---

# Write Commit

Before committing, inspect `git status` and staged diff. Stage only intended files.

Write a concise message:

- Subject: imperative verb first, capitalized, no trailing period; target 50
  characters. Describe one outcome, such as `Add retry handling` or
  `Fix stale cache reads`.
- Body: omit for self-evident changes. Otherwise leave a blank line, wrap at
  72 columns, and explain problem, change, and why this solution matters.
  Record user-visible effects, limitations, or follow-up context when useful;
  do not narrate line-by-line implementation details.

Example:

```text
Do:    Fix stale cache reads
Don't: Fixed cache bug.
```

Always add these trailers, after body (or after subject separated by blank line):

```text
Assisted-by: <current model name>
Signed-off-by: Federico Paolinelli <fpaoline@redhat.com>
```

Use exact current session model name for `Assisted-by`; do not guess or use a generic agent label. Create commit only after user asks to commit, using a message that preserves both trailers.
