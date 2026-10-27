---
feature_slug: referral-system-v2
title: Referral System v2 — Tiered Rewards & Stripe Connect Cash-Out
spec_readiness_score: 88
p0_blockers_remaining: 0
interrogation_mode: full_grill
approved_at: 2026-10-27T07:48:06Z
phase: 2
parent_prd: docs/prd/referral-system-prd.md
generated_by: wheres-my-prd@1.0.0
---

# Referral System v2 — Tiered Rewards & Stripe Connect Cash-Out

> Spec Readiness 88/100 · P0 remaining: 0 · Mode: full_grill
> State 17/20 · Data 18/20 · Abuse 18/20 · Telemetry 17/20 · Rollout 18/20

## 1. Overview & Problem Statement

- **Problem:** v1 credits are a flat $10 with no way to withdraw; heavy referrers have no incentive to keep going and credits have no consumer.
- **Solution:** Referrer reward becomes tiered ($10 for each of a referrer's first 3 rewarded friends, $20 after), and referrers can cash out their earned credit to a bank via Stripe Connect Express.
- **Primary user:** Referrers who have earned credit.
- **Repo context:** Next.js 15, Prisma/Postgres, NextAuth v5 (Google), `stripe@17.4.0` (billing only so far), Upstash ratelimit, PostHog flags (fail closed). `processNewUser` in `src/lib/referral.ts` grants inside a `FOR UPDATE` transaction on the referrer row; `CreditLedger` is append-only in cents with `role`.

### Baseline & Changes

- **Builds on:** `docs/prd/referral-system-prd.md` (v1, shipped; code matches the PRD, no drift found).
- **As built today:** flat `REWARD_CENTS = 1000` for both sides; cap 5 rewarded/referrer/UTC month; `User.credits` cached balance; no Connect account, payout model, or Stripe webhook route.

| Change | What | Why |
|---|---|---|
| Added | Referrer tier: rank by lifetime `rewarded` count (1–3 → 1000c, 4+ → 2000c) | Reward heavy referrers |
| Added | Stripe Connect Express onboarding, `Payout` model, cash-out endpoint, Connect webhook, daily reconciliation | Cash out |
| Added | Cashable balance derived from ledger (referrer-role earnings matured 14d, minus payouts) | Block farming via referee bonus |
| Added | Flag `referral_cashout_enabled` | Independent kill switch |
| Changed | `processNewUser` computes referrer amount by tier; `Referral.referrerRewardCents` records it | Tiering |
| Changed | Dashboard shows cashable / pending / non-cashable balances and payout history | Visibility |
| Changed | v1 Non-Goals "cash payouts, tiered rewards" are now in scope | Phase 2 |
| Removed | nothing | n/a |

- **Carried over unchanged:** referee gets 1000c; 5 rewarded/month cap; email normalization, verified-email, IP limit; `referrals_enabled` flag; existing event names; integer cents; append-only ledger.
- **Existing data and users:** Existing `rewarded` referrals count toward the first 3 (no back-pay, no clawback). Existing referrer-role ledger rows older than 14 days are immediately cashable; none are rewritten. `Referral.referrerRewardCents` is NULL on old rows and treated as 1000 for legacy. Existing referee credit stays non-cashable.

## 2. User Flow & State Machine

**Happy path**
1. Referrer with cashable balance ≥ $25 opens `/dashboard`, clicks "Cash out".
2. If no Connect account: server creates an Express account and redirects to Stripe onboarding; return URL lands on dashboard; `account.updated` webhook sets `payoutsEnabled`.
3. Referrer requests an amount (≤ cashable). Server debits the ledger and creates a Payout in one transaction, then creates the Stripe Transfer with idempotency key.
4. Webhook marks the Payout `paid`; dashboard shows history.

| State | Trigger | What the user/API sees | Next states |
|---|---|---|---|
| Idle | Dashboard load | Cashable / pending (matures date) / non-cashable balances, "Cash out" if flag on | Loading, Empty |
| Loading (onboarding / submitting) | Click Cash out | Button disabled, spinner; redirect to Stripe if onboarding needed | Success, Error |
| Success | Payout `paid` | History row "Paid $X"; balance reduced | Idle |
| Empty | Cashable = 0 and no history | "Earn credit by inviting friends. Cash out from $25." | Idle |
| Error | Transfer or onboarding fails | Payout `failed`, ledger reversal restores balance, retry offered | Idle |
| Rate-Limited | >1 payout request per user per 24h, or >10 cash-out API calls/min | 429 + Retry-After; message "One cash-out per day" | Idle |

Payout statuses: `requested` → `paid` | `failed` | `reversed`.

## 3. Data Contracts & Schema Changes

**Schema changes (additive only)**

| Table / model | Change | Type & nullability | Default / backfill | Index |
|---|---|---|---|---|
| User | add `stripeConnectAccountId` | `String?` | NULL | unique |
| User | add `payoutsEnabled` | `Boolean` | default false | none |
| User | add `payoutFingerprint` | `String?` (Stripe bank-account fingerprint) | NULL | unique |
| Referral | add `referrerRewardCents` | `Int?` | NULL on old rows (legacy = 1000) | none |
| Payout | new: id, userId, amountCents Int, currency String `usd`, status, idempotencyKey, stripeTransferId?, failureCode?, createdAt, updatedAt | see left | n/a | unique(idempotencyKey), unique(stripeTransferId), index(userId, createdAt) |
| CreditLedger | add `payoutId` | `String?` | NULL | unique(payoutId, reason) |
| StripeEvent | new: id (Stripe `event.id`), type, processedAt | see left | n/a | PK on id |

Ledger reasons: existing `referral`; new `cashout` (negative amount), `cashout_reversal` (positive). `User.credits` decremented/incremented in the same transaction. Amounts are integer cents, `currency` is `usd`, all timestamps UTC.

**Cashable balance (derived, ledger is truth):** `sum(amountCents where role=referrer, reason=referral, createdAt <= now-14d) + sum(cashout and cashout_reversal rows)`, floored at 0 and capped at `User.credits`.

**Migration safety:** new nullable columns, one `Boolean DEFAULT false`, new tables only; no locks beyond index builds; revert code and leave tables unused.

**API / payload contracts**

| Endpoint / event | Input (validated) | Output | Errors | Idempotency |
|---|---|---|---|---|
| POST `/api/cashout/onboard` (auth, flag) | none | `{ url }` Stripe account link | 401, 404 flag off, 429 | reuses existing account id |
| POST `/api/cashout` (auth, flag) | `{ amountCents: int, 2500 ≤ n ≤ cashable }` | `{ payoutId, status }` | 400 invalid / below min, 401, 403 not onboarded, 404 flag off, 409 daily limit, 429 | Server-generated key `cashout:<payoutId>` as Stripe idempotency key; unique(idempotencyKey) |
| GET `/api/referral` (auth) | session | existing fields + `cashableCents`, `pendingCents`, `nonCashableCents`, `payouts[]` (additive) | 401 | n/a |
| POST `/api/stripe/connect-webhook` | raw body + `Stripe-Signature` | 200 | 400 bad signature | `StripeEvent.id` unique; replays no-op |

Webhook events handled: `account.updated`, `payout.paid`/`payout.failed` (connected account), `transfer.reversed`. Webhook is the source of truth for final Payout status; the API response is interim.

## 4. Edge Cases, Abuse Vectors & Guardrails

| Case | Expected behavior | Guardrail |
|---|---|---|
| Double-click / two tabs cash out | One Payout | `FOR UPDATE` on User row; cashable recomputed inside the lock; 1 request/day check inside the lock |
| Two simultaneous signups at tier boundary | Exactly first 3 get 1000c | Rank counted inside existing referrer `FOR UPDATE` transaction |
| Farming via referee bonus | Cannot be withdrawn | Referee ledger rows excluded from cashable |
| Farmed referrals then withdraw | Held 14 days; reviewable | 14-day maturity; min $25; 1/day; alert on volume |
| Two users, one bank account | Second blocked at `account.updated` | unique(`payoutFingerprint`); payouts stay disabled |
| Transfer fails after debit | Balance restored | Compensating `cashout_reversal` ledger row; Payout `failed` |
| Transfer later reversed (`transfer.reversed`) | Balance restored, Payout `reversed` | Same, deduped by `StripeEvent.id` |
| Platform balance too low | Payout `failed` (`insufficient_funds`), reversal, alert | Daily reconciliation + low-balance alert |
| Request > cashable / < $25 | 400 | Server-side validation |
| Flag flips off mid-flow | New cash-outs 404; in-flight Payouts still settle via webhook | Webhook not flag-gated |
| Account deleted with pending payout | Payout settles; ledger retained | No cascade on Payout/ledger |
| Non-US Google user | "Not available in your country yet" | Country from Stripe account must be `US`; reject otherwise |

- **AuthZ:** all endpoints scope to session user; Payout reads filtered by `userId`; ledger never client-writable. Webhook verifies signature before any parsing side effects.
- **Third-party failure:** Stripe 5xx/timeout on transfer → Payout stays `requested`, retried with the same idempotency key by reconciliation; webhook outage → reconciliation daily job pulls Stripe state. Stripe outage never affects signup or dashboard reads.
- **Sensitive data:** no bank details, Stripe account ids, emails, or IPs in logs or analytics; ids and amounts only. Bank data lives only in Stripe.

## 5. Telemetry & Event Logging

- **Primary KPI:** 40% of referrers with at least one matured reward connect a bank within 30 days of first cashable balance. Baseline: v1 share rate target (10% of WAU).
- **Alerting:** `cashout_failed` >5 in 1h; platform Stripe balance < sum of `requested` Payouts + $1,000; >$X (default $2,000) requested in 1h; reconciliation mismatch >0 notifies the team.

| Event | Fired when | Properties (no PII) |
|---|---|---|
| referral_rewarded (existing) | grant committed | referrer_id, referee_id, amount_cents (now 1000 or 2000), tier |
| cashout_onboarding_started | account link created | user_id |
| cashout_requested | Payout created | user_id, payout_id, amount_cents |
| cashout_paid | webhook confirms | user_id, payout_id, amount_cents |
| cashout_failed | transfer/payout fails | user_id, payout_id, error_code |
| cashout_reversed | reversal credited back | user_id, payout_id, amount_cents |

## 6. Rollout, Feature Flags & Rollback

- **Flag:** PostHog `referral_cashout_enabled`, default off, fails closed. Tiering ships under the existing `referrals_enabled`.
- **Cohorts:** internal → 10% → 100%.
- **Kill switch:** off hides Cash out and returns 404 on new cash-out calls; credits keep accruing; in-flight Payouts finish via webhook.
- **Rollback:** code revert is safe; migration additive; any `requested` Payouts must be reconciled (webhook/cron) before reverting. Tier amounts already granted stay valid.
- **Launch prerequisites:** Stripe Connect enabled on the account with Express; Connect webhook endpoint + `STRIPE_CONNECT_WEBHOOK_SECRET`; platform balance funded; daily reconciliation cron scheduled; legal and tax sign-off on paying referrers (US-only); `prisma migrate` before deploy.

## 7. Out of Scope (Non-Goals)

- Non-US payouts, other currencies, other payout providers.
- Clawing back past rewards; recovering payouts after referee refund/chargeback.
- Spending credits inside the product (still no consumer).
- Making referee bonus cashable.
- Admin UI for manual payout review.

## 8. Open Risks & Assumed Defaults

| Item | Decision | Source | Risk if wrong |
|---|---|---|---|
| Tier counting | Lifetime `rewarded` rank, inside referrer lock; existing rewarded count; no back-pay; 5/month cap kept; referee 1000c | recommended-default | Heavy referrers may feel the cap blocks the $20 tier |
| Cashable credits | Only referrer-role credits | recommended-default | Referees feel their $10 is stuck |
| Eligibility | Express KYC, 14-day hold, $25 minimum, unique account fingerprint, 1 payout/day | recommended-default | Hold delays legitimate users; minimum strands small balances |
| Payout safety | Debit-then-transfer with idempotency key, webhook truth, compensating reversal, daily reconciliation, low-balance alert | recommended-default | Reconciliation lag shows stale status for up to a day |
| Launch | US-only, separate fail-closed flag, legal/tax prerequisite | recommended-default | Non-US users blocked |
| Events | New `cashout_*` events; v1 names unchanged | assumed | Dashboards need updating |
| Dashboard | Show cashable / pending / non-cashable and history | assumed | n/a |
| KPI | 40% connect within 30d of first cashable | assumed | Target may be wrong |
| Refund after payout | Not recovered | assumed | Paid-out reward for a referee who later refunds is lost |
| Alert threshold | $2,000/hour requested | assumed | Too noisy or too lax |

## 9. Acceptance Criteria

- **AC-1:** Given a referrer with 0–2 prior `rewarded` referrals, when a new valid friend signs up, then the referrer ledger gets 1000c and `Referral.referrerRewardCents` = 1000; with 3+ prior, 2000c; referee always 1000c.
- **AC-2:** Given 4 concurrent signups for a referrer with 2 prior rewards, then exactly one is paid 1000c as tier 1 and the rest 2000c (no double tier-1), subject to the monthly cap.
- **AC-3:** Given v1 `rewarded` referrals, then they count toward the first 3 and no ledger rows are created or changed for them.
- **AC-4:** Given the cashable calculation, then referee-role credits, referrer credits younger than 14 days, and amounts above `User.credits` are excluded.
- **AC-5:** Given amount < 2500 or > cashable, when POST `/api/cashout`, then 400 and no ledger or Payout rows.
- **AC-6:** Given two concurrent valid cash-out requests, then exactly one Payout and one negative ledger row exist (the other gets 409/429).
- **AC-7:** Given a user without a Connect account or with `payoutsEnabled` false, when cashing out, then 403 and onboarding is offered; non-US accounts are rejected.
- **AC-8:** Given a Transfer failure or `transfer.reversed`, then Payout becomes `failed`/`reversed`, a `cashout_reversal` ledger row restores the balance exactly once.
- **AC-9:** Given a replayed or unsigned webhook, then a bad signature returns 400 and a repeated `event.id` has no effect.
- **AC-10:** Given a bank fingerprint already used by another user, then payouts stay disabled for the second user.
- **AC-11:** Given `referral_cashout_enabled` off or unreachable, then Cash out UI is hidden, new cash-out calls return 404, in-flight Payouts still settle, and earning is unaffected.
- **AC-12:** Given the daily reconciliation, when a Payout is `requested` older than 1h, then it is resolved against Stripe or alerted, and mismatches fire an alert.
- **AC-13:** Events `cashout_*` and updated `referral_rewarded` fire with the specified properties and no PII.
- **AC-14:** `GET /api/referral` and cash-out endpoints return only the caller's data; unauthenticated gets 401.

## 10. IMPLEMENTATION_TASKS

- [ ] T1: Prisma migration: User Connect fields, `Referral.referrerRewardCents`, `Payout`, `StripeEvent`, `CreditLedger.payoutId` (additive) (AC-3, AC-6, AC-9, AC-10)
- [ ] T2: Tier calculation in `processNewUser` + tests, incl. concurrency and legacy rows (AC-1, AC-2, AC-3)
- [ ] T3: Cashable balance helper + tests (AC-4)
- [ ] T4: Flag helper `referral_cashout_enabled` (AC-11)
- [ ] T5: `/api/cashout/onboard` and Connect webhook with signature check, dedupe, fingerprint uniqueness, US-only (AC-7, AC-9, AC-10)
- [ ] T6: `/api/cashout` with lock, validation, ledger debit, idempotent Transfer, ratelimit, reversal handling + tests (AC-5, AC-6, AC-8, AC-14)
- [ ] T7: Daily reconciliation job + low-balance alert (AC-12)
- [ ] T8: `/api/referral` additive fields and dashboard UI states (AC-4, AC-11, AC-14)
- [ ] T9: Telemetry events and alert thresholds (AC-13)
