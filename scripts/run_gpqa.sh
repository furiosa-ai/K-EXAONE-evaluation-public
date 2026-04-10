#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NUM_RUNS="${NUM_RUNS:-8}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-128}"

# Session directory: results/gpqa/{MODEL_SHORT}_{YYYYMMDD_HHMMSS}/
SESSION_DIR="${PROJECT_ROOT}/results/gpqa/${SESSION_ID}"
mkdir -p "${SESSION_DIR}"
write_session_json "${SESSION_DIR}" "gpqa" "${NUM_RUNS}"

# Finalize session on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        finalize_session_json "${SESSION_DIR}" "failed"
    fi
}
trap cleanup EXIT

echo "============================================"
echo "GPQA Evaluation - ${NUM_RUNS} runs"
echo "Model: ${MODEL}"
echo "Session: ${SESSION_ID}"
echo "Output: ${SESSION_DIR}"
echo "Start: $(date)"
echo "============================================"

cd "${PROJECT_ROOT}"

for i in $(seq 1 $NUM_RUNS); do
    echo ""
    echo ">>> Run $i / $NUM_RUNS - $(date)"
    echo "--------------------------------------------"

    python -m simple-evals.simple_evals \
        --eval gpqa \
        --model "$MODEL" \
        --custom \
        --base_url "${BASE_URL}" \
        --temperature "${TEMPERATURE}" \
        --top_p "${TOP_P}" \
        --max_tokens None \
        --extra_body '{"chat_template_kwargs": {"enable_thinking": true}}' \
        --n-threads "${MAX_CONCURRENCY}" \
        --n-repeats 1 \
        --output_dir "${SESSION_DIR}" \
    || { echo "!!! Run $i FAILED (exit code: $?) - $(date)"; exit 1; }

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
files = sorted(glob.glob(os.path.join(session_dir, "gpqa_*.json")))
files = [f for f in files if "_allresults" not in f and "_DEBUG" not in f]

if not files:
    print("No result files found!")
    sys.exit(1)

scores = []
print(f"\n{'='*60}")
print(f"  GPQA Results Summary")
print(f"{'='*60}")
print(f"{'#':<4} {'Date/Time':<20} {'Score':<10} {'Chars':<10}")
print(f"{'-'*60}")

for idx, f in enumerate(sorted(files), 1):
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
