#!/usr/bin/env python3
"""Generate the LaTeX tables and macros for report.tex from results/runs.json."""
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNS = json.load(open(HERE.parent / "results" / "runs.json"))
OUT = HERE / "tables"
SUSPICIOUS = 1000.0  # speedups above this almost always mean the timed region was emptied


def short_model(name):
    return name.replace("litellm/", "").replace("_", r"\_")


def outcome(run):
    if run["agent"]["error"]:
        return "agent error"
    if run["verify"]["correct"]:
        return "correct"
    if run["verify"]["rc"] == 100:
        return "build failed"
    if run["verify"]["rc"] == 124:
        return "run timeout"
    return "self-check failed"


def scored(runs):
    return [r for r in runs if outcome(r) == "correct" and r["speedup"]]


def plausible(runs):
    return [r for r in scored(runs) if r["speedup"] <= SUSPICIOUS]


def geomean(values):
    return statistics.geometric_mean(values) if values else float("nan")


def fmt(value, digits=3):
    return "--" if value != value else f"{value:.{digits}g}"


def by(runs, key):
    groups = defaultdict(list)
    for run in runs:
        groups[run[key]].append(run)
    return groups


def model_table():
    rows = []
    for model, runs in sorted(by(RUNS, "model").items()):
        ok, good = scored(runs), plausible(runs)
        rows.append(" & ".join([
            short_model(model), str(len(runs)), str(len(ok)),
            str(sum(r["speedup"] > SUSPICIOUS for r in ok)),
            fmt(statistics.median([r["speedup"] for r in ok])) if ok else "--",
            fmt(geomean([r["speedup"] for r in good])),
            fmt(statistics.median([r["agent"]["wall_seconds"] for r in runs]) / 60, 3),
            f"{sum(r['agent']['usage'].get('output_tokens') or 0 for r in runs) / 1e6:.1f}",
        ]) + r" \\")
    return "\n".join(rows)


def outcome_table():
    rows = []
    for model, runs in sorted(by(RUNS, "model").items()):
        counts = Counter(outcome(r) for r in runs)
        rows.append(" & ".join([short_model(model)] + [
            str(counts[k]) for k in ("correct", "build failed", "self-check failed", "run timeout", "agent error")]
            + [str(sum(r["agent"]["rc"] == 124 for r in runs))]) + r" \\")
    return "\n".join(rows)


def benchmark_table():
    rows = []
    for bench, runs in sorted(by(RUNS, "benchmark").items()):
        ok, good = scored(runs), plausible(runs)
        best = max(good, key=lambda r: r["speedup"]) if good else None
        rows.append(" & ".join([
            bench.replace("_", r"\_"), f"{len(ok)}/{len(runs)}",
            fmt(statistics.median([r["speedup"] for r in ok])) if ok else "--",
            fmt(best["speedup"]) if best else "--",
            short_model(best["model"]) if best else "--",
            str(sum(r["speedup"] > SUSPICIOUS for r in ok)),
        ]) + r" \\")
    return "\n".join(rows)


def macros():
    ok = scored(RUNS)
    counts = Counter(outcome(r) for r in RUNS)
    return "\n".join([
        rf"\newcommand{{\nruns}}{{{len(RUNS)}}}",
        rf"\newcommand{{\nmodels}}{{{len(by(RUNS, 'model'))}}}",
        rf"\newcommand{{\nbenchmarks}}{{{len(by(RUNS, 'benchmark'))}}}",
        rf"\newcommand{{\ncorrect}}{{{counts['correct']}}}",
        rf"\newcommand{{\nbuildfail}}{{{counts['build failed']}}}",
        rf"\newcommand{{\nselfcheckfail}}{{{counts['self-check failed']}}}",
        rf"\newcommand{{\nruntimeout}}{{{counts['run timeout']}}}",
        rf"\newcommand{{\nagenterror}}{{{counts['agent error']}}}",
        rf"\newcommand{{\nagenttimeout}}{{{sum(r['agent']['rc'] == 124 for r in RUNS)}}}",
        rf"\newcommand{{\nsuspicious}}{{{sum(r['speedup'] > SUSPICIOUS for r in ok)}}}",
        rf"\newcommand{{\nslower}}{{{sum(r['speedup'] < 1 for r in ok)}}}",
        rf"\newcommand{{\medianspeedup}}{{{fmt(statistics.median([r['speedup'] for r in ok]))}}}",
        rf"\newcommand{{\suspiciouscap}}{{{int(SUSPICIOUS)}}}",
    ])


def main():
    OUT.mkdir(exist_ok=True)
    (OUT / "models.tex").write_text(model_table() + "\n")
    (OUT / "outcomes.tex").write_text(outcome_table() + "\n")
    (OUT / "benchmarks.tex").write_text(benchmark_table() + "\n")
    (OUT / "macros.tex").write_text(macros() + "\n")
    print("tables written to", OUT)


if __name__ == "__main__":
    main()
