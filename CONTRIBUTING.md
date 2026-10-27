# Contributing

Thanks for helping agents stop shipping half-baked specs.

## Ground rules

- **Edit the skill, not the generated rule.** `.cursor/rules/wheres-my-prd.mdc` is generated from `skills/wheres-my-prd/SKILL.md`. After changing the skill, run `sh scripts/build-cursor-rule.sh`.
- **Keep `SKILL.md` under ~1,800 tokens.** Put depth in `references/`. The test suite enforces the budget.
- **Test behavior changes with a real agent.** Run the affected scenarios with `python3 evals/run.py --only <ids> --reps 3` before and after your change, and paste both result tables in the PR. A wording change that hasn't been tested against an agent is a guess.
- **Stay zero-dependency.** `validate-prd.sh` must run on plain POSIX `sh` (dash, busybox, macOS).

## Good first contributions

- **A new domain pack** in `references/domain-packs.md`, for example healthcare, e-commerce inventory, or data pipelines. Every question needs a severity, a dimension, a "why it matters" line, and a recommended default.
- **Eval runs on other agents or models.** Run `python3 evals/run.py` and add the results file under `evals/results/`.
- **A transcript** for `examples/` from a real session (trim it, and strip anything private).

## Before opening a PR

```bash
sh tests/run.sh
shellcheck -s sh skills/wheres-my-prd/scripts/validate-prd.sh scripts/*.sh tests/*.sh
```

Bump the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `validate-prd.sh` together. The tests check that they match.
