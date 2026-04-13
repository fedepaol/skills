#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/skills"

mkdir -p "$TARGET_DIR"

# Copy each skill directory (any dir containing a SKILL.md)
for skill in "$SCRIPT_DIR"/*/; do
    if [ -f "$skill/SKILL.md" ]; then
        name="$(basename "$skill")"
        echo "Deploying skill: $name"
        cp -r "$skill" "$TARGET_DIR/$name"
    fi
done

echo "Done. Skills deployed to $TARGET_DIR"
