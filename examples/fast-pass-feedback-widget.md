# Fast Pass: a spec that's already good

**Mode:** `fast_pass` · **User turns:** 1 · **Questions asked:** 0 · **Result:** [`prd/beta-feedback-widget-prd.md`](prd/beta-feedback-widget-prd.md) (88/100, 0 P0)

Recorded from a test run: Claude Sonnet as a Claude Code agent on a Next.js 15 + Prisma + NextAuth v5 + Stripe repo. Lightly trimmed for length.

A good spec shouldn't be punished with performative questions. When the score is ≥ 85 with zero P0 blockers, the skill confirms the spec, surfaces only real blind spots, writes the PRD, and stops.

---

### User

> Build the closed-beta feedback widget. Spec:
>
> - Floating "Feedback" button on /dashboard only. Gated by PostHog feature flag `beta-feedback-widget` (default off). Rollout: internal team first, then 100% of the beta cohort. Kill switch: flag off hides the button; feedback already submitted is kept.
> - Clicking opens a modal: message textarea (required, trimmed, 10–2000 chars), optional 1–5 star rating, optional "OK to contact me" checkbox (default unchecked).
> - States: idle; modal open; submitting (submit disabled + spinner); success (toast "Thanks!"); error (inline, text preserved, Retry); rate-limited (429 → "try again in an hour"). Empty state: N/A. Closing mid-submit: the request continues and the toast still shows.
> - API: POST /api/feedback. NextAuth session required (401). Body validated with zod (400). Returns 201 {id}. Idempotency-Key UUID per modal open; unique on (userId, idempotencyKey).
> - Prisma: new Feedback model … @@unique([userId, idempotencyKey]); @@index([createdAt]). Additive migration only.
> - Abuse/security: Upstash ratelimit, 5 per user per hour. Plain text, rendered escaped. Never log message text or emails.
> - Telemetry (PostHog, server-side): feedback_opened, feedback_submitted, feedback_failed, feedback_dismissed. KPI: 30% of beta users submit within 2 weeks. Alert: feedback_failed > 5% over 1h → Slack #beta-alerts.
> - Out of scope: admin UI, email notifications, attachments.
> - Rollback: flag off; table stays; additive migration so reverting is safe.

### Agent

```text
Spec Readiness: 88/100 — PASS (0 P0)
State 18/20 · Data 18/20 · Abuse 18/20 · Telemetry 17/20 · Rollout 17/20
Repo: Next.js 15 · Prisma/Postgres · NextAuth v5 · Upstash ratelimit · posthog-node · Stripe

Your spec is thorough, so no questions. Minor assumptions I made (all in PRD §8):
- The flag is evaluated server-side in the /dashboard server component via posthog-node.
  The repo has no client PostHog SDK.
- feedback_opened / feedback_dismissed are relayed through a tiny authed route
  (POST /api/feedback/events) so all telemetry stays server-side.
- Upstash outage → rate limiter fails open (beta-only, low blast radius).
- A replayed Idempotency-Key returns the original 201 without consuming quota.
- `page` is set server-side from an allowlist, never trusted from the client.
- `zod` isn't installed yet. The toast is a small local component, no new library.
- Messages may contain user PII: stored as plain text, cascade-deleted with the
  user, no retention job in v1.

PRD: docs/prd/beta-feedback-widget-prd.md (13 acceptance criteria, 5 ordered tasks).

Spec is locked. Ready to start implementation?
```

```text
$ sh validate-prd.sh docs/prd/beta-feedback-widget-prd.md
PASS docs/prd/beta-feedback-widget-prd.md (score 88/100, fast_pass)

1 checked, 0 failed
```

**Files written:** `docs/prd/beta-feedback-widget-prd.md` only. Read the full spec: [`prd/beta-feedback-widget-prd.md`](prd/beta-feedback-widget-prd.md).
