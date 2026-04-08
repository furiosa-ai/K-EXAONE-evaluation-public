#!/bin/bash
set -euo pipefail
# GPQA smoke test: 1 run, debug mode (5 examples)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/config.sh"

echo "============================================"
echo "[TEST] GPQA - 1 run, debug mode"
echo "Model: ${MODEL}"
echo "============================================"

cd "${PROJECT_ROOT}"
mkdir -p simple-evals/results

python -m simple-evals.simple_evals \
    --eval gpqa \
    --model "$MODEL" \
    --custom \
    --base_url "${BASE_URL}" \
    --temperature "${TEMPERATURE}" \
    --top_p "${TOP_P}" \
    --max_tokens None \
    --extra_body '{"chat_template_kwargs": {"enable_thinking": true}}' \
    --n-threads 4 \
    --n-repeats 1 \
    --debug

echo "[TEST] GPQA passed"
