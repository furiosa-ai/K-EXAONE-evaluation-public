#!/usr/bin/env python3
"""Aggregate tau2 benchmark results across multiple runs and compute mean/std."""

import argparse
import json
import math
from pathlib import Path
from collections import defaultdict
import numpy as np


def is_successful(reward: float) -> bool:
    return (1 - 1e-6) <= reward <= (1 + 1e-6)


def pass_hat_k(num_trials: int, success_count: int, k: int) -> float:
    return math.comb(success_count, k) / math.comb(num_trials, k)


def load_run_results(data_dir: Path, timestamp: str, run_id: int, domains: list[str]) -> dict[str, dict[str, float]]:
    """Load results for a single run, return metrics per domain."""
    results = {}
    for domain in domains:
        # Support both directory format (results.json inside dir) and flat .json
        dir_path = data_dir / f"outputs_{timestamp}_run{run_id}_{domain}"
        flat_path = data_dir / f"outputs_{timestamp}_run{run_id}_{domain}.json"
        if dir_path.is_dir() and (dir_path / "results.json").exists():
            filepath = dir_path / "results.json"
        elif flat_path.exists():
            filepath = flat_path
        else:
            print(f"Warning: {dir_path} not found, skipping")
            continue
        with open(filepath) as f:
            data = json.load(f)

        task_rewards = defaultdict(list)
        for sim in data["simulations"]:
            task_rewards[sim["task_id"]].append(sim["reward_info"]["reward"])

        all_rewards = [r for rs in task_rewards.values() for r in rs]
        avg_reward = np.mean(all_rewards) if all_rewards else 0.0

        pass1_per_task = []
        for rewards in task_rewards.values():
            n = len(rewards)
            sc = sum(is_successful(r) for r in rewards)
            pass1_per_task.append(pass_hat_k(n, sc, 1))
        pass1 = np.mean(pass1_per_task) if pass1_per_task else 0.0

        any_success_per_task = [1.0 if any(is_successful(r) for r in rs) else 0.0 for rs in task_rewards.values()]
        any_success = np.mean(any_success_per_task) if any_success_per_task else 0.0

        results[domain] = {
            "avg_reward": avg_reward,
            "pass^1": pass1,
            "any_success": any_success,
        }

    return results


def print_metric_table(metric_name: str, all_results: dict[str, list[float]], domains: list[str]):
    print(f"\n  [{metric_name}]")
    print(f"  {'Domain':<12} {'Runs':>5} {'Mean':>8} {'Std':>8} {'Min':>8} {'Max':>8}")
    print(f"  {'-' * 55}")

    overall_scores = []
    for domain in domains:
        scores = all_results.get(domain, [])
        if not scores:
            print(f"  {domain:<12} {'N/A':>5}")
            continue
        overall_scores.append(scores)
        print(f"  {domain:<12} {len(scores):>5} {np.mean(scores):>8.4f} {np.std(scores):>8.4f} {min(scores):>8.4f} {max(scores):>8.4f}")

    if overall_scores:
        min_runs = min(len(s) for s in overall_scores)
        per_run_avg = [np.mean([s[i] for s in overall_scores]) for i in range(min_runs)]
        print(f"  {'-' * 55}")
        print(f"  {'Overall':<12} {len(per_run_avg):>5} {np.mean(per_run_avg):>8.4f} {np.std(per_run_avg):>8.4f} {min(per_run_avg):>8.4f} {max(per_run_avg):>8.4f}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timestamp", required=True, help="Timestamp prefix of the output files")
    parser.add_argument("--num-runs", type=int, default=5)
    args = parser.parse_args()

    data_dir = Path(__file__).parent / "data" / "simulations"
    domains = ["airline", "retail", "telecom"]
    metrics = ["avg_reward", "pass^1", "any_success"]

    # Collect per-run scores: metric -> domain -> list of values
    all_results = {m: defaultdict(list) for m in metrics}
    for run_id in range(1, args.num_runs + 1):
        run_results = load_run_results(data_dir, args.timestamp, run_id, domains)
        for domain, domain_metrics in run_results.items():
            for m in metrics:
                all_results[m][domain].append(domain_metrics[m])

    if not any(all_results["avg_reward"].values()):
        print(f"\nNo results found for timestamp: {args.timestamp}")
        print(f"Expected: {data_dir}/outputs_{args.timestamp}_run*_*/results.json or .json")
        return

    print(f"\nTimestamp: {args.timestamp}")
    print("=" * 60)

    for m in metrics:
        print_metric_table(m, all_results[m], domains)

    print()
    print("=" * 60)

    # Per-run detail
    for m in metrics:
        print(f"\n  [{m}] Per-run detail")
        print(f"  {'Run':<6}", end="")
        for domain in domains:
            print(f"{domain:>12}", end="")
        print(f"{'Average':>12}")
        print(f"  {'-' * 54}")
        for run_id in range(1, args.num_runs + 1):
            print(f"  {run_id:<6}", end="")
            run_scores = []
            for domain in domains:
                scores = all_results[m].get(domain, [])
                if run_id <= len(scores):
                    print(f"{scores[run_id-1]:>12.4f}", end="")
                    run_scores.append(scores[run_id - 1])
                else:
                    print(f"{'N/A':>12}", end="")
            if run_scores:
                print(f"{np.mean(run_scores):>12.4f}")
            else:
                print()


if __name__ == "__main__":
    main()
