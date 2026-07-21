# Kassiber Skill

Agent Skill for helping AI coding agents and terminal assistants use the
Kassiber CLI correctly.

This repository is intentionally small and installable on its own. It focuses
on CLI navigation: workflow order, safe handling rules, report selection, and
the places where command syntax is easy to guess wrong. It also documents the
terminal-first operator broker used for capability-scoped work sessions against
SQLCipher-encrypted projects.

## Contents

- `SKILL.md` - top-level routing, rules, fast paths, and gotchas
- `references/` - focused CLI command and workflow references
- `scripts/` - small helpers used by the skill
- `agents/` - agent-specific metadata

## Install

```bash
npx skills add bitcoinaustria/kassiber-skill
```

Manual install:

```bash
git clone https://github.com/bitcoinaustria/kassiber-skill.git kassiber-skill
cp -R kassiber-skill ~/.agents/skills/kassiber
```

For Claude Code specifically:

```bash
cp -R kassiber-skill ~/.claude/skills/kassiber
```

## Requirements

- Kassiber installed on `PATH`, or a Kassiber source checkout available via
  `KASSIBER_REPO=/path/to/kassiber`
- `jq` for `scripts/verify-state.sh`
- `uv` only when falling back to a source checkout

## Privacy

Kassiber data can include balances, transaction history, notes, wallet labels,
tax treatment, and other sensitive accounting context. This skill helps an
agent operate Kassiber, but it does not change where your AI provider sends
prompts and tool output.

Use a local or confidential inference setup if you do not want that accounting
context to leave your machine.

## License

AGPL-3.0-only. See `LICENSE`.
