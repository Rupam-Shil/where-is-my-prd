# Phase 2: "referrals v1 is live, let's do phase 2"

**Mode:** `full_grill`, `phase: 2` · **User turns:** 2 · **Result:** [`prd/referral-system-v2-prd.md`](prd/referral-system-v2-prd.md) (88/100, 0 P0), linked to [`prd/referral-system-prd.md`](prd/referral-system-prd.md), then the build

Recorded from eval scenario `21-referral-phase-2` ([`evals/`](../evals/)): headless Claude Code (Sonnet) on [`acme-saas-referrals`](../evals/fixtures/acme-saas-referrals), which is the fixture app plus the v1 referral system and its locked PRD. Lightly trimmed for length.

---

### User

> referrals v1 is live. let's do phase 2: tiered rewards ($10 for each of a referrer's first 3 friends, $20 per friend after that) and let referrers cash out their credit balance to their bank through Stripe Connect

### Agent: baseline first, no files touched

```text
Baseline: what phase 2 builds on (docs/prd/referral-system-prd.md, v1; the code shipped)
- Referral status is rewarded / referrer_capped / rejected. CreditLedger is append-only in cents,
  User.credits is a cached balance. Flat REWARD_CENTS = 1000 both sides, 5 rewarded/month cap.
- The v1 PRD lists cash payouts and tiered rewards as Non-Goals. Phase 2 reverses both, so it
  needs its own PRD, and the gate stays closed until that PRD is locked.
- Nothing spends User.credits today. The ledger can't tell promo credit from cash-grade credit,
  except by role.
- stripe@17.4.0 is installed, but there's no Connect account, payout model, or webhook route.

Spec Readiness: 38/100 — BLOCKED (5 P0)
State 8/20 · Data 8/20 · Abuse 4/20 · Telemetry 8/20 · Rollout 10/20

1. [P0 BLOCKER] How does "first 3 friends, then $20" count, and does the v1 5/month cap stay?
   Why it matters: The tier is decided inside the FOR UPDATE transaction in processNewUser. If the
   count or the cap is ambiguous, concurrent signups pay the wrong amount, and v1 referrals
   already paid at $10 get double-counted or paid again.
   A) Lifetime count of rewarded referrals, existing ones included. No back-pay, no clawback.
      The 5/month cap stays. Referee still gets $10 [Recommended Default]
   B) Same, but remove the monthly cap
   C) Reset everyone to 0 at launch

2. [P0 BLOCKER] Which credits can be cashed out?
   Why it matters: User.credits mixes referrer rewards with referee signup bonuses. If all of it
   is cashable, anyone can sign up through a link, withdraw $10, and repeat with throwaway
   Google accounts.
   A) Only referrer-earned credit (role = referrer). Referee bonus stays promo credit.
      Cashable balance = earned minus paid out, from the ledger [Recommended Default]
   B) The whole balance   C) Nothing until something spends credits

3. [P0 BLOCKER] What eligibility, hold, and minimum apply before money leaves?
4. [P0 BLOCKER] How is a payout made safe against double-pay and half-failures?
5. [P0 BLOCKER] Where and how does this launch (jurisdiction, tax, flag)?

Reply like `1A 2B 3: 7-day hold`, or `defaults` to accept every recommendation.
```

### User

> defaults

### Agent: a new linked PRD, then the build

```text
Spec locked in docs/prd/referral-system-v2-prd.md (phase 2, 88/100, passes validate-prd.sh).
I left the v1 PRD unedited.

Rules locked:
- Tiers: $10 for each of a referrer's first 3 friends, $20 after. The friend still gets $10.
- Existing paid referrals count toward the first 3, with no back-pay. The 5/month cap stays.
- Only referrer-earned credit is cashable, 14 days after it's granted. $25 minimum,
  1 cash-out per day. US only, via Stripe Express. One bank account per user.
- Kill switch: the new PostHog flag referral_cashout_enabled fails closed.

Built: an additive schema (Connect fields, Payout, StripeEvent, referrerRewardCents),
tiering under the existing referrer row lock, cashout.ts, onboarding and cash-out routes,
a signed and deduped Connect webhook, a daily payout reconciliation cron, and dashboard balances.

Flagged for review: Stripe's payout.paid/failed events don't say which of our payouts they're
for. I match them to the oldest open payout, which is safe only because of the 1-per-day limit.
Run /code-review before this goes near money.
```

### The PRD's lineage

```yaml
# docs/prd/referral-system-v2-prd.md
feature_slug: referral-system-v2
phase: 2
parent_prd: docs/prd/referral-system-prd.md
```

Its **Baseline & Changes** section records:

- **The drift check:** "code matches the PRD, no drift found".
- **Added / Changed / Removed:** the full table.
- **Carried over unchanged:** the referee's $10, the 5/month cap, the anti-farming rules, and the event names.
- **Existing data and users:** past referrals count toward tiers. Legacy rows with no stored amount are treated as $10, and existing referee credit stays non-cashable.

The v1 PRD is byte-for-byte unchanged: it's the record of what shipped.
