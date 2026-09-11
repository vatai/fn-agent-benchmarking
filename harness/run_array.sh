#!/usr/bin/env bash
#SBATCH --job-name=agent-bench
#SBATCH --partition=gpu
#SBATCH --gpus=1
#SBATCH --time=02:30:00
# Job-array wrapper: line $SLURM_ARRAY_TASK_ID (0-based) of the manifest given
# as $1 holds "TOOL MODEL BENCH REP"; runs it through run_agent.sh.
set -euo pipefail
MANIFEST="$1"
read -r TOOL MODEL BENCH REP < <(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$MANIFEST")
exec "${SLURM_SUBMIT_DIR:-$(dirname "$(dirname "$MANIFEST")")}/harness/run_agent.sh" "$TOOL" "$MODEL" "$BENCH" "$REP"
