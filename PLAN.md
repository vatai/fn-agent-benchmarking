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
- Slurm: partition `gpu`, 1 GPU per job, account from `$SBATCH_ACCOUNT`
  (valid accounts: rkp00042, rkp00033; note `.envrc` currently has a typo
  `rkp000042`). The agent itself runs inside the job: compute nodes reach the
  Anthropic API and RiVault; claude uses the claude.ai login in `~/.claude`,
  opencode needs `RIVAULT_API_KEY` (from `.envrc`). Verified 2026-09-11.
- fn-eval: figure of merit `speedup` (unit x), value = measured speedup,
  satisfaction derived from it (1 = slower/incorrect, 3 = ~1x, 5 = >=100x).
- Results: one JSON file per run plus summary tables in Markdown files.
- Isolation: each agent run gets its own copy of the benchmark directory.
- Concurrency: runs are independent Slurm jobs and may execute concurrently.
- Repetitions: 3 independent runs per (model, benchmark) pair.
- Benchmarks: the `benchmarks/*` that compile with `Makefile.nvc` (`VERIFY=yes`),
  run, and pass their built-in self-check (`pass` in `results/baseline_report.md`).

## TODO (to be removed once the user has provided everything)

1. Instructions: confirm/edit the proposed agent prompt and constraints below.

## Proposed agent instructions (to confirm)

Prompt given to every agent (same for claude and opencode), run inside the
isolated copy of one benchmark directory:

> You are in the directory of a small HPC benchmark written in serial C/C++.
> Your task is to make it run as fast as possible on this machine (NVIDIA GB200
> GPU, 144-core Grace CPU; `nvc++` from `module load nvhpc-nompi/26.5` is the
> compiler used by `Makefile.nvc`). You may use OpenMP (CPU or target offload),
> OpenACC, CUDA, or any other approach the compiler supports, and you may change
> `Makefile.nvc` (flags, sources) but not `main`'s command-line interface or the
> problem sizes in the `run` target.
> Build with `make -f Makefile.nvc SM=cc100 VERIFY=yes`, run with
> `make -f Makefile.nvc SM=cc100 run`. The program prints its own kernel time
> and a PASS/FAIL self-check; the result only counts if the self-check passes.
> Iterate: measure, optimise, re-verify. Do not modify the verification code or
> the reference implementation. When done, leave the fastest correct version in
> place and stop.

Constraints: one benchmark per run; wall-time limit 1 h per job; no turn/token
cap beyond that (claude: `--max-turns` unset; opencode default); agent gets
`--dangerously-skip-permissions` / equivalent since it runs isolated in a Slurm
job. The harness independently rebuilds and runs the result, checks PASS,
extracts the printed kernel time and computes speedup vs the stripped baseline.

## Plan/Steps

1. [done] `prepare_benchmarks.sh`: strip HeCBench ktwork src2/*-omp into `benchmarks/`
   (pragmas removed, CRLF normalised, sibling-variant headers copied in, HeCBench clone deleted).
2. [done] `build_and_test_benchmarks.sh`: build all with nvc++ (nvhpc-nompi/26.5, cc100),
   run `make run`, report in `results/baseline_report.md`.
   Result (VERIFY=yes): 322 total, 284 compile, 58 pass self-check, 76 run w/o self-check,
   69 timeout (300 s), 43 crash, 38 self-check fail.
3. [done] Benchmark subset = the 58 with `pass` in the report; correctness = built-in self-check.
4. Agent launcher (sbatch, claude/opencode, fn-eval), result collection, report.
