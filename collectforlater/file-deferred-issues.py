#!/usr/bin/env python3
"""
file-deferred-issues.py — read a collect-for-later markdown file,
file GitHub issues for items marked with [x] in the File? field,
and update the file with the filed issue URLs.

Usage: python3 file-deferred-issues.py <markdown-file>
Requires: gh CLI, authenticated
"""

import re
import subprocess
import sys
from pathlib import Path


ITEM_HEADING = re.compile(r'^### Item \d+: (.+)$', re.MULTILINE)
FILE_FIELD = re.compile(r'^- \*\*File\?\*\*: \[([xX ])\]$', re.MULTILINE)
ASSIGNEE_FIELD = re.compile(r'^- \*\*Assignee\*\*: (.+)$', re.MULTILINE)
BODY_BLOCK = re.compile(r'\*\*Proposed Issue Body\*\*:\n\n(.+?)(?=\n---|\Z)', re.DOTALL)
ALREADY_FILED = re.compile(r'^- \*\*Filed Issue\*\*:', re.MULTILINE)


def split_items(content):
    """Split markdown content into a header block and a list of item blocks."""
    positions = [m.start() for m in ITEM_HEADING.finditer(content)]
    if not positions:
        return content, []
    header = content[:positions[0]]
    items = []
    for i, start in enumerate(positions):
        end = positions[i + 1] if i + 1 < len(positions) else len(content)
        items.append((start, end, content[start:end]))
    return header, items


def file_issue(title, body, assignee):
    result = subprocess.run(
        ["gh", "issue", "create", "--title", title, "--body", body, "--assignee", assignee],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()  # URL of created issue


def main():
    if len(sys.argv) != 2:
        print("Usage: file-deferred-issues.py <markdown-file>", file=sys.stderr)
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    content = path.read_text()
    header, items = split_items(content)

    if not items:
        print("No items found in the file.")
        sys.exit(0)

    filed = 0
    skipped_already = 0
    skipped_not_marked = 0
    failed = 0

    new_items = []
    for start, end, item in items:
        # Skip items already filed
        if ALREADY_FILED.search(item):
            skipped_already += 1
            new_items.append(item)
            continue

        file_match = FILE_FIELD.search(item)
        if not file_match or file_match.group(1).strip() not in ('x', 'X'):
            skipped_not_marked += 1
            new_items.append(item)
            continue

        title_match = ITEM_HEADING.search(item)
        assignee_match = ASSIGNEE_FIELD.search(item)
        body_match = BODY_BLOCK.search(item)

        if not (title_match and assignee_match and body_match):
            print(f"⚠️  Could not parse item — skipping: {item[:80].strip()}...", file=sys.stderr)
            failed += 1
            new_items.append(item)
            continue

        title = title_match.group(1).strip()
        assignee = assignee_match.group(1).strip().lstrip('@')
        body = body_match.group(1).strip()

        print(f"Filing: {title}")
        try:
            url = file_issue(title, body, assignee)
            number = url.rstrip('/').split('/')[-1]
            updated = item.replace(
                file_match.group(0),
                file_match.group(0) + f'\n- **Filed Issue**: [#{number}]({url})',
                1,
            )
            new_items.append(updated)
            print(f"  ✅ #{number}: {url}")
            filed += 1
        except RuntimeError as e:
            print(f"  ❌ Failed: {e}", file=sys.stderr)
            failed += 1
            new_items.append(item)

    path.write_text(header + ''.join(new_items))

    print(f"\n{filed} filed, {skipped_not_marked} not marked, {skipped_already} already filed, {failed} failed.")
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
