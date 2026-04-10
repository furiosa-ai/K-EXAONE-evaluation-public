#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NUM_RUNS="${NUM_RUNS:-35}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-128}"

# Session directory: results/aime25/{MODEL_SHORT}_{YYYYMMDD_HHMMSS}/
SESSION_DIR="${PROJECT_ROOT}/results/aime25/${SESSION_ID}"
mkdir -p "${SESSION_DIR}"
write_session_json "${SESSION_DIR}" "aime25" "${NUM_RUNS}"

# Finalize session on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        finalize_session_json "${SESSION_DIR}" "failed"
    fi
}
trap cleanup EXIT

echo "============================================"
echo "AIME25 Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Session: ${SESSION_ID}"
echo "Output: ${SESSION_DIR}"
echo "Start: $(date)"
echo "============================================"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "--------------------------------------------"

    RUN_DIR="${SESSION_DIR}/run_$(printf '%02d' $i)"

    python -m lm_eval \
        --model local-chat-completions \
        --model_args "model=${MODEL},base_url=${BASE_URL}/chat/completions,tokenized_requests=False,tokenizer_backend=None,max_length=131072,num_concurrent=${MAX_CONCURRENCY},timeout=36000" \
        --tasks aime25 \
        --batch_size 1 \
        --num_fewshot 0 \
        --gen_kwargs '{"temperature":'"${TEMPERATURE}"',"top_p":'"${TOP_P}"',"max_gen_toks":120000,"n":1,"chat_template_kwargs":{"enable_thinking":true}}' \
        --write_out \
        --log_samples \
        --output_path "${RUN_DIR}" \
        --apply_chat_template

    update_session_progress "${SESSION_DIR}" "$i"
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
import json, sys, statistics, os, glob

session_dir = sys.argv[1]
files = sorted(glob.glob(os.path.join(session_dir, "**/results_*.json"), recursive=True))

if not files:
    print("No result files found!")
    sys.exit(1)

scores = []
print(f"\n{'='*60}")
print(f"  AIME25 Results Summary")
print(f"{'='*60}")
print(f"{'#':<4} {'Run':<30} {'exact_match':<12}")
print(f"{'-'*60}")

for idx, f in enumerate(sorted(files), 1):
    with open(f) as fp:
        data = json.load(fp)

    results = data.get("results", {})
    aime = results.get("aime25", results.get("aime_25", {}))
    score = aime.get("exact_match,none", aime.get("exact_match", 0))
    scores.append(score)

    run_name = os.path.basename(os.path.dirname(os.path.dirname(f)))
    print(f"{idx:<4} {run_name:<30} {score:<12.4f}")

print(f"{'-'*60}")
if scores:
    avg = statistics.mean(scores)
    std = statistics.stdev(scores) if len(scores) > 1 else 0
    print(f"{'Avg':<4} {'':<30} {avg:<12.4f}")
    print(f"{'Std':<4} {'':<30} {std:<12.4f}")
    print(f"{'Min':<4} {'':<30} {min(scores):<12.4f}")
    print(f"{'Max':<4} {'':<30} {max(scores):<12.4f}")
    print(f"{'N':<4} {'':<30} {len(scores)}")
print(f"{'='*60}")
PYEOF
