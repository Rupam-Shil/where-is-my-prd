# Domain Packs

Load the pack(s) whose triggers match the request or the repo. Each pack adds checks on top of the 5-dimension rubric. Use the questions as patterns: rewrite them with the user's actual tables, routes, and providers. Each question shows its default severity and the dimension it scores under.

Format: **Question**. *Why it matters.* Options, with the recommended default first.

---

## 1. Payments & Escrow

**Triggers:** Stripe, Paddle, Razorpay, Adyen, PayPal, LemonSqueezy, checkout, subscription, invoice, refund, payout, wallet, credits, escrow, metered or usage-based billing.

- **[P0 · Data] What is the idempotency key for each charge, credit, and refund?** *Retries and double-clicks cause double charges.* A) Provider idempotency key derived from `<order_id>:<action>` plus a DB unique constraint [Recommended Default] · B) DB unique constraint only
- **[P0 · Abuse] Which webhook events are the source of truth, and how are they deduplicated and verified?** *Unsigned or replayed webhooks grant paid access for free.* A) Verify the signature, store `event.id` with a unique constraint, process in a queue [Recommended Default] · B) Verify the signature and process inline
- **[P0 · Data] Are amounts stored in minor units with an explicit currency?** *Float dollars drift, and mixed currencies corrupt totals.* A) Integer minor units plus an ISO-4217 `currency` column [Recommended Default] · B) Decimal(12,2) with a single fixed currency
- **[P0 · State] What happens when the payment succeeds at the provider but our DB write fails, or the reverse?** *Customers get charged with no access, or get access with no charge.* A) The webhook reconciles state; the client redirect is cosmetic only [Recommended Default] · B) A nightly reconciliation job
- **[P1 · State] What happens on failed renewal, dunning, downgrade, and proration?** *Users keep paid features forever, or lose them with no warning.* A) Provider-managed dunning, 7-day grace period, then downgrade [Recommended Default] · B) Immediate downgrade
- **[P1 · Telemetry] Is there a ledger table, or only a balance column?** *Without a ledger you can't answer "why is my balance X?" or reconcile.* A) Append-only ledger; balance derived or cached [Recommended Default] · B) Balance column plus an audit log

## 2. Fintech & Regulated Products

**Triggers:** KYC, AML, lending, investing, trading, crypto, insurance, health data, "advice", portfolio, tax, HIPAA, PCI, SOC 2, GDPR deletion.

- **[P0 · Abuse] Does any copy, notification, or AI output read as financial, medical, or legal advice?** *Non-advisory language is often a legal requirement, and violations are regulatory events.* A) Fixed disclaimer plus a reviewed copy allowlist [Recommended Default] · B) Legal review before launch, tracked as a launch prerequisite
- **[P0 · Telemetry] Which actions need an immutable audit log (who, what, when, before/after)?** *Regulators and auditors ask for this; you can't reconstruct it later.* A) Append-only audit table for every state change on regulated records [Recommended Default] · B) Provider-side audit trail only
- **[P0 · Data] Which fields are PII or regulated, and where may they be stored, logged, or exported?** *PII leaking into logs, analytics, or LLM prompts is a reportable incident.* A) Field-level classification, redacted in logs and events [Recommended Default] · B) Encrypt at rest only
- **[P0 · Rollout] Which jurisdictions launch first, and what is geo-blocked?** *Launching in an unlicensed region creates legal exposure.* A) Allowlisted regions behind a flag [Recommended Default] · B) Global launch
- **[P1 · Data] What is the data-retention and deletion policy (GDPR/CCPA right to erasure)?** *Hard deletes can break audit requirements, and soft deletes can break erasure requirements.* A) Anonymize PII while keeping audit rows [Recommended Default] · B) Hard delete after N days

## 3. AI / LLM Features

**Triggers:** LLM, GPT, Claude, Gemini, embeddings, RAG, agent, chatbot, summarization, "AI-generated", prompt, tool calling.

- **[P0 · Abuse] Can user-controlled text (inputs, uploaded docs, retrieved web pages) inject instructions that trigger tools or leak data?** *Prompt injection can exfiltrate other users' data or take actions on someone's behalf.* A) Treat retrieved and user content as data, gate side-effecting tools behind confirmation, and scope tool permissions to the user [Recommended Default] · B) Read-only tools only for v1
- **[P0 · Abuse] What is the per-user and per-day token/cost cap?** *One script can burn your monthly API budget overnight.* A) Per-user daily cap plus a global circuit breaker with an alert [Recommended Default] · B) Global monthly cap only
- **[P0 · State] What does the user see when the model times out, is rate-limited, or returns malformed output?** *A spinner that never ends, or a crash on unparsable JSON.* A) A timeout, one retry with a fallback model, then a graceful error with retry [Recommended Default] · B) A graceful error only
- **[P1 · Abuse] How are hallucinations contained for factual claims?** *Confidently wrong answers erode trust and create liability.* A) Ground answers in cited sources and refuse when nothing is retrieved [Recommended Default] · B) Disclaimer only
- **[P1 · Data] Are prompts and outputs stored? Which model/version and prompt version produced each output?** *You can't debug or evaluate regressions without them.* A) Store prompt version, model id, latency, and tokens; redact PII [Recommended Default] · B) Don't store
- **[P1 · Telemetry] How is quality measured after launch?** *"It feels better" isn't a metric.* A) Thumbs up/down events plus a weekly offline eval set [Recommended Default] · B) Usage volume only

## 4. Real-Time / Socket Flows

**Triggers:** WebSocket, SSE, Socket.IO, Pusher, Ably, Liveblocks, presence, live cursors, chat, multiplayer, collaborative editing, notifications feed.

- **[P0 · State] What happens on disconnect and reconnect? Does the client resync from a snapshot, replay missed events, or reload?** *Clients silently diverge and show stale or duplicated data.* A) Monotonic sequence ids; on reconnect, fetch the delta since the last id, with a full snapshot as fallback [Recommended Default] · B) Full refetch on reconnect
- **[P0 · Data] What is the ordering and conflict rule for concurrent edits?** *Last-write-wins silently drops a user's work.* A) Server-assigned order with per-field LWW, plus a conflict toast [Recommended Default] · B) CRDT/OT library · C) Pessimistic lock
- **[P0 · Abuse] How is channel subscription authorized?** *Anyone who guesses a channel name reads private messages.* A) Server-signed, short-lived channel tokens scoped to the user [Recommended Default] · B) Auth on connect only
- **[P1 · State] How does a late joiner get current state?** *New users see an empty room until the next event.* A) Snapshot on join, then the stream [Recommended Default] · B) Replay the last N events
- **[P1 · Abuse] What are the message rate and size limits per connection?** *One client floods every subscriber.* A) N msgs/sec plus a max payload size; disconnect on abuse [Recommended Default] · B) Size limit only

## 5. Multi-Tenant SaaS / B2B

**Triggers:** workspace, organization, team, tenant, seats, roles, RBAC, admin, invite, SSO, SAML, SCIM, enterprise.

- **[P0 · Abuse] Where is tenant isolation enforced: every query, row-level security, or middleware?** *One missing `where tenantId` leaks a customer's data to another.* A) Tenant-scoped data-access helper plus RLS or tests that assert isolation [Recommended Default] · B) Middleware check only
- **[P0 · Abuse] Which roles can perform this action, and who can grant roles?** *Members escalating to admin is a classic enterprise blocker.* A) Reuse existing roles; only owners and admins can change roles [Recommended Default] · B) New permission
- **[P1 · State] What happens to a user's data and in-flight work when they are removed from the workspace?** *Orphaned records, or ex-employees keeping access.* A) Revoke access immediately and transfer ownership to the workspace owner [Recommended Default] · B) Delete their records
- **[P1 · Rollout] Is the feature gated by plan tier, and what do lower tiers see?** *Free users get enterprise features, or a broken UI.* A) Plan check server-side, with an upgrade prompt in the UI [Recommended Default] · B) Available to all tiers

## 6. Mobile Apps

**Triggers:** iOS, Android, React Native, Expo, Flutter, Swift, Kotlin, push notifications, App Store, offline.

- **[P0 · Data] Will old app versions still in the wild break when the API changes?** *Users who never update crash on launch.* A) Additive API changes only, plus a server-driven minimum-version gate [Recommended Default] · B) Versioned endpoint
- **[P0 · State] What works offline, and how are queued actions replayed and deduplicated?** *Duplicate submissions or lost writes on flaky networks.* A) Offline read-only; writes require a connection, with a clear banner [Recommended Default] · B) Offline queue with idempotency keys
- **[P1 · Rollout] Can this ship without an app-store release (remote config or flag)?** *A bug takes days to fix through store review.* A) Server-side flag plus remote config kill switch [Recommended Default] · B) Requires a release
- **[P1 · Abuse] Push notifications: what is the opt-in moment, frequency cap, and deep-link target?** *Notification spam gets the app's permission revoked.* A) Contextual opt-in, max 1 per day, deep link to the relevant screen [Recommended Default] · B) Opt-in on first launch
