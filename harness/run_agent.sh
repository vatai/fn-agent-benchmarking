#!/usr/bin/env bash
#SBATCH --job-name=agent-bench
#SBATCH --partition=gpu
#SBATCH --gpus=1
#SBATCH --time=02:30:00
# One agent run: sbatch run_agent.sh TOOL MODEL BENCHMARK REP
#   TOOL  = claude | opencode      MODEL = as accepted by the tool's --model
# Measures the stripped baseline, lets the agent optimise an isolated copy for
# up to 2 h, re-verifies the result, computes the speedup, records fn-eval
# feedback and writes result.json.
set -uo pipefail

TOOL="$1"; MODEL="$2"; BENCH="$3"; REP="${4:-1}"
HERE="${SLURM_SUBMIT_DIR:-$(dirname "$(readlink -f "$0")")}"
HARNESS="$HERE/harness"
RUNS_DIR="${RUNS_DIR:-$HERE/../fn-agent-benchmarking-runs}"
MODULE="nvhpc-nompi/26.5"
SM="cc100"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-7200}"
BASELINE_TIMEOUT="${BASELINE_TIMEOUT:-900}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-900}"
CLAUDE_FEEDBACK="$HOME/.claude/plugins/cache/fn-agent-telemetry/fn-claude-telemetry/0.4.0/bin/agent-telemetry-feedback"
OPENCODE_FEEDBACK="$HOME/.local/share/fn-agent-telemetry/plugins/opencode/bin/agent-telemetry-feedback"

model_slug() { printf '%s' "$1" | tr '/:' '__'; }
now() { date +%s.%N; }
elapsed_since() { python3 -c "import sys,time; print(round(time.time()-float(sys.argv[1]),3))" "$1"; }
divide() { python3 -c "import sys; print(round(float(sys.argv[1])/float(sys.argv[2]),6))" "$1" "$2"; }

RUN_DIR="$RUNS_DIR/$TOOL/$(model_slug "$MODEL")/$BENCH/rep$REP"
WORK="$RUN_DIR/work"
BASELINE="$RUN_DIR/baseline"

setup_environment() {
  [[ -f "$HERE/.envrc" ]] && source "$HERE/.envrc"
  source /etc/profile.d/modules.sh 2>/dev/null || true
  module load "$MODULE"
  mkdir -p "$RUN_DIR"
}

fresh_copy() {
  rm -rf "$1"
  cp -r "$HERE/benchmarks/$BENCH" "$1"
  make -C "$1" -f Makefile.nvc clean >/dev/null 2>&1
}

# Builds and runs a copy; leaves build.log/run.log next to it. Returns run rc.
build_and_run() {
  local dir="$1" timeout_s="$2"
  make -C "$dir" -f Makefile.nvc SM="$SM" VERIFY=yes >"$dir.build.log" 2>&1 || return 100
  timeout "$timeout_s" make -C "$dir" -f Makefile.nvc SM="$SM" run >"$dir.run.log" 2>&1
}

# Kernel time printed by the program, else wall time of the run.
measured_seconds() {
  local dir="$1" wall="$2"
  python3 "$HARNESS/extract_time.py" <"$dir.run.log" 2>/dev/null || echo "$wall"
}

self_check_passed() {
  local log="$1"
  ! grep -qE '\bFAIL|Mismatch|mismatch|FAILED|incorrect' "$log" \
    && grep -qE '\bPASS\b|Test passed|passed' "$log"
}

measure_baseline() {
  fresh_copy "$BASELINE"
  local start rc wall
  start=$(now)
  build_and_run "$BASELINE" "$BASELINE_TIMEOUT"; rc=$?
  wall=$(elapsed_since "$start")
  BASELINE_RC=$rc
  BASELINE_SECONDS=$(measured_seconds "$BASELINE" "$wall")
}

set_agent_command() {
  local prompt="$1"
  case "$TOOL" in
    claude)   AGENT_CMD=(claude -p "$prompt" --model "$MODEL" --dangerously-skip-permissions
                         --output-format json) ;;
    opencode) AGENT_CMD=(opencode run --model "$MODEL" --format json --auto "$prompt") ;;
    *) echo "unknown tool $TOOL" >&2; exit 2 ;;
  esac
}

run_agent() {
  fresh_copy "$WORK"
  local start
  set_agent_command "$(cat "${PROMPT_FILE:-$HARNESS/agent_prompt.md}")"
  start=$(now)
  (cd "$WORK" && timeout "$AGENT_TIMEOUT" "${AGENT_CMD[@]}" \
      >"$RUN_DIR/agent_output.json" 2>"$RUN_DIR/agent_stderr.log")
  AGENT_RC=$?
  AGENT_WALL=$(elapsed_since "$start")
}

verify_result() {
  make -C "$WORK" -f Makefile.nvc clean >/dev/null 2>&1
  local start rc wall
  start=$(now)
  build_and_run "$WORK" "$VERIFY_TIMEOUT"; rc=$?
  wall=$(elapsed_since "$start")
  VERIFY_RC=$rc
  if [[ $rc -eq 0 ]] && self_check_passed "$WORK.run.log"; then
    CORRECT=true; AGENT_SECONDS=$(measured_seconds "$WORK" "$wall")
    SPEEDUP=$(divide "$BASELINE_SECONDS" "$AGENT_SECONDS")
  else
    CORRECT=false; AGENT_SECONDS=null; SPEEDUP=0
  fi
}

# 1 = incorrect or slower, 3 = ~1x, 5 = >=100x; log-linear in between.
satisfaction_from_speedup() {
  python3 -c "
import math,sys
s=float(sys.argv[1]); correct=sys.argv[2]=='true'
if not correct or s<0.9: print(1)
else: print(max(1,min(5,round(3+2*math.log10(max(s,1))/2))))" "$SPEEDUP" "$CORRECT"
}

record_feedback() {
  local cli satisfaction
  case "$TOOL" in claude) cli="$CLAUDE_FEEDBACK" ;; *) cli="$OPENCODE_FEEDBACK" ;; esac
  satisfaction=$(satisfaction_from_speedup)
  (cd "$WORK" && "$cli" --subject "Optimise HeCBench $BENCH (serial baseline) on GB200" \
      --fom speedup --unit x --value "$SPEEDUP" --satisfaction "$satisfaction" \
      --comment "correct=$CORRECT tool=$TOOL model=$MODEL rep=$REP") \
    >"$RUN_DIR/feedback.log" 2>&1
  FEEDBACK_LINE=$(tail -1 "$RUN_DIR/feedback.log")
}

write_result() {
  local usage
  usage=$(python3 "$HARNESS/agent_usage.py" "$TOOL" "$RUN_DIR/agent_output.json")
  USAGE_JSON="$usage" NODE="$(hostname)" python3 - "$RUN_DIR/result.json" <<'PY'
import json, os, sys
env = os.environ
def num(name):
    value = env.get(name, "")
    return None if value in ("", "null") else float(value)
result = {
  "tool": env["TOOL"], "model": env["MODEL"], "benchmark": env["BENCH"], "rep": int(env["REP"]),
  "slurm_job_id": env.get("SLURM_JOB_ID", ""), "node": env["NODE"],
  "baseline": {"rc": int(env["BASELINE_RC"]), "seconds": num("BASELINE_SECONDS")},
  "agent": {"rc": int(env["AGENT_RC"]), "wall_seconds": num("AGENT_WALL"), "usage": json.loads(env["USAGE_JSON"])},
  "verify": {"rc": int(env["VERIFY_RC"]), "correct": env["CORRECT"] == "true", "seconds": num("AGENT_SECONDS")},
  "speedup": num("SPEEDUP"),
  "feedback": env.get("FEEDBACK_LINE", "").strip(),
}
json.dump(result, open(sys.argv[1], "w"), indent=2)
print(json.dumps(result))
PY
}

export TOOL MODEL BENCH REP
export_measurements() {
  export BASELINE_RC BASELINE_SECONDS AGENT_RC AGENT_WALL VERIFY_RC CORRECT AGENT_SECONDS SPEEDUP FEEDBACK_LINE
}

setup_environment
measure_baseline
run_agent
verify_result
record_feedback
export_measurements
write_result
