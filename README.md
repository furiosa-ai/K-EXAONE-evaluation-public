# K-EXAONE Evaluation

K-EXAONE 모델의 벤치마크 평가를 위한 통합 레포지토리.
각 벤치마크를 N회 반복 수행하여 mean/std 리포트를 생성한다.

## Benchmarks

| Benchmark | 평가 대상 | 반복 횟수 (기본) | 평가 도구 |
|-----------|----------|:-----------:|----------|
| **GPQA** | Graduate-level Q&A | 8 | [simple-evals](simple-evals/) |
| **AIME 2025** | 수학 문제풀이 | 35 | [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) |
| **IFBench** | Instruction Following | 5 | [IFBench](IFBench/) |
| **Tau2** | Tool-Agent-User 상호작용 | 5 (x3 domains) | [tau2-bench](tau2-bench/) |

## 구조

```
K-EXAONE-evaluation/
├── Makefile                  # setup / 서버 / 벤치마크 실행
├── evaluation_reference.md   # 벤치마크별 커맨드 레퍼런스
├── scripts/
│   ├── config.sh             # 공통 설정 (MODEL, BASE_URL, TEMPERATURE 등)
│   ├── run_gpqa.sh           # GPQA N회 반복
│   ├── run_aime25.sh         # AIME25 N회 반복
│   ├── run_ifbench.sh        # IFBench N회 반복
│   └── run_tau2.sh           # Tau2 3개 도메인 x N회 반복
├── tests/                    # Smoke tests (setup 검증용)
│   ├── README.md
│   ├── test_gpqa.sh
│   ├── test_aime25.sh
│   ├── test_ifbench.sh
│   └── test_tau2.sh
├── simple-evals/             # submodule - GPQA 평가
├── IFBench/                  # submodule - IFBench 평가
└── tau2-bench/               # submodule - Tau2 평가
```

## Quick Start

### 1. Setup

[uv](https://docs.astral.sh/uv/)를 사용하여 환경을 구성한다.

**API Key 설정:**

GPQA grading(gpt-4.1)과 Tau2 user simulator(gpt-4.1)에 OpenAI API key가 필요하다.

```bash
# 셸 환경변수로 설정 (.bashrc, .zshrc 등에 추가)
export OPENAI_API_KEY=sk-your-key-here
```

**의존성 설치:**

```bash
# 전체 setup (venv 생성 + 모든 벤치마크 의존성 설치)
make setup

# 또는 개별 setup
make setup-base          # vllm, transformers, compressed-tensors
make setup-lm-eval       # lm-evaluation-harness (AIME25)
make setup-simple-evals  # simple-evals 의존성 (GPQA)
make setup-ifbench       # IFBench 의존성
make setup-tau2          # tau2-bench 의존성
```

> Tau2는 자체 `tau2-bench/.env` 파일이 필요하다.
> `make setup-tau2` 실행 시 `OPENAI_API_KEY` 환경변수가 설정되어 있으면 자동으로 생성된다.

주요 의존성 버전:
- `vllm==0.15.1`
- `compressed-tensors==0.13.0`
- `transformers==5.1.0`

### 2. vLLM 서버 시작

모든 벤치마크는 vLLM 서버에 요청을 보내는 구조이다.
서버를 먼저 띄운 뒤, 별도 터미널에서 벤치마크를 실행한다.

```bash
# 터미널 1: vLLM 서버 시작 (foreground로 실행됨)
make vllm-serve

# 또는 직접 실행
source .venv/bin/activate
vllm serve LGAI-EXAONE/K-EXAONE-236B-A23B-FP8 \
    --reasoning-parser deepseek_v3 \
    --tensor-parallel-size 8 \
    --enable-auto-tool-choice \
    --tool-call-parser hermes \
    --max-model-len 131072 \
    --max-num-seqs 8
```

```bash
# 터미널 2: 서버 상태 확인
make vllm-check
```

서버 설정 오버라이드:
```bash
make vllm-serve MODEL=my-org/my-model TP_SIZE=4 VLLM_PORT=8001
```

### 3. 벤치마크 실행

```bash
# 터미널 2: 개별 벤치마크 실행
make run-gpqa
make run-aime25
make run-ifbench
make run-tau2

# 전체 순차 실행
make run-all
```

반복 횟수 등 파라미터 오버라이드:
```bash
NUM_RUNS=3 make run-gpqa          # GPQA 3회만
NUM_RUNS=10 make run-aime25       # AIME25 10회
NUM_RUNS=2 make run-tau2          # Tau2 도메인별 2회
MODEL=my-org/my-model make run-gpqa
```

## 설정

모든 스크립트는 `scripts/config.sh`의 공통 설정을 사용하며, 환경변수로 오버라이드 가능하다.

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `MODEL` | `LGAI-EXAONE/K-EXAONE-236B-A23B-FP8` | 평가 대상 모델 |
| `VLLM_HOST` | `localhost` | vLLM 서버 호스트 |
| `VLLM_PORT` | `8000` | vLLM 서버 포트 |
| `TEMPERATURE` | `1.0` | 샘플링 temperature |
| `TOP_P` | `0.95` | Top-p sampling |
| `NUM_RUNS` | 벤치마크별 상이 | 반복 실행 횟수 |

### 벤치마크별 추가 설정

**Tau2** 전용:
| 변수 | 기본값 | 설명 |
|------|--------|------|
| `NUM_TRIALS` | `4` | tau2 `--num-trials` (태스크당 시행 횟수) |
| `MAX_CONCURRENCY` | `50` | 동시 실행 수 |
| `USER_LLM` | `gpt-4.1` | 유저 시뮬레이터 모델 |
| `DOMAINS` | `airline retail telecom` | 평가 도메인 |

## 결과

각 벤치마크의 결과는 다음 경로에 저장된다:

| Benchmark | 결과 경로 |
|-----------|----------|
| GPQA | `simple-evals/results/` |
| AIME25 | `results/aime25/` |
| IFBench | `IFBench/eval/run{N}/` |
| Tau2 | `tau2-bench/data/simulations/` |

모든 스크립트는 실행 완료 후 자동으로 mean/std 요약을 출력한다.

### 통합 리포트

전체 벤치마크 결과를 한눈에 확인할 수 있다.

```bash
make report          # 터미널에 요약 출력
make report-json     # JSON 포맷으로 출력
```

출력 예시:
```
  Summary
  ============================================================
  Benchmark              N       Mean        Std
  --------------------------------------------------
  GPQA                   8     0.7200     0.0312
  AIME25                35     0.8200     0.0150
  IFBench (loose)        5    72.30%      1.20%
  Tau2 (airline)         5     0.7420     0.0201
  Tau2 (retail)          5     0.8250     0.0087
  Tau2 (telecom)         5     0.7654     0.0180
```

## Smoke Tests

본 실행 전에 서버 연결, 의존성, 스크립트 동작을 빠르게 검증할 수 있다.
자세한 내용은 [tests/README.md](tests/README.md) 참고.

```bash
make test-gpqa      # GPQA: debug mode, 5 examples
make test-aime25    # AIME25: 2 samples
make test-ifbench   # IFBench: 5 prompts
make test-tau2      # Tau2: airline, 1 trial, 2 tasks
make test-all       # 전체 smoke test
```

## Makefile 타겟 목록

```bash
make help    # 전체 타겟 목록 확인
make status  # 현재 설정 및 submodule 상태 확인
make clean   # .venv 삭제 (결과 파일은 보존)
```
