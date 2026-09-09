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
`instructions.md` and target-specific frontmatter in `claude.yaml`,
`codex.yaml`, and `opencode.yaml`. Run `./deploy.sh` to install it at:

- Claude: `~/.claude/agents/<name>.md`; invoke with `@<name>`.
- Codex: `$CODEX_HOME/agents/<name>.md` (or `~/.codex/agents/`); use as an
  `agent_type` for an isolated subagent.
- OpenCode: `~/.config/opencode/agents/<name>.md`; select it as a primary
  agent or invoke it as configured by OpenCode.

`architect` ships as a Kubernetes, networking, and Go architecture persona.
Its Codex model is `gpt-5.6-sol`; replace `XXX` in its Claude and OpenCode
metadata with the desired model before deployment.
