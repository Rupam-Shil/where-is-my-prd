---
feature_slug: beta-feedback-widget
title: Closed-Beta Feedback Widget
spec_readiness_score: 88
p0_blockers_remaining: 0
interrogation_mode: fast_pass
approved_at: 2026-10-26T19:44:24Z
generated_by: wheres-my-prd@1.0.0
---

# Closed-Beta Feedback Widget

> Spec Readiness 88/100 · P0 remaining: 0 · Mode: fast_pass
> State 18/20 · Data 18/20 · Abuse 18/20 · Telemetry 17/20 · Rollout 17/20

## 1. Overview & Problem Statement

- **Problem:** Closed-beta users have no in-product way to send feedback; the team can't learn what is broken or confusing.
- **Solution:** A flag-gated floating "Feedback" button on /dashboard opening a modal that POSTs to /api/feedback.
- **Primary user:** Closed-beta users (internal team first).
- **Repo context:** Next.js 15 App Router, React 19, NextAuth v5 beta (`auth()` from `@/auth`), Prisma 6/Postgres (`User`, `Subscription`; `db` in `src/lib/db.ts`), `@upstash/ratelimit` and `posthog-node` already installed. No `zod`, no client PostHog SDK, no existing feedback model, no toast lib found. /dashboard is a server component.

## 2. User Flow & State Machine

**Happy path**
1. Server component for /dashboard evaluates flag `beta-feedback-widget` for the user (posthog-node); if on, renders the button.
2. Click opens modal; client generates an Idempotency-Key UUID; `feedback_opened` is sent.
3. User enters message (and optional rating, contact checkbox) and submits.
4. POST /api/feedback returns 201; toast "Thanks!" shows; modal closes.

| State | Trigger | What the user/API sees | Next states |
|---|---|---|---|
| Idle | Flag on, /dashboard loaded | Floating "Feedback" button | Modal open |
| Modal open | Click button | Form: textarea (required, trimmed, 10-2000), optional 1-5 stars, "OK to contact me" unchecked | Submitting, Idle (dismiss) |
| Loading (submitting) | Submit with valid input | Submit disabled + spinner; double-click cannot double-submit | Success, Error, Rate-Limited |
| Success | 201 | Toast "Thanks!", modal closes, form reset | Idle |
| Empty | N/A - no list view in v1 | N/A | N/A |
| Error | Network failure / 5xx / 400 | Inline message, typed text preserved, Retry button (reuses same Idempotency-Key) | Submitting, Idle (dismiss) |
| Rate-Limited | HTTP 429 | "You've sent a lot of feedback — try again in an hour"; text preserved | Modal open, Idle |

- Closing the modal mid-submit: request continues; success toast still shows on 201; on failure, no UI is shown (the draft is discarded on close) and `feedback_failed` is still emitted.
- Key is regenerated only on a fresh modal open, not on Retry.

## 3. Data Contracts & Schema Changes

**Schema changes**

| Table / model | Change | Type & nullability | Default / backfill | Index |
|---|---|---|---|---|
| Feedback | New table | id String cuid PK; userId String FK to User, onDelete Cascade; message VarChar(2000) NOT NULL; rating Int?; contactOk Boolean; idempotencyKey String; page String; createdAt DateTime (UTC) | contactOk false; createdAt now(); no backfill | @@unique([userId, idempotencyKey]); @@index([createdAt]) |
| User | Add back-relation `feedback Feedback[]` (Prisma-only, no column) | n/a | n/a | n/a |

**Migration safety:** Additive only (CREATE TABLE + FK + indexes); new empty table, no lock on existing tables, no backfill. Reverting code leaves the table unused and harmless.

**API / payload contracts**

| Endpoint / event | Input (validated) | Output | Errors | Idempotency |
|---|---|---|---|---|
| POST /api/feedback | Header `Idempotency-Key` (UUID, required). Body zod: `message` string, trimmed, 10-2000; `rating` int 1-5 optional; `contactOk` boolean (default false). `page` set server-side from a fixed allowlist (`/dashboard`), not trusted from client. Body size capped (~8 KB). | 201 `{id}` | 401 no session; 400 `{errors: {field: [msgs]}}` (zod flatten); 429 + Retry-After; 500 | Unique (userId, idempotencyKey); on conflict return the original row's 201 `{id}` |

## 4. Edge Cases, Abuse Vectors & Guardrails

| Case | Expected behavior | Guardrail |
|---|---|---|
| Double-click submit | One row | Submit disabled while in flight + DB unique constraint |
| Retry after network drop where first request succeeded | Original 201 `{id}`, no second row | Same Idempotency-Key + unique constraint |
| Duplicate replay vs quota | Duplicate returns original 201 without consuming extra quota (lookup before limiter) | Existing-row check first |
| Two tabs | Distinct keys; both count toward the limit | Upstash limit |
| Spam | 5 submissions / user / hour, sliding window | `@upstash/ratelimit` keyed `feedback:<userId>` |
| Upstash unavailable | Fail open with server error log (no message text); accept submission | Documented tradeoff: beta-only, low blast radius |
| Malicious markup in message | Stored as plain text; always rendered escaped (React default; never `dangerouslySetInnerHTML`; Prisma Studio shows raw text) | Escaped rendering |
| Flag turned off mid-session | Button hidden on next load; in-flight/open modal may complete; API still accepts authed requests | Existing feedback retained |
| User deleted | Feedback rows cascade-deleted | FK onDelete Cascade |

- **AuthZ:** NextAuth session required (401 otherwise); userId always from session, never from body. No read endpoint in v1, so no cross-user read path.
- **Third-party failure:** PostHog failures never block or fail the request (fire-and-forget, errors swallowed and logged without PII). Flag eval failure resolves to off.
- **Sensitive data:** Never log message text or emails; log only feedback id. PostHog distinct id is `user.id`; no message or email in event properties.

## 5. Telemetry & Event Logging

- **Primary KPI:** 30% of beta users submit at least once within 2 weeks of flag exposure.
- **Alerting:** `feedback_failed` > 5% of attempts over 1 hour posts to Slack #beta-alerts (PostHog alert/insight with Slack destination; attempts = `feedback_submitted` + `feedback_failed`).

All events are captured server-side via posthog-node. Client-only moments (opened, dismissed) are relayed through a small authenticated route (`POST /api/feedback/events`, body `{event: "opened"|"dismissed"}`, allowlisted) that captures them server-side.

| Event | Fired when | Properties (no PII) |
|---|---|---|
| feedback_opened | Modal opened | page |
| feedback_submitted | 201 returned (new row) | feedback_id, rating, has_contact_ok, page |
| feedback_failed | Any non-2xx outcome of a submit attempt | error_code (validation, unauthorized, rate_limited, server_error, network) |
| feedback_dismissed | Modal closed without a successful submit | page |

## 6. Rollout, Feature Flags & Rollback

- **Flag:** `beta-feedback-widget` in PostHog. Default off.
- **Cohorts:** Internal team (email/cohort in PostHog) -> 100% of the beta cohort.
- **Kill switch:** Flag off hides the button on next load; submitted feedback is kept. Open modal may finish its submit.
- **Rollback:** Turn the flag off; table stays; migration is additive, so reverting code is safe with no data repair.
- **Launch prerequisites:** `UPSTASH_REDIS_REST_URL/TOKEN`, `POSTHOG_API_KEY/HOST` env vars; PostHog flag and beta cohort created; Slack #beta-alerts destination connected; `zod` added to dependencies; toast mechanism (small local component, no new lib).

## 7. Out of Scope (Non-Goals)

- Admin UI (read via Prisma Studio)
- Email notifications
- Screenshots / attachments
- Any list view of feedback

## 8. Open Risks & Assumed Defaults

| Item | Decision | Source | Risk if wrong |
|---|---|---|---|
| Flag evaluation location | Server-side in /dashboard server component via posthog-node, passed as prop | repo (no client PostHog SDK) | Flag staleness until reload; acceptable |
| Opened/dismissed events | Relayed via authed server route | recommended-default | Extra endpoint; low |
| Rate limiter outage | Fail open | recommended-default | Brief unmetered window |
| Duplicate replays | Don't consume quota | recommended-default | Slight limiter complexity |
| `page` field | Server-set from allowlist | recommended-default | None |
| Toast | Minimal local component | recommended-default | Swap later |
| Message may contain user PII | Stored plain; cascade-delete with user; no retention job in v1 | recommended-default | Retention policy may be needed later |

## 9. Acceptance Criteria

- **AC-1:** Given the flag is off, When /dashboard loads, Then no Feedback button renders; given on, the button renders on /dashboard only.
- **AC-2:** Given the modal, When message trimmed length is <10 or >2000, Then submit is blocked client-side and the API returns 400 with field errors.
- **AC-3:** Given no session, When POST /api/feedback, Then 401.
- **AC-4:** Given a valid body and key, When POSTed, Then 201 `{id}` and one Feedback row with userId from the session, contactOk default false, page `/dashboard`.
- **AC-5:** Given a repeated Idempotency-Key for the same user, When POSTed again, Then 201 with the original id and still one row.
- **AC-6:** Given 5 submissions in an hour, When a 6th is sent, Then 429 and the UI shows the rate-limit message with text preserved.
- **AC-7:** Given submission in flight, When the user double-clicks submit, Then exactly one request is sent and the button shows a spinner and is disabled.
- **AC-8:** Given a server/network error, When it occurs, Then an inline error appears, typed text is preserved, and Retry resubmits with the same key.
- **AC-9:** Given the modal is closed mid-submit, When 201 arrives, Then the "Thanks!" toast shows.
- **AC-10:** Given the 201 path, Then toast "Thanks!" shows and the modal closes.
- **AC-11:** Given any request, Then logs contain no message text or email, only the feedback id; message renders escaped.
- **AC-12:** Given the events table in section 5, When each action occurs, Then the matching PostHog server-side event fires with the listed properties and no PII.
- **AC-13:** Given the migration, Then it only creates the Feedback table (additive) and cascade-deletes rows on user delete.

## 10. IMPLEMENTATION_TASKS

- [ ] T1: Add `zod` dependency; Feedback model + User back-relation + additive migration (AC-13)
- [ ] T2: POST /api/feedback with auth, zod, idempotency, Upstash limit, safe logging, tests (AC-2, AC-3, AC-4, AC-5, AC-6, AC-11)
- [ ] T3: Feedback button + modal client component with all states, toast, mid-submit close, tests (AC-2, AC-7, AC-8, AC-9, AC-10)
- [ ] T4: PostHog server-side events + /api/feedback/events relay + Slack alert config doc (AC-12)
- [ ] T5: Flag evaluation in /dashboard server component and rollout steps (AC-1)
