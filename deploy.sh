#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TARGET_DIR="$HOME/.claude/skills"
CODEX_TARGET_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
AGENTS_TARGET_DIR="$HOME/.agents/skills"
PERSONAS_SOURCE_DIR="$SCRIPT_DIR/personas"
CLAUDE_PERSONAS_DIR="$HOME/.claude/agents"
CODEX_PERSONAS_DIR="${CODEX_HOME:-$HOME/.codex}/agents"
OPENCODE_PERSONAS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
INSTRUCTIONS_SOURCE="$SCRIPT_DIR/agents/AGENTS.md"
CLAUDE_INSTRUCTIONS="$HOME/.claude/CLAUDE.md"
CODEX_INSTRUCTIONS="${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
OPENCODE_INSTRUCTIONS="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"
GIT_TEMPLATE_DIR="$HOME/.git-templates"
CODEGRAPH_HOOK="$GIT_TEMPLATE_DIR/hooks/post-checkout"

for target_dir in "$CLAUDE_TARGET_DIR" "$CODEX_TARGET_DIR" "$AGENTS_TARGET_DIR"; do
    mkdir -p "$target_dir"

    # Copy each skill directory (any dir containing a SKILL.md)
    for skill in "$SCRIPT_DIR"/skills/*/; do
        if [ -f "$skill/SKILL.md" ]; then
            name="$(basename "$skill")"
            echo "Deploying skill to $target_dir: $name"
            cp -r "$skill" "$target_dir/$name"
        fi
    done
done

deploy_personas() {
    local platform="$1"
    local target_dir="$2"

    mkdir -p "$target_dir"

    for persona_dir in "$PERSONAS_SOURCE_DIR"/*/; do
        if [ -f "$persona_dir/instructions.md" ] && [ -f "$persona_dir/$platform.yaml" ]; then
            name="$(basename "$persona_dir")"
            echo "Deploying persona to $target_dir: $name"
            {
                printf '%s\n' '---'
                cat "$persona_dir/$platform.yaml"
                printf '%s\n\n' '---'
                cat "$persona_dir/instructions.md"
            } > "$target_dir/$name.md"
        fi
    done
}

deploy_personas claude "$CLAUDE_PERSONAS_DIR"
deploy_personas codex "$CODEX_PERSONAS_DIR"
deploy_personas opencode "$OPENCODE_PERSONAS_DIR"

for instructions_target in "$CLAUDE_INSTRUCTIONS" "$CODEX_INSTRUCTIONS" "$OPENCODE_INSTRUCTIONS"; do
    mkdir -p "$(dirname "$instructions_target")"
    echo "Deploying general instructions to $instructions_target"
    cp "$INSTRUCTIONS_SOURCE" "$instructions_target"
done

mkdir -p "$(dirname "$CODEGRAPH_HOOK")"
cat > "$CODEGRAPH_HOOK" <<'EOF'
#!/usr/bin/env sh

# Git runs post-checkout after clone and after later branch checkouts.
[ -d .codegraph ] && exit 0
command -v codegraph >/dev/null 2>&1 || exit 0

if ! codegraph init; then
    echo "warning: codegraph init failed; the clone completed successfully" >&2
fi
EOF
chmod +x "$CODEGRAPH_HOOK"
git config --global init.templateDir "$GIT_TEMPLATE_DIR"
echo "Installed CodeGraph clone hook at $CODEGRAPH_HOOK"

echo "Done. Skills deployed to $CLAUDE_TARGET_DIR, $CODEX_TARGET_DIR, and $AGENTS_TARGET_DIR"
echo "Personas deployed to $CLAUDE_PERSONAS_DIR, $CODEX_PERSONAS_DIR, and $OPENCODE_PERSONAS_DIR"
echo "General instructions deployed for Claude, Codex, and OpenCode"
