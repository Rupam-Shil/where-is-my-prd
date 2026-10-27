---
feature_slug: referral-system
title: Referral System
spec_readiness_score: 86
p0_blockers_remaining: 0
interrogation_mode: full_grill
approved_at: 2026-10-26T20:35:13Z
generated_by: wheres-my-prd@1.0.0
---

# Referral System

> Spec Readiness 86/100 · P0 remaining: 0 · Mode: full_grill
> State 16/20 · Data 18/20 · Abuse 18/20 · Telemetry 16/20 · Rollout 18/20

## 1. Overview & Problem Statement

- **Problem:** No viral/acquisition loop; growth depends entirely on direct signups.
- **Solution:** Each user gets a referral link; when a friend signs up through it, both receive $10 credit.
- **Primary user:** Existing signed-in users (referrers) and new Google sign-ups (referees).
- **Repo context:** Next.js 15, Prisma/Postgres, NextAuth v5 (Google only, database sessions, `src/auth.ts`), Stripe, Upstash ratelimit (`src/lib/ratelimit.ts`), PostHog (`src/lib/analytics.ts`). `User.credits Int @default(0)` exists with no ledger and no consumer. No feature-flag system and no existing PRD.

## 2. User Flow & State Machine

**Happy path**
1. Referrer opens `/dashboard`, sees link `https://<host>/r/<code>` (code created lazily on first view).
2. Friend visits `/r/<code>`; server validates the code and sets a 30-day httpOnly cookie `ref`, then redirects to sign-in.
3. Friend completes Google sign-in; NextAuth `events.createUser` reads the cookie and runs the grant in one DB transaction.
4. Both users receive 1000 cents; the dashboard shows the new balance and referral count.

| State | Trigger | What the user/API sees | Next states |
|---|---|---|---|
| Idle | Dashboard load | Referral link, copy button, rewards earned this month (n/5) | Loading, Empty |
| Loading (link creation) | First dashboard view, no code yet | Skeleton for link | Success, Error |
| Success | Referral granted | Referrer: "+$10" in balance, count updated. Referee: $10 balance | Idle |
| Empty | Referrer has 0 referrals | "Invite a friend, you both get $10" | Idle |
| Error | Code creation or grant fails | Dashboard shows retry; sign-in is never blocked (grant failure is logged and does not fail signup) | Idle |
| Rate-Limited | >5 referral signups from one IP in 24h, or >30 `/r/<code>` hits per IP per minute | `/r` returns 429 + Retry-After; signup still succeeds but no reward (`rejected: ip_limit`) | Idle |

## 3. Data Contracts & Schema Changes

**Schema changes (additive only)**

| Table / model | Change | Type & nullability | Default / backfill | Index |
|---|---|---|---|---|
| User | add `referralCode` | `String?` | NULL; lazily generated (8-char base32, random) | unique |
| User | add `emailNormalized` | `String?` | NULL; set at signup (lowercase, Gmail dots and `+tag` stripped, googlemail.com→gmail.com) | unique |
| Referral | new model: id, referrerId, refereeId, status (`rewarded` / `referrer_capped` / `rejected`), rejectReason?, createdAt | see left | n/a | unique(refereeId), index(referrerId, createdAt) |
| CreditLedger | new model, append-only: id, userId, amountCents Int, reason, referralId?, role (`referrer` / `referee`), createdAt | see left | n/a | unique(referralId, role), index(userId) |

`User.credits` becomes a cached balance in **integer cents** (so $10 = 1000). It is updated with `increment` in the same transaction as the ledger insert. Existing rows keep their value; assumed 0 everywhere today (no consumer exists in the repo), so no backfill.

**Migration safety:** all new columns nullable, new tables only, no locks on populated tables beyond brief index creation; reversible by reverting code and leaving tables unused.

**API / payload contracts**

| Endpoint / event | Input (validated) | Output | Errors | Idempotency |
|---|---|---|---|---|
| GET `/r/[code]` | code matches `^[A-Z2-7]{8}$` | sets `ref` cookie (httpOnly, Secure, SameSite=Lax, 30d), 302 to sign-in | 404 unknown code, 429 | n/a |
| `events.createUser` hook | cookie `ref` | transaction: insert Referral + 2 ledger rows + 2 credit increments | failures swallowed and logged; signup unaffected | unique(refereeId), unique(referralId, role) |
| GET `/api/referral` (auth) | session | `{ code, link, rewardedThisMonth, remainingThisMonth, totalReferrals }` | 401 | n/a, creates code if missing (unique-violation retry) |

## 4. Edge Cases, Abuse Vectors & Guardrails

| Case | Expected behavior | Guardrail |
|---|---|---|
| Self-referral (own link) | No reward; Referral `rejected: self` | Referrer id == referee id check; existing users never hit `createUser` |
| Alias farming (`a+1@gmail.com`, dotted variants) | No reward; `rejected: duplicate_email` | `emailNormalized` unique |
| Scripted/throwaway Google accounts | No reward beyond limits | Referee email must be `emailVerified`; 5 referral signups per IP per 24h via `ratelimit` |
| Referrer exceeds cap | Referee still gets $10; referrer gets nothing; status `referrer_capped` | Cap: **5 rewarded referrals per referrer per calendar month (UTC)**, counted from Referral rows with status `rewarded` inside the grant transaction |
| Existing user clicks a link | No reward | Reward only in `createUser` |
| Callback fires twice / retry | One grant only | unique(refereeId), unique(referralId, role) |
| Cookie missing/expired/invalid code | Normal signup, no reward | Silent no-op |
| Flag off | Normal signup, no attribution | See §6 |
| Referrer or referee deleted | Ledger rows retained; references stay valid | No cascade delete on ledger; soft-handle at account-deletion time |

- **AuthZ:** `/api/referral` returns only the session user's own data. Ledger is never client-writable.
- **Third-party failure:** Upstash down → fail open for signup (no reward granted, logged as `rejected: ratelimit_unavailable`); never blocks login.
- **Sensitive data:** no emails, IPs, or codes in analytics events or logs; use user ids and hashed IP only.

## 5. Telemetry & Event Logging

- **Primary KPI:** 10% of weekly active users share a link and 3% of new signups come via referral within 60 days of launch.
- **Alerting:** `referral_rejected` rate >30% of attributed signups in 1h, or >50 `referral_rewarded` in 1h, notifies the team (possible farming).

| Event | Fired when | Properties (no PII) |
|---|---|---|
| referral_link_viewed | `/r/<code>` hit with valid code | referrer_id |
| referral_attributed | cookie set | referrer_id |
| referral_rewarded | grant committed | referrer_id, referee_id, amount_cents |
| referral_rejected | attribution rejected or capped | referrer_id, reason |
| referral_failed | grant transaction errors | referrer_id, error_code |

## 6. Rollout, Feature Flags & Rollback

- **Flag:** PostHog feature flag `referrals_enabled`, default off, fails closed (if PostHog is unreachable, treat as off).
- **Cohorts:** internal emails → 10% → 100%.
- **Kill switch:** off stops `/r` attribution and new grants; link UI hidden; existing credits and ledger untouched.
- **Rollback:** code revert is safe; migration is additive; no data repair needed. Granted credits remain valid.
- **Launch prerequisites:** `POSTHOG_API_KEY` set; Upstash env vars set; `prisma migrate` run before deploy; confirm what, if anything, spends `User.credits` (nothing does today).

## 7. Out of Scope (Non-Goals)

- Spending/redeeming credits (no consumer exists).
- Cash payouts, tiered or paid-conversion rewards.
- Email/SMS invite sending, multiple providers, non-Google signup.
- Clawbacks/refund handling for credits already granted.

## 8. Open Risks & Assumed Defaults

| Item | Decision | Source | Risk if wrong |
|---|---|---|---|
| Credit unit | Integer cents, $10 = 1000, with append-only CreditLedger | recommended-default | Wrong grant size if credits were meant as 1 = $1 |
| Grant timing | At signup with guards (verified email, normalization, self-block, 5/IP/day) | recommended-default | Some farming still possible via real distinct Google accounts |
| Referrer cap | 5 rewarded referrals per referrer per month (replaces default 20 lifetime) | user | Limits viral upside; heavy referrers hit the wall quickly |
| Behavior at cap | Referee still gets $10, referrer gets $0 | assumed | Extra cost of up to $10 per capped referral; alternative is to reward neither |
| Attribution | `/r/<code>` cookie, 30d, applied only in `createUser`, unique(refereeId) | recommended-default | Cookie blocked by browser means lost attribution |
| Kill switch | PostHog flag `referrals_enabled`, fail closed | recommended-default | Flag service outage disables referrals |
| Month boundary | Calendar month, UTC | assumed | Cap resets at month start, allowing bursts around boundaries |
| Existing credit values | Assumed 0 for all users | assumed | If non-zero and in other units, the cents change misinterprets them |

## 9. Acceptance Criteria

- **AC-1:** Given a signed-in user, when they open `/dashboard`, then they see a unique referral link and a stable `referralCode` is created at most once.
- **AC-2:** Given a valid `/r/<code>` and a new Google user with a verified email, when they sign up, then exactly one Referral (`rewarded`) and two ledger rows of 1000 cents exist and both `User.credits` increase by 1000.
- **AC-3:** Given a repeated callback or retry for the same referee, then no additional ledger rows or credits are created.
- **AC-4:** Given a self-referral, a duplicate normalized email, or an existing user clicking a link, then no credit is granted and a rejection reason is recorded.
- **AC-5:** Given a referrer with 5 `rewarded` referrals in the current UTC month, when a 6th friend signs up, then the friend gets 1000 cents, the referrer gets 0, and status is `referrer_capped`.
- **AC-6:** Given more than 5 referral signups from one IP in 24h, then further signups succeed without reward (`ip_limit`) and `/r` returns 429 above 30 hits per IP per minute.
- **AC-7:** Given the flag `referrals_enabled` is off (or PostHog is unreachable), then `/r` sets no cookie, no grant occurs, the link UI is hidden, and signup is unaffected.
- **AC-8:** Given a grant transaction failure, then signup still completes, nothing is partially written, and `referral_failed` fires.
- **AC-9:** Events `referral_link_viewed`, `referral_attributed`, `referral_rewarded`, `referral_rejected`, `referral_failed` fire with the specified properties and no PII.
- **AC-10:** `GET /api/referral` returns 401 when unauthenticated and only the caller's own data otherwise.

## 10. IMPLEMENTATION_TASKS

- [ ] T1: Prisma migration: `User.referralCode`, `User.emailNormalized`, `Referral`, `CreditLedger` (additive) (AC-1, AC-2, AC-3)
- [ ] T2: Email normalization helper and unit tests (AC-4)
- [ ] T3: Flag helper (`referrals_enabled`, fail closed) (AC-7)
- [ ] T4: `/r/[code]` route with validation, cookie, ratelimit (AC-6, AC-7)
- [ ] T5: Grant logic in `events.createUser` with transaction, caps, idempotency, tests (AC-2, AC-3, AC-4, AC-5, AC-6, AC-8)
- [ ] T6: `/api/referral` endpoint and dashboard UI with Empty/Loading/Error/Success states (AC-1, AC-10)
- [ ] T7: PostHog events and alert thresholds (AC-9)
