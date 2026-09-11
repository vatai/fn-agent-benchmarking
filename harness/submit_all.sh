#!/usr/bin/env bash
# Submit every (tool, model, benchmark, repetition) as its own Slurm job.
# Reproduces the whole experiment: models from models_*.txt, benchmarks = those
# marked "pass" in results/baseline_report.md, REPS repetitions each.
#   env: REPS (3), TOOLS ("claude opencode"), BENCHMARKS (override list),
#        DRY_RUN=1 (print sbatch commands only), RUNS_DIR (see run_agent.sh)
set -euo pipefail

HERE="$(dirname "$(readlink -f "$(dirname "$0")")")"
REPS="${REPS:-3}"
TOOLS="${TOOLS:-claude opencode}"
: "${SBATCH_ACCOUNT:?set SBATCH_ACCOUNT (e.g. via .envrc)}"

models_for() {
  grep -vE '^\s*(#|$)' "$HERE/models_$1.txt"
}

passing_benchmarks() {
  grep -E '\| pass \|' "$HERE/results/baseline_report.md" | cut -d'|' -f2 | tr -d ' '
}

submit() {
  local tool="$1" model="$2" bench="$3" rep="$4"
  local cmd=(sbatch --parsable --account="$SBATCH_ACCOUNT" --chdir="$HERE"
             --job-name="$tool-$bench-r$rep" --output="$HERE/results/slurm/%x-%j.out"
             "$HERE/harness/run_agent.sh" "$tool" "$model" "$bench" "$rep")
  if [[ -n "${DRY_RUN:-}" ]]; then echo "${cmd[*]}"; else
    echo "$(${cmd[@]}) $tool $model $bench $rep"
  fi
}

main() {
  local benchmarks tool model bench rep
  mkdir -p "$HERE/results/slurm"
  benchmarks="${BENCHMARKS:-$(passing_benchmarks)}"
  for tool in $TOOLS; do
    for model in $(models_for "$tool"); do
      for bench in $benchmarks; do
        for rep in $(seq 1 "$REPS"); do submit "$tool" "$model" "$bench" "$rep"; done
      done
    done
  done | tee -a "$HERE/results/submitted_jobs.txt"
}

main
