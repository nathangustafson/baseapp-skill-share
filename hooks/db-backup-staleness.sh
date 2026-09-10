#!/bin/bash
#
# SessionStart hook: surface a reminder when the local DB backups need attention.
#
# Covers both cadences the team asked for:
#   - "weekly"          → STALE_DAYS below
#   - "before major work" → a session starting IS the start of work, so a stale
#                           backup gets flagged exactly when it still matters
#
# THREE checks, because for months this hook was green while the backup system
# was quietly broken:
#   1. AGE      — is the newest non-empty backup recent enough?
#   2. COUNT    — are there more auto-backups than retention should ever leave?
#                 This is the one that would have caught the real 2026-08 bug:
#                 backup-db.sh's prune step died on macOS bash 3.2 AFTER the dump
#                 succeeded, and with no `set -e` the script still exited 0. Age
#                 stayed green — a fresh dump was written every time — while
#                 backups/ grew ~480 MB a run and nothing was ever reclaimed.
#                 Freshness alone cannot see a prune that never runs.
#   3. SIZE     — total footprint, as a backstop for anything the count misses
#                 (hand-labelled dumps accumulating, a stray copy).
#
# Deliberately ADVISORY, never blocking. It cannot take the backup itself: a dump
# of the ~1 GB entities table inside a 512 MB Postgres container will OOM-kill the
# backend if anything else is touching the DB, so it must be a considered action,
# not a surprise at session start. scripts/backup-db.sh enforces that guard.
#
# Every uncertain path exits 0 silently — a hook that cries wolf gets ignored,
# and this one is the only thing standing between us and another 0-byte backup.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/backups"
DB_NAME="baseapp_local"
STALE_DAYS=7

# backup-db.sh keeps 3 newest + one per week-bucket x 4 = 7 at steady state.
# More than that means pruning is not completing.
EXPECT_MAX_AUTOS=7
MAX_TOTAL_GB=8

cat >/dev/null 2>&1   # drain hook JSON on stdin; we don't need it

[[ -d "$BACKUP_DIR" ]] || exit 0

# Newest NON-EMPTY backup. Size matters: backups/ has held 0-byte files that sat
# unnoticed for months (2025-12-03, 2026-04-12), and a zero-byte file must never
# read as "recently backed up".
NEWEST=""
NEWEST_MTIME=0
while IFS= read -r f; do
  [[ -s "$f" ]] || continue
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  if [[ "$m" -gt "$NEWEST_MTIME" ]]; then NEWEST_MTIME=$m; NEWEST="$f"; fi
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.dump' -o -name '*.sql' \) 2>/dev/null)

NOW=$(date +%s)

if [[ -z "$NEWEST" ]]; then
  echo "⚠️  No local database backup found in backups/. Run: ./scripts/backup-db.sh"
  exit 0
fi

# ---------------------------------------------------------------- 1. age
AGE_DAYS=$(( (NOW - NEWEST_MTIME) / 86400 ))
if [[ "$AGE_DAYS" -ge "$STALE_DAYS" ]]; then
  echo "⚠️  Newest DB backup is ${AGE_DAYS} days old ($(basename "$NEWEST"))."
  echo "    Take one before major work:  ./scripts/backup-db.sh"
  echo "    It validates the dump (TOC + entities row parity) and prunes old auto-backups."
fi

# ------------------------------------------------------- 2. prune actually ran
AUTO_COUNT=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  AUTO_COUNT=$(( AUTO_COUNT + 1 ))
done < <(ls -1 "${BACKUP_DIR}/${DB_NAME}_auto_"*.dump 2>/dev/null)

if [[ "$AUTO_COUNT" -gt "$EXPECT_MAX_AUTOS" ]]; then
  echo "⚠️  ${AUTO_COUNT} auto-backups in backups/ — retention should leave at most ${EXPECT_MAX_AUTOS}."
  echo "    Pruning is not completing. Check the exit code:  ./scripts/backup-db.sh --dry-run"
  echo "    (exit 4 = the dump succeeded but housekeeping failed)"
fi

# (A production-backup staleness check was removed from the shared copy; add one
# for your own off-box dump location if you keep one.)

# --------------------------------------------------------------- 3. footprint
TOTAL_KB=$(du -sk "$BACKUP_DIR" 2>/dev/null | cut -f1)
if [[ -n "${TOTAL_KB:-}" ]]; then
  TOTAL_GB=$(( TOTAL_KB / 1024 / 1024 ))
  if [[ "$TOTAL_GB" -ge "$MAX_TOTAL_GB" ]]; then
    echo "⚠️  backups/ is ${TOTAL_GB}GB across ${AUTO_COUNT} auto-backup(s) + hand-labelled history."
    echo "    Hand-labelled dumps are never auto-pruned — review them by hand if this keeps growing."
  fi
fi

exit 0
