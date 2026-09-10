---
name: phase-status-report
description: Generate a project status report for multi-phase initiatives (launches, migrations, refactors with named phases). Produces a single combined progress chart (item count and effort-weighted in one view), a SEPARATE deployment stage section that is never counted toward completion and carries its own cross-session Atlas coordination code, plus session-commits table, what's-left list organized by priority, newly-captured futures items, and branch state. Use this whenever the user asks for a "status report", "where are we", "progress update", or "summary report" on a project that has phases like W1.x / W2.x / Phase 0-4 or similar. Also trigger when the user wants to wrap up a coding session with a checkpoint summary, especially long sessions with multiple commits across distinct work items. Do NOT use for simple "what's done" questions on single-task work — this is for projects with structure.
---

# Phase Status Report

A focused format for reporting progress on multi-phase project initiatives — product launches, big refactors, anything with phases and item-level tracking.

## When to produce one

- End of a working session that touched multiple items across phases.
- User explicitly asks: "status report", "where are we", "progress update", "summary".
- Cumulative report across a multi-day stretch (commit log shows ≥5 commits since last summary).

## Output structure

ALWAYS use this exact section order. Skip a section only when it would be empty.

```
## <Project name> — status report

### Progress

<single combined chart: one row per phase, showing BOTH the item count and the weighted
count — and NO weight table above it; the chart already carries those numbers>

<one-line interpretation: usually "weighted matches the headline" or "weighted shifts X")

### Deployment — <stage name> (tracked separately)

<deployment chart or checklist — NEVER folded into the progress numbers above. See "Deployment is its own stage".>

### Session commits

<table of commits this session>

### Token spend

<one line + the ledger delta — see "Token spend" below. Always include it; if the
interval genuinely used no subagents, say "0 subagent tokens — all main-loop.">

### Related plans

<links to active/related plan + handoff docs, so the reader can open them in parallel>

### What's left

<priority-organized list>

### Newly captured in <futures file>

<bullet list of follow-ups captured but not on-deck>

### <Optional: heads-up section if anything load-bearing changed>

<short bullets>
```

## Token spend

The owner wants a running sense of whether subagent use is efficient — not precise
accounting. Keep this cheap: it is two numbers and one sentence, never its own
investigation.

**The ledger.** `.claude/token-ledger.jsonl`, one JSON line per report, appended at
report time. It is the durable record; the interval between the last line and now is
what you report.

```json
{"at":"2026-08-16T22:10:00Z","report":"front-door rounds","branch":"feature/x","commits":3,"subagent_tokens":597227,"workflows":1,"agents":0,"note":"4-checker adversarial verify"}
```

**Measuring the interval.** Sum what the harness already told you — do NOT spawn an
agent or run a script to find this:
- Every `Workflow` completion notification carries `subagent_tokens` (and
  `agent_count`). Sum them since the last ledger line.
- Every `Agent` completion carries its own token figure. Add those.
- Main-loop tokens are NOT directly observable. Say so once; never estimate them as
  if measured. The ledger tracks *subagent* spend, which is the part that scales
  dangerously and the part fan-out decisions actually control.

If no ledger file exists, create it and write the current interval as the first
entry, noting `"baseline":true` — the first report simply has no prior interval to
diff against.

**Reporting it.** Two lines, no table unless several workflows deserve breaking out:

```
### Token spend
~597k subagent tokens since the last report (1 workflow, 8 agents; main-loop not
measurable). Fan-out was the 8-reader recon + 4-checker verify — the verify caught
2 round-breaking defects, so the spend bought something.
```

Judge the spend, briefly and honestly. "Bought two blocking defects" and "three
agents re-read the same file" are both useful sentences. If an interval looks
wasteful, say which call was the waste — that is the whole point of tracking it.

## Chart format

Use 10-character unicode bars: `█` for filled, `░` for empty. Right-pad phase labels to a consistent width (~25 chars). Show `done / total` and percent. Add a `←` arrow with inline annotation for whatever just moved or is in flight.

```
Foundation (Phase 0):     ██████████   5 /  5    100%
Build (Phase 1):          ███████░░░   7 / 11     64%   ← W1.10 in flight
Polish — launch-blockers: ███████░░░   8 / 16     50%
Verification (3.5 A-E):   ████░░░░░░   2 /  5     40%
Cutover (Phase 4):        ░░░░░░░░░░   0 /  1      0%
                                      ──────
Critical path:                         22 / 38     58%
```

The horizontal rule before the totals line is `──────` (6 box-drawing horizontals). Aligns visually under the count column.

## Effort weighting

The unweighted view counts items equally. That hides which phases are actually heavy. The weighted view fixes this.

**Pick weights that reflect your honest read of effort per item in each phase.** Typical scale (1 = quick fix, 5 = multi-session build):

| Phase type | Suggested weight per item |
|---|---:|
| Foundation / config (mostly user clicks + small wiring) | 1 |
| Bug-fix polish (single-file edits, small UI tweaks) | 2 |
| Build (new features, multi-file frontend + backend) | 3 |
| Verification / walkthrough (user-driven, time-bound) | 2 |
| Cutover / release (high stakes, orchestration-heavy) | 5 |

These are starting points — adjust by feel. If a phase has wildly varying item sizes, you can break out items individually rather than using a flat per-phase weight.

Do the weight arithmetic in your head (or in a scratch tool call) and render ONLY the
chart. **Do not publish a weight table above it.** The chart already carries every number
the table would — items done/total, weight done/total, and the percentage — so a table
above it is the same data twice, and the reader has to look at both to learn one thing.

The chart is ONE block carrying both numbers. The bar is drawn from the WEIGHTED
percentage (that is the honest read of remaining effort); the item count rides alongside it.

```
Foundation (Phase 0):     ██████████   5 /  5 items    5 /  5 wt   100%
Build (Phase 1):          ██████████  11 / 11 items   33 / 33 wt   100%
Polish — launch-blockers: ███████░░░   8 / 16 items   22 / 32 wt    69%
Verification (3.5 A-E):   ██████░░░░   3 /  5 items    6 / 10 wt    60%
Cutover (Phase 4):        ░░░░░░░░░░   0 /  1 items    0 /  5 wt     0%
                                      ──────────────────────────
Critical path:                        27 / 38 items   66 / 85 wt    78%
```

DO NOT render two separate charts, and DO NOT precede the chart with a weight table.
Both were corrected by the owner for the same reason, a year apart in skill-versions:
an earlier version emitted an unweighted chart followed by a weighted chart with the
same rows, and a later one put the full weight table directly above the chart that
restates it. Each time the reader had to cross-reference two renderings to extract one
fact. **One chart. Both columns. The interpretation line carries the comparison.**

If a phase genuinely needs its arithmetic shown — an unusual weight that a reader would
otherwise dispute — justify it in the interpretation line in prose, not by reinstating
the table.

End the section with one line interpreting the delta: usually one of
- "Weighted matches the headline" (unweighted and weighted are close)
- "Weighted shifts X" (e.g., "the remaining 21% is concentrated in one heavy item")
- "Weighted reveals X is bigger than it looked" (or smaller)

## Deployment is its own stage — NEVER inside the progress numbers

Deployment does not count toward completion. It is a separate stage that begins after
the local gate closes, and it gets its own section, its own checklist, and its own
Atlas code.

**Why this is a rule and not a preference.** Folding deploy steps into the main chart
does two harmful things at once. It makes the project look less finished than it is
(prod steps sit at 0% while the actual work is done), and it makes "done" mean
"deployed", which pressures a release before local verification has closed. The owner
corrected exactly this on 2026-08-14: prod migrations had been listed as owner tasks
alongside local test-mode work, and the reply was — *"the deployment should sit outside
of the 100% unless it is part of the planned work"*.

**Sort every remaining item into one of two buckets, and say which is which:**

| Bucket | Contains | Counts toward 100%? |
|---|---|---:|
| **Local** | Anything verifiable on dev: code, tests, front-door validation, **test-mode** payment flows, browser walkthroughs | **Yes** |
| **Deployment** | Anything touching prod or a release pipeline: prod migrations, the CD pipeline run, post-deploy prod passes, DNS/secret cutover | **No** |

The trap is **test-mode payment work**. Driving Stripe Connect and a first invoice in
TEST mode on a dev site is LOCAL — it is verification, not release — even though it
feels release-shaped and the same person does it. Sort by *which environment it
touches*, not by who does it or how final it feels.

If the deployment genuinely IS the planned work (a migration project whose deliverable
is the cutover), say so explicitly in one line and then it may be a phase — but it
still gets its own Atlas code per below.

### Deployment ALWAYS gets an Atlas code

A deploy aggregates work from every session that contributed to the branch, so it
cannot be tracked inside any one session's requirement. Create (or reuse) a
deployment-coordination code and reference it in the report.

- One code per deployment, e.g. `DEPLOY-<initiative>-<YYYY-MM-DD>`.
- Its `depends_on_codes` lists the requirement codes the deploy is shipping — that is
  the cross-session manifest, and it is the thing that makes "are we ready?" answerable
  without polling three humans.
- It stays `proposed` until every dependency is `verified` and the local gate is
  closed; only then is the deploy cleared to run.
- The report's deployment section names the code and shows its blocking dependencies.

**Cross-session coordination is the whole point.** With parallel sessions on one
branch, no single agent can see everyone's remaining work, and asking each session
"are you done?" produces three confident answers and no shared truth. `pm drift`
across all projects is the objective readout; the deployment code is where that
readout is anchored. Before reporting a deploy as ready, run the drift check and
report the actual result — including work belonging to sessions that are not yours.

### Rendering it

```
### Deployment — DEPLOY-INIT-A-2026-08-15 (separate stage, not counted above)

Blocked by 2 unverified dependencies:
  INIT-A-HANDOFF-ESCALATION-02          regressed   ← CRIT, in flight
  INIT-B-VOCAB-FREEZE-01                regressed

  [ ] 6 prod migrations        (docs/runbooks/...)
  [ ] CD pipeline run          (<your CD pipeline>)
  [ ] post-deploy prod delta   (29 items)
```

State plainly whether the gate is open or closed. "Deploy is cleared" and "deploy is
blocked by N codes" are both useful; "deploy is 40% done" is not, because a partially
executed deploy is a rollback conversation, not a progress bar.

## Session commits table

Pull from `git log --oneline <session-start-ref>..HEAD`. Include short hash + scope-flagged subject. Cap at the commits from THIS session — if you reported the last session's commits already, don't repeat.

```
| Commit | Item |
|---|---|
| `0ec478e9` | W1.10 — canonical consumer subscribe URL |
| `6bfbda3b` | WL-config helper tenant-by-slug fallback (partial W2.20) |
| ... |
```

Keep the right column terse — the project's work-item ID + a 4–8 word descriptor. Reader will git-show for detail.

End with branch state: `Branch is N commits ahead of origin`, unpushed status if relevant.

## Related plans

Always include this section when any active or related plan exists, so the reader can pull the full plan up alongside the report and review in parallel. A status report is a summary; the plan is the source of truth for scope, and the reader often wants both open at once.

**Where to look** (scan these, link whatever is relevant to the work this session touched):
- `.claude/plans/` — active plan scratch space (project-local)
- `~/.claude/plans/` — named long-form plan files (e.g. the `*-<adjective>-<noun>.md` ones referenced from memory)
- `docs/plans/` — handoff + cold-start guides (e.g. `HANDOFF-*.md`)
- `futures/` — the futures file(s) for deferred scope, if a phase maps to one
- Any plan path called out in `MEMORY.md` / project memory as the canonical plan for the module in flight

**How to render.** Markdown links with the repo-relative path as the href (clickable in the terminal), one per line, each with a 4–10 word descriptor of what it covers and — if known — how current it is:

```
### Related plans
- [docs/plans/HANDOFF-2026-06-09.md](docs/plans/HANDOFF-2026-06-09.md) — cold-start guide; §7 (doubled-nav) now done
- [~/.claude/plans/<named-plan-file>.md](~/.claude/plans/<named-plan-file>.md) — IntegrationRegistry migration waves
- [futures/migrated-plans-2026-04-22.md](futures/migrated-plans-2026-04-22.md) — deferred / unbuilt scope backlog
```

Mark a plan `*(stale)*` if the report's progress has clearly outrun it, and `*(active)*` for the one currently driving the work. If you genuinely find no plan, handoff, or futures file related to the session, write a single line — `No active plan file found for this work.` — rather than omitting the section silently, so the reader knows you looked.

## What's left

Organize by priority using these colored bullets:

- 🔴 **Critical** — blocking, in-flight, or actively broken
- 🟠 **High** — important for the next milestone
- 🟡 **Medium** — known but not urgent
- ⚫ **Cutover / release-gated** — depends on everything above

Inside each tier, group by phase. Sub-bullets list the actual items with short context:

```
**🟠 Phase 2 launch-blockers (5 remaining of 16)**
- W2.5 — `trial_days` per-product field
- W2.10 — pre-checkout email-verify OTP *(possibly obviated by W1.10's flow)*
- W2.12 — operator notification emails + delivery preferences
- W2.14 — multi-step consumer purchase flow (modifiers/add-ons)
- W2.17 — add-on items separate from subscription plans

**🟡 Phase 3.5 verification (2 remaining — user-driven)**
- 3.5.D — business-owner experience walkthrough
- 3.5.E — reorder + adjust + notifications walkthrough
```

Use italic *(parens)* for caveats that affect priority (deferred, obviated, blocked-on-X).

## Newly captured in futures

When the session uncovered work that should be tracked but isn't on-deck, list it separately from "what's left". This keeps "what's left" focused on real plate-cleaners. Use the same colored bullet system. Include a short identifier so the reader can find the full entry in the futures file.

```
### Newly captured in `futures/bugs.md`
- 🟠 **Lock critical pages from delete/archive** with per-block edit gating + admin override
- 🟠 **WL profile-page lobby content** — active subscriptions / upcoming deliveries / invoices
- 🟡 **Timestamp / tz-aware audit** — three instances fixed; systematic grep recommended
- 🔴 → 🟢 **Queue-agent re-send loop** — fixed; pattern documented for future similar bugs
```

The `🔴 → 🟢` notation flags items that were resolved during this session — useful contrast against ones that landed for triage.

## Heads-up section (optional)

Only include if something load-bearing changed that the user needs to know going in:

- Configuration the user must update before next session
- Containers that should stay stopped / started
- Migrations that ran
- Data state that changed in non-obvious ways

Keep tight — 2–4 bullets max. If there's nothing weight-bearing, omit the section entirely. The status report shouldn't bury the lede.

## What NOT to include

- Long commit diffs or file lists — the table is enough; reader will git-show
- Reasoning behind decisions — that lives in commit messages
- Repeating known facts ("Phase 0 is the foundation phase") — context shorthand is fine; expository prose is not
- Speculation about future scope creep — stick to what's tracked
- Apologies, hedges, or "I think this should..." — be assertive about the state
