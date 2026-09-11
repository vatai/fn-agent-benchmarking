# PLAN

## Goal

Evaluate how well various LLM coding agents (Claude Code and OpenCode, with
different models) can optimise a set of benchmarks on this HPC hardware.

## Specification

- Agents are launched via Slurm (`sbatch`), `--account` taken from `$SBATCH_ACCOUNT`.
- Spawning is reproducible: a script does a best effort to recreate the results.
- Both `claude` and `opencode` have the `fn-eval` plugin installed; it must be
  invoked when an agent finishes its evaluation.
- Record per run: token usage, wall time, speedup.
- Output of the generated code is verified for correctness.
- Benchmark details to be provided by the user.

## TODO (to be removed once the user has provided everything)

1. Benchmark: source, build command, run command, correctness check (reference
   output / tolerance), timing method, baseline to compute speedup against.
2. Model list: which models for claude (`--model`) and opencode
   (`provider/model`), and how many repetitions per model.
3. Instructions: the exact prompt given to agents, and constraints (time/turn/
   token budget per run; allowed to change build flags/compiler; allowed to use
   GPU; etc.).
4. Slurm: partition, nodes/GPUs per job, wall-time limit, whether the agent
   itself runs inside the sbatch job (needs network + API keys on compute nodes)
   or only the benchmark runs do.
5. Credentials: API keys/auth for both tools available on compute nodes (env
   vars or config files).
6. fn-eval: what it expects as input and where it stores telemetry, so it can be
   collected.
7. Isolation: one git worktree/copy per agent run (default: yes), and whether
   runs may execute concurrently on the same node (timing interference).
8. Results format: e.g. CSV/JSON per run plus a summary table.

## Plan/Steps

1. [done] `prepare_benchmarks.sh`: strip HeCBench ktwork src2/*-omp into `benchmarks/`
   (pragmas removed, CRLF normalised, sibling-variant headers copied in, HeCBench clone deleted).
2. [done] `build_and_test_benchmarks.sh`: build all with nvc++ (nvhpc-nompi/26.5, cc100),
   run `make run`, report in `results/baseline_report.md`.
   Result (VERIFY=yes): 322 total, 284 compile, 58 pass self-check, 76 run w/o self-check,
   69 timeout (300 s), 43 crash, 38 self-check fail.
3. [next] Decide benchmark subset + correctness oracle (original omp output vs stripped).
4. Agent launcher (sbatch, claude/opencode, fn-eval), result collection, report.
