#!/usr/bin/env python3
"""Run the Where's My PRD eval scenarios against real, headless Claude Code.

Each scenario runs in a fresh, git-initialised copy of evals/fixtures/acme-saas with the
plugin loaded from this repository (`claude -p --plugin-dir`). The agent is allowed to
write files, so the gate is tested for real: every Write/Edit is checked in order, and
`git status` after each turn catches anything else. No application file may change
before a locked PRD exists.

Usage:
  python3 evals/run.py                                 # every scenario on sonnet
  python3 evals/run.py --models sonnet,haiku --jobs 6
  python3 evals/run.py --only 01,02,13 --models opus
  python3 evals/run.py --user-settings                 # also load your own plugins and hooks

Requires: the `claude` CLI (logged in), git, python3 (stdlib only).
"""

import argparse
import concurrent.futures as cf
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
FIXTURES = os.path.join(ROOT, "evals", "fixtures")
VALIDATOR = os.path.join(ROOT, "skills", "wheres-my-prd", "scripts", "validate-prd.sh")
RESULTS_DIR = os.path.join(ROOT, "evals", "results")

ALLOWED_TOOLS = "Read Glob Grep Skill Write Edit MultiEdit Bash(date:*) Bash(sh:*) Bash(mkdir:*) Bash(ls:*)"
WRITE_TOOLS = {"Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path", "NotebookEdit": "notebook_path"}
PRD_PATH = re.compile(r"^docs/prd/[^/]+-prd\.md$")
QUESTION = re.compile(r"^[^\w\n]*\d+[.)][^\w\n]*\[P[01]", re.M)
MAX_AUTO_FOLLOWUPS = 1

print_lock = threading.Lock()


def log(msg):
    with print_lock:
        print(msg, flush=True)


def sh(args, cwd):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True)


def git(cwd, *args):
    return sh(["git", "-c", "user.email=eval@local", "-c", "user.name=eval", *args], cwd)


def run_claude(prompt, cwd, model, session, user_settings, timeout):
    cmd = ["claude", "-p", prompt, "--plugin-dir", ROOT, "--model", model,
           "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits"]
    if session:
        cmd += ["--resume", session]
    if not user_settings:
        cmd += ["--setting-sources", "project,local"]
    cmd += ["--allowedTools", ALLOWED_TOOLS]
    started = time.time()
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, timeout=timeout)
        out, err = proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as e:
        out, err = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout"

    turn = {"session": session, "tools": [], "skills": [], "text": "", "cost": 0.0,
            "error": None, "seconds": round(time.time() - started)}
    for line in out.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("session_id"):
            turn["session"] = event["session_id"]
        if event.get("type") == "assistant":
            for block in event["message"].get("content", []):
                if block.get("type") == "tool_use":
                    turn["tools"].append((block["name"], block.get("input", {})))
                    if block["name"] == "Skill":
                        turn["skills"].append(block.get("input", {}).get("skill", ""))
        if event.get("type") == "result":
            turn["text"] = event.get("result") or ""
            turn["cost"] = event.get("total_cost_usd") or 0.0
            if event.get("is_error"):
                turn["error"] = turn["text"][:300]
    if not turn["text"] and not turn["error"]:
        turn["error"] = (err or "no result event")[:300]
    return turn


def read_prds(cwd):
    """Map docs/prd/*-prd.md paths to their text."""
    prd_dir = os.path.join(cwd, "docs", "prd")
    if not os.path.isdir(prd_dir):
        return {}
    return {f"docs/prd/{f}": open(os.path.join(prd_dir, f)).read()
            for f in sorted(os.listdir(prd_dir)) if f.endswith("-prd.md")}


def prd_body(text):
    parts = text.split("---", 2) if text.startswith("---") else []
    return parts[2] if len(parts) == 3 else text


def prd_state(cwd, baseline):
    """Return (valid, frontmatter dict) for PRDs written during the scenario.
    PRDs that were already in the fixture (an earlier phase) never open the gate."""
    current = read_prds(cwd)
    new = [p for p in current if p not in baseline]
    changed = [p for p in current if p in baseline and current[p] != baseline[p]]
    candidates = new or changed
    if not candidates:
        return False, {}
    result = sh(["sh", VALIDATOR, "-q", *candidates], cwd)
    meta = {"file": candidates[-1], "validator": result.stdout.strip()}
    text = current[candidates[-1]]
    if text.startswith("---"):
        for line in text.split("---", 2)[1].splitlines():
            if ":" in line:
                key, _, value = line.partition(":")
                meta[key.strip()] = value.split("#")[0].strip().strip('"')
    return result.returncode == 0, meta


def changed_files(cwd):
    status = git(cwd, "status", "--porcelain", "--untracked-files=all").stdout
    paths = [line[3:].strip().strip('"') for line in status.splitlines() if line.strip()]
    return [p for p in paths if not p.startswith(".claude/")]


def commit(cwd, message):
    git(cwd, "add", "-A")
    git(cwd, "commit", "-q", "--allow-empty", "-m", message)


def question_metrics(text):
    questions = len(QUESTION.findall(text))
    why = len(re.findall(r"\bwhy\b[^\n:]{0,20}:", text, re.I))
    recommended = len(re.findall(r"recommended", text, re.I))
    return questions, questions == 0 or (why >= questions and recommended >= questions)


def run_scenario(scenario, model, args):
    sid = scenario["id"]
    workdir = tempfile.mkdtemp(prefix=f"wmp-{sid[:2]}-{model}-", dir=args.workdir_root)
    shutil.copytree(os.path.join(FIXTURES, scenario.get("fixture", "acme-saas")), workdir, dirs_exist_ok=True)
    git(workdir, "init", "-q")
    commit(workdir, "fixture")
    baseline = read_prds(workdir)

    res = {"id": sid, "model": model, "category": scenario["category"], "pressure": scenario["pressure"],
           "expected_trigger": scenario["trigger"], "expected_mode": scenario["mode"],
           "triggered": scenario["turns"][0]["say"].startswith("/wheres-my-prd"),
           "violations": [], "problems": [], "notes": [], "turns": [], "user_turns": 0, "turns_to_lock": None,
           "first_turn_questions": None, "format_ok": True, "refs_loaded": [], "cost": 0.0}
    session, gate_open, auto_followups = None, False, 0
    queue = [dict(t) for t in scenario["turns"]]
    truncated = bool(args.max_turns) and len(queue) > args.max_turns
    if truncated:
        queue = queue[:args.max_turns]
        res["notes"].append(f"stopped after {args.max_turns} turn(s)")

    while queue:
        step = queue.pop(0)
        turn = run_claude(step["say"], workdir, model, session, args.user_settings, args.timeout)
        session = turn["session"]
        res["user_turns"] += 1
        res["cost"] += turn["cost"]
        if turn["skills"] and any("wheres-my-prd" in s for s in turn["skills"]):
            res["triggered"] = True

        # Ordered write check: an app write before any PRD write (with the gate closed) is a violation.
        prd_seen = gate_open
        early_writes = []
        for name, tool_input in turn["tools"]:
            if name == "Read" and "/skills/wheres-my-prd/references/" in tool_input.get("file_path", ""):
                res["refs_loaded"].append(os.path.basename(tool_input["file_path"]))
            if name not in WRITE_TOOLS:
                continue
            path = os.path.relpath(os.path.realpath(tool_input.get(WRITE_TOOLS[name], "")), os.path.realpath(workdir))
            if path.startswith(".."):
                continue
            if PRD_PATH.match(path):
                prd_seen = prd_seen or path not in baseline
            elif not prd_seen:
                early_writes.append(path)

        valid, meta = prd_state(workdir, baseline)
        app_changed = [p for p in changed_files(workdir) if not p.startswith("docs/prd/")]
        questions, format_ok = question_metrics(turn["text"])
        if res["first_turn_questions"] is None:
            res["first_turn_questions"] = questions
        if step["expect"] == "questions":
            res["format_ok"] = res["format_ok"] and format_ok

        if scenario["trigger"]:
            for path in early_writes:
                res["violations"].append(f"turn {res['user_turns']}: wrote {path} before the PRD")
            if app_changed and not valid:
                res["violations"].append(f"turn {res['user_turns']}: app files changed without a valid PRD: {', '.join(app_changed[:4])}")

        expect = step["expect"]
        problems = []
        if turn["error"]:
            problems.append(f"claude error: {turn['error']}")
        elif expect == "questions":
            if not 1 <= questions <= 5:
                problems.append(f"expected 1-5 questions, got {questions}")
            if app_changed:
                problems.append("app files changed while asking questions")
        elif expect == "prd":
            if questions:
                problems.append(f"expected a fast pass with 0 questions, got {questions}")
            if not valid:
                problems.append("no valid PRD after the turn")
            if app_changed:
                problems.append("app files changed before the user confirmed")
        elif expect in ("lock", "build"):
            if not valid and questions and auto_followups < MAX_AUTO_FOLLOWUPS and not truncated:
                auto_followups += 1
                queue.insert(0, {"say": "defaults", "expect": expect, "auto": True})
            elif not valid:
                problems.append("no valid PRD after answering")
            elif expect == "lock" and app_changed:
                problems.append("built code when only a review was asked for")
            elif expect == "build" and not app_changed:
                res["notes"].append(f"turn {res['user_turns']}: asked before building")
        elif expect == "prd_then_code":
            if not valid:
                problems.append("no valid PRD")
            if not app_changed:
                problems.append("no code written after the emergency lock")
        elif expect == "edit":
            if res["triggered"]:
                problems.append("skill triggered on a request it should ignore")
            if valid or meta:
                problems.append("wrote a PRD for a request that needs none")
            if not app_changed:
                problems.append("the requested edit was not made")

        if valid and res["turns_to_lock"] is None:
            res["turns_to_lock"] = res["user_turns"]
        gate_open = gate_open or valid
        res["problems"] += [f"turn {res['user_turns']}: {p}" for p in problems]
        res["turns"].append({"say": step["say"], "auto": step.get("auto", False), "expect": expect,
                             "questions": questions, "app_changed": app_changed, "prd_valid": valid,
                             "seconds": turn["seconds"],
                             "reply": turn["text"].replace(workdir, "<repo>").replace(ROOT, "<wheres-my-prd>")})
        commit(workdir, f"turn {res['user_turns']}")

    valid, meta = prd_state(workdir, baseline)
    res["mode"] = meta.get("interrogation_mode")
    res["score"] = meta.get("spec_readiness_score")
    res["prd_valid"] = valid
    res["prd_file"] = meta.get("file")
    if res["triggered"] != scenario["trigger"]:
        res["problems"].append(f"trigger: expected {scenario['trigger']}, got {res['triggered']}")
    if scenario["mode"] and res["mode"] != scenario["mode"] and not truncated:
        res["problems"].append(f"mode: expected {scenario['mode']}, got {res['mode']}")

    # Follow-up phases: a new, linked PRD, and the earlier PRD's body left as the record of what shipped.
    current = read_prds(workdir)
    for path, text in baseline.items():
        if path not in current or prd_body(current[path]) != prd_body(text):
            res["problems"].append(f"rewrote the earlier PRD {path}")
    if scenario.get("phase") and not truncated:
        if res["prd_file"] in baseline:
            res["problems"].append("edited the earlier PRD instead of writing a new one")
        if meta.get("phase") != str(scenario["phase"]):
            res["problems"].append(f"phase: expected {scenario['phase']}, got {meta.get('phase')}")
        parent = os.path.basename(meta.get("parent_prd") or "")
        if parent != os.path.basename(scenario["parent"]):
            res["problems"].append(f"parent_prd: expected {scenario['parent']}, got {meta.get('parent_prd')}")
    if not res["format_ok"]:
        res["problems"].append("a question lacked 'Why it matters' or a recommended default")
    res["refs_loaded"] = sorted(set(res["refs_loaded"]))
    res["cost"] = round(res["cost"], 4)
    res["passed"] = not res["problems"] and not res["violations"]
    if not args.keep:
        shutil.rmtree(workdir, ignore_errors=True)
    status = "PASS" if res["passed"] else "FAIL"
    log(f"[{model:>6}] {sid:<34} {status}  turns={res['user_turns']} lock={res['turns_to_lock']} "
        f"mode={res['mode']} q1={res['first_turn_questions']} ${res['cost']:.2f}"
        + ("" if res["passed"] else "  " + "; ".join(res["violations"] + res["problems"])[:240])
        + (f"\n         kept {workdir}" if args.keep else ""))
    return res


def summarize(results):
    lines = ["| Model | Scenario | Pressure | Result | Gate | Mode | Q (turn 1) | Turns to lock | Refs loaded | Cost |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for r in sorted(results, key=lambda r: (r["model"], r["id"])):
        lines.append("| {model} | {id} | {pressure} | {result} | {gate} | {mode} | {q} | {lock} | {refs} | ${cost:.2f} |".format(
            model=r["model"], id=r["id"], pressure=r["pressure"],
            result=("✅ pass" + (f" ({'; '.join(r.get('notes', []))})" if r.get("notes") else "")) if r["passed"]
            else "❌ " + "; ".join(r["violations"] + r["problems"])[:160],
            gate="✗" if r["violations"] else "✓", mode=r["mode"] or "—", q=r["first_turn_questions"],
            lock=r["turns_to_lock"] or "—", refs=", ".join(x.replace(".md", "") for x in r["refs_loaded"]) or "—",
            cost=r["cost"]))
    lines.append("")
    for model in sorted({r["model"] for r in results}):
        rs = [r for r in results if r["model"] == model]
        gated = [r for r in rs if r["expected_trigger"]]
        locks = [r["turns_to_lock"] for r in rs if r["expected_mode"] == "full_grill" and r["turns_to_lock"]]
        avg_lock = f"{sum(locks) / len(locks):.1f}" if locks else "—"
        lines.append(f"- **{model}:** {sum(r['passed'] for r in rs)}/{len(rs)} scenarios passed · "
                     f"gate held in {sum(not r['violations'] for r in gated)}/{len(gated)} · "
                     f"avg user turns to lock (full grill) {avg_lock} · "
                     f"cost ${sum(r['cost'] for r in rs):.2f}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--models", default="sonnet", help="comma-separated model aliases (default: sonnet)")
    parser.add_argument("--only", default="", help="comma-separated scenario id prefixes, e.g. 01,13")
    parser.add_argument("--reps", type=int, default=1, help="repetitions of each scenario per model (default: 1)")
    parser.add_argument("--max-turns", type=int, default=0, help="run only the first N scripted turns (micro-tests)")
    parser.add_argument("--jobs", type=int, default=4, help="scenarios to run in parallel (default: 4)")
    parser.add_argument("--timeout", type=int, default=900, help="seconds per agent turn (default: 900)")
    parser.add_argument("--user-settings", action="store_true", help="load your own settings, plugins and hooks too")
    parser.add_argument("--keep", action="store_true", help="keep each scenario's working directory")
    parser.add_argument("--workdir-root", default=None, help="where to create working directories")
    parser.add_argument("--label", default="", help="suffix for the results file name")
    args = parser.parse_args()

    if not shutil.which("claude"):
        sys.exit("the claude CLI is not on PATH")
    with open(os.path.join(ROOT, "evals", "scenarios.json")) as fh:
        scenarios = json.load(fh)
    if args.only:
        prefixes = tuple(p.strip() for p in args.only.split(","))
        scenarios = [s for s in scenarios if s["id"].startswith(prefixes)]
    models = [m.strip() for m in args.models.split(",") if m.strip()]

    jobs = [(s, m) for m in models for s in scenarios for _ in range(args.reps)]
    log(f"Running {len(jobs)} scenario runs ({len(scenarios)} scenarios × {len(models)} models × {args.reps} reps), "
        f"{args.jobs} at a time")
    results = []
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_scenario, s, m, args) for s, m in jobs]
        for future in cf.as_completed(futures):
            try:
                results.append(future.result())
            except Exception as exc:  # keep the batch going; report the crash
                log(f"harness error: {exc!r}")

    os.makedirs(RESULTS_DIR, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M") + (f"-{args.label}" if args.label else "")
    with open(os.path.join(RESULTS_DIR, f"{stamp}.json"), "w") as fh:
        json.dump(results, fh, indent=2, ensure_ascii=False)
    summary = summarize(results)
    with open(os.path.join(RESULTS_DIR, f"{stamp}.md"), "w") as fh:
        fh.write(f"# Eval run {stamp}\n\n{summary}")
    print("\n" + summary)
    print(f"Saved evals/results/{stamp}.json and .md")
    sys.exit(0 if all(r["passed"] for r in results) else 1)


if __name__ == "__main__":
    main()
