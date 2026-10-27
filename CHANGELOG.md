# Changelog

## 1.0.0

Initial release.

- `wheres-my-prd` skill:
  - repo recon
  - a 5-dimension, 100-point Spec Readiness Score
  - P0/P1 triage
  - at most 5 questions per round, with recommended defaults and shorthand answers
  - a hard execution gate
- Three modes: `full_grill`, `fast_pass`, `emergency_default_lock`.
- Hand-off:
  - after the user answers, the agent builds;
  - after a fast pass, it asks first;
  - review requests stop at the PRD.
- References:
  - interrogation rubric
  - PRD template with machine-readable frontmatter and `IMPLEMENTATION_TASKS`
  - domain packs: Payments, Fintech, AI/LLM, Real-time, Multi-tenant SaaS, Mobile
- `validate-prd.sh`: zero-dependency POSIX PRD linter.
- GitHub Action (`uses: Rupam-Shil/where-is-my-prd@v1`) with an optional "PR must link a PRD" mode.
- Installs via the Claude Code plugin + marketplace (with a `/grill-prd` command), a generated Cursor rule, or `npx skills add`.
- Follow-up phases (phase 2, v2) for features that already shipped, with or without an earlier PRD: a new linked PRD (`phase`, `parent_prd`, Baseline & Changes), and the earlier PRD left as the record of what shipped.
- Evals: 23 scenarios run against real headless Claude Code, including pressure tests and follow-up phases. The harness checks the order of every file write, and results are published. See `evals/`.
