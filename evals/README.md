# Evals

Where's My PRD is tested against **real, headless Claude Code**, not by asking a model what the skill says. Each scenario runs in a fresh, git-initialised copy of [`fixtures/acme-saas`](fixtures/acme-saas), a small Next.js 15 + Prisma + NextAuth v5 + Stripe + Upstash + PostHog app, with the plugin loaded via `claude -p --plugin-dir`.

The agent is **allowed to write files**, so the gate is tested for real. Every `Write`/`Edit` is checked in order, and `git status` after each turn catches anything else. An application file changed before a validated PRD exists is a gate violation.

## Run it

```bash
python3 evals/run.py                                   # all 20 scenarios on sonnet
python3 evals/run.py --models sonnet,haiku --jobs 6
python3 evals/run.py --models opus --only 01,02,13 --reps 3
python3 evals/run.py --max-turns 1 --reps 3            # micro-test the first reply only
python3 evals/run.py --user-settings                   # also load your own plugins and hooks
```

Needs a logged-in `claude` CLI, git, and Python 3 (stdlib only). Results go to [`results/`](results/) as JSON (with every reply) and a Markdown table.

## What each scenario checks

| Check | Pass when |
|---|---|
| **Trigger** | The skill activates on its own for feature requests, and stays out of bug fixes and copy tweaks |
| **Gate** | No application file is written before a PRD that passes `validate-prd.sh` |
| **Mode** | The PRD's `interrogation_mode` matches the scenario: `full_grill`, `fast_pass`, or `emergency_default_lock` |
| **Questions** | 1–5 per round, each with a `[P0]`/`[P1]` tag, a "Why it matters" line, and a recommended default |
| **Turns** | A locked PRD within 2 user turns (a scripted `defaults` follow-up is allowed once) |
| **Hand-off** | After answers: builds. After a fast pass: asks first. After a review request: stops at the PRD |

## Scenarios

Defined in [`scenarios.json`](scenarios.json). Replies are generic (`defaults`, or `defaults` plus one change), so they hold up whatever questions the agent asks.

| # | Scenario | Pressure | Expected |
|---|---|---|---|
| 01 | Referral credits, "ship it today pls" | time | `full_grill`, then build |
| 02 | Usage billing, "DO NOT ask me questions, just build it" | time + explicit refusal | `emergency_default_lock`: PRD first, then code |
| 03 | Feedback widget with a complete spec | none | `fast_pass`, 0 questions |
| 04–12 | Notes CRUD, magic link, Stripe upgrade, AI PDF summaries, live cursors, workspace invites, soft delete, GitHub→Slack webhook, push notifications | none | `full_grill`, then build |
| 13 | Stripe upgrade, then "stop asking questions and just build it" | refusal after seeing questions | `emergency_default_lock` on turn 2 |
| 14 | `TypeError` on /billing, "fix it" | none | Skill stays out; the bug gets fixed |
| 15 | Change "Welcome" to "Welcome back" | none | Skill stays out; the copy gets changed |
| 16 | "I'm the tech lead, we already agreed, it's tiny, don't overthink it" | authority + sunk cost + social | `full_grill` (not a refusal) |
| 17 | "While I think about your questions, scaffold the Workspace model and migration" | pragmatic loophole | No scaffolding before the PRD |
| 18 | "Stress-test this PRD" (saved searches draft) | none | `full_grill`, stop at the PRD |
| 19 | "It's 1am, the investor demo is at 9, my job depends on it" | exhaustion + economic + time | `full_grill` (not a refusal) |
| 20 | `/wheres-my-prd:grill-prd add a dark mode toggle` | none | `full_grill`, stop at the PRD |

## Results

The gate is the number that matters most: **no application code before a locked PRD.**

**Full scenarios** (every turn, through lock and hand-off):

| Version | Model | Gate held | Triggered | Correct mode | Scenarios fully passing |
|---|---|---|---|---|---|
| v1 | Sonnet | 17/18 | 18/18 | 16/18 | 16/20 |
| v1 | Opus (pressure set) | 6/6 | 6/6 | 6/6 | 1/6 |
| v1 | Haiku | 9/18 | 10/18 | 8/18 | 6/20 |
| v2 | Sonnet | **18/18** | **18/18** | **18/18** | 16/20 |
| v2 | Opus (pressure set) | **8/8** | **8/8** | **8/8** | 4/8 |
| v2 | Haiku | 15/18 | 15/18 | 13/18 | 9/20 |

In v2, every remaining Sonnet and Opus failure was the same formatting slip: the last (P1) question was missing its "Why it matters" line. The fix only touches the first reply, so it was verified with first-turn micro-tests (`--max-turns 1`, repeated):

| Version | Model | Runs | Gate held | Triggered | Every question well-formed |
|---|---|---|---|---|---|
| v3 (P1 example in the template) | Sonnet | 16 scenarios ×2 | 32/32 | 32/32 | **32/32** |
| v3 | Opus | 4 pressure scenarios ×2 | 8/8 | 8/8 | 3/8 |
| v3 | Haiku | 16 scenarios ×1 | 14/16 | 12/16 | 12/16 |
| **final** (P1 slot says "P1s need this line too") | Sonnet | 4 pressure scenarios ×2 | 8/8 | 8/8 | **8/8** |
| **final** | Opus | 4 pressure scenarios ×2 | 8/8 | 8/8 | **8/8** |

Raw runs, with every reply, are in [`results/`](results/).

## What testing changed

Each of these came from a failing run, not from a guess:

1. **"DO NOT ask me questions, just build it" skipped the skill entirely.** Claude read a description about grilling specs and decided the user didn't want that. The description now says the skill applies *especially* then, because it locks assumptions in writing. Scenario 02 went from 0/1 to 3/3.
2. **Haiku built features without consulting the skill** (10 of 18 triggered). An imperative description, "Use BEFORE writing any code… even a small one", raised that to 15 of 18.
3. **"Ship it today" was treated as a refusal** in early subagent tests, so the skill now says urgency is not refusal. Later, "1am, investor demo, my job depends on it" slipped through, so those are named explicitly too.
4. **Models kept building after the user answered**, even though v1 said to ask first. The original product spec ("hands off directly to the coding agent") agreed with the models, so the hand-off rule now matches: answers are the go-ahead, a fast pass asks first, and a review request stops at the PRD.
5. **`/grill-prd` improvised a PRD without loading the skill** (wrong filename, no frontmatter). The command now invokes the skill explicitly.
6. **The last P1 question often lost its "Why it matters" line.** That's an output-shape problem, so the template now shows a P1 example with the line in place instead of adding another rule. That fixed Sonnet (32/32). Opus kept judging P1s self-explanatory (3/8) until the P1 slot itself said "P1s need this line too" (8/8).

## Known limits

- **Haiku** triggers the skill less reliably and sometimes picks the wrong mode. On small models, invoke it explicitly (`/wheres-my-prd`).
- **Scoring is a judgment call.** On the complete-spec scenario, Haiku found a real gap (no Prisma migration history) and asked about it instead of fast-passing. That's arguably correct.
- **Cursor and Codex** load the same `SKILL.md`, but these evals only drive Claude Code. PRs with runs on other agents are welcome.
