# Tau2 Benchmark Evaluation Scripts

## Scripts

### `run_eval.sh`
단일 run 실행. 환경변수로 제어.

| 환경변수 | 기본값 | 설명 |
|----------|--------|------|
| `EVAL_RUN_ID` | 1 | Run 번호 |
| `EVAL_TIMESTAMP` | 현재시각 | 출력 파일 timestamp |

- 기존 결과 파일이 있으면 `yes y |`로 자동 resume
- domain 3개(airline, retail, telecom) 순차 실행

### `run_eval_5x.sh`
5회 반복 실행 + 자동 retry + 결과 집계.

```bash
# 새로 시작
bash run_eval_5x.sh

# 기존 run resume (불완전한 run만 자동 재시도)
bash run_eval_5x.sh --resume 20260403_145051

# 특정 run만 resume
bash run_eval_5x.sh --resume 20260403_145051 --runs 2,4

# retry 횟수 조정 (기본 5회)
bash run_eval_5x.sh --resume 20260403_145051 --max-retries 10
```

동작 흐름:
1. 5개 run 실행 (또는 `--runs`로 지정한 run만)
2. 완료 여부 체크 (각 domain의 simulation 수 == tasks x num_trials)
3. 불완전한 run만 자동 재실행 (tau2 내장 resume 활용)
4. 모두 완료되거나 max-retries 도달 시 결과 집계

### `aggregate_results.py`
결과 집계. 3가지 지표를 domain별로 출력.

```bash
python aggregate_results.py --timestamp 20260403_145051 --num-runs 5
```

| 지표 | 설명 |
|------|------|
| `avg_reward` | 전체 simulation reward의 단순 평균 |
| `pass^1` | 태스크별 성공률(성공수/trial수)의 평균 |
| `any_success` | 1회라도 성공한 태스크의 비율 (best-case) |
