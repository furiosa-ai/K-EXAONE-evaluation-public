#!/bin/bash
set -e

MODEL="furiosa-ai/K-EXAONE-236B-A23B-NVFP4A16-GPTQ-think-token-fix8"
RESULTS_DIR="/workspace/k-exaone-eval/simple-evals/results"
NUM_RUNS=8

# Snapshot existing files before runs
BEFORE_FILES=$(mktemp)
ls "${RESULTS_DIR}"/*.json 2>/dev/null | sort > "$BEFORE_FILES"

echo "============================================"
echo "GPQA Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Start: $(date)"
echo "============================================"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "--------------------------------------------"

    python -m simple-evals.simple_evals \
        --eval gpqa \
        --model "$MODEL" \
        --custom \
        --temperature 1.0 \
        --top_p 0.95 \
        --max_tokens None \
        --extra_body '{"chat_template_kwargs": {"enable_thinking": true}}' \
        --n-threads 8 \
        --n-repeats 1

    echo ">>> Run $i completed - $(date)"
done

echo ""
echo "============================================"
echo "All ${NUM_RUNS} runs completed - $(date)"
echo "============================================"
echo ""

# Collect only new files
AFTER_FILES=$(mktemp)
ls "${RESULTS_DIR}"/*.json 2>/dev/null | sort > "$AFTER_FILES"
NEW_FILES=$(comm -13 "$BEFORE_FILES" "$AFTER_FILES" | grep -v "_allresults" || true)
rm -f "$BEFORE_FILES" "$AFTER_FILES"

# Summarize results
echo "Summarizing results (this session only)..."
python3 - $NEW_FILES <<'PYEOF'
import json, sys, statistics

files = sys.argv[1:]
if not files:
    print("No new result files found!")
    sys.exit(1)

scores = []
print(f"\n{'='*60}")
print(f"  GPQA Results Summary (this session)")
print(f"{'='*60}")
print(f"{'#':<4} {'Date/Time':<20} {'Score':<10} {'Chars':<10}")
print(f"{'-'*60}")

for idx, f in enumerate(sorted(files), 1):
    import os
    with open(f) as fp:
        data = json.load(fp)
    score = data.get("score", 0)
    chars = data.get("chars", 0)
    scores.append(score)
    basename = os.path.basename(f)
    parts = basename.replace(".json", "").split("_")
    dt = f"{parts[-2]}_{parts[-1]}"
    print(f"{idx:<4} {dt:<20} {score:<10.4f} {chars:<10.1f}")

print(f"{'-'*60}")
if scores:
    avg = statistics.mean(scores)
    std = statistics.stdev(scores) if len(scores) > 1 else 0
    print(f"{'Avg':<4} {'':<20} {avg:<10.4f}")
    print(f"{'Std':<4} {'':<20} {std:<10.4f}")
    print(f"{'Min':<4} {'':<20} {min(scores):<10.4f}")
    print(f"{'Max':<4} {'':<20} {max(scores):<10.4f}")
    print(f"{'N':<4} {'':<20} {len(scores)}")
print(f"{'='*60}")
PYEOF
