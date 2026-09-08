#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TARGET_DIR="$HOME/.claude/skills"
CODEX_TARGET_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
AGENTS_TARGET_DIR="$HOME/.agents/skills"

for target_dir in "$CLAUDE_TARGET_DIR" "$CODEX_TARGET_DIR" "$AGENTS_TARGET_DIR"; do
    mkdir -p "$target_dir"

    # Copy each skill directory (any dir containing a SKILL.md)
    for skill in "$SCRIPT_DIR"/*/; do
        if [ -f "$skill/SKILL.md" ]; then
            name="$(basename "$skill")"
            echo "Deploying skill to $target_dir: $name"
            cp -r "$skill" "$target_dir/$name"
        fi
    done
done

echo "Done. Skills deployed to $CLAUDE_TARGET_DIR, $CODEX_TARGET_DIR, and $AGENTS_TARGET_DIR"
