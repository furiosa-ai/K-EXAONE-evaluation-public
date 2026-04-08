#!/bin/bash
set -euo pipefail
# AIME25 smoke test: 1 run, limit 2 samples

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/config.sh"

RESULTS_DIR="${PROJECT_ROOT}/results/aime25_test"
mkdir -p "${RESULTS_DIR}"

echo "============================================"
echo "[TEST] AIME25 - 1 run, 2 samples"
echo "Model: ${MODEL}"
echo "============================================"

python -m lm_eval \
    --model local-chat-completions \
    --model_args "model=${MODEL},base_url=${BASE_URL}/chat/completions,tokenized_requests=False,tokenizer_backend=None,max_length=131072,num_concurrent=2,timeout=36000" \
    --tasks aime25 \
    --batch_size 1 \
    --num_fewshot 0 \
    --limit 2 \
    --gen_kwargs '{"temperature":'"${TEMPERATURE}"',"top_p":'"${TOP_P}"',"max_gen_toks":120000,"n":1,"chat_template_kwargs":{"enable_thinking":true}}' \
    --log_samples \
    --output_path "${RESULTS_DIR}" \
    --apply_chat_template

echo "[TEST] AIME25 passed"
