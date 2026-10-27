# Follow-Up Phases: phase 2, v2, and changes to shipped features

Use this when the request changes or extends a feature that already exists:

- **It has a locked PRD in `docs/prd/`.** Examples: "referrals phase 2", "billing v2", "add cash-out to referrals", "raise the referral cap".
- **It exists in code without a PRD.** This is an existing project from before the skill was installed, or a spec that lives somewhere else.

A locked PRD covers only the scope it describes. New scope gets its own PRD, and the gate stays closed until that PRD validates. An earlier phase's PRD never opens the gate for a later phase.

## 1. Baseline (recon, before any question)

1. **With an earlier PRD,** read it: decisions, the Assumptions table, Open Risks, Non-Goals, and which `IMPLEMENTATION_TASKS` are checked.
2. **Read the code that shipped.** If it drifted from the PRD in a way the new scope depends on, raise the drift as a question. It's P0 when it touches data, money, or security.
3. **Without an earlier PRD,** build the baseline from the code, plus any spec the user points to (README, ticket, exported doc). Ask whether current behavior is intended only where the change depends on it.
4. **Open your first reply with the baseline** in at most 5 bullets, so the user sees what you're building on.

## 2. Score only the change

Score what is Added, Changed, or Removed on the five dimensions:

- **Earlier decisions that still hold are already answered.** Score them as answered and don't re-ask them.
- **Earlier Open Risks and Non-Goals that the new scope touches** must be resolved or re-logged.

## 3. Checks that only exist in later phases

Ask these on top of the rubric when they apply:

| Check | Typical P0 |
|---|---|
| **Existing data** | Records created by the earlier phase: migrate, backfill, or leave as-is? Old and new records mixed in one table? |
| **Existing users and in-flight work** | Do current users switch immediately or mid-flow, or are they grandfathered? |
| **Reversed decisions** | A changed limit, price, or reward: is it retroactive? Does it touch past earnings or past invoices? |
| **Compatibility** | API consumers, webhooks, mobile clients, analytics event names, emails already sent |
| **Money moving out** | New payouts or refunds: identity checks, fraud holds, reconciliation with the existing ledger |
| **Rollout and rollback** | The new behavior sits behind its own flag. The earlier phase stays as the fallback. Rollback needs no data repair. |
| **Telemetry continuity** | Keep the earlier event names, so before and after compare. Use the earlier KPI as the baseline. |

## 4. The new PRD

- **File:** `docs/prd/<feature-slug>-v<N>-prd.md` (for example `referral-system-v2-prd.md`) with `feature_slug: <feature-slug>-v<N>`.
- **Frontmatter:** `phase: <N>` and `parent_prd: docs/prd/<previous>-prd.md`. Use `parent_prd: none` when the earlier phase shipped without a PRD.
- **Baseline & Changes:** fill this section of the template (`prd-template.md`): what it builds on, what is built today (with any drift), the Added/Changed/Removed table, what carries over, and what happens to existing data and users.
- **Assumptions table:** decisions carried over unchanged use the source `previous-phase`.
- **`IMPLEMENTATION_TASKS`:** cover only the change, plus any migration of existing data.
- **The earlier PRD:** never rewrite it, because it is the record of what shipped. The only edit allowed is adding `superseded_by: docs/prd/<new>-prd.md` to its frontmatter.

## Not a new phase

These need no new PRD. Handle them normally:

- a copy tweak
- a styling change
- a bug fix in shipped code that restores what the PRD already says

Changing a number the earlier PRD decided (a cap, a price, a reward) *is* a new phase, because it has money and data consequences. When no P0 comes up, fast-pass it.
