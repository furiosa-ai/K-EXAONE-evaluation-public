#!/bin/bash
# ============================================
# Shared configuration for all benchmark scripts
# ============================================

# Project root (parent of scripts/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Model
MODEL="${MODEL:-LGAI-EXAONE/K-EXAONE-236B-A23B}"

# vLLM server
VLLM_HOST="${VLLM_HOST:-localhost}"
VLLM_PORT="${VLLM_PORT:-8000}"
BASE_URL="http://${VLLM_HOST}:${VLLM_PORT}/v1"

# Common generation parameters
TEMPERATURE="${TEMPERATURE:-1.0}"
TOP_P="${TOP_P:-0.95}"
