#!/usr/bin/env bash
# Build every benchmark in benchmarks/ with nvc++ (Makefile.nvc), run each one
# via its "make run" target, and write a Markdown report classifying the result.
set -uo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
BENCH_DIR="${BENCH_DIR:-$HERE/benchmarks}"
OUT_DIR="${OUT_DIR:-$HERE/results/baseline}"
REPORT="${REPORT:-$HERE/results/baseline_report.md}"
MODULE="nvhpc-nompi/26.5"
SM="cc100"
BUILD_JOBS="${BUILD_JOBS:-32}"
RUN_JOBS="${RUN_JOBS:-8}"
RUN_TIMEOUT="${RUN_TIMEOUT:-300}"

load_compiler() {
  source /etc/profile.d/modules.sh 2>/dev/null || true
  module load "$MODULE"
}

list_benchmarks() {
  find "$BENCH_DIR" -mindepth 2 -maxdepth 2 -name Makefile.nvc -printf '%h\n' | sort
}

build_one() {
  local dir="$1" name log
  name=$(basename "$dir")
  log="$OUT_DIR/$name.build.log"
  make -C "$dir" -f Makefile.nvc clean >/dev/null 2>&1
  if make -C "$dir" -f Makefile.nvc SM="$SM" >"$log" 2>&1; then
    echo ok >"$OUT_DIR/$name.build"
  else
    echo fail >"$OUT_DIR/$name.build"
  fi
}

run_one() {
  local dir="$1" name log rc
  name=$(basename "$dir")
  [[ "$(cat "$OUT_DIR/$name.build")" == ok ]] || return 0
  log="$OUT_DIR/$name.run.log"
  timeout "$RUN_TIMEOUT" make -C "$dir" -f Makefile.nvc SM="$SM" run >"$log" 2>&1
  echo $? >"$OUT_DIR/$name.rc"
}

# Classification: PASS/FAIL strings are the HeCBench convention for self-checks.
classify_run() {
  local name="$1" rc log
  rc=$(cat "$OUT_DIR/$name.rc" 2>/dev/null || echo none)
  log="$OUT_DIR/$name.run.log"
  if [[ "$rc" == 124 ]]; then echo timeout
  elif grep -qE '\bFAIL|Mismatch|mismatch|FAILED|incorrect' "$log"; then echo fail
  elif [[ "$rc" != 0 ]]; then echo "crash($rc)"
  elif grep -qE '\bPASS\b|Test passed|passed' "$log"; then echo pass
  else echo unverified
  fi
}

write_report() {
  local name build run
  local n_total=0 n_built=0 n_pass=0 n_unverified=0
  {
    echo "# Baseline build/run report (OpenMP pragmas removed)"
    echo
    echo "Compiler: nvc++ ($MODULE), SM=$SM, run timeout ${RUN_TIMEOUT}s."
    echo
    echo "| benchmark | compiled | run result |"
    echo "|---|---|---|"
    for dir in $(list_benchmarks); do
      name=$(basename "$dir")
      build=$(cat "$OUT_DIR/$name.build")
      n_total=$((n_total + 1))
      if [[ "$build" == ok ]]; then
        n_built=$((n_built + 1)); run=$(classify_run "$name")
        [[ "$run" == pass ]] && n_pass=$((n_pass + 1))
        [[ "$run" == unverified ]] && n_unverified=$((n_unverified + 1))
      else
        run="-"
      fi
      echo "| $name | $build | $run |"
    done
    echo
    echo "## Summary"
    echo
    echo "- total: $n_total"
    echo "- compiled: $n_built"
    echo "- ran and self-check passed: $n_pass"
    echo "- ran without error but no self-check (unverified): $n_unverified"
    echo "- other (fail/crash/timeout): $((n_built - n_pass - n_unverified))"
  } >"$REPORT"
}

export -f build_one run_one
export OUT_DIR SM RUN_TIMEOUT

load_compiler
mkdir -p "$OUT_DIR"
list_benchmarks | xargs -P "$BUILD_JOBS" -I{} bash -c 'build_one "$@"' _ {}
list_benchmarks | xargs -P "$RUN_JOBS" -I{} bash -c 'run_one "$@"' _ {}
write_report
echo "Report written to $REPORT"
