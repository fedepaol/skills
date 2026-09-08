#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TARGET_DIR="$HOME/.claude/skills"
CODEX_TARGET_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
AGENTS_TARGET_DIR="$HOME/.agents/skills"
INSTRUCTIONS_SOURCE="$SCRIPT_DIR/agents/AGENTS.md"
CLAUDE_INSTRUCTIONS="$HOME/.claude/CLAUDE.md"
CODEX_INSTRUCTIONS="${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
OPENCODE_INSTRUCTIONS="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"

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

for instructions_target in "$CLAUDE_INSTRUCTIONS" "$CODEX_INSTRUCTIONS" "$OPENCODE_INSTRUCTIONS"; do
    mkdir -p "$(dirname "$instructions_target")"
    echo "Deploying general instructions to $instructions_target"
    cp "$INSTRUCTIONS_SOURCE" "$instructions_target"
done

echo "Done. Skills deployed to $CLAUDE_TARGET_DIR, $CODEX_TARGET_DIR, and $AGENTS_TARGET_DIR"
echo "General instructions deployed for Claude, Codex, and OpenCode"
