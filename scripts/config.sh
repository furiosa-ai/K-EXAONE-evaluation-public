#!/bin/bash
# ============================================
# Shared configuration for all benchmark scripts
# ============================================

# Project root (parent of scripts/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Model
MODEL="${MODEL:-LGAI-EXAONE/K-EXAONE-236B-A23B}"
MODEL_SHORT="${MODEL##*/}"

# vLLM server
VLLM_HOST="${VLLM_HOST:-localhost}"
VLLM_PORT="${VLLM_PORT:-8000}"
BASE_URL="http://${VLLM_HOST}:${VLLM_PORT}/v1"

# Common generation parameters
TEMPERATURE="${TEMPERATURE:-1.0}"
TOP_P="${TOP_P:-0.95}"

# Session: unique per script invocation (model + timestamp)
SESSION_TS="${SESSION_TS:-$(date +%Y%m%d_%H%M%S)}"
SESSION_ID="${MODEL_SHORT}_${SESSION_TS}"

# --- Session helper functions ---

# Write initial session.json
# Usage: write_session_json <dir> <benchmark> <num_runs> [extra_json]
write_session_json() {
    local dir="$1" benchmark="$2" num_runs="$3" extra="${4:-}"
    python3 -c "
import json, datetime
d = {
    'version': 1,
    'benchmark': '${benchmark}',
    'model': '${MODEL}',
    'model_short': '${MODEL_SHORT}',
    'session_id': '${SESSION_ID}',
    'started_at': datetime.datetime.now().isoformat(),
    'finished_at': None,
    'status': 'running',
    'num_runs_completed': 0,
    'num_runs_requested': int('${num_runs}'),
    'config': {
        'temperature': float('${TEMPERATURE}'),
        'top_p': float('${TOP_P}'),
        'max_concurrency': int('${MAX_CONCURRENCY:-0}'),
        'vllm_host': '${VLLM_HOST}',
        'vllm_port': int('${VLLM_PORT}'),
    },
}
extra_str = '''${extra}'''
if extra_str:
    d['config'].update(json.loads(extra_str))
with open('${dir}/session.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}

# Update run progress in session.json
# Usage: update_session_progress <dir> <completed_count>
update_session_progress() {
    local dir="$1" count="$2"
    python3 -c "
import json
p = '${dir}/session.json'
with open(p) as f:
    d = json.load(f)
d['num_runs_completed'] = int('${count}')
with open(p, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}

# Finalize session.json (set status + finished_at)
# Usage: finalize_session_json <dir> <status>
finalize_session_json() {
    local dir="$1" status="$2"
    python3 -c "
import json, datetime
p = '${dir}/session.json'
with open(p) as f:
    d = json.load(f)
d['finished_at'] = datetime.datetime.now().isoformat()
d['status'] = '${status}'
with open(p, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}
