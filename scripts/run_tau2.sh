#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NUM_RUNS="${NUM_RUNS:-5}"
NUM_TRIALS="${NUM_TRIALS:-4}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-128}"
USER_LLM="${USER_LLM:-gpt-4.1}"
DOMAINS="${DOMAINS:-airline retail telecom}"
TAU2_DIR="${PROJECT_ROOT}/tau2-bench"

# Session directory: results/tau2/{MODEL_SHORT}_{YYYYMMDD_HHMMSS}/
SESSION_DIR="${PROJECT_ROOT}/results/tau2/${SESSION_ID}"
mkdir -p "${SESSION_DIR}"
write_session_json "${SESSION_DIR}" "tau2" "${NUM_RUNS}" \
    '{"num_trials":'"${NUM_TRIALS}"',"user_llm":"'"${USER_LLM}"'","domains":"'"${DOMAINS}"'"}'

# Finalize session on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        finalize_session_json "${SESSION_DIR}" "failed"
    fi
}
trap cleanup EXIT

echo "============================================"
echo "Tau2 Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Session: ${SESSION_ID}"
echo "Output: ${SESSION_DIR}"
echo "Domains: ${DOMAINS}"
echo "Trials per domain: ${NUM_TRIALS}"
echo "User LLM: ${USER_LLM}"
echo "Start: $(date)"
echo "============================================"

cd "${TAU2_DIR}"

COMPLETED=0
for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo "=========================================="
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "=========================================="

    for domain in ${DOMAINS}; do
        echo ""
        echo ">>> Run $i - Domain: ${domain} - $(date)"
        echo "--------------------------------------------"

        # Use a temp name with session timestamp to avoid collisions
        SAVE_NAME="tmp_${SESSION_TS}_${domain}_run${i}"

        uv run tau2 run \
            --domain "${domain}" \
            --save-to "${SAVE_NAME}" \
            --agent-llm "openai/${MODEL}" \
            --agent-llm-args "{\"temperature\":${TEMPERATURE},\"top_p\":${TOP_P},\"api_base\":\"${BASE_URL}\",\"extra_body\":{\"chat_template_kwargs\":{\"enable_thinking\":true}}}" \
            --user-llm "${USER_LLM}" \
            --num-trials "${NUM_TRIALS}" \
            --max-concurrency "${MAX_CONCURRENCY}"

        # Move results from native location to session directory
        NATIVE_DIR="${TAU2_DIR}/data/simulations/${SAVE_NAME}"
        DEST_DIR="${SESSION_DIR}/${domain}_run_$(printf '%02d' $i)"
        mv "${NATIVE_DIR}" "${DEST_DIR}"

        echo ">>> Run $i - Domain ${domain} completed - $(date)"
    done

    COMPLETED=$i
    update_session_progress "${SESSION_DIR}" "$COMPLETED"
    echo ">>> Run $i completed - $(date)"
done

finalize_session_json "${SESSION_DIR}" "completed"

echo ""
echo "============================================"
echo "All ${NUM_RUNS} runs completed - $(date)"
echo "============================================"
echo ""

# Summarize results
echo "Summarizing results..."
python3 - "${SESSION_DIR}" <<'PYEOF'
import json, os, glob, statistics, sys

session_dir = sys.argv[1]

# Collect results grouped by domain
domain_scores = {}
for result_dir in sorted(glob.glob(os.path.join(session_dir, "*_run_*"))):
    result_file = os.path.join(result_dir, "results.json")
    if not os.path.exists(result_file):
        continue
    name = os.path.basename(result_dir)
    # Extract domain from name: {domain}_run_{NN}
    parts = name.rsplit("_run_", 1)
    domain = parts[0] if parts else "unknown"
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
