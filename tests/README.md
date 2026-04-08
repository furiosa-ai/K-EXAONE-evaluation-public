# Smoke Tests

벤치마크 본 실행 전에 **서버 연결, 의존성 설치, 스크립트 동작**을 빠르게 검증하기 위한 최소 단위 테스트.

## 실행

```bash
# 전제: vLLM 서버가 실행 중이어야 한다
make vllm-check

# 개별 실행
make test-gpqa
make test-aime25
make test-ifbench
make test-tau2

# 전체 실행
make test-all
```

## 테스트 상세

| 테스트 | 스크립트 | 내용 | 예상 소요 |
|--------|----------|------|----------|
| GPQA | `test_gpqa.sh` | `--debug` 모드 (5 examples, 1 repeat) | ~2분 |
| AIME25 | `test_aime25.sh` | `--limit 2` (2문제만 평가) | ~5분 |
| IFBench | `test_ifbench.sh` | 첫 5개 prompt만 추출하여 생성 + 평가 | ~3분 |
| Tau2 | `test_tau2.sh` | airline 도메인만, 1 trial, 2 tasks | ~3분 |

> 예상 소요 시간은 모델/하드웨어에 따라 다를 수 있다.

## 본 실행과의 차이

| | Smoke Test | 본 실행 |
|--|-----------|--------|
| **목적** | setup 검증 | 결과 리포트 생성 |
| **데이터** | 최소 샘플 (2~5개) | 전체 데이터셋 |
| **반복** | 1회 | N회 (mean/std 산출) |
| **결과 저장** | 별도 test 경로 | 공식 결과 경로 |

## 결과 저장 경로

테스트 결과는 본 실행과 섞이지 않도록 별도 경로에 저장된다:

| 테스트 | 결과 경로 |
|--------|----------|
| GPQA | `simple-evals/results/` (`_DEBUG` suffix) |
| AIME25 | `results/aime25_test/` |
| IFBench | `IFBench/eval/test/` |
| Tau2 | `tau2-bench/data/simulations/test_smoke/` |

## 설정 오버라이드

테스트도 `scripts/config.sh`의 공통 설정을 사용하므로 환경변수로 오버라이드 가능하다:

```bash
MODEL=my-org/my-model make test-gpqa
VLLM_PORT=8001 make test-all
```
