#!/usr/bin/env python3
"""Aggregate every result.json under RUNS_DIR into results/runs.json and
results/summary.md (per model x benchmark: best/mean speedup, correctness,
tokens, wall time)."""
import json
import os
import statistics
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
RUNS_DIR = Path(os.environ.get("RUNS_DIR", HERE.parent / "fn-agent-benchmarking-runs"))


def load_runs():
    return [json.load(open(p)) for p in sorted(RUNS_DIR.glob("*/*/*/rep*/result.json"))]


def group_by_model_benchmark(runs):
    groups = defaultdict(list)
    for run in runs:
        groups[(run["tool"], run["model"], run["benchmark"])].append(run)
    return groups


def mean_or_none(values):
    values = [v for v in values if v is not None]
    return round(statistics.mean(values), 3) if values else None


def summarise(group):
    correct = [r for r in group if r["verify"]["correct"]]
    speedups = [r["speedup"] for r in correct]
    return {
        "runs": len(group),
        "correct": len(correct),
        "best_speedup": round(max(speedups), 3) if speedups else None,
        "mean_speedup": mean_or_none(speedups),
        "mean_wall_s": mean_or_none([r["agent"]["wall_seconds"] for r in group]),
        "mean_input_tokens": mean_or_none([r["agent"]["usage"].get("input_tokens") for r in group]),
        "mean_output_tokens": mean_or_none([r["agent"]["usage"].get("output_tokens") for r in group]),
    }


def fmt(value):
    return "-" if value is None else (f"{value:.3g}" if isinstance(value, float) else str(value))


def benchmark_table(groups):
    lines = ["| tool | model | benchmark | runs | correct | best speedup | mean speedup | mean wall (s) | mean in tok | mean out tok |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for (tool, model, bench), group in sorted(groups.items()):
        s = summarise(group)
        lines.append(f"| {tool} | {model} | {bench} | {s['runs']} | {s['correct']} | {fmt(s['best_speedup'])} | "
                     f"{fmt(s['mean_speedup'])} | {fmt(s['mean_wall_s'])} | {fmt(s['mean_input_tokens'])} | {fmt(s['mean_output_tokens'])} |")
    return "\n".join(lines)


def model_table(runs):
    per_model = defaultdict(list)
    for run in runs:
        per_model[(run["tool"], run["model"])].append(run)
    lines = ["| tool | model | runs | correct | geo-mean speedup (correct) | mean wall (s) | total in tok | total out tok |",
             "|---|---|---|---|---|---|---|---|"]
    for (tool, model), group in sorted(per_model.items()):
        speedups = [r["speedup"] for r in group if r["verify"]["correct"] and r["speedup"] > 0]
        geo = round(statistics.geometric_mean(speedups), 3) if speedups else None
        total_in = sum(r["agent"]["usage"].get("input_tokens") or 0 for r in group)
        total_out = sum(r["agent"]["usage"].get("output_tokens") or 0 for r in group)
        lines.append(f"| {tool} | {model} | {len(group)} | {len(speedups)} | {fmt(geo)} | "
                     f"{fmt(mean_or_none([r['agent']['wall_seconds'] for r in group]))} | {total_in} | {total_out} |")
    return "\n".join(lines)


def main():
    runs = load_runs()
    if not runs:
        sys.exit(f"no result.json found under {RUNS_DIR}")
    json.dump(runs, open(HERE / "results" / "runs.json", "w"), indent=1)
    report = ["# Agent optimisation results", "", f"{len(runs)} runs collected from `{RUNS_DIR}`.", "",
              "## Per model", "", model_table(runs), "", "## Per model and benchmark", "",
              benchmark_table(group_by_model_benchmark(runs)), ""]
    (HERE / "results" / "summary.md").write_text("\n".join(report))
    print(f"{len(runs)} runs -> results/summary.md, results/runs.json")


if __name__ == "__main__":
    main()
