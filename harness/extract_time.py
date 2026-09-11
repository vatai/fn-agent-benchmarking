#!/usr/bin/env python3
"""Sum every kernel/execution time a benchmark prints, in seconds.

HeCBench programs print lines such as
  "Average kernel execution time: 202.06 (ms)" or "elapsed time: 120.28 sec".
The same program prints the same set of lines before and after optimisation,
so their sum is a consistent per-benchmark runtime figure.
"""
import re
import sys

UNIT_TO_SECONDS = {"s": 1.0, "sec": 1.0, "seconds": 1.0, "ms": 1e-3,
                   "us": 1e-6, "µs": 1e-6, "usec": 1e-6, "ns": 1e-9}
NUMBER = r"([0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)"
UNIT = r"(s|sec|seconds|ms|us|µs|usec|ns)"
# "... time: 202.06 (ms)"   and   "# Total Time (s) : 5.03605"
VALUE_THEN_UNIT = re.compile(r"time[^\n]*?" + NUMBER + r"\s*\(?\s*" + UNIT + r"\b\)?", re.I)
UNIT_THEN_VALUE = re.compile(r"time\s*\(" + UNIT + r"\)\s*:?\s*" + NUMBER, re.I)


def times_in_seconds(text):
    found = [(v, u) for v, u in VALUE_THEN_UNIT.findall(text)]
    found += [(v, u) for u, v in UNIT_THEN_VALUE.findall(text)]
    return [float(v) * UNIT_TO_SECONDS[u.lower()] for v, u in found]


def main():
    text = sys.stdin.read()
    found = times_in_seconds(text)
    if not found:
        sys.exit(1)
    print(f"{sum(found):.9g}")


if __name__ == "__main__":
    main()
