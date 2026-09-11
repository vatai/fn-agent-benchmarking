#!/usr/bin/env bash
# Submit every (tool, model, benchmark, repetition) as Slurm job-array tasks.
# Reproduces the whole experiment: models from models_*.txt, benchmarks = those
# marked "pass" in results/baseline_report.md, REPS repetitions each. One array
# per tool (chunked to MaxArraySize) with a concurrency cap, since the agents
# share API rate limits.
#   env: REPS (3), TOOLS ("claude opencode"), BENCHMARKS (override list),
#        MAX_CONCURRENT_claude (4), MAX_CONCURRENT_opencode (64),
#        DRY_RUN=1 (print sbatch commands only), RUNS_DIR (see run_agent.sh)
set -euo pipefail

HERE="$(dirname "$(readlink -f "$(dirname "$0")")")"
REPS="${REPS:-3}"
TOOLS="${TOOLS:-claude opencode}"
MAX_CONCURRENT_claude="${MAX_CONCURRENT_claude:-4}"
MAX_CONCURRENT_opencode="${MAX_CONCURRENT_opencode:-64}"
ARRAY_CHUNK=2000
: "${SBATCH_ACCOUNT:?set SBATCH_ACCOUNT (e.g. via .envrc)}"

models_for() {
  grep -vE '^\s*(#|$)' "$HERE/models_$1.txt"
}

passing_benchmarks() {
  grep -E '\| pass \|' "$HERE/results/baseline_report.md" | cut -d'|' -f2 | tr -d ' '
}

write_manifest() {
  local tool="$1" manifest="$2" model bench rep
  : >"$manifest"
  for model in $(models_for "$tool"); do
    for bench in ${BENCHMARKS:-$(passing_benchmarks)}; do
      for rep in $(seq 1 "$REPS"); do echo "$tool $model $bench $rep" >>"$manifest"; done
    done
  done
}

# Array indices must stay below MaxArraySize, so each chunk file is 0-based.
# Chunks of one tool run concurrently, each capped separately.
submit_chunk() {
  local tool="$1" chunk="$2" cap n
  cap=$(eval echo "\$MAX_CONCURRENT_$tool")
  n=$(wc -l <"$chunk")
  local cmd=(sbatch --parsable --account="$SBATCH_ACCOUNT" --chdir="$HERE"
             --job-name="$tool-bench" --array="0-$((n - 1))%$cap"
             --output="$HERE/results/slurm/%x-%A_%a.out"
             "$HERE/harness/run_array.sh" "$chunk")
  if [[ -n "${DRY_RUN:-}" ]]; then echo "${cmd[*]}"; else echo "$("${cmd[@]}") $tool $chunk ($n tasks)"; fi
}

submit_tool() {
  local tool="$1" manifest="$HERE/results/slurm/manifest_$tool.txt" chunk
  write_manifest "$tool" "$manifest"
  rm -f "$manifest".chunk*
  split -l "$ARRAY_CHUNK" -d "$manifest" "$manifest.chunk"
  for chunk in "$manifest".chunk*; do submit_chunk "$tool" "$chunk"; done
}

main() {
  mkdir -p "$HERE/results/slurm"
  for tool in $TOOLS; do submit_tool "$tool"; done | tee -a "$HERE/results/slurm/submitted_arrays.txt"
}

main
