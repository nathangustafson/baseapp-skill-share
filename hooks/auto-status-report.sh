#!/bin/bash
#
# Stop hook: auto-runs the phase-status-report skill when a working session
# has produced NEW git commits that haven't been reported yet.
#
# Fires (blocks the Stop so Claude continues and generates the report) only if:
#   - This Stop is NOT already a continuation of a prior stop hook
#     (stop_hook_active guard — prevents an infinite report loop), AND
#   - HEAD has moved since the last time we reported (i.e. real commits
#     happened this stretch of work).
#
# It will NOT fire on plain Q&A turns (HEAD unchanged) — see the user's
# choice "Auto-run on new commits" (2026-06-08).
#
# Dedup marker lives OUTSIDE the repo (.claude/settings.json + hooks are
# tracked; we don't want a churny state file in git). The marker is advanced
# to the current HEAD at fire time, so the report runs exactly once per batch
# of new commits regardless of what Claude does next.
#
# Must NEVER hard-block: any failure path exits 0 (allow the Stop).

set -u

MARKER="${HOME}/.claude/.baseapp-last-status-report-head"

INPUT=$(cat)

# Loop guard: if we're already continuing because of a stop hook, let it stop.
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Resolve the project dir (fall back to cwd from the hook payload, then $PWD).
PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Current HEAD. If this isn't a git repo or git fails, do nothing.
HEAD_SHA=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
[ -z "$HEAD_SHA" ] && exit 0

LAST_SHA=""
[ -f "$MARKER" ] && LAST_SHA=$(cat "$MARKER" 2>/dev/null)

# No new commits since the last report -> nothing to do.
[ "$HEAD_SHA" = "$LAST_SHA" ] && exit 0

# Advance the marker NOW so this report fires exactly once for these commits
# and can never loop, even if the report is skipped downstream.
mkdir -p "$(dirname "$MARKER")" 2>/dev/null
printf '%s' "$HEAD_SHA" > "$MARKER" 2>/dev/null

# Block the Stop and instruct Claude to produce the report.
cat <<'JSON'
{"decision": "block", "reason": "New commits landed this session. Run the phase-status-report skill now to generate an end-of-work status report (include the Related plans section). If you already produced a status report for these exact commits in this turn, you may stop instead."}
JSON
