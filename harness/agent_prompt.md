You are in the directory of a small HPC benchmark written in serial C/C++.
Your task is to make it run as fast as possible on this machine (NVIDIA GB200
GPU, 144-core Grace CPU; `nvc++` from `module load nvhpc-nompi/26.5` is the
compiler used by `Makefile.nvc`). You may use OpenMP (CPU or target offload),
OpenACC, CUDA, or any other approach the compiler supports, and you may change
`Makefile.nvc` (flags, sources) but not `main`'s command-line interface or the
problem sizes in the `run` target.

Build with `make -f Makefile.nvc SM=cc100 VERIFY=yes`, run with
`make -f Makefile.nvc SM=cc100 run`. The program prints its own kernel time and
a PASS/FAIL self-check; the result only counts if the self-check passes.
Iterate: measure, optimise, re-verify. Do not modify the verification code or
the reference implementation.

You have a time limit of 2 hours in total. When done, leave the fastest
correct version in place and stop.
