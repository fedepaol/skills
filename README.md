# Agent Skills

Custom skills for [Claude Code](https://claude.ai/claude-code) and Codex.

## Setup

Run deploy script to install skills into Claude, Codex, and shared agent skill
directories: `~/.claude/skills/`, `$CODEX_HOME/skills` (or `~/.codex/skills`
when `CODEX_HOME` unset), and `~/.agents/skills/`. It also installs personas
from `personas/` to each tool's agent directory.

```bash
./deploy.sh
```

## Adding a New Skill

Create a directory under `skills/` with a `SKILL.md` file and run `./deploy.sh`
again.

## Personas

Create one directory per persona in `personas/`. Add shared instructions in
`instructions.md` and target-specific metadata in `claude.yaml`,
`codex.yaml`, and `opencode.yaml`. The deploy script combines the shared
instructions with each platform's metadata and renders Codex TOML files. Run
`./deploy.sh` to install them at:

- Claude: `~/.claude/agents/<name>.md`; invoke with `@<name>`.
- Codex: `$CODEX_HOME/agents/<name>.toml` (or `~/.codex/agents/`); ask
  Codex to delegate a task to the named agent.
- OpenCode: `~/.config/opencode/agents/<name>.md`; select it as a primary
  agent or invoke it as configured by OpenCode.

`architect` ships as a Kubernetes, networking, and Go architecture persona.
Its Codex model is `gpt-5.6-sol`. Claude Code and OpenCode inherit the selected
model; set a platform-specific model in its metadata when needed.
