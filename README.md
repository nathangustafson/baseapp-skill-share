# BaseApp Skill Share

**Repository:** https://github.com/nathangustafson/baseapp-skill-share

Seven Claude Code skills, four hooks, and one script, lifted from a real production codebase and packaged so another team can install them in an afternoon.

They came out of roughly a year of building **BaseApp**, a multi-tenant SaaS platform (FastAPI + PostgreSQL backend, React + TypeScript frontend, everything run through Docker Compose locally). Development was done almost entirely with Claude Code, often with several sessions working the same branch in parallel. Every rule in these files was paid for by a real incident; the skills carry those lessons so the next session does not have to relearn them.

The most-used skill here, `phase-status-report`, was invoked 172 times across 36 sessions. The others fill in around it: keeping a requirements register honest, testing through the product's own screens, working an unattended queue, and never trusting a backup you have not proven restorable.

> **Read the glossary first.** These files talk about "Atlas", "front-door", "operators", "tenants" and a few internal codenames. Section 2 defines every one of them. Section 8 lists what was edited out of the originals before sharing.

---

## 1. What is in the box

```
BaseApp Skill Share/
├── README.md                      ← you are here
├── LICENSE                        ← MIT
├── install.sh                     ← copies skills + hooks, merges settings.json
├── settings.hooks.example.json    ← the hook wiring, ready to merge
├── skills/
│   ├── phase-status-report/       ← end-of-session status report (172 uses)
│   ├── pm-update/                 ← keep the requirements register current
│   ├── frontdoor-test/            ← validate through the UI only, file every gap
│   ├── work-the-queue/            ← autonomous execution of a pasted work list
│   ├── backup-db/                 ← validated, pruned Postgres backups
│   ├── walkthrough-test-plan/     ← multi-persona acceptance runbook generator
│   └── efficiency-review/         ← page-load and query anti-pattern review
├── hooks/
│   ├── auto-status-report.sh      ← Stop: run the status report when commits landed
│   ├── pm-coverage-gate.sh        ← Stop: block if feat/fix commits unregistered
│   ├── db-backup-staleness.sh     ← SessionStart: warn on stale/unpruned backups
│   └── enforce-docker.sh          ← PreToolUse: block host python/pytest/npm run dev
└── scripts/
    └── backup-db.sh               ← dump, prove restorable, prune generationally
```

Each `skills/<name>/SKILL.md` is a standard Claude Code skill: YAML frontmatter with `name` and `description`, then the instructions Claude follows when you type `/<name>` or when the description matches what you asked for. Three of them (`pm-update`, `backup-db`, `efficiency-review`) lived as `.claude/commands/*.md` files in the source repo and were given frontmatter here so all seven install the same way.

---

## 2. Glossary: terms that are specific to BaseApp

You will see these throughout the skill files. None of them are Claude Code concepts.

| Term | What it means in these files |
|---|---|
| **Atlas** / **Project Map** | BaseApp's requirements register, stored *inside the product's own database* as rows (`pm_requirement`, `pm_objective`, `pm_progress_event`). It is the "persistent development memory": every user-facing change maps to a requirement **code** such as `OP-SUB-04` or `DEPLOY-INIT-A-2026-08-15`. Think Jira or Azure DevOps Boards, but queryable by the agent and reconciled from test results. **You will replace this with your own tracker.** |
| **`scripts/pm.py`** | The command-line write surface for Atlas. Subcommands referenced in the skills: `apply` (upsert requirements from a JSON batch), `record-round` (log what a dev round touched), `reconcile` (flip requirements to `verified`/`regressed` from test outcomes), `snapshot` (write a Markdown copy of the register into the repo), `drift` (list requirements with evidence but stale state). Not included; it is BaseApp-specific. |
| **Requirement code** | An uppercase, dash-separated identifier ending in a number: `BILL-CRON-01`. Tests are tagged `@pytest.mark.requirement("CODE")` so `reconcile` can advance state automatically. |
| **State** | A requirement's lifecycle: `proposed` → `implemented` → `verified` (or `regressed`). The recurring failure these skills guard against is code shipping while the register still says `proposed`. |
| **Severity casing** | Atlas accepts `CRIT` / `HIGH` (upper) and `med` / `low` (lower). Mixed on purpose; the skills mention it because `MED` is rejected. |
| **Owner** | The product owner / the human running the session. "The owner corrected this on 2026-08-14" means a real correction that became a rule. |
| **Front-door** / **back-door** | The owner's terms. *Front-door* = exercising a capability only through the product's screens, as a real user would. *Back-door* = seeders, SQL, scripts, or API calls that bypass the UI. A back-door change proves the data can change; a front-door one proves the product can. |
| **Persona** | A role in a test plan: anonymous visitor, new customer, returning customer, operator, platform admin. Runbooks are sequenced so each persona builds on the previous one's state. |
| **Tenant** / **operator** / **system_admin** | BaseApp is multi-tenant. A *tenant* is one customer organisation; an *operator* is a business user administering one tenant; *system_admin* is the platform-level role. Test plans insist on least-privilege actors because admin rights hide authorization bugs. |
| **Entity model** / **`entities` table** | BaseApp stores almost everything in one PostgreSQL table with a JSONB `data` column, typed by `data->>'type_fk'`. Several rules ("bare-key lookups", "JSONB JOIN anti-pattern", "type predicate") only matter if you have a similar single-table design. Skip them otherwise. |
| **`futures/`** | A directory of Markdown files that hold deferred and unbuilt scope, the human-readable backlog. `futures/bugs.md` is where post-launch findings go. |
| **`docs/runbooks/`**, **`docs/project-map/batches/`** | Where walkthrough runbooks and Atlas requirement batch JSON live in the BaseApp repo. Change the paths to suit yours. |
| **Token ledger** | `.claude/token-ledger.jsonl`: one JSON line per status report recording subagent token spend for the interval, so fan-out cost stays visible. |
| **Docker-only rule** | BaseApp never runs Python, pytest, or the dev server on the host; everything goes through `docker exec`. The `enforce-docker.sh` hook makes that a hard rule. |
| **Codenames** | Initiative labels in the Lessons sections and examples (`Initiative A` / `B` / `C`, `INIT-A-…` codes, `W1.x` / `W2.x`, `Phase 0-4`) are anonymised placeholders for real BaseApp initiatives. The dates and the defects are real; every defect was fixed before release. |
| **Severity emoji** | 🔴 blocker · 🟠 pre-launch · 🟡 post-launch · 🟢 cosmetic · ✅ resolved this session · 🚪 front-door gap (no screen or permission exists). Used consistently across runbooks and status reports. |

---

## 3. Installing

**Prerequisites:** Claude Code, `git`, `jq` (for the settings merge). The backup pieces additionally need Docker with a Postgres container. All shell is written for macOS bash 3.2 and Linux bash 4+.

### Fastest path

```bash
cd /path/to/your/repo
/path/to/BaseApp\ Skill\ Share/install.sh
```

That copies the skills to `.claude/skills/`, the hooks to `.claude/hooks/`, the backup script to `scripts/`, and merges the hook wiring into `.claude/settings.json` (backing up the old file first, and appending to any hooks you already have rather than replacing them).

Other modes:

```bash
./install.sh --user          # skills only, into ~/.claude/skills — available in every project
./install.sh --skills-only   # project skills, no hooks or settings changes
./install.sh --force         # overwrite skills that already exist
```

### By hand

1. Copy each `skills/<name>/` directory into `.claude/skills/` (project) or `~/.claude/skills/` (user).
2. Copy `hooks/*.sh` into `.claude/hooks/` and `chmod +x` them.
3. Merge `settings.hooks.example.json` into `.claude/settings.json`. Hook commands use `$CLAUDE_PROJECT_DIR`, which Claude Code sets at runtime, so no absolute paths are needed.
4. Copy `scripts/backup-db.sh` into `scripts/` and set `DB_USER`, `DB_NAME`, and the container names at the top.

### Prompt to let Claude do the install for you

Open Claude Code in your repo and paste:

> Install the skills and hooks from the folder `<path to BaseApp Skill Share>` into this project. Read its README first. Copy the seven skills into `.claude/skills/`, the hooks into `.claude/hooks/`, and merge `settings.hooks.example.json` into `.claude/settings.json` without dropping any hooks I already have. Then read `.claude/hooks/pm-coverage-gate.sh` and tell me exactly which lines assume the BaseApp requirements register, so I can decide how to adapt them to `<Jira / Azure DevOps / GitHub Issues>`.

### Verify

```bash
ls .claude/skills            # seven directories
jq '.hooks | keys' .claude/settings.json   # ["PreToolUse","SessionStart","Stop"]
```

Then in Claude Code, type `/phase-status-report`. If the skill loads and asks about phases, the install worked.

---

## 4. The skills

### 4.1 `phase-status-report`  (172 uses, 36 sessions)

**What it does.** Produces a fixed-shape status report for any project with named phases: one combined progress chart (item count and effort-weighted in a single view), a **separately tracked deployment stage that never counts toward completion**, a table of this session's commits, token spend for the interval, links to the active plan files, a priority-organised what's-left list, and anything newly captured to the backlog.

**Why it is useful.** Long agent sessions end with a wall of scrollback. The report turns that into one screen a reader can act on cold, in the same shape every time, so you stop re-reading transcripts to find out where things stand. Two rules in it were each corrected twice by the owner: render **one** chart carrying both counts (never a weight table above a chart that restates it), and keep deployment **outside the 100%** so "done" never quietly comes to mean "deployed".

**Hook tie-in: `hooks/auto-status-report.sh` (Stop).** When a session ends and `HEAD` has moved since the last report, the hook blocks the stop once and tells Claude to run this skill. A marker file outside the repo (`~/.claude/.baseapp-last-status-report-head`) makes it fire exactly once per batch of commits. It never fires on question-and-answer turns and never hard-blocks: every failure path allows the stop. Rename the marker if you like; it is just a file holding a commit hash.

**Adapting.** Change the "Related plans" search paths (`.claude/plans/`, `docs/plans/`, `futures/`) to wherever your plans live. If you do not track token spend, delete the "Token spend" section. The Atlas coordination code for deployments becomes a ticket or epic in your tracker.

**Prompts to run.**

> /phase-status-report

> Give me a status report on the `<initiative>` work. Phases are `<Phase 0 / 1 / 2 ...>`. Weight build items at 3, polish at 2, cutover at 5. Deployment is separate.

> We are wrapping up. Run the status report, then list which items are local and which are deployment, and say whether the deploy gate is open or blocked.

---

### 4.2 `pm-update`  (8 uses)

> **Adapt this one before using it.** `pm-update` writes to Atlas, BaseApp's in-database requirements register, through `scripts/pm.py`. That script is not included and would not work outside BaseApp. **Rewrite the "How to run" and "dev-round workflow" sections to target your project's tracking tool: Jira, Azure DevOps Boards, Linear, GitHub Issues, or a Markdown register in the repo.** The *shape* of the workflow is the valuable part: record what changed → capture new requirements → reconcile state from tests → snapshot into the repo.

**What it does.** Keeps the requirements register current as development happens. Four steps: `record-round` (which requirement codes this round touched, with branch and SHA), `apply` (upsert newly discovered requirements from a JSON batch file), `reconcile` (run the test suite and flip requirements to `verified` or `regressed` from tests tagged `@pytest.mark.requirement("CODE")`), and `snapshot` (write a diffable Markdown copy of the register into the repo and commit it).

**Why it is useful.** The failure it prevents is silent: a whole initiative shipped in BaseApp with the register still saying `proposed`, because the parallel session recorded normally and this one did not. Model memory alone is not enough under load. The skill also insists that **you are the intelligence**: compose the requirement content from your own reasoning about the work; do not delegate it to an LLM endpoint or a content-generating subagent. The tool is only the write surface.

**Hook tie-in: `hooks/pm-coverage-gate.sh` (Stop).** Blocks the stop once when the session's new commits include `feat(...)`/`fix(...)` subjects (Conventional Commits) and no round was recorded for them. A stronger check runs first: if the diff added `@pytest.mark.requirement("CODE")` tags for codes that are still unverified, it blocks and says to run `reconcile`. Pure `chore`/`docs`/`ci`/`refactor` commits are exempt. **The bottom of this hook queries the BaseApp database for a fresh progress event.** Replace that `psql` block with a check against your tracker (a Jira JQL query for a recently updated issue, an `az boards` call, a `gh issue list --search`), or delete it and keep only the tagged-test check.

**Mapping the concepts to your tracker.**

| Atlas | Jira | Azure DevOps | GitHub |
|---|---|---|---|
| requirement code | issue key (`PROJ-123`) | work item ID | issue number |
| objective | epic | feature / epic | milestone / project |
| `record-round` | comment + transition, or worklog | discussion + state change | comment + label |
| `reconcile` from tagged tests | CI step that transitions issues named in test markers | pipeline task updating work-item state | Action that closes issues from test output |
| `snapshot` | export or a generated `docs/register.md` | query export | `gh issue list --json` → Markdown |

**Prompts to run.**

> /pm-update — record this round for `<codes>`, then reconcile from the tagged suite and snapshot the register.

> Rewrite `.claude/skills/pm-update/SKILL.md` so every `pm.py` command becomes the equivalent `<jira / az boards / gh>` command against our tracker. Keep the four-step workflow and the "you are the intelligence" rule exactly as they are.

> Before we stop: which of this session's feat/fix commits are not yet linked to a ticket?

---

### 4.3 `frontdoor-test`  (5 uses)

**What it does.** Plans and executes a *front-door validation*: driving a capability strictly through the product's own screens as a least-privilege user, with no seeders, SQL, scripts, or UI-bypassing API calls. Every step that cannot be completed through the UI is filed as its own gap requirement. Two modes: `plan` (write the runbook and register wiring) and `execute` (drive it in a real browser and close out with a per-persona CAN / CORRECTLY-REFUSED / BROKEN-MISSING report).

**Why it is useful.** Driving real screens found two launch blockers that a 16-agent static review missed entirely. A page that returned 403 for every genuine operator stayed hidden in dev because every seeded account happened to be an admin. The most valuable finding of one exercise was a screen that **did not exist**. Static analysis cannot find missing buttons, dead routes, or absent notifications; a real user can, and this skill makes Claude behave like one. Ten numbered "laws" govern the run (screens only; least privilege; the absence is the finding; the escalation ladder is data; both halves of evidence; money in test mode only; notifications through the product path; prove persistence by reload; enumerate, do not fix mid-run; predict before you drive). The **Lessons** section at the bottom is a dated log of every surprise, and the skill instructs Claude to append to it.

**Hook tie-in.** None directly. Law 6 (test-mode money only) and law 7 (real deliverable inboxes only) are enforced in BaseApp at the code level, not by hooks.

**Adapting.** Replace the persona roster and the platform-legitimate steps list with your own roles. Change the runbook and batch-file paths. Keep the laws and the Lessons format verbatim: they are product-agnostic. Delete or rewrite the entity-model-specific lessons if you do not use a single-table JSONB design.

**Prompts to run.**

> Create a front-door test plan for `<capability>`. Personas: anonymous visitor → new customer → operator → platform admin. Only `<steps>` may use the admin account. Predict the verdict for every step before we drive it.

> Execute the front-door runbook at `docs/runbooks/`<file>`.md` in the browser. Fresh session per persona. File every gap as its own requirement. Do not fix anything mid-run unless it halts the whole exercise.

> Prove that an operator can `<do X>` unaided, through the screens only. If they cannot, tell me exactly which screen or permission is missing.

---

### 4.4 `work-the-queue`  (2 uses)

**What it does.** Executes a pasted list of work items without supervision: recon first, one batched round of only-blocking questions, sub-agent fan-out on **disjoint file partitions**, an adversarial verifier per claim, central commits by the orchestrator only, a register round, and a report that leads with corrections.

**Why it is useful.** "I'll leave you to it, I expect everything resolved when I return" is a common instruction and an easy one to fail quietly. This skill fixes the failure modes seen in practice: agents editing the same file and colliding, tests that pass while verifying nothing, "not caught" conclusions drawn from mutations that never applied, and reports that bury the fact that an earlier summary was wrong. The **test quality bar** section is worth reading on its own: mutation-prove headline claims, pair every DENY with an ALLOW, read persistence back through a separate session, never assert a value the test itself assigned to a mock.

**Hook tie-in: `hooks/enforce-docker.sh` (PreToolUse on Bash).** The skill's "house rules" block references it: the hook blocks any Bash command that starts with `python`, `pip`, `pytest`, `npm run dev`, or `npx playwright test` unless the line already goes through `docker exec` or `docker compose`. It exists because sub-agents reach for host Python constantly. Only install it if your project is Docker-only; it is a hard block.

**Adapting.** The "house rules block" is BaseApp-specific (Docker paths, JSONB gotchas, conftest patching). Replace its bullets with your own project's footguns, keeping the instruction to paste the block into every agent prompt. Replace the "Atlas round" close-out step with your tracker's equivalent.

**Prompts to run.**

> Queue all of this. Plan first and ask me any blocking questions up front in one round, then work it until done. Use sub-agents on disjoint files. Verify every claim adversarially before committing. `<paste the list>`

> Here are the open items from the last status report. Keep at it until everything is resolved. I am leaving; report honestly on what you could not do and why.

---

### 4.5 `backup-db`  (2 uses)

**What it does.** Takes a timestamped `pg_dump` of the Dockerised Postgres, then **proves** it: copies the archive back into the container so `pg_restore --list` reads a seekable file, counts TOC entries, and compares dumped rows on the biggest table to live rows (a shortfall over 1% fails). Optionally restores into a scratch database (`--restore-test`) to prove the dump actually comes back, pgvector extension included. Only then does it prune, keeping the N newest plus the newest from each of the last W week-buckets. Hand-labelled dumps are never pruned.

**Why it is useful.** `pg_dump` exiting 0 is not proof of a good backup and neither is a plausible file size. The BaseApp backups folder held two 0-byte files and one 184 MB truncated dump that all looked fine for months. A prune step also died silently on macOS bash 3.2 after a successful dump, so the folder grew by half a gigabyte every run while the "freshness" check stayed green. The script's header comments document each of these; the exit codes distinguish "dump failed" from "backup is good but housekeeping failed".

**Hook tie-in: `hooks/db-backup-staleness.sh` (SessionStart).** Prints a warning at the start of every session when the newest non-empty backup is older than 7 days, when there are more auto-backups than retention should leave (the prune is not running), or when the folder exceeds 8 GB. Advisory only; it never blocks and never takes the backup itself, because a dump of a large table inside a small container can starve the app if it runs while tests are hammering the database. The script refuses to run while pytest is active in the backend container for the same reason.

**Adapting.** Set `PG_CONTAINER`, `BACKEND_CONTAINER`, `DB_USER`, `DB_NAME` at the top of `scripts/backup-db.sh` (or export them). Change `entities` to your largest table in the parity check. Drop the pgvector assertion if you do not use the extension. The hook reads `backups/` relative to the repo root; `.gitignore` it.

**Prompts to run.**

> /backup-db — label it predeploy.

> Run `scripts/backup-db.sh --restore-test` and tell me the restored row count and whether pgvector came back.

> The session-start hook says backups are stale. Take one now, then show me what the prune kept and why.

---

### 4.6 `walkthrough-test-plan`  (1 use)

**What it does.** Generates two artifacts for a multi-persona launch: a read-only **pre-flight probe** script (about 15 checks that verify seeded data and config exist before a human starts clicking; exit code = failure count) and a **runbook** Markdown document with 3–5 sequential personas, one screen or action per step, `[ ] Pass / [ ] Partial / [ ] Fail` checkboxes, a `Verify:` list, a `Notes:` field, a per-persona acceptance gate, and a findings-triage section.

**Why it is useful.** A multi-surface initiative that just merged needs a human to walk it end to end before launch, and a good runbook is the difference between a two-hour session and a lost afternoon. The skill encodes the shape that worked: personas in dependency order so each builds on the previous one's state; no bundled steps; no "estimated time" column (always wrong); cross-cutting invariants to check every time (manual parity for AI features, unified rollback, per-user scoping, idempotency). It composes with `phase-status-report` to report the disposition and with `frontdoor-test` for the stricter no-seeders variant.

**Hook tie-in.** None.

**Adapting.** The probe template imports BaseApp's `SessionLocal` and queries the entity table; rewrite the check functions against your schema and ORM. Change the runbook path and the reference runbooks named in the frontmatter.

**Prompts to run.**

> Write a walkthrough test plan for `<initiative>`. Phase letter `<X>`. Five personas: first-time consumer, returning consumer, `<alternate variant>`, operator, platform admin. Critical surfaces: `<routes>`. Also write the pre-flight probe.

> We just merged `<branch>`. Generate the acceptance walkthrough and tell me which persona to run first and how many sessions it will take.

---

### 4.7 `efficiency-review`  (1 use)

**What it does.** Reviews one page or route for load performance. Traces every API call made on mount, effect, and context provider into a table (endpoint, trigger, timing, whether the data is actually rendered). Audits each query for specificity: filters, bounded result sets, pagination, field selection. On the backend, hunts for the anti-patterns that kill single-table JSONB designs: `JOIN ... ON entity_id::text = data->>'fk'` (O(n²), and O(n⁴) when chained), fetch-everything-then-filter, N+1 loops, missing LIMIT. Ends with proposed solutions, each with an impact estimate, the file and line, and the tests required.

**Why it is useful.** The review that produced this skill found a tenants page making eight sequential API calls in about six seconds, five of them for data the page never displayed; the fix took it to two or three calls and about a second. The skill turns that one-off investigation into a repeatable checklist, including grep commands to find every offending JOIN in a codebase.

**Hook tie-in.** None.

**Adapting.** The JSONB JOIN section is specific to entity-attribute-value or single-table designs; keep it if that describes you, delete it otherwise. The frontend section (React `useEffect` tracing, client-side filtering) applies to any SPA. Replace the named helper functions (`lookup_operator_tenants_via_subscriptions` and friends) with your own batch-lookup utilities or remove them.

**Prompts to run.**

> /efficiency-review /admin/users?section=tenants

> Review `<PageComponent>.tsx` for load performance. Table every API call on mount, mark which ones render nothing, and propose the smallest change that removes the sequential chain.

> Run the JSONB JOIN grep from the efficiency-review skill across `src/` and rank the hits by nesting depth.

---

## 5. The hooks, in one place

| Hook | Event | What it does | Blocks? | Depends on |
|---|---|---|---|---|
| `auto-status-report.sh` | Stop | Runs `phase-status-report` once per batch of new commits | Once, then allows | `git`, `jq` |
| `pm-coverage-gate.sh` | Stop | Blocks if `feat`/`fix` commits were never recorded, or tagged tests were added for unverified codes | Once, then allows | `git`, `jq`, **your tracker** (edit the `psql` block) |
| `db-backup-staleness.sh` | SessionStart | Warns on stale, unpruned, or oversized backups | Never | `backups/` dir |
| `enforce-docker.sh` | PreToolUse (Bash) | Blocks host `python`/`pip`/`pytest`/`npm run dev`/`npx playwright test` | Always, when matched | Docker-only workflow |

Both Stop hooks honour `stop_hook_active` so they can never loop, and both advance their marker *before* blocking so a report or round that is skipped downstream is not asked for again. Every "cannot determine" path exits 0. A hook that cries wolf gets ignored; these were tuned not to.

**Prompt to test the hooks after install:**

> Make a trivial `chore:` commit, then stop. Confirm neither Stop hook fired. Then make a `feat:` commit and stop; confirm the status-report hook fires once and the coverage gate fires once, and that stopping a second time is allowed.

---

## 6. Adapting to your project: a checklist

1. **Tracker.** Rewrite `pm-update` and the tail of `pm-coverage-gate.sh` for Jira / Azure DevOps / GitHub Issues (section 4.2 has the mapping table).
2. **Paths.** `docs/runbooks/`, `docs/project-map/batches/`, `futures/`, `.claude/plans/`: find-and-replace to your layout.
3. **Containers and DB.** `PG_CONTAINER`, `BACKEND_CONTAINER`, `DB_USER`, `DB_NAME` in `scripts/backup-db.sh` and `hooks/db-backup-staleness.sh`; the biggest-table name in the parity check.
4. **House rules.** Replace the BaseApp footguns in `work-the-queue` with your own; keep the instruction to paste them into every agent prompt.
5. **Personas.** Replace the consumer/operator/admin roster in `frontdoor-test` and `walkthrough-test-plan` with your roles.
6. **Delete what does not apply.** Entity-model lessons, JSONB JOIN section, pgvector check, token ledger, `enforce-docker.sh` if you are not Docker-only.
7. **Keep the Lessons sections alive.** `frontdoor-test` asks Claude to append a dated lesson per surprise. That habit is where most of this value came from.

---

## 7. Conventions these skills assume

- **Conventional Commits** (`feat(scope): ...`, `fix(scope): ...`). The coverage gate keys on the prefix.
- **Tests tagged to requirements**: `@pytest.mark.requirement("CODE")`. Any test framework with markers or tags can do the same.
- **Agent commits, human pushes.** Several skills say "stage only your own paths, never `git add -A`", because parallel sessions shared a working directory. Harmless if you work alone.
- **Severity emoji** as listed in the glossary, used identically in runbooks, status reports, and backlog files.

---

## 8. What was changed from the originals

So you know exactly what you are getting, and what is not original:

- A personal email address pattern in `frontdoor-test` (law 7) was replaced with `<your-inbox>+<id>@<your-domain>`.
- The dev-environment one-time-password value in `frontdoor-test` was replaced with a placeholder.
- The Postgres role name in `scripts/backup-db.sh`, `hooks/pm-coverage-gate.sh`, and `skills/backup-db` now defaults to `postgres` and reads `$DB_USER` if set.
- A production-backup staleness block was **removed** from `hooks/db-backup-staleness.sh`; it referenced the owner's production database and off-box backup location.
- The CD pipeline name and one personal plan filename in `phase-status-report` were replaced with placeholders.
- `pm-update`, `backup-db`, and `efficiency-review` gained YAML frontmatter so they install as skills rather than slash-command files.
- `hooks/enforce-docker.sh` was added because `work-the-queue` references it; in the source repo it is wired from `settings.local.json`, so here it is wired from the shared example instead.

- Internal initiative and site names in the Lessons sections and examples were replaced with `Initiative A` / `B` / `C` and placeholder requirement codes, and a note was added that every defect described was fixed before release.
Nothing else was edited. Dates and incident descriptions in the Lessons sections are left as they were; they are the evidence behind each rule.

---

## 9. Usage counts, for the curious

Counted from every Claude Code transcript on the author's machine, all projects, as of 2026-09-09:

| Skill | Invocations |
|---|---:|
| phase-status-report | 172 |
| pm-update | 8 |
| frontdoor-test | 5 |
| work-the-queue | 2 |
| backup-db | 2 |
| walkthrough-test-plan | 1 |
| efficiency-review | 1 |

The gap between the first row and the rest is itself a finding: the status report is the one skill wired to a hook, and it ran without anyone asking.

---

## 10. License

MIT. Use it, change it, ship it, commercially or otherwise; keep the copyright notice and license text; no warranty. See `LICENSE`.
