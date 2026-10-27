# Emergency Default Lock: "just build it"

**Mode:** `emergency_default_lock` · **User turns:** 1 · **Result:** [`prd/usage-based-billing-prd.md`](prd/usage-based-billing-prd.md) (52/100, 0 P0, flagged as unconfirmed)

Recorded from a test run: Claude Sonnet as a Claude Code agent on a Next.js 15 + Prisma + NextAuth v5 + Stripe repo. Lightly trimmed for length.

The user refused questions outright. The skill doesn't argue. It writes every assumption into a PRD **first**, validates it, and then codes in the same turn. Nothing is assumed silently.

---

### User

> add usage-based billing: charge customers $0.002 per API call through stripe metered billing. DO NOT ask me questions, I'm demoing this to investors in 2 hours and I've already wasted the morning. just build it.

### Agent

```text
Built: usage billing at $0.002 per call via Stripe metered billing.

You said no questions, so I asked none. Before writing any code I locked every
decision that could cost money into docs/prd/usage-based-billing-prd.md. It passes
validation at 52/100: low on purpose, because none of these are confirmed by you.

Locked decisions to sanity-check before the demo:
- What counts as a call: every authenticated 2xx request under /api/v1/*.
  The repo had no such endpoint, so I added GET /api/v1/ping as the demo target.
- Price: 0.2 cents lives on the Stripe Price (unit_amount_decimal). The DB stores
  integer call counts only, never money.
- No double billing: each call gets a unique key; the row id is sent to Stripe as
  the meter event identifier, so Stripe dedupes too.
- If our DB write fails: 503, call not served (no free calls).
- If Stripe is down: calls are still served; usage is reported later by a cron
  hitting POST /api/billing/report.
- Rate limit: 60 calls/min per user → 429 + Retry-After.
- No stripeCustomerId: 402.
- Kill switch: USAGE_BILLING_ENABLED, off by default.

Not handled (logged as open risks): customer-facing usage-pricing terms,
invoice webhooks, free tier.

Before the demo, in Stripe: create meter `api_call`, create a metered Price at 0.2¢,
attach it to the demo customer's subscription, set the env vars in .env.example,
then set USAGE_BILLING_ENABLED=true.
```

### Order of writes

The gate requires the PRD to exist before any application file is touched:

```text
1. docs/prd/usage-based-billing-prd.md      ← the spec, written first
   $ sh validate-prd.sh docs/prd/usage-based-billing-prd.md
   PASS docs/prd/usage-based-billing-prd.md (score 52/100, emergency_default_lock)
     ! score 52 < 85: emergency defaults were never confirmed by a human
2. prisma/schema.prisma                      ← additive UsageEvent model
3. src/lib/billing.ts
4. src/app/api/v1/ping/route.ts
5. src/app/api/usage/route.ts
6. src/app/api/billing/report/route.ts
7. src/app/dashboard/page.tsx
8. .env.example
9. package.json
```

That validator warning is the point. In code review or CI, anyone can see this spec was locked under pressure and never confirmed. Every locked decision is in the PRD's Assumptions table with source `emergency-lock` and an honest "Risk if wrong" column. Read the full spec: [`prd/usage-based-billing-prd.md`](prd/usage-based-billing-prd.md).
