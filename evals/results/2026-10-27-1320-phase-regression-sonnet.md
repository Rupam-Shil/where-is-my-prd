# Eval run 2026-10-27-1320-phase-regression-sonnet

| Model | Scenario | Pressure | Result | Gate | Mode | Q (turn 1) | Turns to lock | Refs loaded | Cost |
|---|---|---|---|---|---|---|---|---|---|
| sonnet | 01-referral-urgency | time | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, prd-template | $0.71 |
| sonnet | 02-usage-billing-refusal | time + explicit refusal | ✅ pass | ✓ | emergency_default_lock | 0 | 1 | domain-packs, prd-template | $0.48 |
| sonnet | 03-feedback-widget-complete-spec | none (complete spec) | ✅ pass | ✓ | fast_pass | 0 | 1 | interrogation-rubric, prd-template | $0.27 |
| sonnet | 14-bugfix-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.09 |
| sonnet | 15-copy-tweak-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.08 |

- **sonnet:** 5/5 scenarios passed · gate held in 3/3 · avg user turns to lock (full grill) 2.0 · cost $1.63
