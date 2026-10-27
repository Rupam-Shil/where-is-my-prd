# PRD Output Template

Write the PRD to `docs/prd/<feature-slug>-prd.md`. Copy the template below and replace every `{{placeholder}}`. `validate-prd.sh` fails if any `{{` remains.

Rules:

- **Frontmatter is machine-readable.** Downstream skills and CI read it to check the gate. Keep the keys exactly as written.
- **`feature_slug`** is kebab-case and matches the filename: `docs/prd/{{feature_slug}}-prd.md`.
- **`interrogation_mode`** is one of `full_grill`, `fast_pass`, or `emergency_default_lock`.
- **`approved_at`** is UTC ISO-8601 from `date -u +%Y-%m-%dT%H:%M:%SZ`.
- **`phase`** is `1` for a new feature. For a follow-up phase it's `2`, `3`, …, with `parent_prd` set to the previous phase's PRD (or `none` if that phase shipped without one), a `-v<N>` slug, and the Baseline & Changes section filled in. See `next-phase.md`. For phase 1, delete that section.
- **The state table** names all six states. Map feature-specific names onto them, as in `Loading (submitting)`. Write `N/A — <reason>` for a state that truly can't occur.
- **Acceptance criteria** are testable statements (Given / When / Then, or a single observable assertion), numbered `AC-1`, `AC-2`, …
- **Every `IMPLEMENTATION_TASKS` item** cites the AC ids it satisfies, and every AC is cited by at least one task.
- **Be terse.** Tables and bullets, not prose. A PRD an agent can execute in one shot beats a long one.

---

```markdown
---
feature_slug: {{feature-slug}}
title: {{Human readable feature name}}
spec_readiness_score: {{0-100}}
p0_blockers_remaining: 0
interrogation_mode: {{full_grill | fast_pass | emergency_default_lock}}
approved_at: {{YYYY-MM-DDTHH:MM:SSZ}}
phase: {{1 | 2 | 3 …}}
parent_prd: {{none | docs/prd/<previous-phase>-prd.md}}
generated_by: wheres-my-prd@1.0.0
---

# {{Human readable feature name}}

> Spec Readiness {{score}}/100 · P0 remaining: 0 · Mode: {{mode}}
> State {{n}}/20 · Data {{n}}/20 · Abuse {{n}}/20 · Telemetry {{n}}/20 · Rollout {{n}}/20

## 1. Overview & Problem Statement

- **Problem:** {{who hurts, and how, today}}
- **Solution:** {{one-sentence description of the feature}}
- **Primary user:** {{segment}}
- **Repo context:** {{stack, relevant existing models, routes, and libs found during recon}}

### Baseline & Changes (phase 2+ only; delete for phase 1)

- **Builds on:** {{parent PRD path, or "code as built, no earlier PRD"}}
- **As built today:** {{what the shipped code does now, including any drift from the parent PRD}}

| Change | What | Why |
|---|---|---|
| Added | {{…}} | {{…}} |
| Changed | {{…}} | {{…}} |
| Removed | {{… or "nothing"}} | {{…}} |

- **Carried over unchanged:** {{earlier decisions that still hold; not re-asked}}
- **Existing data and users:** {{what happens to records and in-flight users from earlier phases}}

## 2. User Flow & State Machine

**Happy path**
1. {{step}}
2. {{step}}

| State | Trigger | What the user/API sees | Next states |
|---|---|---|---|
| Idle | {{trigger}} | {{ui/response}} | {{states}} |
| Loading | {{trigger}} | {{ui/response}} | {{states}} |
| Success | {{trigger}} | {{ui/response}} | {{states}} |
| Empty | {{trigger}} | {{ui/response}} | {{states}} |
| Error | {{trigger}} | {{ui/response, including the retry path}} | {{states}} |
| Rate-Limited | {{trigger}} | {{ui/response, e.g. 429 + Retry-After}} | {{states}} |

## 3. Data Contracts & Schema Changes

**Schema changes**

| Table / model | Change | Type & nullability | Default / backfill | Index |
|---|---|---|---|---|
| {{table}} | {{add/alter}} | {{type}} | {{default or backfill plan}} | {{index}} |

**Migration safety:** {{additive? nullable? backfill steps? lock risk?}}

**API / payload contracts**

| Endpoint / event | Input (validated) | Output | Errors | Idempotency |
|---|---|---|---|---|
| {{route}} | {{fields + limits}} | {{shape}} | {{codes}} | {{key or unique constraint}} |

## 4. Edge Cases, Abuse Vectors & Guardrails

| Case | Expected behavior | Guardrail |
|---|---|---|
| {{edge or abuse case}} | {{behavior}} | {{rate limit, unique constraint, auth check, …}} |

- **AuthZ:** {{who can do what; ownership/tenant checks}}
- **Third-party failure:** {{timeout, retry, fallback}}
- **Sensitive data:** {{what never goes to logs/analytics/URLs}}

## 5. Telemetry & Event Logging

- **Primary KPI:** {{metric, target, window}}
- **Alerting:** {{threshold → who is paged/notified}}

| Event | Fired when | Properties (no PII) |
|---|---|---|
| {{feature}}_started | {{when}} | {{props}} |
| {{feature}}_completed | {{when}} | {{props}} |
| {{feature}}_failed | {{when}} | {{props incl. error_code}} |

## 6. Rollout, Feature Flags & Rollback

- **Flag:** {{flag name and system}}. Default off.
- **Cohorts:** {{internal → 10% → 100%, or other}}
- **Kill switch:** {{what users see when the flag flips off mid-flow}}
- **Rollback:** {{code revert safe? data repair needed?}}
- **Launch prerequisites:** {{env vars, legal copy, provider approval, cron}}

## 7. Out of Scope (Non-Goals)

- {{explicitly not doing}}

## 8. Open Risks & Assumed Defaults

| Item | Decision | Source | Risk if wrong |
|---|---|---|---|
| {{gap}} | {{locked choice}} | {{user / recommended-default / emergency-lock / repo / previous-phase / open-risk}} | {{impact}} |

## 9. Acceptance Criteria

- **AC-1:** {{Given … When … Then …}}
- **AC-2:** {{…}}

## 10. IMPLEMENTATION_TASKS

Ordered. Each task is small enough for one commit and cites the ACs it satisfies.

- [ ] T1: {{migration / schema}} (AC-{{n}})
- [ ] T2: {{server logic + tests}} (AC-{{n}})
- [ ] T3: {{UI states + tests}} (AC-{{n}})
- [ ] T4: {{telemetry events}} (AC-{{n}})
- [ ] T5: {{flag wiring + rollout}} (AC-{{n}})
```

---

## Mode Notes

- **`fast_pass`**: the spec arrived complete. Section 8 lists only the minor assumptions you made.
- **`full_grill`**: Section 8 records every answer the user gave (source `user`) and every default they accepted (source `recommended-default`).
- **`emergency_default_lock`**: every P0 that was locked without the user's input has source `emergency-lock` and an honest "Risk if wrong". Emergency-locked items score 2 instead of 4, so the score is often below 85. The validator allows that in this mode, but prints a warning so reviewers see the spec was never confirmed.
