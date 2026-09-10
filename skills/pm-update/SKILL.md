---
name: pm-update
description: Update the Project Map ("Atlas") — record a dev round, apply newly discovered requirements from a batch file, reconcile verified/regressed state from tagged tests, and snapshot the register into the repo. Use at the end of any dev round that changed behavior, after a test run, or when new requirements surface. Adapt the write surface to your own tracker (Jira, Azure DevOps, Linear, GitHub Issues).
---

# Update the Project Map

Keep the Project Map ("Atlas") graph current as development happens — record what
a dev round touched, capture newly-discovered requirements, and re-derive verified
status from tests. This is the **persistent development memory** for the codebase.

## The "leverage Claude" principle (read first)

**You (this session) are the intelligence.** Compose the content from your own
reasoning about the work just done — do NOT call the in-app `/project-map/agent/draft`
LLM endpoint and do NOT spawn content-generating subagents. `scripts/pm.py` is just
the write surface: it persists what you decide via the existing CRUD (idempotent,
attributed `actor=agent/claude`). Read-only Explore agents to survey code are fine;
the requirement/persona *content* must be yours.

All writes are system-tenant only and re-runnable (apply upserts by `code`).

## When to invoke

- At the end of a dev round / before wrapping a session that changed behavior.
- After running the test suite (to reconcile verified/regressed status).
- When you discover requirements that should be tracked but aren't in the map.
- Explicit: `/pm-update`.

## How to run pm.py (scripts/ is not container-mounted → pipe via stdin)

```
docker exec -i baseapp-backend-1 python3 - <cmd> [args] < scripts/pm.py
```
Batch input for `apply` goes through a MOUNTED path (write the JSON under
`docs/project-map/batches/` first), because stdin is consumed by the piped script.

## The dev-round workflow

1. **Record what changed.** For the requirements your work touched:
   ```
   docker exec -i baseapp-backend-1 python3 - record-round \
     --summary "wired billing cron + overdue marking" \
     --codes BILL-CRON-01,OP-SUB-04,CON-BILL-03 < scripts/pm.py
   ```
   Pass `--sha`/`--branch` if you know them (the backend container has no git).

2. **Capture new / changed requirements** (only if you discovered or materially
   changed scope). Write a batch to `docs/project-map/batches/<topic>.json`:
   ```json
   {"requirements": [
     {"code": "OP-REF-20", "statement": "...", "acceptance_criteria": "...",
      "objective_ref": "<existing objective code>", "persona_refs": ["operator"],
      "severity": "med", "coverage": "missing", "state": "proposed",
      "depends_on_codes": []}
   ]}
   ```
   then `apply --project <code> --file docs/project-map/batches/<topic>.json`.
   Reuse existing objective/persona codes (`pm projects` / `pm status` to see them);
   apply updates an existing code rather than duplicating.

3. **Reconcile from tests** (after the suite ran and wrote the outcomes report):
   ```
   docker exec baseapp-backend-1 python3 -m pytest src/tests/api src/tests/services -q --no-cov
   docker exec -i baseapp-backend-1 python3 - reconcile --dry-run < scripts/pm.py   # preview
   docker exec -i baseapp-backend-1 python3 - reconcile          < scripts/pm.py   # apply
   ```
   Tagging a test with `@pytest.mark.requirement("CODE")` is what lets reconcile flip
   it `verified`/`regressed`. Use the requirement detail page's "Test stub" (or the
   `/test-stub` endpoint) to scaffold a marker-tagged stub for an untested requirement.

4. **Snapshot to repo** (diffable register that travels with the branch):
   ```
   docker exec -i baseapp-backend-1 python3 - snapshot --project <code> < scripts/pm.py
   ```
   then commit `docs/project-map/requirements-snapshot-<code>-<date>.md`.

## Notes

- `pm status --project <code>` returns the buckets `phase-status-report` consumes
  (by_coverage/by_state/by_severity, effort-weighted %, launch_blockers, recent_progress).
- Everything is rollback-able: each write logs a `pm_progress_event`; the requirement
  detail UI has a per-event "Roll back".
- Manual parity is unaffected — these are the same writes the UI dialogs perform.
