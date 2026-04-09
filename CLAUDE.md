# CLAUDE.md

## Scripts & README Sync

`scripts/` 디렉토리의 스크립트를 수정할 때는 반드시 `README.md`도 함께 확인하고 동기화할 것.

체크리스트:
- 환경변수 추가/삭제/기본값 변경 → README 설정 테이블 업데이트
- 벤치마크 추가/삭제 → README Benchmarks 테이블, 구조, 결과 경로 업데이트
- vLLM 서버 옵션 변경 → README Quick Start 섹션 업데이트
- Makefile 타겟 변경 → README 실행 예시 업데이트

대상 파일:
- `README.md`
- `scripts/config.sh`
- `scripts/run_gpqa.sh`
- `scripts/run_aime25.sh`
- `scripts/run_ifbench.sh`
- `scripts/run_tau2.sh`
- `Makefile`
