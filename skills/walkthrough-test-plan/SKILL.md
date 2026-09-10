---
name: walkthrough-test-plan
description: >-
  Generate a comprehensive end-to-end test plan for a multi-persona module launch, in the
  canonical BaseApp shape — a guided runbook with N sequential personas, per-step `[ ] Pass / [ ]
  Partial / [ ] Fail` checkboxes, inline notes fields, severity-emoji findings, plus a paired
  pre-flight probe script. Use whenever the user asks for a "test plan", "walkthrough", "guided
  walkthrough", "phase X walkthrough", "acceptance walkthrough", or "end-to-end test plan" for a
  module, feature initiative, or product surface that has multiple user roles and a
  state-building flow (consumer → operator → admin). Produces TWO artifacts: a runbook markdown
  doc at `docs/runbooks/<name>_walkthrough_<YYYY-MM-DD>.md` and an audit probe script at
  `scripts/audit_<name>.py`. Reference: `docs/runbooks/<initiative>_walkthrough_<date>.md` (your
  first two runbooks become the house references). Do NOT use for single-feature acceptance
  tests, code-level unit tests, or post-mortem reports — this is specifically for "we just
  shipped a multi-surface initiative and need to walk through it end-to-end in a real browser
  before launch."
---

# Walkthrough Test Plan

The canonical BaseApp pattern for end-to-end product walkthroughs that gate launch. One pre-flight probe + one runbook doc + a triage step.

## When to produce one

- A multi-phase initiative just merged and needs a launch-gate review across multiple user roles (consumer, operator, admin).
- User asks for: "test plan", "walkthrough", "guided walkthrough", "phase X walkthrough", "acceptance walkthrough", "end-to-end test plan", or "guided review".
- The surface touches ≥3 distinct user roles or ≥2 customer-facing sites.

If it's a single-screen change or a code-level test, decline — use unit tests, integration tests, or a one-paragraph acceptance criterion instead.

## Two artifacts to produce

1. **`scripts/audit_<name>.py`** — read-only probe that programmatically verifies prerequisites before a human starts clicking. Target 15 checks. Exit code = failure count.
2. **`docs/runbooks/<name>_walkthrough_<YYYY-MM-DD>.md`** — the executable runbook. 5 personas (or 3–5 if the surface is smaller). Sequential, state-building.

Don't write the test plan into the plan file (the design lives there; the executable runbook lives in `docs/runbooks/`).

## Step 1 — Establish the four design parameters

Ask the user (or infer from context) before writing:

1. **Phase letter / short name** — e.g. "Phase 5" for one initiative, "Phase J" for another. Used in every step ID (J.A.1, 5.A.1).
2. **Personas** — 3–5 roles, in dependency order. Persona 2 must build on Persona 1's state. Default shape:
   - Persona 1: first-time consumer (cold visit → core happy path)
   - Persona 2: returning consumer (recurring use + edge cases)
   - Persona 3: alternate consumer variant OR a different consumer site (parity validation)
   - Persona 4: operator / business owner (admin of one tenant)
   - Persona 5: system admin / platform admin
3. **Critical surfaces** — list of routes/components to exercise. Pull from `App.tsx` routes + the merged commits' diff stat.
4. **The probe's 15 checks** — derive from the seeders: which entity types must exist, which seeded rows must be present, which env config (API keys, etc.) must be set.

## Step 2 — Write the audit probe

Mirror your most recent `scripts/audit_<name>.py` line by line (the template below is the canonical shape). Required elements:

```python
"""<initiative> — Phase <X> walkthrough readiness probe.

[2-3 paragraph docstring explaining what each section probes.]

Read-only — no DB writes, no Stripe calls. Safe to run anytime.

Invocation:
    docker exec -i baseapp-backend-1 python3 < scripts/audit_<name>.py
"""

from __future__ import annotations
import logging, sys
from typing import Callable, List, Tuple
from sqlalchemy import text
from src.database.core import SessionLocal

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

CheckResult = Tuple[str, bool, str]  # (label, passed, detail)

def _section(name: str, checks: List[Callable[[], CheckResult]]) -> int:
    logger.info(f"\n══ {name} ══")
    fails = 0
    for check in checks:
        label, ok, detail = check()
        marker = "✓" if ok else "✗"
        logger.info(f"  {marker}  {label}")
        if detail:
            for line in detail.splitlines():
                logger.info(f"        {line}")
        if not ok:
            fails += 1
    return fails

# ─── one section per persona group ─────────────────────────────
# Each check: def check_<thing>(db) -> CheckResult: ...
#   returns (label, ok, detail)

def main() -> int:
    db = SessionLocal()
    try:
        total_fails = 0
        total_fails += _section("X.A / X.B — <group label>", [
            lambda: check_<thing>(db), ...
        ])
        # ... more sections ...
        logger.info("\n" + "═" * 60)
        if total_fails == 0:
            logger.info("ALL CHECKS PASSED — <N>/<N> — ready for human walkthrough.")
        else:
            logger.info(f"{total_fails} CHECK(S) FAILED — fix before walking through.")
        return total_fails
    finally:
        db.close()

if __name__ == "__main__":
    sys.exit(main())
```

Each check uses the entity-model query pattern: `SELECT entity_id::text FROM entities WHERE data->>'key' = '<type_key>' LIMIT 1` for type-id resolution, then queries scoped to that type_fk.

## Step 3 — Write the runbook doc

Mirror `docs/runbooks/<initiative>_walkthrough_<date>.md` exactly. Required sections in order:

### Header

```markdown
# Phase <X> — <Initiative> guided walkthrough (<N> persona scenarios)

<1-paragraph context: what just shipped, why this walkthrough exists, what it validates.>

**How to use this runbook:**
- Work top-to-bottom — each persona builds on state from the previous (...explain the sequencing...).
- Tick the checkbox on each step.
- Drop notes inline. Screenshots optional but useful.
- After each persona, share the findings — triage into:
  fix-before-launch / fix-post-launch / capture-to-futures.

**Severity emoji legend** (matches `futures/bugs.md`):
- 🔴 **Critical** — blocking, immediate
- 🟠 **High** — significant UX impact
- 🟡 **Medium** — noticeable, has workaround
- 🟢 **Low** — cosmetic/edge case
- ✅ resolved during the session

**Pre-flight check (run once):**
\`\`\`bash
docker exec -i baseapp-backend-1 python3 < scripts/audit_<name>.py
# expected: ALL CHECKS PASSED — <N>/<N>
\`\`\`
```

### One section per persona

```markdown
## X.A — Persona 1: <role> (<context>)

<1-paragraph scope: what this persona validates, which phases/features.>

### X.A.1 — <short step name>

- [ ] Pass / [ ] Partial / [ ] Fail
- Visit: `<exact URL>`
- Verify: <concrete assertions — what user sees, what state changes>.
- Notes: ___

### X.A.2 — ...
```

Step granularity rules:
- Each step is one screen / one action. Don't bundle "fill the form AND submit AND verify success" into one step.
- Every step has: a URL or trigger, an explicit "Verify:" list of assertions, a "Notes:" placeholder.
- Cross-reference phase IDs in step text — "(F.2 wiring)", "(D.6.4)" — for traceability.
- Reference the actual component name when relevant — "<Feature>Home page", "<Feature>Paywall component".

Each persona ends with:
```markdown
**X.A acceptance**: <one-sentence gate>. <Specific pass criteria — e.g., "No 🔴 findings. ≤ 5 🟠 findings.">
```

### Persona dependency graph

Honor these in step ordering:
- Persona 1 creates the canonical user + first purchase + first artifact + first application/submission.
- Persona 2 builds on Persona 1's persona — recurring use, edge cases (depleted credits, unlimited subscription, status transitions).
- Persona 3 sets up the parity variant on a separate user (different site / different persona type).
- Persona 4 is the operator — sees the data Personas 1–3 created, exercises operator-side surfaces.
- Persona 5 is the platform admin — sees aggregate data, exercises admin/audit surfaces.

### Phase X.5 — Findings triage

```markdown
## Phase <X>.5 — Findings triage

After all <N> personas:

1. Collect all per-step Notes / Fail entries into a table:
   `<step-id> | severity | summary | proposed disposition`
2. Triage:
   - 🔴 **Launch blocker** — fix now, before public launch.
   - 🟠 **Pre-launch polish** — fix in a "Phase <X>.5 fixes" pass.
   - 🟡 **Post-launch** — capture to `futures/bugs.md` under a `## <Initiative> — Phase <X> walkthrough` section, ship in follow-up.
   - 🟢 **Cosmetic** — capture, deprioritize.
3. Re-run the <N>/<N> probe after each fix.
4. When no 🔴 / 🟠 remain unresolved, launch gates open.
```

### Branch state

```markdown
## Branch state at walkthrough start

- `<branch>` at `<commit>`, <N> commits ahead of `origin/<branch>`.
- New entities seeded by `seed_consolidated.py` Phase(s) <X>.
- Probe `scripts/audit_<name>.py` — run before each session.
- <test count> new tests landed with the merge.
```

## Sequencing recommendation in the plan section

Suggest 3–5 sessions of ~2 hours each, with fixes between sessions. Session 1 = build the probe + Persona 1. Stop, triage 🔴/🟠. Then Personas 2 → 5 spread across remaining sessions.

## Cross-cutting invariants to verify per walkthrough

Include in the verification approach section:
- **Manual parity** — every AI-driven mutation has a manual UI counterpart.
- **Unified rollback** — every mutation writes to action history; rollback works.
- **Per-user scoping** — explicit step that opens the same record as a different user to confirm private/shared boundaries hold.
- **Idempotency** — bootstrap-style endpoints called twice produce no duplicates.

## What NOT to include

- Don't include unit-test-level assertions ("function X returns Y"). The runbook is a human-driven browser exercise.
- Don't include code snippets unless they're shell commands the user runs (stripe CLI, fetch calls).
- Don't merge multiple personas into one section. Sequential state-building is the load-bearing structure.
- Don't omit the "Verify:" list on a step — bullet points only, not prose.
- Don't add an "estimated time" column per step — adds visual clutter and is always wrong.

## After producing both artifacts

Report back to the user with:
- The two file paths (runbook + probe).
- Step count per persona.
- A one-line note that the probe will fail until the prerequisites are seeded on the staging DB.
- The sequencing recommendation (which persona to run first).

Use the phase-status-report skill at the end of a walkthrough session if appropriate — the two skills compose naturally (run walkthrough → triage → status-report the disposition).
