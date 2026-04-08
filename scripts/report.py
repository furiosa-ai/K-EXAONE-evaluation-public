#!/usr/bin/env python3
"""Generate a unified evaluation report across all benchmarks, grouped by model."""

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


def extract_model_from_gpqa_filename(filename):
    """Extract model name from gpqa_{model}_{date}_{time}.json"""
    base = os.path.basename(filename).replace(".json", "")
    # gpqa_{model}_{YYYYMMDD}_{HHMMSS}
    m = re.match(r"gpqa_(.+)_(\d{8})_(\d{6})$", base)
    return m.group(1) if m else "unknown"


def collect_gpqa(project_root):
    """Collect GPQA results grouped by model."""
    results_dir = project_root / "simple-evals" / "results"
    files = sorted(glob.glob(str(results_dir / "gpqa_*.json")))
    files = [f for f in files if "_allresults" not in f and "_DEBUG" not in f]

    by_model = defaultdict(list)
    for f in files:
        model = extract_model_from_gpqa_filename(f)
        with open(f) as fp:
            data = json.load(fp)
        by_model[model].append(data.get("score", 0) * 100)

    return dict(by_model)


def collect_aime25(project_root):
    """Collect AIME25 results grouped by model."""
    results_dir = project_root / "results" / "aime25"
    files = sorted(glob.glob(str(results_dir / "**/results_*.json"), recursive=True))

    by_model = defaultdict(list)
    for f in files:
        with open(f) as fp:
            data = json.load(fp)
        # Model name from config
        config = data.get("config", {})
        model = config.get("model", "unknown")
        if model == "unknown":
            model_args = config.get("model_args", "")
            m = re.search(r"model=([^,]+)", model_args)
            if m:
                model = m.group(1)
        # Normalize: remove org prefix for display
        model = model.rsplit("/", 1)[-1] if "/" in model else model

        results = data.get("results", {})
        aime = results.get("aime25", results.get("aime_25", {}))
        score = aime.get("exact_match,none", aime.get("exact_match", None))
        if score is not None:
            by_model[model].append(score * 100)

    return dict(by_model)


def collect_ifbench(project_root):
    """Collect IFBench results grouped by model."""
    eval_dir = project_root / "IFBench" / "eval"

    by_model = defaultdict(lambda: {"strict": [], "loose": []})

    # New structure: eval/{model}/run{N}/
    for model_dir in sorted(eval_dir.iterdir()) if eval_dir.exists() else []:
        if not model_dir.is_dir() or model_dir.name in ("test",):
            continue

        run_dirs = sorted(glob.glob(str(model_dir / "run*")))
        if run_dirs:
            # eval/{model}/run{N}/ structure
            model = model_dir.name
            for run_dir in run_dirs:
                for mode in ["strict", "loose"]:
                    for f in glob.glob(os.path.join(run_dir, f"*eval_results_{mode}.jsonl")):
                        data = [json.loads(line) for line in open(f)]
                        if data:
                            total = len(data)
                            passed = sum(1 for d in data if d.get("follow_all_instructions"))
                            by_model[model][mode].append(passed / total * 100)

    # Legacy structure: eval/run{N}/ (no model dir)
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


def collect_tau2(project_root):
    """Collect Tau2 results grouped by model."""
    sim_dir = project_root / "tau2-bench" / "data" / "simulations"

    by_model = defaultdict(lambda: defaultdict(list))
    for result_dir in sorted(sim_dir.iterdir()) if sim_dir.exists() else []:
        if not result_dir.is_dir() or "test" in result_dir.name:
            continue

        result_file = result_dir / "results.json"
        if not result_file.exists():
            continue

        with open(result_file) as f:
            data = json.load(f)

        # Extract model from agent_info
        agent_info = data.get("info", {}).get("agent_info", {})
        model = agent_info.get("llm", "unknown")
        # Strip openai/ prefix
        model = re.sub(r"^openai/", "", model)
        # Normalize to short name
        model = model.rsplit("/", 1)[-1] if "/" in model else model

        sims = data.get("simulations", [])
        if not sims:
            continue

        # Determine domain
        name = result_dir.name
        for domain in ["airline", "retail", "telecom"]:
            if domain in name:
                rewards = [s["reward_info"]["reward"] for s in sims
                          if s.get("reward_info") and s["reward_info"].get("reward") is not None]
                if rewards:
                    by_model[model][domain].append(sum(rewards) / len(rewards) * 100)
                break

    return {m: dict(d) for m, d in by_model.items()}


def fmt_stats(scores):
    """Format mean ± std (all values in %)."""
    if not scores:
        return "N/A", "N/A", "N/A", 0
    mean = sum(scores) / len(scores)
    std = math.sqrt(sum((s - mean) ** 2 for s in scores) / len(scores)) if len(scores) > 1 else 0
    return f"{mean:.2f}%", f"{std:.2f}%", f"{mean:.2f} ± {std:.2f}%", len(scores)


def print_section(title):
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


def build_report(project_root):
    """Collect all results and build a report dict keyed by model."""
    gpqa = collect_gpqa(project_root)
    aime25 = collect_aime25(project_root)
    ifbench = collect_ifbench(project_root)
    tau2 = collect_tau2(project_root)

    # Gather all model names
    all_models = set()
    all_models.update(gpqa.keys())
    all_models.update(aime25.keys())
    all_models.update(ifbench.keys())
    all_models.update(tau2.keys())

    report = {}
    for model in sorted(all_models):
        entry = {}

        # GPQA
        scores = gpqa.get(model, [])
        mean, std, result, n = fmt_stats(scores)
        entry["gpqa"] = {"scores": scores, "mean": mean, "std": std, "n": n}

        # AIME25
        scores = aime25.get(model, [])
        mean, std, result, n = fmt_stats(scores)
        entry["aime25"] = {"scores": scores, "mean": mean, "std": std, "n": n}

        # IFBench
        ifb = ifbench.get(model, {"strict": [], "loose": []})
        entry["ifbench"] = {}
        for mode in ["strict", "loose"]:
            scores = ifb.get(mode, [])
            mean, std, result, n = fmt_stats(scores)
            entry["ifbench"][mode] = {"scores": scores, "mean": mean, "std": std, "n": n}

        # Tau2
        t2 = tau2.get(model, {})
        entry["tau2"] = {}
        for domain in ["airline", "retail", "telecom"]:
            scores = t2.get(domain, [])
            mean, std, result, n = fmt_stats(scores)
            entry["tau2"][domain] = {"scores": scores, "mean": mean, "std": std, "n": n}

        report[model] = entry

    return report


def print_model_report(model, entry):
    """Print a single model's report."""
    print(f"\n{'=' * 60}")
    print(f"  Model: {model}")
    print(f"{'=' * 60}")

    # GPQA
    r = entry["gpqa"]
    print_section("GPQA (Graduate-level Q&A)")
    if r["n"]:
        print(f"  Runs:   {r['n']}")
        print(f"  Score:  {r['mean']} ± {r['std']}")
        for i, s in enumerate(r["scores"], 1):
            print(f"    Run {i}: {s:.2f}%")
    else:
        print("  No results found")

    # AIME25
    r = entry["aime25"]
    print_section("AIME 2025 (Math)")
    if r["n"]:
        print(f"  Runs:          {r['n']}")
        print(f"  exact_match:   {r['mean']} ± {r['std']}")
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
            print(f"    Accuracy: {r['mean']} ± {r['std']}")
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
            print(f"    Score:  {r['mean']} ± {r['std']}")
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
    parser.add_argument("--json", action="store_true", help="Output as JSON only")
    args = parser.parse_args()

    project_root = find_project_root()
    report = build_report(project_root)

    # Filter by model if specified
    if args.model:
        report = {m: e for m, e in report.items() if args.model in m}

    if not report:
        print("No results found.")
        return

    if args.json:
        print(json.dumps(report, indent=2, default=str))
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
