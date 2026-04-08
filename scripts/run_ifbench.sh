#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: Script failed at line $LINENO (exit code $?)" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NUM_RUNS="${NUM_RUNS:-5}"
IFBENCH_DIR="${PROJECT_ROOT}/IFBench"
EVAL_BASE="${IFBENCH_DIR}/eval"

echo "============================================"
echo "IFBench Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Start: $(date)"
echo "============================================"

cd "${IFBENCH_DIR}"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "--------------------------------------------"

    OUTPUT_FILE="${EVAL_BASE}/run${i}/responses.jsonl"
    EVAL_DIR="${EVAL_BASE}/run${i}"
    mkdir -p "$EVAL_DIR"

    NLTK_DATA="${IFBENCH_DIR}/.nltk_data" \
    python generate_responses.py \
        --api-base "${BASE_URL}" \
        --model "$MODEL" \
        --input-file data/IFBench_test.jsonl \
        --output-file "$OUTPUT_FILE" \
        --temperature "${TEMPERATURE}" \
        --top-p "${TOP_P}" \
        --max-tokens 100000 \
        --workers 8 \
        --enable-thinking

    NLTK_DATA="${IFBENCH_DIR}/.nltk_data" \
    python -m run_eval \
        --input_data=data/IFBench_test.jsonl \
        --input_response_data="$OUTPUT_FILE" \
        --output_dir="$EVAL_DIR"

    echo ">>> Run $i completed - $(date)"
done

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
    path = f'eval/run{i}/responses-eval_results_loose.jsonl'
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
