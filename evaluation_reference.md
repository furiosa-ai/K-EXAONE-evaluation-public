local server 명령어

vllm serve furiosa-ai/K-EXAONE-236B-A23B-NVFP4A16-GPTQ-think-token-fix8     --reasoning-parser deepseek_v3     --tensor-parallel-size 8     --enable-auto-tool-choice     --tool-call-parser hermes     --max-model-len 131072     --max-num-seqs 8

GPQA
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


l   AIME 2025

evaluation repository: lm-evaluation-harness (https://github.com/EleutherAI/lm-evaluation-harness)

주의사항: 없음

python -m lm_eval --model local-chat-completions \
--model_args "model={your_model_name},base_url={your_server},tokenized_requests=False,tokenizer_backend=None,max_length=131072" \
--tasks aime25 \
--batch_size 1 \
--num_fewshot 0 \
--gen_kwargs '{"temperature":1.0,"top_p":0.95,"max_gen_toks":131072,"n":1,"chat_template_kwargs":{"enable_thinking":true}}' \
--write_out \
--log_samples \
--output_path {your_output_path} \
--apply_chat_template

l   IFBench

evaluation repository: IFBench official repository (https://github.com/allenai/IFBench)

주의사항: generate_responses.py 파일과 config.py에 “top-p”, “enable-thinking” arguments 추가해야 함

#!/usr/bin/env bash
cd "$(dirname "$0")" && \
mkdir -p eval && \
NLTK_DATA="$PWD/.nltk_data" \
python generate_responses.py \
--api-base {your_server} \
--model {your_model_name} \
--input-file data/IFBench_test.jsonl \
--output-file data/{your_outputs} \
--temperature 1.0 \
--top-p 0.95 \
--max-tokens 65536 \
--workers 48 \
--enable-thinking && \
NLTK_DATA="$PWD/.nltk_data" \
python -m run_eval \
--input_data=data/IFBench_test.jsonl \
--input_response_data=data/{your_outputs} \
--output_dir=eval

l   Tau2

evaluation repository: Tau2 official repository (https://github.com/sierra-research/tau2-bench)

주의사항: interleaved thinking 구현

참고: https://github.com/sierra-research/tau2-bench/pull/93/changes

tau2 run \
--domain {airline,retail,telecom} \
--save-to {your_outputs} \
--agent-llm {your_model_name} \
--agent-llm-args "{\"temperature\":1.0,\"top_p\":0.95,\"api_base\":\"{your_server}\",\"extra_body\":{\"chat_template_kwargs\":{\"enable_thinking\":true}}}" \
--user-llm gpt-4.1 \
--num-trials 4 \
--max-concurrency 50