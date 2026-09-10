---
name: frontdoor-test
description: Plan and execute a FRONT-DOOR VALIDATION — exercising a capability only through the product's own screens as a real least-privilege user would, with no seeders, no scripts, no SQL, and no UI-bypassing API calls, where every step that cannot be completed front-door is filed as its own gap requirement. Use when the user says "front-door test", "frontdoor validation", "front-door validation", "stand it up through the screens", "prove an operator can do this unaided", or asks to onboard/configure/migrate something "the way a real operator/customer would". Do NOT use for a seeded-state guided walkthrough (walkthrough-test-plan), a go/no-go capability assessment (launch-readiness), or a code-level bug hunt (/code-review) — this skill's product is the enumeration of what the PRODUCT cannot do through its own front door.
---

# Front-door test

## What front-door validation is

**Front-door validation** (owner's term, coined 2026-08-03): exercising a capability only
through the product's own screens, as a real operator or customer would — no seeders, no
scripts, no SQL, no API calls that bypass the UI. Contrast: **back-door**. A back-door change
proves the DATA can change; a front-door one proves the PRODUCT can change it, which is the
only way to find missing buttons, wrong permissions, dead routes, and absent notifications.

Track record (why this earns its cost):
- Driving real screens found two launch blockers a 16-agent static review missed entirely
  (the legal-acceptance gate crashing the operator console; the guided location editor
  silently overwriting unlimited capacity with an invented default).
- A page that 403s for every genuine operator stayed hidden in dev because all three seeded
  operator accounts happened to be system_admin.
- The Initiative A schedule-migration exercise's most valuable deliverable was a screen that does NOT
  exist (filed as its own requirement code) — the absence was the finding.

The purpose is never the configured state — a seeder could produce that in seconds. The
purpose is the enumeration of every place the product cannot do it unaided.

## The laws

1. **Screens only.** Every step goes through the UI. API calls are permitted only where the
   UI itself makes them. Seeders, scripts, SQL, and hand-crafted requests are back-door.
2. **Least-privilege actors.** Never system_admin except for steps that legitimately belong
   to the platform — and those steps are enumerated in the plan BEFORE the run, so scope
   creep is visible. Admin rights mask exactly the authorization gaps the exercise exists to
   find. Account creation is itself step 1, done front-door: signup, or an invite issued
   front-door by the operator persona.
3. **The absence IS the finding.** A step you cannot complete front-door gets filed as its
   own gap requirement naming the missing screen or permission. That filing is worth more
   than completing the step another way. Never quietly fall back to a script.
4. **Escalation ladder is data.** When blocked, climb: operator → tenant admin →
   system_admin → engineer/script. Record every rung you had to climb — each rung above the
   intended actor is a severity signal on the finding.
5. **Evidence, both halves.** Every finding states the screen half (URL, what is shown or
   missing) AND the code half (endpoint / file:line). See
   `docs/project-map/batches/frontdoor-findings-2026-08-03.json` for the canonical shape.
6. **Money moves in TEST mode only.** Stripe test keys, no real card, and the close-out
   asserts every purchase in the window carries a test-mode payment intent. Never enable a
   paid external resource without asking first.
7. **Notifications through the product path.** If a step should notify someone, the product
   must send it — a hand-sent message is a back-door and hides the gap. Use deliverable
   addresses (`<your-inbox>+<id>@<your-domain>`); reserved/fake domains are blocked at the
   queue and prove nothing.
8. **Prove persistence front-door.** After a write, hard-reload or log out/in and confirm
   the change survived. This is the front-door analog of the separate-session read-back —
   the app's own state can lie to the tab that made the change (identity-map effect), and
   silent lost JSONB writes are a measured, recurring bug class here.
9. **Enumerate; don't fix mid-run.** The run is a discovery pass: log, rank, keep driving.
   Two exceptions: an extreme security finding, and a blocker that halts the entire run —
   fix minimally to keep driving, and the finding is still filed (the fix does not erase it).
10. **Predict before you drive.** Before the first click, write an expected-today verdict
    per step from the register and code. A discrepancy in EITHER direction is a finding —
    expected-fail that passes means the register is stale, which is also drift.

## Two modes

- **`plan`** — produce the runbook and its Atlas wiring, ready to pull the trigger.
- **`execute`** — drive an existing runbook in a real browser and close it out.

Invoked bare, infer from context; when the user says "create the plan", stop at plan.

## Plan mode

1. **Recon first, read-only.** Current register state (query `pm_requirement` rows), current
   code state (the register is often stale — verify each known defect in code), and current
   data state (row counts through the canonical type-fenced query shape). Do not trust
   planning docs older than the last big merge.
2. **Persona roster** — dependency-ordered and state-building, each with a named
   least-privilege account and how that account comes to exist front-door:
   anonymous visitor → new customer (happy path, creates the canonical state) → returning
   customer / second variant → operator → platform admin (only for platform-legitimate
   steps). One table: persona | account | how created | role ceiling.
3. **Platform-legitimate steps list.** The explicit short list of steps system_admin is
   ALLOWED to perform (e.g. tenant provisioning, site mode flip). Everything else that ends up
   needing admin is a finding.
4. **Step script** in the house walkthrough format, one screen/action per step:
   - Step IDs `<initiative>.<persona-letter>.<n>`
   - `- [ ] Pass / [ ] Partial / [ ] Fail`
   - `- Actor:` (the account), `- Visit:` (exact URL), `- Do:` (the action),
     `- Verify:` (bulleted concrete assertions), `- Predicted:` (expected-today verdict +
     why, citing code/register), `- Notes: ___`
   - Severity legend: 🔴 launch-blocker · 🟠 pre-launch · 🟡 post-launch/futures · 🟢
     cosmetic · ✅ resolved during session; plus 🚪 = **front-door gap** (no screen/
     permission exists — the signature finding class of this exercise).
   - Per-persona acceptance gate, one sentence.
5. **Honest-scope section**: what is deliberately out of scope, and which steps are expected
   to be blocked and why (needs-infra / needs-data / needs-decision).
6. **Deliverable locations**: runbook at
   `docs/runbooks/<initiative>_frontdoor_validation_<YYYY-MM-DD>.md`; a draft Atlas batch
   `docs/project-map/batches/<initiative>-frontdoor-validation-<date>.json` with one
   requirement per exercise modeled on your first front-door exercise requirement (severity casing: CRIT/HIGH
   upper, med/low lower). Reserve a findings batch filename for the run. Apply the batch at
   trigger-pull, not at plan time, unless the user says otherwise.

## Execute mode

1. **Pre-flight is observation only.** A read-only probe (docker exec + SELECTs, health
   endpoints) may verify the environment is up, mode is TEST, and baseline counts — it must
   not create or repair state. If pre-flight reveals missing data, that is a 📋 finding and
   a stop-decision for the owner, not something to seed quietly.
2. **Fresh browser state per persona.** One fresh tab/profile per account; dev OTP is your fixed dev code
   (one digit per field); the session dies on hard reload — that is the persistence
   read-back, use it.
3. **Fill the runbook in place.** Tick the checkbox, write findings as sub-bullets under
   `Notes:` with severity emoji; the runbook doubles as the execution record.
4. **File as you go**: findings batch entries with both evidence halves, one gap requirement
   per missing screen/permission, dependencies back to the exercise code.
5. **Close-out**:
   - Per-persona capability report: **CAN / CORRECTLY-REFUSED / BROKEN-MISSING**, each line
     with step-ID evidence — not ticked checkboxes.
   - Test-mode assertion (law 6) with the query and its result.
   - Go/no-go for the gate this run feeds, with the blocking codes listed.
   - Atlas: `record-round` then `reconcile` (record-round alone does not advance state),
     snapshot, commit.
6. **Refine this skill.** Append one lesson per surprise to the Lessons section below, with
   the incident that taught it. That is this file's whole reason for being versioned.

## Lessons

> Every defect described below was found in development and fixed before the feature was
> released. Entries are kept because each one produced a rule above. Initiative labels are
> anonymised; the dates are real.

- 2026-08-03 (Initiative A): seeded accounts were all system_admin, so a page that 403s for every real
  operator passed every prior test — least-privilege is law 2 because of this.
- 2026-08-03 (Initiative A): the operator-side schedule-move screen simply did not exist; the consumer
  endpoint's existence had masked it in static review — hence law 3.
- 2026-08-03 (Initiative A): five subscriptions displayed a pickup address 2,000 miles away — a stale
  denormalized snapshot only visible by READING the screen, not the row — hence law 5's
  screen half.
- 2026-08-07 (Initiative B plan): the pre-flight probe is a guard too — run it and read every
  detail line before trusting it. The first Initiative B probe draft hit the bare-key trap (its
  instance query matched five match-RESULT rows and missed the config row) and reported a
  false FIX SHIPPED from an unreadable file path (`bool('') → not present`). Both passed
  silently until checked against known state.
- 2026-08-07 (Initiative B, fixing PF-1/PF-2): **a predicted-finding check must be able to say three
  things, not two.** A `marker in src` probe answers only STILL PRESENT / FIX SHIPPED, so it
  reports a fix when the file is unreadable, when the code was deleted outright, and when
  only the cosmetic half of the bug was renamed. Every such check needs: a blind guard
  (unreadable file proves nothing), the marker matched on the DEFECT rather than an
  incidental name near it, a POSITIVE assertion that the replacement exists, and an
  INCONCLUSIVE verdict when neither the bug nor the fix is detectable. Prove it by feeding
  each known-bad input and watching the verdict change.
- 2026-08-07 (Initiative B, same round): **fixing a dead endpoint can arm a worse one.** The credit
  rail 500'd for every SKU; delegating it to the supported rail fixed the one-time path and
  left the subscription path failing at Stripe with a price/account mismatch. Repairing only
  that mismatch would have activated two defects behind it — no renewal metadata and no
  pending invoice — turning a clean failure into recurring charge-then-grant-nothing. When a
  path is broken in depth, refuse it explicitly and file the gap; a truthful refusal beats a
  purchase that half-works. Adversarial verification is what surfaced this — the
  implementer's own tests were green because every fixture used a product shape no live row
  has.
- 2026-08-07 (Initiative A, dev-first): **the `bool('') → not present` false negative recurred one
  day after being written into this file, and produced a committed runbook.** I queried a
  column named `body_template`, got nothing, and reported the OTP template broken; the field
  is `html_body_template` and `body_template` does not exist on the row at all. From that I
  concluded — and wrote down — that dev structurally could not test the login path. The owner
  refuted it in one sentence ("we have email logging so this is factually not true"). A
  workflow agent with DB write access was already queued to "fix" it by re-seeding, and would
  have overwritten a working template. Three rules follow, and reading the lesson was not
  enough to stop it recurring: (1) **an empty result is not evidence of absence** — prove the
  field exists (`SELECT jsonb_object_keys(data)`) before concluding anything from emptiness;
  (2) **absence-shaped checks need a positive control**, because a mis-fenced, misspelled or
  mistyped query returns exactly what "healthy" returns; (3) **never let a fix agent act on an
  unverified diagnosis** — verification is cheap, and re-seeding on a false negative destroys
  the working state you were testing.
- 2026-08-07 (Initiative A, dev-first): **when a round is split across environments, name the BUILD,
  not the branch.** The prod delta was written against the build cut *before* the dev round's
  fixes, while the dev handoff assumed a deploy would precede the prod pass. Both documents
  were internally consistent and jointly incoherent: whether "dev-proven" meant anything at all
  turned on a deploy neither document checked. Committing is not deploying. Any split round
  needs a first step that records which build will actually run the second half, and states
  what changes in the transfer table for each answer.
- 2026-08-07 (Initiative B run 1): **a page that renders perfectly can still be unsellable, and the
  prettier it is the longer that survives.** Three of the round's worst findings were
  invisible to every static pass: a pricing page whose product grid is a deliberate
  `display:none` placeholder (a LOUD "Unsupported element" had been replaced with a SILENT
  null-renderer, so the page looks finished); a paywall whose buy button loads a different,
  cheaper, useless SKU; and a checkout that displays the right product, right price and right
  description all the way to the final button and then 500s, because the page is key-aware for
  DISPLAY and passes that same key as a UUID for PURCHASE. Read the screen for what it
  *cannot* do, not just for what it shows — and click the last button, because everything up
  to it can be right while it is wrong.
- 2026-08-07 (Initiative B run 1): **stopping early can be the finding.** The round halted at B.4 with
  four of five personas undriven, because the blocker found there makes the gate's own
  criterion ("completes purchase unaided") unreachable and every later step depends on the
  entitlement a purchase grants. Continuing via a hand-built UUID URL would have measured a
  state no user can reach. State the stop, the reason, and the exact undriven scope — a
  truncated round reported honestly beats a completed one propped up by workarounds. Record
  every rung climbed to diagnose (here: one DB lookup to construct the positive-control URL).
- 2026-08-07 (Initiative B run 2): **re-run the fixed step through the SCREEN, not the URL.** Round 1
  proved the checkout bug with a hand-built UUID URL; round 2 only counts because the same
  purchase was reached by clicking the paywall button, which is the thing a beta user does.
  The re-run also produced evidence the code review could not: the paywall now shows a price
  that was previously **absent entirely** — and that absence was the reason the wrong-SKU
  substitution went unnoticed, since the first number the buyer ever saw was in the cart.
- 2026-08-07 (Initiative B run 2, second attempt): **diagnose the harness before blaming the page, and
  before retrying.** Two rounds were lost to Stripe Checkout "not responding to clicks",
  attributed to reflow. One query settled it: `document.visibilityState === "hidden"` — the
  browser pane was hidden, so the page was render-throttled and its radios never received a
  trusted user gesture (`input[type=radio]` all read `checked:false` no matter the
  coordinates, and keyboard focus landed inside `__privateStripeFrame*`). Evidence beats
  persistence: one DOM check would have replaced twenty clicks. When a third-party page will
  not respond, ask what the ENVIRONMENT is doing before concluding anything about the page —
  then hand the human the exact minimal step only they can perform, rather than retrying.
- 2026-08-07 (Initiative B run 2): **a third-party hosted page can end your round, and that is not a
  finding.** Stripe Checkout's payment-method list reflows between screenshot and click under
  automation, so card entry could not be completed. Say plainly that it is tooling friction,
  not a product defect — the product's responsibility ended at handing off a valid Sandbox
  session — and mark the dependent steps undriven rather than inferring they would pass.
- 2026-08-07 (Initiative B run 1): **positive controls caught four false negatives in one session.**
  Querying `cms_page` (real key: `page`), `data->>'slug'` (real: `page_slug`), a guessed site
  UUID, and `legal_document` (real: `legal_document_version`) each returned empty — and empty
  reads exactly like "the thing is missing". Every one would have produced a confident, wrong
  finding. Count the rows for the type FIRST; if the count is 0, the query is wrong, not the
  product.
- 2026-08-07 (Initiative A, dev-first): **a step marked ⬜ untestable-in-this-environment transfers
  nothing, and is the easiest thing to lose.** The dev overlay let the failed-payment/dunning
  cycle be dispositioned ⬜ with "leave it to prod," and the prod pass had no step that picked
  it up — the transfer table meanwhile classified it dev-proven. Any ⬜ must auto-generate a
  step in the other environment, or the capability finishes the round tested in neither.

### Staging by declared file list ships tests without their subject

A fan-out gives each agent a partition and each reports the files it changed. Staging from
those reports is the obvious move and it is subtly wrong: an agent that edits one more file
than it declared leaves that edit behind. Measured — a notification catalogue and its 24
tests were committed while the ingest hook they assert against stayed in the working tree, so
the commit contained a green suite testing a function that did not exist at that commit. The
tree was right; the commit lied.

**Verify the suite against the COMMIT, not the tree you are standing in.** Cheapest form:
after staging, `git stash -u` the remainder and run the tagged suite, or diff
`git diff --cached --name-only` against every file the suite imports. A shared branch makes
this worse, because the "remainder" is a mix of your leftovers and another session's WIP and
the two look identical in `git status`.

### A measurement must not be able to mark the thing it measures as fixed

`reconcile` flips a requirement to `verified` when any tagged test passes. So tagging the
harness's own mechanics tests with the requirement it measures would mark the defect fixed the
moment the *measuring* worked. Register a separate code for the instrument, tag only that, and
re-query the measured requirement afterwards to prove it did not move. Same trap in the other
direction: a requirement with five acceptance clauses reconciles to `verified` off a test
covering three — split the remainder into its own code rather than leaving work hidden behind a
green row.

### "Untyped" is a labelling artifact before it is a finding

An audit that names entity types via `data->>'key'` reports `(untyped)` for any row whose type
carries no `key`. Measured: 72 of 514 type rows are name-only. Two independent sessions read
the same 48 rows as untyped orphans; they were `Audit Log` rows with intact types. Untyped
reads as *corrupt* and invites deletion — which for audit records destroys the evidence of the
cleanup itself. Coalesce `key → name → '(type row missing)'`, and reserve the last bucket for a
`type_fk` that resolves to nothing, which is a genuinely different finding.
- 2026-08-20 (Initiative C): **a form that renders perfectly can be unable to submit, and
  the tell is ZERO network requests behind the error.** The club signup form validated, gated
  consent, and then failed with a generic "try again later" — the reCAPTCHA hook throws when no
  provider wraps the tenant render path, so the failure happened before any API call. Every
  /site signup form had shipped in that state under green suites (jest mocks the api module;
  backend tests call the endpoint directly — neither executes the block's submit path in a
  browser). On any submit failure, read the console AND the network tab before the code.
- 2026-08-20 (Initiative C): **seeded CMS content must be verified against each block's
  prop CONTRACT, not against "the page renders".** Two drifts in one run: nav_links seeded as
  {label, path} against a {id, label, url} contract (crashed every page); heading blocks seeded
  as {text, level} against {variant, content} (rendered empty, silently). Before seeding a
  layout, read the block's index.tsx props — the renderer neither validates nor warns.
