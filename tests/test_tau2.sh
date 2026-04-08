#!/bin/bash
set -euo pipefail
# Tau2 smoke test: 1 domain (airline), 1 trial, 2 tasks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/config.sh"

USER_LLM="${USER_LLM:-gpt-4.1}"
TAU2_DIR="${PROJECT_ROOT}/tau2-bench"

echo "============================================"
echo "[TEST] Tau2 - airline, 1 trial, 2 tasks"
echo "Model: ${MODEL}"
echo "============================================"

cd "${TAU2_DIR}"

uv run tau2 run \
    --domain airline \
    --save-to "test_smoke" \
    --agent-llm "openai/${MODEL}" \
    --agent-llm-args "{\"temperature\":${TEMPERATURE},\"top_p\":${TOP_P},\"api_base\":\"${BASE_URL}\",\"extra_body\":{\"chat_template_kwargs\":{\"enable_thinking\":true}}}" \
    --user-llm "${USER_LLM}" \
    --num-trials 1 \
    --num-tasks 2 \
    --max-concurrency 2

echo "[TEST] Tau2 passed"
