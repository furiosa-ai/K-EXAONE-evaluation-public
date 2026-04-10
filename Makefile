# ============================================
# K-EXAONE Evaluation Makefile
# ============================================
#
# Usage:
#   make setup          - Create venv & install all dependencies
#   make vllm-serve     - Start vLLM server
#   make run-gpqa       - Run GPQA benchmark
#   make run-aime25     - Run AIME25 benchmark
#   make run-ifbench    - Run IFBench benchmark
#   make run-tau2       - Run Tau2 benchmark (all domains)
#   make run-all        - Run all benchmarks sequentially
#
# Configuration (override via environment):
#   MODEL, VLLM_HOST, VLLM_PORT, TEMPERATURE, TOP_P, NUM_RUNS, etc.
# ============================================

SHELL := /bin/bash

# --- Configuration -----------------------------------------------------------
MODEL          ?= LGAI-EXAONE/K-EXAONE-236B-A23B-FP8
VLLM_HOST      ?= localhost
VLLM_PORT      ?= 8000
TP_SIZE        ?= 8
MAX_MODEL_LEN  ?= 131072
MAX_NUM_SEQS   ?= 8

# --- Paths -------------------------------------------------------------------
PROJECT_ROOT   := $(shell pwd)
VENV           := $(PROJECT_ROOT)/.venv
UV             := $(shell command -v uv 2>/dev/null)
PYTHON         := $(VENV)/bin/python
PIP            := $(VENV)/bin/pip
ACTIVATE       := source $(VENV)/bin/activate

# --- Colors ------------------------------------------------------------------
GREEN  := \033[0;32m
YELLOW := \033[0;33m
CYAN   := \033[0;36m
RESET  := \033[0m

# =============================================================================
# Setup
# =============================================================================

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  K-EXAONE Evaluation"
	@echo "  ==================="
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | sed 's/:.*## /:## /' | \
		awk 'BEGIN {FS = ":## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

.PHONY: check-uv
check-uv:
ifndef UV
	@echo "$(YELLOW)uv not found. Installing...$(RESET)"
	curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo "$(GREEN)uv installed. Please restart your shell or run: source $$HOME/.local/bin/env$(RESET)"
	@exit 1
endif

$(VENV)/.setup-done: check-uv
	@echo "$(GREEN)>>> Creating venv with uv...$(RESET)"
	uv venv $(VENV) --python 3.12
	@touch $@

.PHONY: setup
setup: setup-base setup-lm-eval setup-simple-evals setup-ifbench setup-tau2 ## Full setup: venv + all benchmark deps
	@echo ""
	@echo "$(GREEN)>>> All setup complete!$(RESET)"
	@echo "  Activate: source $(VENV)/bin/activate"

.PHONY: setup-base
setup-base: $(VENV)/.setup-done ## Install base dependencies (vllm, transformers)
	@echo "$(GREEN)>>> Installing base dependencies...$(RESET)"
	$(ACTIVATE) && uv pip install "vllm==0.15.1"
	$(ACTIVATE) && uv pip install "compressed-tensors==0.13.0"
	$(ACTIVATE) && uv pip install "transformers==5.1.0"
	$(ACTIVATE) && uv pip install openai pandas jinja2 tqdm numpy requests

.PHONY: setup-lm-eval
setup-lm-eval: $(VENV)/.setup-done ## Install lm-evaluation-harness (for AIME25)
	@echo "$(GREEN)>>> Installing lm-evaluation-harness...$(RESET)"
	$(ACTIVATE) && uv pip install "lm-eval[api]"

.PHONY: setup-simple-evals
setup-simple-evals: $(VENV)/.setup-done ## Install simple-evals dependencies (for GPQA)
	@echo "$(GREEN)>>> Installing simple-evals dependencies...$(RESET)"
	$(ACTIVATE) && uv pip install openai pandas jinja2 tqdm numpy blobfile human-eval

.PHONY: setup-ifbench
setup-ifbench: $(VENV)/.setup-done ## Install IFBench dependencies
	@echo "$(GREEN)>>> Installing IFBench dependencies...$(RESET)"
	$(ACTIVATE) && uv pip install -r IFBench/requirements.txt
	$(ACTIVATE) && uv pip install httpx tqdm "pydantic>=2" pydantic-settings setuptools
	$(ACTIVATE) && $(PYTHON) -c "import nltk; nltk.download('punkt_tab', download_dir='IFBench/.nltk_data')" 2>/dev/null || true
	$(ACTIVATE) && $(PYTHON) -m spacy download en_core_web_sm 2>/dev/null || true

.PHONY: setup-tau2
setup-tau2: $(VENV)/.setup-done ## Install tau2-bench dependencies
	@echo "$(GREEN)>>> Installing tau2-bench...$(RESET)"
	cd tau2-bench && uv sync
	@if [ -n "$$OPENAI_API_KEY" ]; then \
		echo "OPENAI_API_KEY=$$OPENAI_API_KEY" > tau2-bench/.env; \
		echo "$(GREEN)>>> tau2-bench/.env created from OPENAI_API_KEY$(RESET)"; \
	elif [ ! -f tau2-bench/.env ]; then \
		echo "$(YELLOW)>>> WARNING: OPENAI_API_KEY not set and tau2-bench/.env not found$(RESET)"; \
		echo "$(YELLOW)    Tau2 user simulator (gpt-4.1) requires OPENAI_API_KEY$(RESET)"; \
		echo "$(YELLOW)    Run: OPENAI_API_KEY=sk-... make setup-tau2$(RESET)"; \
	fi

# =============================================================================
# vLLM Server
# =============================================================================

.PHONY: vllm-serve
vllm-serve: ## Start vLLM server
	@echo "$(GREEN)>>> Starting vLLM server...$(RESET)"
	@echo "  Model:    $(MODEL)"
	@echo "  TP size:  $(TP_SIZE)"
	@echo "  Port:     $(VLLM_PORT)"
	$(ACTIVATE) && vllm serve $(MODEL) \
		--reasoning-parser deepseek_v3 \
		--tensor-parallel-size $(TP_SIZE) \
		--enable-auto-tool-choice \
		--tool-call-parser hermes \
		--max-model-len $(MAX_MODEL_LEN) \
		--max-num-seqs $(MAX_NUM_SEQS) \
		--port $(VLLM_PORT)

.PHONY: vllm-check
vllm-check: ## Check if vLLM server is running
	@curl -sf http://$(VLLM_HOST):$(VLLM_PORT)/v1/models > /dev/null \
		&& echo "$(GREEN)vLLM server is running on port $(VLLM_PORT)$(RESET)" \
		|| (echo "$(YELLOW)vLLM server is NOT running on port $(VLLM_PORT)$(RESET)" && exit 1)

# =============================================================================
# Benchmarks
# =============================================================================

.PHONY: run-gpqa
run-gpqa: vllm-check ## Run GPQA benchmark
	@echo "$(GREEN)>>> Running GPQA...$(RESET)"
	$(ACTIVATE) && bash scripts/run_gpqa.sh

.PHONY: run-aime25
run-aime25: vllm-check ## Run AIME25 benchmark
	@echo "$(GREEN)>>> Running AIME25...$(RESET)"
	$(ACTIVATE) && bash scripts/run_aime25.sh

.PHONY: run-ifbench
run-ifbench: vllm-check ## Run IFBench benchmark
	@echo "$(GREEN)>>> Running IFBench...$(RESET)"
	$(ACTIVATE) && bash scripts/run_ifbench.sh

.PHONY: run-tau2
run-tau2: vllm-check ## Run Tau2 benchmark (airline, retail, telecom)
	@echo "$(GREEN)>>> Running Tau2...$(RESET)"
	bash scripts/run_tau2.sh

.PHONY: run-all
run-all: run-gpqa run-aime25 run-ifbench run-tau2 ## Run all benchmarks

.PHONY: run-all-except-tau2
run-all-except-tau2: run-gpqa run-aime25 run-ifbench ## Run all benchmarks except Tau2

# =============================================================================
# Smoke Tests (minimal runs to verify setup)
# =============================================================================

.PHONY: test-gpqa
test-gpqa: vllm-check ## Test GPQA (debug mode, 5 examples)
	@echo "$(CYAN)>>> [TEST] GPQA...$(RESET)"
	$(ACTIVATE) && bash tests/test_gpqa.sh

.PHONY: test-aime25
test-aime25: vllm-check ## Test AIME25 (1 run, 2 samples)
	@echo "$(CYAN)>>> [TEST] AIME25...$(RESET)"
	$(ACTIVATE) && bash tests/test_aime25.sh

.PHONY: test-ifbench
test-ifbench: vllm-check ## Test IFBench (1 run, 5 prompts)
	@echo "$(CYAN)>>> [TEST] IFBench...$(RESET)"
	$(ACTIVATE) && bash tests/test_ifbench.sh

.PHONY: test-tau2
test-tau2: vllm-check ## Test Tau2 (airline only, 1 trial, 2 tasks)
	@echo "$(CYAN)>>> [TEST] Tau2...$(RESET)"
	bash tests/test_tau2.sh

.PHONY: test-all
test-all: test-gpqa test-aime25 test-ifbench test-tau2 ## Run all smoke tests

# =============================================================================
# Utilities
# =============================================================================

.PHONY: report
report: ## Generate unified evaluation report (latest sessions)
	@$(ACTIVATE) && python scripts/report.py --latest

.PHONY: report-all
report-all: ## Generate report with all sessions
	@$(ACTIVATE) && python scripts/report.py

.PHONY: report-legacy
report-legacy: ## Generate report including legacy result locations
	@$(ACTIVATE) && python scripts/report.py --legacy

.PHONY: report-json
report-json: ## Generate report in JSON format (latest sessions)
	@$(ACTIVATE) && python scripts/report.py --latest --json

.PHONY: clean
clean: ## Remove venv (will NOT touch results or submodules)
	rm -rf $(VENV)
	@echo "$(GREEN)Cleaned .venv$(RESET)"

.PHONY: status
status: ## Show current configuration
	@echo ""
	@echo "  Configuration"
	@echo "  ============="
	@echo "  MODEL:         $(MODEL)"
	@echo "  VLLM_HOST:     $(VLLM_HOST)"
	@echo "  VLLM_PORT:     $(VLLM_PORT)"
	@echo "  TP_SIZE:       $(TP_SIZE)"
	@echo "  MAX_MODEL_LEN: $(MAX_MODEL_LEN)"
	@echo "  VENV:          $(VENV)"
	@echo ""
	@echo "  Submodules"
	@echo "  ----------"
	@git submodule status
	@echo ""
