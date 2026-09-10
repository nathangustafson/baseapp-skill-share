#!/bin/bash
#
# Install the BaseApp Skill Share into a Claude Code project (or your user profile).
#
#   ./install.sh                      # skills -> ./.claude/skills, hooks -> ./.claude/hooks
#   ./install.sh --project /path/to/repo
#   ./install.sh --user               # skills -> ~/.claude/skills (available in every project)
#   ./install.sh --skills-only        # skip hooks + settings
#   ./install.sh --force              # overwrite skills that already exist
#
# Hooks are only ever installed at PROJECT level, because they call project
# scripts and containers. Settings are MERGED into .claude/settings.json with jq;
# a timestamped backup of the previous file is written first.
#
# Nothing here runs Docker, touches a database, or contacts the network.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$PWD"
USER_LEVEL=0
SKILLS_ONLY=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) TARGET="$2"; shift 2 ;;
    --user) USER_LEVEL=1; shift ;;
    --skills-only) SKILLS_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ $USER_LEVEL -eq 1 ]]; then
  SKILL_DIR="$HOME/.claude/skills"
else
  SKILL_DIR="$TARGET/.claude/skills"
fi
mkdir -p "$SKILL_DIR"

echo "→ skills → $SKILL_DIR"
for s in "$HERE"/skills/*/; do
  name="$(basename "$s")"
  if [[ -e "$SKILL_DIR/$name" && $FORCE -eq 0 ]]; then
    echo "  skip    $name (exists; use --force to overwrite)"
    continue
  fi
  rm -rf "$SKILL_DIR/$name"
  cp -R "$s" "$SKILL_DIR/$name"
  echo "  install $name"
done

[[ $SKILLS_ONLY -eq 1 || $USER_LEVEL -eq 1 ]] && { echo "✓ done (skills only)"; exit 0; }

command -v jq >/dev/null || { echo "jq is required to merge settings (brew install jq)"; exit 1; }

echo "→ hooks → $TARGET/.claude/hooks"
mkdir -p "$TARGET/.claude/hooks" "$TARGET/scripts"
cp "$HERE"/hooks/*.sh "$TARGET/.claude/hooks/"
chmod +x "$TARGET"/.claude/hooks/*.sh
if [[ -e "$TARGET/scripts/backup-db.sh" && $FORCE -eq 0 ]]; then
  echo "  skip    scripts/backup-db.sh (exists)"
else
  cp "$HERE/scripts/backup-db.sh" "$TARGET/scripts/backup-db.sh"; chmod +x "$TARGET/scripts/backup-db.sh"
  echo "  install scripts/backup-db.sh"
fi

SETTINGS="$TARGET/.claude/settings.json"
echo "→ merging hook wiring into $SETTINGS"
if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
else
  echo '{}' > "$SETTINGS"
fi
# Concatenate hook arrays per event instead of replacing them, so existing hooks survive.
jq -s '
  .[0] as $cur | .[1] as $new |
  $cur * { hooks: (
    ($cur.hooks // {}) as $ch | ($new.hooks // {}) as $nh |
    ($ch + $nh) | with_entries(.value = (($ch[.key] // []) + ($nh[.key] // [])))
  ) }' "$SETTINGS" "$HERE/settings.hooks.example.json" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

cat <<MSG
✓ done

Next:
  1. Open the project in Claude Code and run:   /phase-status-report
  2. Edit .claude/hooks/pm-coverage-gate.sh — the Atlas DB query at the bottom is
     BaseApp-specific; point it at your own tracker or delete that block.
  3. Set DB_USER / DB_NAME / container names in scripts/backup-db.sh and
     .claude/hooks/db-backup-staleness.sh if yours differ.
  4. Read README.md → "Adapting to your project".
MSG
