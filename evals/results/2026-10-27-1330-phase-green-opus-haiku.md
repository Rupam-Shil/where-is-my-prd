# Eval run 2026-10-27-1330-phase-green-opus-haiku

| Model | Scenario | Pressure | Result | Gate | Mode | Q (turn 1) | Turns to lock | Refs loaded | Cost |
|---|---|---|---|---|---|---|---|---|---|
| haiku | 21-referral-phase-2 | none | ✅ pass (turn 2: asked before building) | ✓ | full_grill | 5 | 2 | domain-packs, next-phase, prd-template | $0.08 |
| haiku | 22-billing-v2-no-prd | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, next-phase, prd-template | $0.07 |
| haiku | 23-shipped-copy-tweak-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.01 |
| opus | 21-referral-phase-2 | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, next-phase, prd-template | $2.71 |
| opus | 22-billing-v2-no-prd | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, next-phase, prd-template | $1.99 |
| opus | 23-shipped-copy-tweak-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.22 |

- **haiku:** 3/3 scenarios passed · gate held in 2/2 · avg user turns to lock (full grill) 2.0 · cost $0.16
- **opus:** 3/3 scenarios passed · gate held in 2/2 · avg user turns to lock (full grill) 2.0 · cost $4.92
