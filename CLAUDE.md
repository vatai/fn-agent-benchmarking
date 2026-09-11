# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Harness for evaluating LLM coding agents (Claude Code, OpenCode with various
models) on optimising HPC benchmarks. The benchmarks come from HeCBench (branch
`ktwork`, `src2/*-omp`), stripped of all OpenMP pragmas so agents start from
serial code. See `PLAN.md` for goal, specification and current step; keep its
Plan/Steps section updated and never edit Goal/Specification.

## Layout

- `prepare_benchmarks.sh` — clones HeCBench, keeps only `*-omp` benchmarks
  (renamed without suffix), normalises CRLF, deletes `#pragma omp` lines
  (including backslash continuations and commented-out ones), copies headers
  each benchmark `#include`s from sibling variants (`../X-cuda` etc.) and
  rewrites Makefile include paths, then flattens into `benchmarks/` and deletes
  `.git` and the local `HeCBench/` clone. Falls back to the https upstream when
  no local clone exists.
- `build_and_test_benchmarks.sh` — builds every `benchmarks/*/Makefile.nvc`
  with nvc++, runs `make run`, writes `results/baseline_report.md`.
- `benchmarks/`, `HeCBench/`, `results/baseline/` are generated and gitignored;
  only `results/baseline_report.md` is committed.

## Commands

```bash
./prepare_benchmarks.sh [SRC_REPO] [DEST]          # regenerate benchmarks/ (deletes HeCBench/)
./build_and_test_benchmarks.sh                    # full build+run, ~1 h; env: BUILD_JOBS RUN_JOBS RUN_TIMEOUT
grep -E '\| (pass|unverified) \|' results/baseline_report.md | cut -d'|' -f2,4   # usable benchmarks

# single benchmark
module load nvhpc-nompi/26.5
make -C benchmarks/<name> -f Makefile.nvc SM=cc100 VERIFY=yes
make -C benchmarks/<name> -f Makefile.nvc SM=cc100 run
```

## Environment facts

- Compiler: `nvc++` from module `nvhpc-nompi/26.5`; GPUs are NVIDIA GB200
  (`SM=cc100`; Makefiles default to `cc70`). Node has 144 cores, 4 GPUs.
- Jobs on this HPC system go through `sbatch` with `--account $SBATCH_ACCOUNT`.
- The session's `SSH_AUTH_SOCK` can be stale; `~/.ssh/ssh_auth_sock` is the
  stable agent socket (needed for `git push`).
- Commit on a feature branch (currently `setup`), never directly on `main`.

## Benchmark caveats (relevant when judging correctness)

- Stripped kernels that used `omp_get_team_num()`/`omp_get_thread_num()` now
  see 0 for both, so only part of the output is computed; `omp_*` calls and
  `<omp.h>` were deliberately left in place.
- Serial float reductions can exceed the benchmarks' tolerances even when the
  algorithm is right (e.g. softmax-online kernel 1), so the built-in self-checks
  are not a sufficient correctness oracle for the serial baseline.
- Self-checks print `PASS`/`FAIL`; some are only compiled with `VERIFY=yes`.
- Some upstream benchmarks are broken independently of the stripping (missing
  external libs, wrong `reference.h` in bilateral's cuda sibling, softmax-online
  kernel 2 fails at block size 1024 on GB200).
