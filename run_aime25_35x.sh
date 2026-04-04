#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: Script failed at line $LINENO (exit code $?)" >&2' ERR

MODEL="furiosa-ai/K-EXAONE-236B-A23B-NVFP4A16-GPTQ-think-token-fix8"
RESULTS_DIR="./results"
NUM_RUNS=35

# Snapshot existing result files before runs
BEFORE_FILES=$(mktemp)
find "${RESULTS_DIR}" -name "results_*.json" 2>/dev/null | sort > "$BEFORE_FILES"

echo "============================================"
echo "AIME25 Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Start: $(date)"
echo "============================================"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "--------------------------------------------"

    python -m lm_eval \
        --model local-chat-completions \
        --model_args "model=${MODEL},base_url=http://localhost:8000/v1/chat/completions,tokenized_requests=False,tokenizer_backend=None,max_length=131072,num_concurrent=8,timeout=36000" \
        --tasks aime25 \
        --batch_size 1 \
        --num_fewshot 0 \
        --gen_kwargs '{"temperature":1.0,"top_p":0.95,"max_gen_toks":120000,"n":1,"chat_template_kwargs":{"enable_thinking":true}}' \
        --write_out \
        --log_samples \
        --output_path "${RESULTS_DIR}/aime25_run_${i}" \
        --apply_chat_template

    echo ">>> Run $i completed - $(date)"
done

echo ""
echo "============================================"
echo "All ${NUM_RUNS} runs completed - $(date)"
echo "============================================"
echo ""

# Collect only new result files created during this session
AFTER_FILES=$(mktemp)
find "${RESULTS_DIR}" -name "results_*.json" 2>/dev/null | sort > "$AFTER_FILES"
NEW_FILES=$(comm -13 "$BEFORE_FILES" "$AFTER_FILES" || true)
rm -f "$BEFORE_FILES" "$AFTER_FILES"

# Summarize results
echo "Summarizing results (this session only)..."
python3 - $NEW_FILES <<'PYEOF'
import json, sys, statistics, os

files = sys.argv[1:]
if not files:
    print("No new result files found!")
    sys.exit(1)

scores = []
print(f"\n{'='*60}")
print(f"  AIME25 Results Summary (this session)")
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

    # Extract run directory name for display
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
