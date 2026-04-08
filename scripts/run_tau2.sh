#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: Script failed at line $LINENO (exit code $?)" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NUM_RUNS="${NUM_RUNS:-5}"
NUM_TRIALS="${NUM_TRIALS:-4}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-8}"
USER_LLM="${USER_LLM:-gpt-4.1}"
DOMAINS="${DOMAINS:-airline retail telecom}"
TAU2_DIR="${PROJECT_ROOT}/tau2-bench"

echo "============================================"
echo "Tau2 Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Domains: ${DOMAINS}"
echo "Trials per domain: ${NUM_TRIALS}"
echo "User LLM: ${USER_LLM}"
echo "Start: $(date)"
echo "============================================"

cd "${TAU2_DIR}"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo "=========================================="
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "=========================================="

    for domain in ${DOMAINS}; do
        echo ""
        echo ">>> Run $i - Domain: ${domain} - $(date)"
        echo "--------------------------------------------"

        SAVE_NAME="${MODEL//\//_}_${domain}_run${i}"

        uv run tau2 run \
            --domain "${domain}" \
            --save-to "${SAVE_NAME}" \
            --agent-llm "openai/${MODEL}" \
            --agent-llm-args "{\"temperature\":${TEMPERATURE},\"top_p\":${TOP_P},\"api_base\":\"${BASE_URL}\",\"extra_body\":{\"chat_template_kwargs\":{\"enable_thinking\":true}}}" \
            --user-llm "${USER_LLM}" \
            --num-trials "${NUM_TRIALS}" \
            --max-concurrency "${MAX_CONCURRENCY}"

        echo ">>> Run $i - Domain ${domain} completed - $(date)"
    done

    echo ">>> Run $i completed - $(date)"
done

echo ""
echo "============================================"
echo "All ${NUM_RUNS} runs completed - $(date)"
echo "============================================"
echo ""

# Summarize results
echo "Summarizing results..."
python3 - <<'PYEOF'
import json, os, glob, statistics

tau2_data = os.path.join(os.getcwd(), "data", "simulations")
if not os.path.isdir(tau2_data):
    print("No simulation results found.")
    exit(0)

# Collect results grouped by domain
domain_scores = {}
for result_dir in sorted(glob.glob(os.path.join(tau2_data, "*_run*"))):
    result_file = os.path.join(result_dir, "results.json")
    if not os.path.exists(result_file):
        continue
    name = os.path.basename(result_dir)
    # Extract domain from name: ..._<domain>_run<N>
    parts = name.rsplit("_run", 1)
    domain = parts[0].rsplit("_", 1)[-1] if parts else "unknown"
    run_num = parts[1] if len(parts) > 1 else "?"

    with open(result_file) as f:
        data = json.load(f)
    score = data.get("score", data.get("pass_rate", None))
    if score is not None:
        domain_scores.setdefault(domain, []).append((run_num, score))

if not domain_scores:
    print("No results to summarize.")
    exit(0)

print(f"\n{'='*60}")
print(f"  Tau2 Results Summary")
print(f"{'='*60}")
for domain, runs in sorted(domain_scores.items()):
    scores = [s for _, s in runs]
    print(f"\n  Domain: {domain}")
    for run_num, score in runs:
        print(f"    Run {run_num}: {score:.4f}")
    if scores:
        avg = statistics.mean(scores)
        std = statistics.stdev(scores) if len(scores) > 1 else 0
        print(f"    ---")
        print(f"    Mean: {avg:.4f}")
        print(f"    Std:  {std:.4f}")
print(f"\n{'='*60}")
PYEOF
