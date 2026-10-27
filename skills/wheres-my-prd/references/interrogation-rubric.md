# Interrogation Rubric: the 100-Point Spec Readiness Score

Score each dimension from 0 to 20. A dimension has five checks worth 4 points each:

- **4**: stated explicitly by the user, or answered by the repo
- **2**: implied, but ambiguous enough that two engineers would build it differently
- **0**: missing

**Spec Readiness Score** = the sum of the five dimensions (0–100).

**Gate opens** when the score is ≥ 85 **and** `p0_blockers_remaining == 0`.

Items resolved by the user's answer, or by a recommended default the user accepted, score 4. Items locked by the Emergency Default Lock score 2, because nobody confirmed them. Items logged as an Open Discovery Risk score 0. If a check genuinely doesn't apply (an internal cron job has no "empty state UI"), score it 4 and note `N/A — <reason>` in the PRD. Don't penalize the spec for irrelevant checks.

## Severity: P0 vs P1

A gap is **P0 BLOCKER** when guessing wrong causes any of:

- money or credits moving incorrectly (double charge, farmable rewards, lost refunds)
- data loss, corruption, or a migration that fails on existing production rows
- a security or privacy hole (auth bypass, cross-tenant read, PII in logs)
- an outage or blocked critical path (signup, checkout, login)
- a data-model rewrite once the feature is live

Everything else is **P1 DESIGN CHOICE**: it matters, but a safe default exists and changing it later is cheap.

When in doubt, ask whether you could change the decision next week with a one-file PR and no data repair. If yes, it's P1.

---

## 1. State Machine & Edge Cases (20)

| # | Check | Typical P0 trigger |
|---|---|---|
| 1.1 | Every UI/API state is named: Idle, Loading, Success, Empty, Error, Rate-Limited (or N/A) | Missing intermediate state on a money/side-effect action |
| 1.2 | Boundaries: 0 items, 1 item, max items, oversized input | Unbounded list/payload on a hot path |
| 1.3 | Concurrency: double-submit, two tabs, two users editing the same record | Duplicate side effects (double credit, double email, double charge) |
| 1.4 | Interruption: cancel mid-flow, close modal, refresh, network drop, retry | Orphaned half-written records |
| 1.5 | Lifecycle: what happens on expiry, deletion, downgrade, or account closure | Dangling references / rewards on deleted accounts |

**Question patterns**
- "What happens if the user closes the modal while `<async action>` is still pending?"
- "What does the screen show when the user has zero `<items>`?"
- "If the user double-clicks `<submit>`, how many `<side effects>` happen?"

## 2. Data Contracts & Schema Safety (20)

| # | Check | Typical P0 trigger |
|---|---|---|
| 2.1 | New/changed fields have type, nullability, default, and units (cents vs dollars, UTC vs local) | Ambiguous units on money or time |
| 2.2 | Migration is safe on existing rows (nullable or backfilled; no blocking lock on large tables) | `NOT NULL` without default on a populated table |
| 2.3 | Validation rules: required fields, formats, max lengths, payload size caps | Unvalidated input written to the DB or forwarded to a third party |
| 2.4 | Idempotency: keys or unique constraints for anything that can be retried | Webhooks/jobs without dedupe on side effects |
| 2.5 | Backward compatibility: existing API consumers, old clients, and indexes for new query paths | Breaking a public/mobile API contract |

**Question patterns**
- "You're adding `<column>` to `<table>`, which already has rows. Nullable plus lazy fill, or a two-phase backfill?"
- "Is `<amount field>` stored in minor units (cents) or major units?"
- "What uniquely identifies a `<event>` so a retry can't apply it twice?"

## 3. Abuse, Security & Failure Modes (20)

| # | Check | Typical P0 trigger |
|---|---|---|
| 3.1 | AuthN/AuthZ: who can call this, and can user A touch user B's (or tenant B's) data? | Missing ownership/tenant check |
| 3.2 | Abuse/farming: self-referral, sockpuppets, scripted signups, coupon stacking, scraping | Rewards or credits with no anti-farming gate |
| 3.3 | Rate limits and quotas per user/IP/tenant | Unmetered expensive or side-effecting endpoint |
| 3.4 | Third-party failure: timeouts, 5xx, webhook retries, partial success | Critical path hard-depends on an external API |
| 3.5 | Sensitive data: PII/secrets kept out of logs, URLs, analytics, and client bundles | Tokens or emails in query strings or event payloads |

**Question patterns**
- "Can a user trigger `<reward>` against themselves using a second email?"
- "If `<provider>` is down, does `<critical flow>` block, degrade, or queue?"
- "How many times per `<window>` can one user call `<endpoint>`?"

## 4. Telemetry & Success Metrics (20)

| # | Check | Typical P0 trigger (rarely P0) |
|---|---|---|
| 4.1 | A primary KPI with a target and time window ("20% of active users share a link within 30 days") | Regulated or contractual reporting needs |
| 4.2 | Named server-side events covering triggered / completed / failed / dismissed | Money flows with no audit trail |
| 4.3 | Event properties defined (ids, amounts, variant, error codes), with no PII | PII in analytics |
| 4.4 | Error alerting: what rate or volume pages someone | Silent failure on money or auth paths |
| 4.5 | Funnel or dashboard defined so success can be judged post-launch | None (P1) |

**Question patterns**
- "Which events must exist to tell whether this worked? Default: `<feature>_viewed`, `_started`, `_completed`, `_failed` with `user_id`."
- "What number, by what date, means this feature succeeded?"

## 5. Rollout, Flags & Rollback (20)

| # | Check | Typical P0 trigger |
|---|---|---|
| 5.1 | Feature flag or gating mechanism named (and the repo's existing flag system reused) | Irreversible launch with no kill switch on money paths |
| 5.2 | Cohort / targeting: internal, % rollout, plan tier, region | None (P1) |
| 5.3 | Kill-switch behavior: what users see when the flag flips off mid-session | Half-completed flows with no recovery |
| 5.4 | Rollback safety: can the code revert without a data repair? Are migrations reversible/additive? | Destructive migration shipped with the feature |
| 5.5 | Hard dependencies and launch prerequisites (legal copy, provider approval, env vars, cron) | Missing compliance/legal sign-off on regulated flows |

**Question patterns**
- "If we flip this off after 1,000 users have used it, what happens to their `<records/credits>`?"
- "Is the migration additive only, so that reverting the code is safe?"

---

## Writing a Good Question

Every question has exactly four parts:

1. **Tag:** `[P0 BLOCKER]` or `[P1 DESIGN CHOICE]`
2. **Question:** specific to *their* feature and *their* repo. Name their tables, routes, libraries.
3. **Why it matters:** one sentence describing the concrete production failure.
4. **Options:** 2–3 concrete choices, exactly one marked `[Recommended Default]`. The default must be the safest reasonable choice, not the most featureful.

Selection rules:

- At most 5 questions per round. If more than 5 gaps exist, ask the P0s, then the P1s with the highest blast radius. Lock the rest with recommended defaults and list them under "Assumed Defaults".
- Merge related gaps into one question when the options naturally cover both.
- Never ask a question the repo answers. Read `package.json`, the schema, and existing routes first.
- Never ask "Have you thought about X?". Ask "What should happen when X?" and give options.

## Scorecard Output

```
Spec Readiness: 41/100 — BLOCKED (3 P0)
State 8/20 · Data 6/20 · Abuse 2/20 · Telemetry 10/20 · Rollout 15/20
Repo: Next.js 15 · Prisma/Postgres · NextAuth v5 · Stripe · Upstash ratelimit · PostHog
```

Use `PASS` instead of `BLOCKED` when the gate opens. Include the `Repo:` line only when recon found something.
