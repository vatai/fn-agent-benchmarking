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
- Runtime = the kernel time printed by the benchmark itself; speedup is relative
  to the stripped serial version in `benchmarks/` (the agent's starting point).
- Output of the generated code is verified for correctness.
- Models: `models_claude.txt` (sonnet, opus, fable) and `models_opencode.txt`
  (RiVault models via the litellm provider that pass a tool-calling probe).
- Benchmarks: the `benchmarks/*` that compile with `Makefile.nvc` (`VERIFY=yes`),
  run, and pass their built-in self-check (`pass` in `results/baseline_report.md`).

## TODO (to be removed once the user has provided everything)

1. Repetitions per model.
2. Instructions: the exact prompt given to agents, and constraints (time/turn/
   token budget per run; allowed to change build flags/compiler; allowed to use
   GPU; etc.).
3. Slurm: partition, nodes/GPUs per job, wall-time limit, whether the agent
   itself runs inside the sbatch job (needs network + API keys on compute nodes)
   or only the benchmark runs do.
4. Credentials: API keys/auth for both tools available on compute nodes (env
   vars or config files).
5. fn-eval: what it expects as input and where it stores telemetry, so it can be
   collected.
6. Isolation: one git worktree/copy per agent run (default: yes), and whether
   runs may execute concurrently on the same node (timing interference).
7. Results format: e.g. CSV/JSON per run plus a summary table.

## Plan/Steps

1. [done] `prepare_benchmarks.sh`: strip HeCBench ktwork src2/*-omp into `benchmarks/`
   (pragmas removed, CRLF normalised, sibling-variant headers copied in, HeCBench clone deleted).
2. [done] `build_and_test_benchmarks.sh`: build all with nvc++ (nvhpc-nompi/26.5, cc100),
   run `make run`, report in `results/baseline_report.md`.
   Result (VERIFY=yes): 322 total, 284 compile, 58 pass self-check, 76 run w/o self-check,
   69 timeout (300 s), 43 crash, 38 self-check fail.
3. [done] Benchmark subset = the 58 with `pass` in the report; correctness = built-in self-check.
4. Agent launcher (sbatch, claude/opencode, fn-eval), result collection, report.
