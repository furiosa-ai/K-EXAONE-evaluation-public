#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NUM_RUNS="${NUM_RUNS:-5}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-128}"
IFBENCH_DIR="${PROJECT_ROOT}/IFBench"

# Session directory: results/ifbench/{MODEL_SHORT}_{YYYYMMDD_HHMMSS}/
SESSION_DIR="${PROJECT_ROOT}/results/ifbench/${SESSION_ID}"
mkdir -p "${SESSION_DIR}"
write_session_json "${SESSION_DIR}" "ifbench" "${NUM_RUNS}"

# Finalize session on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        finalize_session_json "${SESSION_DIR}" "failed"
    fi
}
trap cleanup EXIT

echo "============================================"
echo "IFBench Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Session: ${SESSION_ID}"
echo "Output: ${SESSION_DIR}"
echo "Start: $(date)"
echo "============================================"

cd "${IFBENCH_DIR}"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "--------------------------------------------"

    RUN_NUM="$(printf '%02d' $i)"
    EVAL_DIR="${SESSION_DIR}/run_${RUN_NUM}"
    OUTPUT_FILE="${EVAL_DIR}/responses.jsonl"
    mkdir -p "$EVAL_DIR"

    NLTK_DATA="${IFBENCH_DIR}/.nltk_data" \
    python generate_responses.py \
        --api-base "${BASE_URL}" \
        --model "$MODEL" \
        --input-file data/IFBench_test.jsonl \
        --output-file "$OUTPUT_FILE" \
        --temperature "${TEMPERATURE}" \
        --top-p "${TOP_P}" \
        --max-tokens 65536 \
        --workers "${MAX_CONCURRENCY}" \
        --enable-thinking

    NLTK_DATA="${IFBENCH_DIR}/.nltk_data" \
    python -m run_eval \
        --input_data=data/IFBench_test.jsonl \
        --input_response_data="$OUTPUT_FILE" \
        --output_dir="$EVAL_DIR"

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
echo "Computing mean/std across ${NUM_RUNS} runs..."
python3 -c "
import json, math

accs = []
for i in range(1, ${NUM_RUNS} + 1):
    path = '${SESSION_DIR}/run_{:02d}/responses-eval_results_loose.jsonl'.format(i)
    try:
        data = [json.loads(l) for l in open(path)]
    except FileNotFoundError:
        print(f'  Run {i}: MISSING')
        continue
    total = len(data)
    passed = sum(1 for d in data if d['follow_all_instructions'])
    acc = passed / total * 100
    accs.append(acc)
    print(f'  Run {i}: {acc:.2f}% ({passed}/{total})')

if accs:
    mean = sum(accs) / len(accs)
    std = math.sqrt(sum((a - mean) ** 2 for a in accs) / len(accs))
    print()
    print(f'  Prompt-level accuracy (loose)')
    print(f'  Mean: {mean:.2f}%')
    print(f'  Std:  {std:.2f}%')
    print(f'  Result: {mean:.2f} +/- {std:.2f}')
"
