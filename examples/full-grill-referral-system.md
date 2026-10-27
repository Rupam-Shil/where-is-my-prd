# Full Grill: "add a referral system"

**Mode:** `full_grill` · **User turns:** 2 · **Result:** [`prd/referral-system-prd.md`](prd/referral-system-prd.md) (86/100, 0 P0), then the build

Recorded from eval scenario `01-referral-urgency` ([`evals/`](../evals/)): headless Claude Code (Sonnet) with the plugin loaded, on the [fixture app](../evals/fixtures/acme-saas) (Next.js 15, Prisma, NextAuth v5 with Google, Stripe, Upstash, PostHog). Lightly trimmed for length.

---

## Without the skill

Same prompt, same repo shape, same model. The agent:

- asked **zero** questions
- edited **4 files**, including `prisma/schema.prisma`
- made **9 decisions nobody asked for**, including:
  - granting $10 at raw signup, which anyone can farm with throwaway emails
  - no ledger, so there is no record of why a balance changed
  - no per-referrer cap
  - assuming `credits` is in cents without checking

After writing the code, it listed the questions it *would* have asked.

---

## With the skill

### User

> add a referral system — users get a referral link, and when a friend signs up both of them get $10 credit. ship it today pls

### Agent: 45 seconds, no files touched

```text
Spec Readiness: 32/100 — BLOCKED (3 P0)
State 10/20 · Data 6/20 · Abuse 4/20 · Telemetry 6/20 · Rollout 6/20
Repo: Next.js 15 · Prisma/Postgres · NextAuth v5 (Google only, database sessions) · Stripe · Upstash ratelimit · PostHog

What the repo already answers: `User.credits` is an Int with no ledger and nothing that spends it;
sign-in is Google-only, so `events.createUser` in `src/auth.ts` is the hook; there is no
feature-flag system and no existing PRD.

1. [P0 BLOCKER] What unit is `User.credits`, and what is "$10"?
   Why it matters: Guess wrong and every referral grants 10x or 1000x the intended amount, and the fix is balance repair.
   A) Integer cents (1000 = $10) + an append-only CreditLedger (unique referralId + role);
      User.credits becomes a cached balance [Recommended Default]
   B) 1 credit = $1, so the grant is 10, with no ledger
   C) Something else

2. [P0 BLOCKER] When is the $10 granted, and what stops farming?
   Why it matters: Google accounts are free, so `+aliases` and throwaways would mint unlimited credit for one person.
   A) Grant at signup, with guards: verified Google email, Gmail dots/+tags normalized,
      self-referral blocked, 5 signups per IP per day, at most 20 rewards per referrer [Recommended Default]
   B) Credit both sides only after the friend's first paid Stripe invoice
   C) Grant at signup with no caps (not recommended)

3. [P0 BLOCKER] How is a referral attributed, and how is it kept from paying twice?
   Why it matters: The OAuth redirect drops `?ref=`, and a retried callback could credit twice.
   A) `/r/<code>` sets a 30-day httpOnly cookie, applied only in `events.createUser`;
      Referral.refereeId is unique; referral + both ledger rows in one transaction [Recommended Default]
   B) Pass the code through the OAuth `state`
   C) Make the friend type the code in by hand

4. [P0 BLOCKER] What is the kill switch, and what if it flips off?
   Why it matters: This path moves money, and abuse found after launch needs an off switch that doesn't need a deploy.
   A) A PostHog flag `referrals_enabled` that fails closed: off stops new grants, earned credits stay;
      additive migration, so the code can be rolled back safely [Recommended Default]
   B) An env var (changing it needs a redeploy)

Reply like `1A 2B 3A 4A`, or `defaults` to accept every recommendation.
```

### User

> use your recommended defaults, except cap referral rewards at 5 per referrer per month

### Agent: PRD first, then the build

```text
Spec: docs/prd/referral-system-prd.md passes the validator (86/100, 0 P0 left), with your cap
of 5 rewards per referrer per calendar month (UTC) in place of the default 20.

What I built:
- Schema: User.referralCode + User.emailNormalized (nullable, unique), new Referral and
  CreditLedger models. All additive. User.credits is now a cached balance in cents.
- /r/[code]: sets a 30-day httpOnly cookie, rate-limited to 30 per IP per minute.
- src/lib/referral.ts, called from events.createUser:
  - blocks self-referral, duplicate Gmail aliases, unverified emails, and more than 5 signups per IP per day
  - locks the referrer's row so concurrent signups can't both pass the monthly cap
  - writes the referral, both ledger rows, and both balances in one transaction
  - never blocks signup if anything fails
- Dashboard: shows the link, count, and monthly progress. /api/referral returns 401 when signed out.
- Kill switch: PostHog `referrals_enabled`, fails closed.
- Events: referral_link_viewed, referral_attributed, referral_rewarded, referral_rejected,
  referral_failed. No PII.

Before you ship: npm i && npx prisma migrate dev && npx tsc --noEmit; create the flag (off);
add tests for the grant transaction and the email normalization (there's no test framework yet).

One decision for you: a capped referrer gets nothing, but the friend still gets the $10 they
were promised. If you'd rather reward neither, it's a one-line change.
```

```text
$ git log --stat
docs/prd/referral-system-prd.md   ← written and validated first
prisma/schema.prisma
src/lib/referral.ts
src/auth.ts
src/app/r/[code]/route.ts
src/app/api/referral/route.ts
src/app/dashboard/page.tsx
src/lib/email.ts
src/lib/flags.ts
```

The eval harness checks the order of every write. The PRD existed and passed validation before the first application file was touched. Read the full spec: [`prd/referral-system-prd.md`](prd/referral-system-prd.md).
