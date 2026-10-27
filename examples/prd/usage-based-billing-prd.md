---
feature_slug: usage-based-billing
title: Usage-Based Billing (Stripe Metered)
spec_readiness_score: 52
p0_blockers_remaining: 0
interrogation_mode: emergency_default_lock
approved_at: 2026-10-26T19:44:16Z
generated_by: wheres-my-prd@1.0.0
---

# Usage-Based Billing (Stripe Metered)

> Spec Readiness 52/100 · P0 remaining: 0 · Mode: emergency_default_lock
> State 10/20 · Data 12/20 · Abuse 10/20 · Telemetry 10/20 · Rollout 10/20

## 1. Overview & Problem Statement

- **Problem:** Customers cannot be charged per API call; only flat subscriptions exist.
- **Solution:** Record each billable API call locally and report it to a Stripe Billing Meter priced at $0.002 per call.
- **Primary user:** Authenticated customers calling the product API.
- **Repo context:** Next.js 15 App Router, Prisma/Postgres, NextAuth v5 (`@/auth`), `stripe@17.4.0`, `@upstash/ratelimit`, `posthog-node`. `User.stripeCustomerId` and `Subscription` exist. The only API route is `src/app/api/auth/route.ts`; there is no billable API yet, so a demo route `GET /api/v1/ping` is the metered endpoint.

## 2. User Flow & State Machine

**Happy path**
1. Signed-in user with a `stripeCustomerId` calls `GET /api/v1/ping`.
2. Server checks flag, auth, and rate limit, then inserts a `UsageEvent` row (unique `idempotencyKey`).
3. Server returns 200 immediately; a reporter sends unreported rows to the Stripe meter, using the row id as the Stripe event identifier.
4. Dashboard shows calls this period and estimated cost.

| State | Trigger | What the user/API sees | Next states |
|---|---|---|---|
| Idle | No calls this period | Dashboard: 0 calls, $0.00 | Loading |
| Loading | Dashboard fetches usage | Skeleton text | Success, Empty, Error |
| Success | Call recorded | 200 + body; dashboard count and estimate | Idle, Rate-Limited |
| Empty | User has no `stripeCustomerId` | 402 `billing_not_set_up`; dashboard shows "Set up billing" | Idle |
| Error | DB write fails | 503 `usage_unavailable`; call is NOT served (fail closed, no free calls) | Idle |
| Rate-Limited | Over 60 calls/min per user | 429 + `Retry-After` | Idle |

## 3. Data Contracts & Schema Changes

**Schema changes**

| Table / model | Change | Type & nullability | Default / backfill | Index |
|---|---|---|---|---|
| UsageEvent | add table | id cuid PK; userId String; idempotencyKey String unique; quantity Int; reportedAt DateTime? ; createdAt DateTime | quantity 1; reportedAt null until sent | (userId, createdAt), (reportedAt) |

**Migration safety:** Additive only (new table, no changes to existing tables). No backfill, no locks on existing rows. Money is not stored: price lives in Stripe; we store integer call counts only. Price constant is 0.002 USD = 0.2 cents, held in the Stripe Price (`unit_amount_decimal: "0.2"`, currency usd), never as a float in our DB.

**API / payload contracts**

| Endpoint / event | Input (validated) | Output | Errors | Idempotency |
|---|---|---|---|---|
| GET /api/v1/ping | optional header `Idempotency-Key` (max 64 chars, [A-Za-z0-9_-]); else server-generated | `{ok:true}` | 401, 402, 429, 503 | `UsageEvent.idempotencyKey` unique per user: `<userId>:<key>` |
| GET /api/usage | none (session user only) | `{calls, estimatedCents}` for current month | 401, 503 | read-only |
| POST /api/billing/report | cron secret header | `{reported:n}` | 401 | Stripe meter event `identifier` = UsageEvent.id |

## 4. Edge Cases, Abuse Vectors & Guardrails

| Case | Expected behavior | Guardrail |
|---|---|---|
| Client retries same request | Counted once | Unique idempotencyKey; duplicate returns 200 without a second row |
| Stripe down / meter call fails | Calls still served; rows stay unreported and retry on the next run | reportedAt null; reporter is retried; Stripe `identifier` dedupes |
| Reporter runs twice concurrently | No double billing | Stripe meter event `identifier` = row id (Stripe dedupes) |
| Script floods endpoint | 429 | Upstash ratelimit 60/min per user |
| User A reads user B usage | Impossible | userId always from session, never from input |
| Account without Stripe customer | 402, no usage row | Check before insert |

- **AuthZ:** Session required (`auth()`); userId only from session. Report endpoint requires `CRON_SECRET` bearer.
- **Third-party failure:** Stripe errors never block the API call; reporting is async with retry.
- **Sensitive data:** No emails or Stripe ids in logs or PostHog properties; use internal userId only.

## 5. Telemetry & Event Logging

- **Primary KPI:** Share of recorded calls reported to Stripe within 15 minutes, target 99.9% over 30 days.
- **Alerting:** Any UsageEvent unreported older than 1 hour notifies the on-call channel (manual check of `/api/billing/report` result for the demo).

| Event | Fired when | Properties (no PII) |
|---|---|---|
| usage_billing_started | call recorded | user_id, event_id |
| usage_billing_completed | meter event accepted by Stripe | user_id, event_id, quantity |
| usage_billing_failed | Stripe or DB error | user_id, error_code |

## 6. Rollout, Feature Flags & Rollback

- **Flag:** `USAGE_BILLING_ENABLED` env var (no flag system exists in the repo beyond PostHog; env var is the simplest kill switch). Default off.
- **Cohorts:** Internal accounts, then all, via env.
- **Kill switch:** When off, `/api/v1/ping` still serves but records nothing; already-recorded rows are still reported.
- **Rollback:** Code revert is safe; the new table is additive and unreported rows can be reported later or voided by hand.
- **Launch prerequisites:** `STRIPE_SECRET_KEY`, `STRIPE_METER_EVENT_NAME`, `CRON_SECRET`, Upstash env vars; a Stripe Billing Meter (event name `api_call`, sum aggregation), a metered Price at `unit_amount_decimal` 0.2 USD, attached to each subscriber's subscription; `prisma migrate`.

## 7. Out of Scope (Non-Goals)

- Invoices UI, dunning, proration, free tiers or volume discounts.
- Webhook handling for invoice events.
- Metering endpoints other than the demo route.

## 8. Open Risks & Assumed Defaults

| Item | Decision | Source | Risk if wrong |
|---|---|---|---|
| What counts as an "API call" | Every authenticated 2xx request to `/api/v1/*` | emergency-lock | Wrong events billed; customers overcharged |
| Unit/price representation | 0.2 cent per call via Stripe `unit_amount_decimal`; integer counts locally | emergency-lock | Float drift or 10x mispricing |
| Idempotency | Local unique key plus Stripe meter `identifier` | emergency-lock | Double charges |
| Failure mode on DB error | Fail closed (503) | emergency-lock | Lost availability vs free calls |
| Reporting mechanism | Async batch via cron endpoint, not inline | emergency-lock | Billing lag up to cron interval |
| Free tier / minimums | None | emergency-lock | Customers charged for trivial usage |
| Subscription attachment | Meter price must be added to the Stripe subscription by hand | emergency-lock | Events accepted but not invoiced |
| Rate limit | 60/min per user | emergency-lock | Legit heavy users blocked |
| Customer notice / ToS for usage pricing | Not handled | open-risk | Disputes; legal review needed before real charges |
| Stripe price/meter exist in Stripe | Assumed to be created manually | open-risk | Reporting fails until created |

## 9. Acceptance Criteria

- **AC-1:** Given a signed-in user with a Stripe customer, when they call `/api/v1/ping` with flag on, then exactly one UsageEvent is created and 200 is returned.
- **AC-2:** Given the same Idempotency-Key twice, then only one UsageEvent exists.
- **AC-3:** Given no session, then 401 and no row; given no stripeCustomerId, then 402 and no row.
- **AC-4:** Given more than 60 calls in a minute, then 429 with Retry-After.
- **AC-5:** Given unreported rows, when the report endpoint runs with the cron secret, then each is sent to Stripe with identifier = row id and reportedAt is set; without the secret, 401.
- **AC-6:** Given Stripe fails, then the API call is still served and reportedAt stays null.
- **AC-7:** Given flag off, then no rows are created.
- **AC-8:** `/api/usage` returns only the session user's current-month count.
- **AC-9:** Billing events are emitted to PostHog without email or Stripe ids.

## 10. IMPLEMENTATION_TASKS

- [ ] T1: Add `UsageEvent` model to Prisma schema (additive) (AC-1, AC-2)
- [ ] T2: Billing lib: flag, ratelimit, record usage, report to Stripe meter (AC-2, AC-4, AC-5, AC-6, AC-7)
- [ ] T3: Routes `/api/v1/ping`, `/api/usage`, `/api/billing/report` (AC-1, AC-3, AC-4, AC-5, AC-8)
- [ ] T4: Dashboard usage display with empty state (AC-8)
- [ ] T5: PostHog events (AC-9)
- [ ] T6: Env flag wiring and `.env.example` (AC-7)
