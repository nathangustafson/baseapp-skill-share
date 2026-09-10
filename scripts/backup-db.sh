#!/bin/bash
#
# Dump the local Postgres, PROVE the dump is restorable, then prune old auto-backups.
#
# Why this exists rather than a bare `pg_dump`:
#
#   1. `pg_dump` exiting 0 is not proof of a good backup, and neither is a
#      plausible file size. On 2026-07-31 a dump exited 1 partway through the
#      `entities` COPY and still left a 184 MB file on disk that looked fine.
#      backups/ also held two 0-byte files (2025-12-03, 2026-04-12) — silent
#      failures nobody noticed until we went looking. Both were pruned 2026-08-28.
#   2. Verifying a custom-format archive needs a SEEKABLE file. Piping it to
#      `pg_restore --list /dev/stdin` fails with "did not find magic string in
#      file header" for a PERFECTLY GOOD dump, so that check reports corruption
#      that isn't there — and, worse, would look identical for one that is.
#   3. Pruning must never run before the new backup is validated, or a bad run
#      deletes good history and leaves you with nothing. Same for --restore-test:
#      if the new dump does not restore, the old ones are all you have.
#   4. READABLE IS NOT RESTORABLE, and until 2026-08-28 nothing here had ever
#      restored a backup. TOC + row parity prove the archive is intact; they say
#      nothing about whether it comes back. These dumps carry `EXTENSION vector`,
#      and CREATE EXTENSION is exactly what fails against a target that is not
#      byte-identical to this container — which is the target you would really be
#      restoring to. `--restore-test` is the only check that answers it.
#   5. A failure AFTER validation used to be invisible. There is no `set -e`, and
#      the prune step runs after the last statement that can change the exit
#      code, so on macOS bash 3.2 `mapfile: command not found` still exited 0
#      while pruning silently never ran and backups/ grew ~480 MB a run.
#      Housekeeping failures now exit 4 — the backup is good, the reclaim is not.
#
# Usage:
#   scripts/backup-db.sh                        # dump + validate + prune
#   scripts/backup-db.sh --label predeploy      # hand-labelled; never auto-pruned
#   scripts/backup-db.sh --keep 5               # retain N newest auto-backups (default 3)
#   scripts/backup-db.sh --weeks 6              # ...plus one per week-bucket (default 4)
#   scripts/backup-db.sh --no-prune             # dump + validate only
#   scripts/backup-db.sh --prune-empty          # additionally delete 0-byte files
#   scripts/backup-db.sh --restore-test         # also restore the new dump into a scratch DB
#   scripts/backup-db.sh --restore-test-file F  # restore-test an EXISTING backup; no new dump
#   scripts/backup-db.sh --dry-run              # show what pruning WOULD remove
#
# Exit codes:
#   0  ok
#   1  dump failed
#   2  validation failed (archive unreadable or short)
#   3  preconditions failed
#   4  backup is GOOD but housekeeping failed — old history was not reclaimed
#   5  restore test failed — the archive reads clean but does not come back

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/backups"
PG_CONTAINER="baseapp-postgres-1"
BACKEND_CONTAINER="baseapp-backend-1"
DB_USER="${DB_USER:-postgres}"
DB_NAME="baseapp_local"
SCRATCH_DB="${DB_NAME}_restoretest"

KEEP=3
WEEKS=4
LABEL="auto"
DO_PRUNE=1
PRUNE_EMPTY=0
RESTORE_TEST=0
RESTORE_TEST_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    --weeks) WEEKS="$2"; shift 2 ;;
    --no-prune) DO_PRUNE=0; shift ;;
    --prune-empty) PRUNE_EMPTY=1; shift ;;
    --restore-test) RESTORE_TEST=1; shift ;;
    --restore-test-file) RESTORE_TEST_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 3 ;;
  esac
done

say() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; }

RC=0                       # 0 unless housekeeping fails; see exit codes above
SCRATCH_CREATED=0
STAGED_FILES=""

cleanup() {
  local p
  for p in $STAGED_FILES; do
    docker exec "$PG_CONTAINER" rm -f "$p" >/dev/null 2>&1 || true
  done
  if [[ "$SCRATCH_CREATED" -eq 1 ]]; then
    docker exec "$PG_CONTAINER" dropdb -U "$DB_USER" --if-exists "$SCRATCH_DB" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------------- helpers

# 20260828T193100Z -> 2026-W35. Falls back to a per-DAY bucket if date(1) cannot
# parse it, which retains MORE rather than less — the safe direction to fail.
week_bucket() {
  local d="${1:0:8}"
  date -j -f '%Y%m%d' "$d" +'%G-W%V' 2>/dev/null \
    || date -d "$d" +'%G-W%V' 2>/dev/null \
    || printf 'day-%s' "$d"
}

# Retention is GENERATIONAL, not keep-N-newest. Keep-N alone carries no time
# diversity: on 2026-08-28 three of four auto-backups were same-day, so three
# default runs after one bad afternoon — a destructive migration, a stray
# seeder, the suite writing to baseapp_local — would have put the damage in
# every surviving slot. Policy: the KEEP newest, PLUS the newest member of each
# of the WEEKS most recent distinct week-buckets.
#
# Ordering is by the UTC timestamp IN THE FILENAME, never mtime. `ls -t` was
# wrong here: docker cp, a restore, touch, rsync and Time Machine all rewrite
# mtime, and "keep the 3 newest" would then keep the wrong three. The names are
# fixed-width ISO, so a plain lexicographic reverse sort IS newest-first.
prune_autos() {
  local all=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    all+=("$f")
  done < <(ls -1 "${BACKUP_DIR}/${DB_NAME}_auto_"*.dump 2>/dev/null | sort -r)

  local n=${#all[@]}
  if [[ $n -eq 0 ]]; then
    say "  no auto-backups present — nothing to prune"
    return 0
  fi

  local keep_reason=()
  local seen=""
  local buckets=0
  local i=0 f ts b
  while [[ $i -lt $n ]]; do
    f="${all[$i]}"
    ts="$(basename "$f")"; ts="${ts##*_auto_}"; ts="${ts%.dump}"
    b="$(week_bucket "$ts")"
    if [[ $i -lt $KEEP ]]; then
      keep_reason[$i]="newest ${KEEP}"
    elif [[ "$seen" != *"|${b}|"* && $buckets -lt $WEEKS ]]; then
      keep_reason[$i]="weekly ${b}"
    else
      keep_reason[$i]=""
    fi
    if [[ "$seen" != *"|${b}|"* ]]; then
      seen="${seen}|${b}|"
      buckets=$(( buckets + 1 ))
    fi
    i=$(( i + 1 ))
  done

  local removed=0 failed=0 sz
  i=0
  while [[ $i -lt $n ]]; do
    f="${all[$i]}"
    sz="$(du -h "$f" 2>/dev/null | cut -f1)"
    if [[ -n "${keep_reason[$i]}" ]]; then
      say "  keep    $(basename "$f") (${sz})  [${keep_reason[$i]}]"
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      say "  WOULD remove $(basename "$f") (${sz})"
    elif rm -f "$f" 2>/dev/null; then
      say "  removed $(basename "$f") (${sz})"
      removed=$(( removed + 1 ))
    else
      fail "could not remove $(basename "$f")"
      failed=$(( failed + 1 ))
    fi
    i=$(( i + 1 ))
  done

  say "  retention: ${KEEP} newest + 1 per week-bucket x ${WEEKS}; removed ${removed}"
  [[ $failed -eq 0 ]]
}

prune_empties() {
  local failed=0 f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ "$DRY_RUN" -eq 1 ]]; then
      say "  WOULD remove 0-byte backup: $(basename "$f")"
    elif rm -f "$f" 2>/dev/null; then
      say "  removed 0-byte backup: $(basename "$f")"
    else
      fail "could not remove $(basename "$f")"; failed=$(( failed + 1 ))
    fi
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -size 0 2>/dev/null)
  [[ $failed -eq 0 ]]
}

# The only check that proves a backup COMES BACK. Restores into a scratch
# database in the same container, asserts the data landed, then drops it.
# Expensive by nature — opt-in, meant for a weekly run, not every dump.
restore_test() {
  local src="$1"
  local expect="${2:-}"

  say "→ restore test: $(basename "$src") → ${SCRATCH_DB}"

  # A dropdb pointed at the wrong name would destroy the dev database. Two
  # independent fences, because one typo in SCRATCH_DB should not be enough.
  if [[ "$SCRATCH_DB" == "$DB_NAME" || "$SCRATCH_DB" != *_restoretest ]]; then
    fail "refusing to restore-test into '${SCRATCH_DB}' — not a scratch name"
    return 1
  fi

  # A restore that fills the volume would take the REAL database down with it.
  local avail_kb need_kb
  avail_kb=$(docker exec "$PG_CONTAINER" bash -c "df -Pk /var/lib/postgresql/data | tail -1 | awk '{print \$4}'" 2>/dev/null | tr -d '[:space:]')
  need_kb=$(( $(du -k "$src" | cut -f1) * 4 ))
  if [[ -n "$avail_kb" && "$avail_kb" -lt "$need_kb" ]]; then
    fail "not enough free space in $PG_CONTAINER: need ~$(( need_kb / 1024 ))MB, have $(( avail_kb / 1024 ))MB"
    return 1
  fi

  local staged="/tmp/restoretest_$$.dump"
  if ! docker cp "$src" "${PG_CONTAINER}:${staged}" >/dev/null 2>&1; then
    fail "could not stage $(basename "$src") into $PG_CONTAINER"; return 1
  fi
  STAGED_FILES="$STAGED_FILES $staged"

  docker exec "$PG_CONTAINER" dropdb -U "$DB_USER" --if-exists "$SCRATCH_DB" >/dev/null 2>&1 || true
  if ! docker exec "$PG_CONTAINER" createdb -U "$DB_USER" "$SCRATCH_DB" >/dev/null 2>&1; then
    fail "could not create scratch database ${SCRATCH_DB}"; return 1
  fi
  SCRATCH_CREATED=1

  local rerr="/tmp/restoretest_$$.err"
  STAGED_FILES="$STAGED_FILES $rerr"
  docker exec "$PG_CONTAINER" bash -c \
    "pg_restore -U '$DB_USER' -d '$SCRATCH_DB' --no-owner --no-acl '$staged' 2>'$rerr'" >/dev/null 2>&1
  local errs
  errs=$(docker exec "$PG_CONTAINER" bash -c "grep -c 'error:' '$rerr' 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
  if [[ "${errs:-0}" -gt 0 ]]; then
    fail "pg_restore reported ${errs} error(s):"
    docker exec "$PG_CONTAINER" bash -c "grep 'error:' '$rerr' | head -5" 2>/dev/null | sed 's/^/    /' >&2
    return 1
  fi

  # Restored, but did the DATA arrive? An empty restore exits 0.
  local got
  got=$(docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$SCRATCH_DB" -tAc \
    "SELECT count(*) FROM entities;" 2>/dev/null | tr -d '[:space:]')
  if [[ -z "${got:-}" || "${got:-0}" -lt 1 ]]; then
    fail "restored database has no entities rows (got='${got:-}')"; return 1
  fi

  # pgvector is the reason this check exists — see note 4.
  local ext
  ext=$(docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$SCRATCH_DB" -tAc \
    "SELECT extname FROM pg_extension WHERE extname = 'vector';" 2>/dev/null | tr -d '[:space:]')
  if [[ "$ext" != "vector" ]]; then
    fail "pgvector extension did NOT restore — a vector column would be unusable"
    return 1
  fi

  if [[ -n "$expect" && "$got" != "$expect" ]]; then
    fail "restored entities=${got} but expected ${expect}"; return 1
  fi

  say "  restored entities: ${got}   pgvector: present"
  say "  RESTORABLE ✓"
  return 0
}

# ---------------------------------------------------------------- preconditions
if ! docker ps --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  fail "$PG_CONTAINER is not running"; exit 3
fi

# A dump of a ~1 GB table inside a 512 MB Postgres container will OOM-kill the
# backend if the suite is also hammering it — that is exactly how the 184 MB
# truncated file happened. Refuse rather than produce a corrupt backup.
if docker exec "$BACKEND_CONTAINER" bash -c 'ps -eo args 2>/dev/null | grep -q "[m] pytest"' 2>/dev/null; then
  fail "pytest is running in $BACKEND_CONTAINER — a concurrent dump risks OOM-killing Postgres. Wait for it to finish."
  exit 3
fi

mkdir -p "$BACKUP_DIR"

# ------------------------------------------------- restore-test an OLD backup
# Standalone mode: no dump, no prune. This is how you audit stored history.
if [[ -n "$RESTORE_TEST_FILE" ]]; then
  if [[ ! -s "$RESTORE_TEST_FILE" ]]; then
    fail "no such backup (or empty): $RESTORE_TEST_FILE"; exit 3
  fi
  restore_test "$RESTORE_TEST_FILE" || exit 5
  exit 0
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/${DB_NAME}_${LABEL}_${TS}.dump"

# ---------------------------------------------------------------------- dump
say "→ dumping ${DB_NAME} → $(basename "$OUT")"
if ! docker exec -i "$PG_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" \
      -Fc --no-owner --no-acl > "$OUT" 2>"${OUT}.err"; then
  fail "pg_dump exited non-zero"
  sed 's/^/    /' "${OUT}.err" | head -5 >&2
  rm -f "$OUT" "${OUT}.err"          # never leave a half-written file behind
  exit 1
fi
if [[ -s "${OUT}.err" ]]; then
  say "  pg_dump stderr (non-fatal):"; sed 's/^/    /' "${OUT}.err" | head -3
fi
rm -f "${OUT}.err"

if [[ ! -s "$OUT" ]]; then
  fail "dump is empty"; rm -f "$OUT"; exit 1
fi
say "  wrote $(du -h "$OUT" | cut -f1)"

# ------------------------------------------------------------------ validate
# Copy into the container so pg_restore reads a real, seekable path (see note 2).
say "→ validating"
VERIFY="/tmp/verify_$$.dump"
STAGED_FILES="$STAGED_FILES $VERIFY"

if ! docker cp "$OUT" "${PG_CONTAINER}:${VERIFY}" >/dev/null 2>&1; then
  fail "could not stage dump into $PG_CONTAINER for validation"; exit 2
fi

TOC_COUNT=$(docker exec "$PG_CONTAINER" bash -c \
  "pg_restore --list '$VERIFY' 2>/dev/null | grep -c '^[0-9]'" 2>/dev/null || echo 0)
if [[ "${TOC_COUNT:-0}" -lt 1 ]]; then
  fail "archive header/TOC unreadable — dump is NOT restorable"
  rm -f "$OUT"; exit 2
fi
say "  TOC entries: ${TOC_COUNT}"

# Row-count parity on the biggest table: proves the DATA is complete, not merely
# that a header parsed. A truncated dump lists fine but comes up short here.
LIVE=$(docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT count(*) FROM entities;" 2>/dev/null | tr -d '[:space:]')
DUMPED=$(docker exec "$PG_CONTAINER" bash -c \
  "pg_restore --data-only --table=entities -f - '$VERIFY' 2>/dev/null | grep -c '^[0-9a-f]\{8\}-'" 2>/dev/null || echo 0)

if [[ -z "${LIVE:-}" || "${DUMPED:-0}" -lt 1 ]]; then
  fail "could not compare entities row counts (live='${LIVE:-}' dumped='${DUMPED:-0}')"
  rm -f "$OUT"; exit 2
fi
if [[ "$DUMPED" != "$LIVE" ]]; then
  # Rows legitimately drift if something writes mid-dump; a SHORTFALL beyond a
  # small delta means truncation. Treat any shortfall >1% as a failure.
  DELTA=$(( LIVE - DUMPED )); [[ $DELTA -lt 0 ]] && DELTA=$(( -DELTA ))
  if [[ $(( DELTA * 100 )) -gt $LIVE ]]; then
    fail "entities row mismatch: dumped=${DUMPED} live=${LIVE} (delta ${DELTA})"
    rm -f "$OUT"; exit 2
  fi
  say "  entities rows: dumped=${DUMPED} live=${LIVE} (delta ${DELTA}, within tolerance)"
else
  say "  entities rows: ${DUMPED} == live ${LIVE}"
fi
say "  VALIDATED ✓"

# --------------------------------------------------------------- restore test
# Before pruning, per note 3: if the new dump does not come back, the old ones
# are the only history there is.
if [[ "$RESTORE_TEST" -eq 1 ]]; then
  if ! restore_test "$OUT" "$DUMPED"; then
    fail "restore test failed — KEEPING all existing backups, nothing pruned"
    exit 5
  fi
fi

# --------------------------------------------------------------------- prune
# Only ever prunes files this script created (…_auto_…). Hand-labelled backups
# (predeploy, pre_commerce_work, prod_*) are history someone chose to keep.
if [[ "$PRUNE_EMPTY" -eq 1 ]]; then
  prune_empties || RC=4
fi

if [[ "$DO_PRUNE" -eq 1 ]]; then
  say "→ pruning auto-backups (keep ${KEEP} newest + 1 per week x ${WEEKS})"
  prune_autos || RC=4
fi

if [[ "$RC" -ne 0 ]]; then
  fail "backup is GOOD but housekeeping failed — old backups were not reclaimed"
  say "✓ backup complete (housekeeping incomplete): $OUT"
  exit "$RC"
fi

say "✓ backup complete: $OUT"
exit 0
