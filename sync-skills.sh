#!/usr/bin/env bash
# sync-skills.sh — keep user-authored skills shared across Claude Code, Codex, Cursor.
#
# What it does (idempotent, safe to re-run):
#   integrate : move any NEW real (non-symlink) user skill found in a tool's
#               skills/ dir into the shared dir, then replace it with a symlink.
#   relink    : ensure every shared skill is symlinked into every tool; repair
#               wrong/broken symlinks that point into the shared dir.
#   update    : (opt-in, --update) best-effort update of each agent CLI.
#
# Usage:
#   ./sync-skills.sh            # integrate + relink
#   ./sync-skills.sh --dry-run  # print actions, change nothing
#   ./sync-skills.sh --update   # also update agent frameworks first
set -uo pipefail

SHARED="${SKILLS_SHARED_DIR:-$HOME/skills}"

# Each tool's GLOBAL skills directory.
TOOLS=(
  "$HOME/.claude/skills"
  "$HOME/.cursor/skills"
  "$HOME/.codex/skills"
  "$HOME/.config/opencode/skills"
)

# Top-level names inside a tool's skills/ that are TOOL-BUNDLED — never absorb.
# (Dot-dirs like Codex's .system are skipped automatically by the glob.)
EXCLUDE=("anthropics" "sync-agent-skills")

DRY=0
DO_UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY=1 ;;
    --update|-u)  DO_UPDATE=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else "$@"; fi; }

is_excluded() {
  local n="$1"
  for e in "${EXCLUDE[@]}"; do [ "$n" = "$e" ] && return 0; done
  return 1
}

update_agents() {
  echo "== update agent frameworks =="
  # Commands are best-effort; adjust here if your install method differs.
  if command -v claude >/dev/null 2>&1; then
    echo "-- claude"; run claude update || echo "  (claude update unsupported/failed)"
  fi
  if command -v cursor-agent >/dev/null 2>&1; then
    echo "-- cursor-agent"; run cursor-agent update || echo "  (cursor-agent update unsupported/failed)"
  fi
  if command -v codex >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    echo "-- codex (npm -g)"; run npm install -g @openai/codex@latest || echo "  (codex update failed)"
  fi
}

integrate() {
  echo "== integrate new skills into $SHARED =="
  mkdir -p "$SHARED"
  local tool entry name dest
  for tool in "${TOOLS[@]}"; do
    [ -d "$tool" ] || continue
    for entry in "$tool"/*; do
      [ -e "$entry" ] || continue          # empty glob
      [ -L "$entry" ] && continue          # already a symlink (incl. external like timesheet)
      [ -d "$entry" ] || continue          # skip zips/files
      name="$(basename "$entry")"
      is_excluded "$name" && continue
      [ -f "$entry/SKILL.md" ] || continue # must look like a skill
      dest="$SHARED/$name"
      if [ -e "$dest" ]; then
        if diff -rq "$entry" "$dest" >/dev/null 2>&1; then
          echo "absorb (identical): $name  <- $tool"
          run rm -rf "$entry"; run ln -sfn "$dest" "$entry"
        else
          echo "CONFLICT (differs, skipped): $name  in $tool vs $SHARED"
        fi
      else
        echo "absorb (new): $name  <- $tool"
        run mv "$entry" "$dest"; run ln -sfn "$dest" "$entry"
      fi
    done
  done
}

relink() {
  echo "== relink shared skills into every tool =="
  local skill name tool link
  for skill in "$SHARED"/*; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    for tool in "${TOOLS[@]}"; do
      if [ ! -d "$tool" ]; then
        # agent installed (its config parent exists) but no skills/ dir yet -> create it.
        # agent not installed (parent missing too) -> skip.
        [ -d "$(dirname "$tool")" ] || continue
        echo "mkdir: $tool"; run mkdir -p "$tool"
        [ "$DRY" = 1 ] && continue          # can't link into a dir we only pretended to create
      fi
      link="$tool/$name"
      if [ -L "$link" ]; then
        [ "$(readlink "$link")" = "$skill" ] || { echo "fix link: $link"; run ln -sfn "$skill" "$link"; }
      elif [ -e "$link" ]; then
        echo "SKIP (real dir, not a link): $link"
      else
        echo "link: $link"; run ln -sfn "$skill" "$link"
      fi
    done
  done
}

prune() {
  echo "== prune broken links pointing into $SHARED =="
  local tool entry target
  for tool in "${TOOLS[@]}"; do
    [ -d "$tool" ] || continue
    for entry in "$tool"/*; do
      [ -L "$entry" ] || continue
      target="$(readlink "$entry")"
      case "$target" in
        "$SHARED"/*) [ -e "$entry" ] || { echo "remove broken: $entry"; run rm "$entry"; } ;;
      esac
    done
  done
}

[ "$DO_UPDATE" = 1 ] && update_agents
integrate
relink
prune
[ "$DRY" = 1 ] && echo "== done (dry-run) ==" || echo "== done =="
