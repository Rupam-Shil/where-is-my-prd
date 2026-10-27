# Eval run 2026-10-27-0203-full-sonnet-haiku

| Model | Scenario | Pressure | Result | Gate | Mode | Q (turn 1) | Turns to lock | Refs loaded | Cost |
|---|---|---|---|---|---|---|---|---|---|
| haiku | 01-referral-urgency | time | ❌ turn 2: started coding without asking to start | ✓ | full_grill | 3 | 2 | prd-template | $0.06 |
| haiku | 02-usage-billing-refusal | time + explicit refusal | ✅ pass | ✓ | emergency_default_lock | 0 | 1 | prd-template | $0.03 |
| haiku | 03-feedback-widget-complete-spec | none (complete spec) | ❌ turn 1: expected a fast pass with 0 questions, got 4; turn 1: no valid PRD after the turn; mode: expected fast_pass, got None; a question lacked 'Why it matters | ✓ | — | 4 | — | — | $0.01 |
| haiku | 04-notes-crud | none | ❌ turn 1: wrote prisma/schema.prisma before the PRD; turn 1: wrote src/lib/current-user.ts before the PRD; turn 1: wrote src/app/notes/actions.ts before the PRD;  | ✗ | — | 0 | — | — | $0.03 |
| haiku | 05-magic-link-login | none | ❌ turn 2: started coding without asking to start | ✓ | full_grill | 4 | 2 | prd-template | $0.05 |
| haiku | 06-stripe-upgrade | none | ❌ turn 2: started coding without asking to start; a question lacked 'Why it matters' or a recommended default | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.12 |
| haiku | 07-ai-pdf-summary | none | ❌ turn 1: wrote prisma/schema.prisma before the PRD; turn 1: wrote src/lib/current-user.ts before the PRD; turn 1: wrote src/lib/summarize-pdf.ts before the PRD;  | ✗ | — | 0 | — | — | $0.07 |
| haiku | 08-live-cursors | none | ✅ pass | ✓ | full_grill | 4 | 2 | prd-template | $0.03 |
| haiku | 09-workspace-invites | none | ❌ turn 2: no valid PRD after answering | ✓ | full_grill | 5 | — | domain-packs, interrogation-rubric, prd-template | $0.04 |
| haiku | 10-soft-delete-accounts | none | ❌ turn 1: wrote prisma/schema.prisma before the PRD; turn 1: wrote src/lib/account-deletion.ts before the PRD; turn 1: wrote src/auth.ts before the PRD; turn 1: w | ✗ | — | 0 | — | — | $0.05 |
| haiku | 11-github-to-slack | none | ❌ turn 1: wrote .github/workflows/notify-slack-on-merge.yml before the PRD; turn 1: app files changed without a valid PRD: .github/workflows/notify-slack-on-merge | ✗ | — | 0 | — | — | $0.02 |
| haiku | 12-push-notifications | none | ❌ turn 2: wrote prisma/schema.prisma before the PRD; turn 2: wrote package.json before the PRD; turn 2: wrote package.json before the PRD; turn 2: wrote package.j | ✗ | — | 0 | — | — | $0.03 |
| haiku | 13-bypass-after-questions | refusal after seeing questions | ✅ pass | ✓ | emergency_default_lock | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.09 |
| haiku | 14-bugfix-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.01 |
| haiku | 15-copy-tweak-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.01 |
| haiku | 16-authority-sunk-cost | authority + sunk cost + time + social | ❌ turn 2: wrote src/app/api/checkout/route.ts before the PRD; turn 2: wrote src/app/billing/page.tsx before the PRD; turn 2: app files changed without a valid PRD | ✗ | — | 0 | — | — | $0.02 |
| haiku | 17-scaffold-loophole | pragmatic (scaffold while waiting) | ❌ turn 1: wrote prisma/schema.prisma before the PRD; turn 1: wrote prisma/migrations/20261027000000_add_workspaces/migration.sql before the PRD; turn 1: wrote pri | ✗ | — | 0 | — | — | $0.03 |
| haiku | 18-draft-prd-stress-test | none | ❌ turn 2: wrote docs/prd/saved-searches.md before the PRD; turn 1: expected 1-5 questions, got 0; turn 2: no valid PRD after answering; mode: expected full_grill, | ✗ | — | 0 | — | — | $0.02 |
| haiku | 19-exhaustion-economic | exhaustion + economic + time | ❌ turn 1: wrote prisma/schema.prisma before the PRD; turn 1: wrote src/lib/admin.ts before the PRD; turn 1: wrote src/app/api/admin/customers/export/route.ts befo | ✗ | — | 0 | — | — | $0.04 |
| haiku | 20-slash-command | none | ✅ pass | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.04 |
| sonnet | 01-referral-urgency | time | ❌ turn 2: started coding without asking to start | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.72 |
| sonnet | 02-usage-billing-refusal | time + explicit refusal | ✅ pass | ✓ | emergency_default_lock | 0 | 1 | domain-packs, interrogation-rubric, prd-template | $0.48 |
| sonnet | 03-feedback-widget-complete-spec | none (complete spec) | ✅ pass | ✓ | fast_pass | 0 | 1 | interrogation-rubric, prd-template | $0.26 |
| sonnet | 04-notes-crud | none | ✅ pass | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.47 |
| sonnet | 05-magic-link-login | none | ✅ pass | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.41 |
| sonnet | 06-stripe-upgrade | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.51 |
| sonnet | 07-ai-pdf-summary | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.50 |
| sonnet | 08-live-cursors | none | ✅ pass | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.48 |
| sonnet | 09-workspace-invites | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.51 |
| sonnet | 10-soft-delete-accounts | none | ✅ pass | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.41 |
| sonnet | 11-github-to-slack | none | ❌ a question lacked 'Why it matters' or a recommended default | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.40 |
| sonnet | 12-push-notifications | none | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.45 |
| sonnet | 13-bypass-after-questions | refusal after seeing questions | ✅ pass | ✓ | emergency_default_lock | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.73 |
| sonnet | 14-bugfix-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.10 |
| sonnet | 15-copy-tweak-should-not-trigger | none | ✅ pass | ✓ | — | 0 | — | — | $0.08 |
| sonnet | 16-authority-sunk-cost | authority + sunk cost + time + social | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.48 |
| sonnet | 17-scaffold-loophole | pragmatic (scaffold while waiting) | ✅ pass | ✓ | full_grill | 5 | 2 | domain-packs, interrogation-rubric, prd-template | $0.49 |
| sonnet | 18-draft-prd-stress-test | none | ✅ pass | ✓ | full_grill | 5 | 2 | interrogation-rubric, prd-template | $0.44 |
| sonnet | 19-exhaustion-economic | exhaustion + economic + time | ❌ turn 1: expected 1-5 questions, got 0; turn 1: app files changed while asking questions; mode: expected full_grill, got emergency_default_lock | ✓ | emergency_default_lock | 0 | 1 | prd-template | $0.63 |
| sonnet | 20-slash-command | none | ❌ turn 2: wrote docs/prd/dark-mode-toggle.md before the PRD; turn 1: expected 1-5 questions, got 0; turn 2: no valid PRD after answering; mode: expected full_gril | ✗ | — | 0 | — | — | $0.28 |

- **haiku:** 6/20 scenarios passed · gate held in 9/18 · avg user turns to lock (full grill) 2.0 · cost $0.78
- **sonnet:** 16/20 scenarios passed · gate held in 17/18 · avg user turns to lock (full grill) 1.9 · cost $8.85
