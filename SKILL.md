---
name: sync-agent-skills
description: Use right after you create, rename, move, or delete a skill in any agent's skills directory (~/.claude/skills, ~/.cursor/skills, ~/.codex/skills), or when a skill authored under one agent is missing from the others, or when those skills directories contain broken or wrong symlinks. Propagates a skill made in one agent (Claude Code, Codex, Cursor) to all of them.
---

# Sync Agent Skills

## Overview

You (the agent) keep user-authored global skills shared across every agent CLI.
The real skill folders live once in `~/skills` (override `$SKILLS_SHARED_DIR`);
each agent's `skills/` directory holds symlinks back into it. When a skill is
born or changed in one agent, run the sync so it appears in all of them.

This is mechanical work — don't reimplement it by hand. Run the bundled
`sync-skills.sh`, which is idempotent.

## When to run it

Run the sync **as the last step** of any of these, without being asked:

- You just **created, renamed, moved, or deleted** a skill under any agent's
  `skills/` directory (so a skill authored in one agent reaches the others).
- A skill exists in one agent but the user reports it **missing** in another.
- A `skills/` directory has **broken or wrong symlinks**.

If none of these happened, do not run it.

## How to run it

```bash
~/skills/sync-agent-skills/sync-skills.sh
```

It's idempotent and prints exactly what it changed — just run it (no `--dry-run`
needed in normal flow). Then read the output:

- Lines like `absorb`, `link`, `fix link`, `remove broken` = it did the work.
- A `CONFLICT (differs, skipped)` line = the same skill name exists in both an
  agent dir and `~/skills` with **different** contents. Stop and tell the user;
  do not guess which to keep.
- A `SKIP (real dir, not a link)` line = something occupies the link path; report it.

Use `--dry-run` only when the user explicitly wants a preview, or `--update` when
they ask to update the agent CLIs first.

## How it works (so you can reason about the output)

1. **integrate** — moves each *new real* (non-symlink) skill folder containing a
   `SKILL.md` from an agent dir into `~/skills`, then replaces it with a symlink.
   Skips tool-bundled skills (`anthropics/`, Codex `.system/`, Cursor's separate
   `skills-cursor/`), existing symlinks (e.g. project links), and non-directories.
2. **relink** — symlinks every shared skill into every installed agent; fixes
   wrong targets.
3. **prune** — removes dangling symlinks that pointed into `~/skills`.

## Config

Edit the top of `sync-skills.sh`: `TOOLS` (the per-agent skills dirs), `EXCLUDE`
(names never absorbed), `update_agents()` (the `--update` commands).
