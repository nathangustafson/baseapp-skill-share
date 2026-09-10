#!/bin/bash
#
# Stop hook: nudge to record this session's behavior-changing commits into the
# Project Map ("Atlas") before stopping, so work can't silently ship invisible to
# the persistent development memory (as an entire initiative did on
# 2026-06-23 — see CLAUDE.md "Project Map (Atlas)").
#
# Fires (blocks the Stop so Claude runs /pm-update) only if ALL of:
#   - this Stop is NOT already a continuation of a prior stop hook
#     (stop_hook_active guard — prevents an infinite loop), AND
#   - HEAD moved since we last evaluated (real new commits this stretch), AND
#   - the new commits include a feat(...)/fix(...) that changes behavior
#     (chore/docs/ci/refactor/test are exempt), AND
#   - NO actor=agent pm_progress_event (a dev_round) is newer than the oldest
#     of those new commits (i.e. they were never record-round'ed).
#
# Mirrors auto-status-report.sh: advances its marker at evaluation time so it
# nags at most once per batch of commits, and NEVER hard-blocks — every
# can't-determine path exits 0 (allow the Stop) to avoid false nags.

set -u

MARKER="${HOME}/.claude/.baseapp-last-pm-coverage-head"
CONTAINER="baseapp-postgres-1"
DB_USER="${DB_USER:-postgres}"
DB_NAME="baseapp_local"

INPUT=$(cat)

# Loop guard: if we're already continuing because of a stop hook, let it stop.
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

HEAD_SHA=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
[ -z "$HEAD_SHA" ] && exit 0

LAST_SHA=""
[ -f "$MARKER" ] && LAST_SHA=$(cat "$MARKER" 2>/dev/null)
[ "$HEAD_SHA" = "$LAST_SHA" ] && exit 0

# Range of new commits since last evaluation.
if [ -n "$LAST_SHA" ] && git -C "$PROJECT_DIR" cat-file -e "$LAST_SHA" 2>/dev/null; then
  RANGE="${LAST_SHA}..${HEAD_SHA}"
else
  # No valid marker (first run / rebased): bound the window to recent history.
  BASE=$(git -C "$PROJECT_DIR" rev-parse "HEAD~20" 2>/dev/null)
  if [ -n "$BASE" ]; then RANGE="${BASE}..${HEAD_SHA}"; else RANGE="$HEAD_SHA"; fi
fi

# Behavior-changing commits = feat(/fix( subjects in range (exclude chore/docs/ci/refactor/test).
SUBJECTS=$(git -C "$PROJECT_DIR" log --no-merges --pretty=%s "$RANGE" 2>/dev/null)
BEHAVIOR=$(printf '%s\n' "$SUBJECTS" | grep -E '^(feat|fix)(\(|:)' )

# Advance the marker now so we evaluate each batch at most once (never loop).
mkdir -p "$(dirname "$MARKER")" 2>/dev/null
printf '%s' "$HEAD_SHA" > "$MARKER" 2>/dev/null

# No behavior-changing commits in this batch -> nothing to record.
[ -z "$BEHAVIOR" ] && exit 0

# Reconcile-enforcement (stronger than the record-round check below). Codes whose
# @pytest.mark.requirement test was ADDED/changed in this batch must reach state=verified:
# record-round only logs the round, it does NOT advance state — only `reconcile` does. This
# catches "wrote the test, skipped reconcile" (exactly how the commerce go-live set sat at
# `proposed` for weeks). `pm drift --fail` exits 2 only when an in-scope code is unverified;
# anything else (clean, container down, no pm.py) falls through to the record-round check.
SESSION_CODES=$(git -C "$PROJECT_DIR" diff "$RANGE" -- src/tests 2>/dev/null \
  | grep -E '^\+' \
  | grep -oE 'requirement\(["'"'"'][A-Z][A-Z0-9-]*-[0-9]+' \
  | grep -oE '[A-Z][A-Z0-9-]*-[0-9]+' | sort -u | paste -sd, -)
if [ -n "$SESSION_CODES" ] && [ -f "$PROJECT_DIR/scripts/pm.py" ]; then
  docker exec -i baseapp-backend-1 python3 - drift --codes "$SESSION_CODES" --fail \
    < "$PROJECT_DIR/scripts/pm.py" >/dev/null 2>&1
  if [ "$?" -eq 2 ]; then
    cat <<'JSON'
{"decision": "block", "reason": "This session added @pytest.mark.requirement tests for code whose Atlas state is still not `verified`. record-round logs the round but does NOT advance state — only `reconcile` does, and it looks skipped (this is exactly how the commerce go-live set sat at `proposed` for weeks). Run the tagged suite, then `pm reconcile` (the /pm-update flow). List them with: docker exec -i baseapp-backend-1 python3 - drift --codes <session codes> < scripts/pm.py"}
JSON
    exit 0
  fi
fi

# Oldest new commit's UNIX timestamp (committer date) — the floor for the window fallback.
OLDEST_CT=$(git -C "$PROJECT_DIR" log --pretty=%ct "$RANGE" 2>/dev/null | tail -1)
[ -z "$OLDEST_CT" ] && exit 0   # can't determine -> don't false-nag

# Freshness compares against the SESSION WINDOW, not the new commits' own timestamps.
# Window start = the commit that was HEAD at our last evaluation ($LAST_SHA, captured
# before the marker advanced), so ANY agent dev_round since then counts — including one
# recorded just BEFORE these commits, which is the normal record-round-then-commit order.
# (Comparing against OLDEST_CT false-fired on that order: the round predates the commit.)
# Falls back to the range base, then to a day's grace before the oldest commit.
if [ -n "$LAST_SHA" ] && git -C "$PROJECT_DIR" cat-file -e "$LAST_SHA" 2>/dev/null; then
  WINDOW_REF="$LAST_SHA"
else
  WINDOW_REF=$(git -C "$PROJECT_DIR" rev-parse "${HEAD_SHA}~20" 2>/dev/null)
fi
WINDOW_START_CT=$(git -C "$PROJECT_DIR" log -1 --pretty=%ct "$WINDOW_REF" 2>/dev/null)
[ -z "$WINDOW_START_CT" ] && WINDOW_START_CT=$((OLDEST_CT - 86400))

# Was an agent dev_round recorded within this session window? (DB is in Docker.)
FRESH_RAW=$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c \
  "SELECT 1 FROM entities e JOIN entities ty ON ty.entity_id::text = e.data->>'type_fk' \
   WHERE ty.data->>'key' = 'pm_progress_event' \
     AND e.data->>'actor_type' = 'agent' \
     AND extract(epoch from e.created_at) > ${WINDOW_START_CT} LIMIT 1;" 2>/dev/null)
PSQL_RC=$?
# Can't reach the DB (container down, etc.) -> can't determine coverage -> allow stop.
[ "$PSQL_RC" -ne 0 ] && exit 0
FRESH=$(printf '%s' "$FRESH_RAW" | tr -d '[:space:]')
[ "$FRESH" = "1" ] && exit 0   # coverage recorded -> allow stop.

# Behavior-changing commits with no fresh Atlas dev_round -> nudge.
cat <<'JSON'
{"decision": "block", "reason": "feat/fix commits landed this session but no Project Map (Atlas) dev_round was recorded for them — they'd ship invisible to the persistent development memory. Run the /pm-update flow before stopping: apply any new pm_requirement codes from a docs/project-map/batches/<initiative>.json (apply --project baseapp --file ...), then record-round --codes <codes> --branch <branch> via scripts/pm.py. Pure chore/docs/ci/refactor commits are exempt. If you already recorded a round for these exact commits, you may stop."}
JSON
