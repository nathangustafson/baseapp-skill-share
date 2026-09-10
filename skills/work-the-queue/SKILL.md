---
name: work-the-queue
description: Execute a pasted list of work items autonomously — plan, ask only genuinely-blocking questions, fan out sub-agents on disjoint file partitions, adversarially verify every claim, commit centrally, record an Atlas round, and report honestly including corrections. Use when the user pastes a queue of findings or open items (often from a previous status report) and says any of "queue all of this", "keep at it until everything is done", "I'll leave you to it", "when I return I expect everything resolved", "plan first and ask me questions up front", or "leverage sub agents as needed". Do NOT use for a single task, for exploratory questions, or when the user is still deciding what they want — this is for a settled list the user is walking away from.
---

# Work the queue

The user has pasted a list and left. They will judge the result by whether every item is
genuinely resolved, whether the claims survive scrutiny, and whether you told them the truth
about what you could not do.

## The shape

1. **Recon before questions.** Never ask a question you could answer by looking. Size the
   biggest item first — the answer usually changes what is worth asking.
2. **One question round, only what blocks.** Batch into a single `AskUserQuestion` (max 4).
   Ask only where different answers change the work materially. Everything else: decide, and
   say so in the kickoff message. If nothing blocks, skip the round entirely and start.
3. **Kick off, then report.** Launch the work, tell the user what is running and what you
   decided on their behalf, and note anything that will still be theirs at the end.
4. **Verify adversarially.** Every claim gets an independent skeptic.
5. **Commit centrally, record the round, report honestly.**

## Recon first — the questions get better

Sizing an item usually reframes it. Real example: a queue said "773 call sites to sweep."
A ten-minute AST scan found **zero** direct writers — a false negative caused by indirection —
but the same scan surfaced **166 untested mutating routes** in the affected modules, which was
the actual risk. The question changed from "how deep a sweep?" to "which routes do we exercise
first?", and that is a question worth the user's time.

If recon shows an item is smaller, larger, or different from how the user described it, **say
so before asking**. They queued it on your earlier summary; if that summary was wrong, the
correction is the most valuable thing in your reply.

## Sub-agent fan-out

Use `Workflow` for anything beyond ~2 items. Structure:

```
Phase 1  recon (read-only) — only where acting on a wrong premise is costly
Phase 2  build — parallel, DISJOINT file partitions
Phase 3  verify — one adversarial skeptic per claim
```

**Partition by file, explicitly.** Name each agent's files and tell it to STOP and report
rather than edit outside them. Concurrent agents in one working copy will collide otherwise.

**Sequence anything with a wide blast radius alone**, after the others — a change to an ORM
base class or a shared conftest will destabilise every other agent's test runs.

**Agents must not commit.** A parallel session may share the directory and branch. Agents
report changed paths; the orchestrator stages its own paths and commits atomically. Never
`git add -A`.

## The house rules block

Paste this into every agent prompt. It is not boilerplate — each line cost a real incident.

- **Docker only.** `docker compose run --rm --no-deps -T backend python3 -m pytest <path> -q --no-cov`.
  A PreToolUse hook blocks host Python. The hook also blocks any command whose line *starts*
  with `pip`/`python` — a commit message line beginning "pipeline" has tripped it. Write long
  text to a file and use `-F`.
- **DB safety.** `WHERE data->>'type_fk' IN (SELECT entity_id::text FROM entities ...)` combined
  with `ILIKE` or a whole-table aggregate has OOM-killed the dev Postgres. Resolve ids in Python
  first, then `= ANY(:ids)`.
- **Bare-key antipattern.** `WHERE data->>'key'='X' LIMIT 1` returns an INSTANCE, not the type —
  135 rows carry `key='tenant_user'` and one is the type. Use `find_entity_type_id`. This has
  bitten four times, including the orchestrator's own code.
- **conftest patches `flag_modified` globally.** An import inside a test body resolves at call
  time and gets the Mock; a module-level import binds the real function first. This has silently
  defeated whole test files.
- **entities.created_at is NOT NULL** — insert via the ORM, not raw INSERT. `entity_id` is uuid:
  compare with `CAST(:i AS uuid)`.
- **Tests share the dev DB.** Use throwaway data and clean up.

## The test quality bar

The recurring failure in this repo is not broken code — it is tests that pass while verifying
nothing. Require, in every agent prompt:

- **Mutation-prove headline claims.** Break the production code, confirm RED, revert, confirm
  `git diff` is EMPTY, confirm GREEN.
- **VERIFY THE MUTATION ACTUALLY APPLIED** before believing any "not caught" result. A pattern
  that matched the wrong occurrence in a large file, or did not match at all, has produced
  multiple false conclusions. Diff the file.
- **Every DENY needs a paired ALLOW.** A fence that denies everyone passes a deny-only suite
  while breaking the product.
- **Persistence assertions read through a SEPARATE session.** The writing session serves the
  mutated object from its identity map whether or not an UPDATE was emitted.
- **Never assert a value the test assigned to a mock in the same body.**
- A test that cannot be reddened by breaking the thing it names is worse than no test — the
  skip at least advertises the gap.

## The adversarial verifier

One per claim, prompted to disbelieve:

> Assume the work below is WRONG until you personally reproduce it. Be blunt; agreeableness is
> worthless here. Re-run every mutation claimed, and confirm the mutation actually changed the
> file before believing a "not caught" result. Hunt for vacuous tests among the new ones —
> sample at least 4 the agent did NOT mutation-test. Confirm nothing outside the partition was
> edited and no production file is left mutated.

A verifier that **refuses to pass work** is the most valuable result a phase can produce. When
one does, act on it before committing — do not average it against the builder's confidence.

## Closing out

1. **Run both full suites** and report exact tail lines. Baselines drift when a parallel session
   is active; reconcile the numbers rather than asserting them.
2. **Commit in logical units**, staging only your own paths.
3. **Atlas round** — `apply` → `record-round` → run the tagged suite → `reconcile` → `snapshot`.
   The tagged suite and `reconcile` MUST run in the same container: `/app/reports` is
   container-local, so a `docker compose run` suite writes outcomes `reconcile` never reads.
   Symptom: `verified=1` when you expected a dozen.
4. **Check `pm drift`** and attribute anything left to the right session.

## Reporting

Lead with what the user must act on, not with what you did.

- **State corrections first.** If something you told them earlier was wrong, that outranks the
  new work. It is the item they may have queued effort against.
- **Distinguish blocked-by-platform from awaiting-owner from deferred-by-design.** These are
  three different states and get conflated under pressure.
- **Give measured numbers, not adjectives.** "18 tests fail, all `assert None is not None`" beats
  "some tests would need updating".
- **Name what you did NOT check.** A sweep that says "I checked X, not Y" is trustworthy; one
  that implies completeness is not.
- Do not claim a clean run from a syntax-shaped detector. It is a lead list. Say so.
