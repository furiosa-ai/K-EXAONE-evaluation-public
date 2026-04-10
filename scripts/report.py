#!/usr/bin/env python3
"""Generate a unified evaluation report across all benchmarks, grouped by model.

Reads results from the session-based directory structure:
    results/{benchmark}/{MODEL_SHORT}_{YYYYMMDD_HHMMSS}/session.json

Also supports legacy result locations via --legacy flag.
"""

import argparse
import glob
import json
import math
import os
import re
from collections import defaultdict
from pathlib import Path


def find_project_root():
    return Path(__file__).resolve().parent.parent


# =============================================================================
# Session discovery
# =============================================================================

def discover_sessions(project_root):
    """Walk results/ tree and return list of session metadata dicts."""
    sessions = []
    results_dir = project_root / "results"
    if not results_dir.exists():
        return sessions

    for benchmark_dir in sorted(results_dir.iterdir()):
        if not benchmark_dir.is_dir():
            continue
        benchmark = benchmark_dir.name
        if benchmark not in ("gpqa", "aime25", "ifbench", "tau2"):
            continue
        for session_dir in sorted(benchmark_dir.iterdir()):
            if not session_dir.is_dir():
                continue
            session_file = session_dir / "session.json"
            if session_file.exists():
                with open(session_file) as f:
                    meta = json.load(f)
                meta["_dir"] = str(session_dir)
                meta["_benchmark"] = benchmark
                sessions.append(meta)
    return sessions


# =============================================================================
# Score extraction from session directories
# =============================================================================

def extract_gpqa_scores(session_dir):
    """Extract GPQA scores from session directory."""
    files = sorted(glob.glob(os.path.join(session_dir, "gpqa_*.json")))
    files = [f for f in files if "_allresults" not in f and "_DEBUG" not in f]
    scores = []
    for f in files:
        with open(f) as fp:
            data = json.load(fp)
        scores.append(data.get("score", 0) * 100)
    return scores


def extract_aime25_scores(session_dir):
    """Extract AIME25 scores from session directory."""
    files = sorted(glob.glob(os.path.join(session_dir, "**", "results_*.json"), recursive=True))
    scores = []
    for f in files:
        with open(f) as fp:
            data = json.load(fp)
        results = data.get("results", {})
        aime = results.get("aime25", results.get("aime_25", {}))
        score = aime.get("exact_match,none", aime.get("exact_match", None))
        if score is not None:
            scores.append(score * 100)
    return scores


def extract_ifbench_scores(session_dir):
    """Extract IFBench scores from session directory. Returns {mode: [scores]}."""
    result = {"strict": [], "loose": []}
    for mode in ["strict", "loose"]:
        for f in sorted(glob.glob(os.path.join(session_dir, "**", f"*eval_results_{mode}.jsonl"), recursive=True)):
            data = [json.loads(line) for line in open(f)]
            if data:
                total = len(data)
                passed = sum(1 for d in data if d.get("follow_all_instructions"))
                result[mode].append(passed / total * 100)
    return result


def extract_tau2_scores(session_dir):
    """Extract Tau2 scores from session directory. Returns {domain: [scores]}."""
    result = defaultdict(list)
    for result_dir in sorted(glob.glob(os.path.join(session_dir, "*_run_*"))):
        result_file = os.path.join(result_dir, "results.json")
        if not os.path.exists(result_file):
            continue
        name = os.path.basename(result_dir)
        # Parse: {domain}_run_{NN}
        parts = name.rsplit("_run_", 1)
        domain = parts[0] if parts else "unknown"

        with open(result_file) as f:
            data = json.load(f)
        sims = data.get("simulations", [])
        if sims:
            rewards = [s["reward_info"]["reward"] for s in sims
                      if s.get("reward_info") and s["reward_info"].get("reward") is not None]
            if rewards:
                result[domain].append(sum(rewards) / len(rewards) * 100)
    return dict(result)


# =============================================================================
# Legacy collectors (for --legacy flag)
# =============================================================================

def collect_legacy_gpqa(project_root):
    """Collect GPQA results from old simple-evals/results/ location."""
    results_dir = project_root / "simple-evals" / "results"
    files = sorted(glob.glob(str(results_dir / "gpqa_*.json")))
    files = [f for f in files if "_allresults" not in f and "_DEBUG" not in f]

    by_model = defaultdict(list)
    for f in files:
        base = os.path.basename(f).replace(".json", "")
        m = re.match(r"gpqa_(.+)_(\d{8})_(\d{6})$", base)
        model = m.group(1) if m else "unknown"
        with open(f) as fp:
            data = json.load(fp)
        by_model[model].append(data.get("score", 0) * 100)
    return dict(by_model)


def collect_legacy_aime25(project_root):
    """Collect AIME25 results from old results/aime25/aime25_run_* location."""
    results_dir = project_root / "results" / "aime25"
    # Only look at old-style aime25_run_* directories (not session dirs)
    files = sorted(glob.glob(str(results_dir / "aime25_run_*" / "**" / "results_*.json"), recursive=True))

    by_model = defaultdict(list)
    for f in files:
        with open(f) as fp:
            data = json.load(fp)
        config = data.get("config", {})
        model = config.get("model", "unknown")
        if model == "unknown":
            model_args = config.get("model_args", "")
            m = re.search(r"model=([^,]+)", model_args)
            if m:
                model = m.group(1)
        model = model.rsplit("/", 1)[-1] if "/" in model else model
        results = data.get("results", {})
        aime = results.get("aime25", results.get("aime_25", {}))
        score = aime.get("exact_match,none", aime.get("exact_match", None))
        if score is not None:
            by_model[model].append(score * 100)
    return dict(by_model)


def collect_legacy_ifbench(project_root):
    """Collect IFBench results from old IFBench/eval/ location."""
    eval_dir = project_root / "IFBench" / "eval"
    by_model = defaultdict(lambda: {"strict": [], "loose": []})

    if not eval_dir.exists():
        return dict(by_model)

    for model_dir in sorted(eval_dir.iterdir()):
        if not model_dir.is_dir() or model_dir.name in ("test",):
            continue
        run_dirs = sorted(glob.glob(str(model_dir / "run*")))
        if run_dirs:
            model = model_dir.name
            for run_dir in run_dirs:
                for mode in ["strict", "loose"]:
                    for f in glob.glob(os.path.join(run_dir, f"*eval_results_{mode}.jsonl")):
                        data = [json.loads(line) for line in open(f)]
                        if data:
                            total = len(data)
                            passed = sum(1 for d in data if d.get("follow_all_instructions"))
                            by_model[model][mode].append(passed / total * 100)

    # Legacy flat structure: eval/run{N}/
    legacy_runs = sorted(glob.glob(str(eval_dir / "run*")))
    if legacy_runs:
        model = "unknown"
        for run_dir in legacy_runs:
            for mode in ["strict", "loose"]:
                for f in glob.glob(os.path.join(run_dir, f"*eval_results_{mode}.jsonl")):
                    data = [json.loads(line) for line in open(f)]
                    if data:
                        total = len(data)
                        passed = sum(1 for d in data if d.get("follow_all_instructions"))
                        by_model[model][mode].append(passed / total * 100)

    return dict(by_model)


def collect_legacy_tau2(project_root):
    """Collect Tau2 results from old tau2-bench/data/simulations/ location."""
    sim_dir = project_root / "tau2-bench" / "data" / "simulations"
    by_model = defaultdict(lambda: defaultdict(list))

    for result_dir in sorted(sim_dir.iterdir()) if sim_dir.exists() else []:
        if not result_dir.is_dir() or "test" in result_dir.name:
            continue
        # Skip session-moved dirs (tmp_* are temp names from new scripts)
        if result_dir.name.startswith("tmp_"):
            continue
        result_file = result_dir / "results.json"
        if not result_file.exists():
            continue

        with open(result_file) as f:
            data = json.load(f)
        agent_info = data.get("info", {}).get("agent_info", {})
        model = agent_info.get("llm", "unknown")
        model = re.sub(r"^openai/", "", model)
        model = model.rsplit("/", 1)[-1] if "/" in model else model

        sims = data.get("simulations", [])
        if not sims:
            continue

        name = result_dir.name
        for domain in ["airline", "retail", "telecom"]:
            if domain in name:
                rewards = [s["reward_info"]["reward"] for s in sims
                          if s.get("reward_info") and s["reward_info"].get("reward") is not None]
                if rewards:
                    by_model[model][domain].append(sum(rewards) / len(rewards) * 100)
                break

    return {m: dict(d) for m, d in by_model.items()}


# =============================================================================
# Report building
# =============================================================================

def fmt_stats(scores):
    """Format mean +/- std (all values in %)."""
    if not scores:
        return "N/A", "N/A", "N/A", 0
    mean = sum(scores) / len(scores)
    std = math.sqrt(sum((s - mean) ** 2 for s in scores) / len(scores)) if len(scores) > 1 else 0
    return f"{mean:.2f}%", f"{std:.2f}%", f"{mean:.2f} \u00b1 {std:.2f}%", len(scores)


def build_report(project_root, include_legacy=False, session_filter=None, model_filter=None, latest_only=False):
    """Build report dict keyed by model."""
    sessions = discover_sessions(project_root)

    # Filter by session ID
    if session_filter:
        sessions = [s for s in sessions if session_filter in s.get("session_id", "")]

    # Filter by model
    if model_filter:
        sessions = [s for s in sessions if model_filter in s.get("model_short", "") or model_filter in s.get("model", "")]

    # Only completed sessions by default
    sessions = [s for s in sessions if s.get("status") in ("completed", "running")]

    # Latest only: keep most recent session per model per benchmark
    if latest_only:
        latest = {}
        for s in sessions:
            key = (s.get("model_short", "unknown"), s.get("_benchmark", ""))
            if key not in latest or s.get("started_at", "") > latest[key].get("started_at", ""):
                latest[key] = s
        sessions = list(latest.values())

    # Group sessions by model
    model_sessions = defaultdict(list)
    for s in sessions:
        model_sessions[s.get("model_short", "unknown")].append(s)

    # Build report from sessions
    report = {}
    for model, sess_list in sorted(model_sessions.items()):
        entry = _empty_entry()

        for s in sess_list:
            benchmark = s.get("_benchmark", "")
            session_dir = s.get("_dir", "")
            if not session_dir:
                continue

            if benchmark == "gpqa":
                entry["gpqa"]["scores"].extend(extract_gpqa_scores(session_dir))
            elif benchmark == "aime25":
                entry["aime25"]["scores"].extend(extract_aime25_scores(session_dir))
            elif benchmark == "ifbench":
                ifb = extract_ifbench_scores(session_dir)
                entry["ifbench"]["strict"]["scores"].extend(ifb["strict"])
                entry["ifbench"]["loose"]["scores"].extend(ifb["loose"])
            elif benchmark == "tau2":
                t2 = extract_tau2_scores(session_dir)
                for domain in ["airline", "retail", "telecom"]:
                    entry["tau2"][domain]["scores"].extend(t2.get(domain, []))

        # Store session metadata for display
        entry["_sessions"] = sess_list
        report[model] = entry

    # Merge legacy results if requested
    if include_legacy:
        _merge_legacy(project_root, report)

    # Compute stats
    for model, entry in report.items():
        for key in ["gpqa", "aime25"]:
            scores = entry[key]["scores"]
            mean, std, result, n = fmt_stats(scores)
            entry[key].update({"mean": mean, "std": std, "n": n})
        for mode in ["strict", "loose"]:
            scores = entry["ifbench"][mode]["scores"]
            mean, std, result, n = fmt_stats(scores)
            entry["ifbench"][mode].update({"mean": mean, "std": std, "n": n})
        for domain in ["airline", "retail", "telecom"]:
            scores = entry["tau2"][domain]["scores"]
            mean, std, result, n = fmt_stats(scores)
            entry["tau2"][domain].update({"mean": mean, "std": std, "n": n})

    return report


def _empty_entry():
    return {
        "gpqa": {"scores": []},
        "aime25": {"scores": []},
        "ifbench": {
            "strict": {"scores": []},
            "loose": {"scores": []},
        },
        "tau2": {
            "airline": {"scores": []},
            "retail": {"scores": []},
            "telecom": {"scores": []},
        },
    }


def _merge_legacy(project_root, report):
    """Merge legacy results into the report dict."""
    # GPQA
    for model, scores in collect_legacy_gpqa(project_root).items():
        if model not in report:
            report[model] = _empty_entry()
        report[model]["gpqa"]["scores"].extend(scores)

    # AIME25
    for model, scores in collect_legacy_aime25(project_root).items():
        if model not in report:
            report[model] = _empty_entry()
        report[model]["aime25"]["scores"].extend(scores)

    # IFBench
    for model, modes in collect_legacy_ifbench(project_root).items():
        if model not in report:
            report[model] = _empty_entry()
        for mode in ["strict", "loose"]:
            report[model]["ifbench"][mode]["scores"].extend(modes.get(mode, []))

    # Tau2
    for model, domains in collect_legacy_tau2(project_root).items():
        if model not in report:
            report[model] = _empty_entry()
        for domain in ["airline", "retail", "telecom"]:
            report[model]["tau2"][domain]["scores"].extend(domains.get(domain, []))


# =============================================================================
# Output formatting
# =============================================================================

def print_section(title):
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


def print_model_report(model, entry):
    """Print a single model's report."""
    print(f"\n{'=' * 60}")
    print(f"  Model: {model}")

    # Show session info if available
    sessions = entry.get("_sessions", [])
    if sessions:
        benchmarks = sorted(set(s.get("_benchmark", "") for s in sessions))
        for s in sessions:
            ts = s.get("started_at", "")[:19]
            bm = s.get("_benchmark", "")
            status = s.get("status", "")
            n_done = s.get("num_runs_completed", "?")
            n_req = s.get("num_runs_requested", "?")
            print(f"  Session: {s.get('session_id', '')} [{bm}] {status} ({n_done}/{n_req} runs) {ts}")

    print(f"{'=' * 60}")

    # GPQA
    r = entry["gpqa"]
    print_section("GPQA (Graduate-level Q&A)")
    if r["n"]:
        print(f"  Runs:   {r['n']}")
        print(f"  Score:  {r['mean']} \u00b1 {r['std']}")
        for i, s in enumerate(r["scores"], 1):
            print(f"    Run {i}: {s:.2f}%")
    else:
        print("  No results found")

    # AIME25
    r = entry["aime25"]
    print_section("AIME 2025 (Math)")
    if r["n"]:
        print(f"  Runs:          {r['n']}")
        print(f"  exact_match:   {r['mean']} \u00b1 {r['std']}")
        for i, s in enumerate(r["scores"], 1):
            print(f"    Run {i}: {s:.2f}%")
    else:
        print("  No results found")

    # IFBench
    print_section("IFBench (Instruction Following)")
    has_ifbench = False
    for mode in ["strict", "loose"]:
        r = entry["ifbench"][mode]
        if r["n"]:
            has_ifbench = True
            print(f"  [{mode}]")
            print(f"    Runs:     {r['n']}")
            print(f"    Accuracy: {r['mean']} \u00b1 {r['std']}")
            for i, s in enumerate(r["scores"], 1):
                print(f"      Run {i}: {s:.2f}%")
    if not has_ifbench:
        print("  No results found")

    # Tau2
    print_section("Tau2 (Tool-Agent-User)")
    has_tau2 = False
    domain_means = []
    for domain in ["airline", "retail", "telecom"]:
        r = entry["tau2"][domain]
        if r["n"]:
            has_tau2 = True
            domain_means.append(float(r["mean"].rstrip("%")))
            print(f"  [{domain}]")
            print(f"    Runs:   {r['n']}")
            print(f"    Score:  {r['mean']} \u00b1 {r['std']}")
    if domain_means:
        print(f"\n  Overall:  {sum(domain_means) / len(domain_means):.2f}%")
    if not has_tau2:
        print("  No results found")

    # Summary table
    print(f"\n  {'─' * 50}")
    print(f"  {'Benchmark':<20} {'N':>5} {'Mean':>10} {'Std':>10}")
    print(f"  {'─' * 50}")
    for name, key in [("GPQA", "gpqa"), ("AIME25", "aime25")]:
        r = entry[key]
        print(f"  {name:<20} {r['n']:>5} {r['mean']:>10} {r['std']:>10}")
    for mode in ["strict", "loose"]:
        r = entry["ifbench"][mode]
        print(f"  {'IFBench (' + mode + ')':<20} {r['n']:>5} {r['mean']:>10} {r['std']:>10}")
    for domain in ["airline", "retail", "telecom"]:
        r = entry["tau2"][domain]
        print(f"  {'Tau2 (' + domain + ')':<20} {r['n']:>5} {r['mean']:>10} {r['std']:>10}")
    print(f"  {'─' * 50}")


def main():
    parser = argparse.ArgumentParser(description="Generate unified evaluation report")
    parser.add_argument("--model", type=str, default=None,
                        help="Filter results by model name substring")
    parser.add_argument("--session", type=str, default=None,
                        help="Filter by session ID substring")
    parser.add_argument("--latest", action="store_true",
                        help="Only show most recent session per model per benchmark")
    parser.add_argument("--legacy", action="store_true",
                        help="Also scan legacy result locations (old directory structure)")
    parser.add_argument("--json", action="store_true",
                        help="Output as JSON only")
    args = parser.parse_args()

    project_root = find_project_root()
    report = build_report(
        project_root,
        include_legacy=args.legacy,
        session_filter=args.session,
        model_filter=args.model,
        latest_only=args.latest,
    )

    if not report:
        print("No results found.")
        return

    if args.json:
        # Remove internal fields before JSON output
        out = {}
        for model, entry in report.items():
            e = {k: v for k, v in entry.items() if not k.startswith("_")}
            out[model] = e
        print(json.dumps(out, indent=2, default=str))
        return

    print()
    print("=" * 60)
    print("  K-EXAONE Evaluation Report")
    print(f"  Models: {len(report)}")
    print("=" * 60)

    for model, entry in report.items():
        print_model_report(model, entry)

    print()


if __name__ == "__main__":
    main()
