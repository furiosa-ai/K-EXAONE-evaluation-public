#!/bin/bash
set -euo pipefail
# IFBench smoke test: 1 run, 2 workers, first 5 prompts only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/config.sh"

IFBENCH_DIR="${PROJECT_ROOT}/IFBench"
EVAL_DIR="${IFBENCH_DIR}/eval/test"
INPUT_FILE="${IFBENCH_DIR}/data/IFBench_test.jsonl"
INPUT_SUBSET="${EVAL_DIR}/test_subset.jsonl"
OUTPUT_FILE="${EVAL_DIR}/responses.jsonl"
mkdir -p "${EVAL_DIR}"

echo "============================================"
echo "[TEST] IFBench - 1 run, 5 prompts"
echo "Model: ${MODEL}"
echo "============================================"

cd "${IFBENCH_DIR}"

# Extract first 5 prompts for quick test
head -n 5 "${INPUT_FILE}" > "${INPUT_SUBSET}"

NLTK_DATA="${IFBENCH_DIR}/.nltk_data" \
python generate_responses.py \
    --api-base "${BASE_URL}" \
    --model "$MODEL" \
    --input-file "${INPUT_SUBSET}" \
    --output-file "$OUTPUT_FILE" \
    --temperature "${TEMPERATURE}" \
    --top-p "${TOP_P}" \
    --max-tokens 4096 \
    --workers 2 \
    --enable-thinking

NLTK_DATA="${IFBENCH_DIR}/.nltk_data" \
python -m run_eval \
    --input_data="${INPUT_SUBSET}" \
    --input_response_data="$OUTPUT_FILE" \
    --output_dir="$EVAL_DIR"

echo "[TEST] IFBench passed"
