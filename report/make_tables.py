#!/usr/bin/env python3
"""Generate the LaTeX tables and macros for report.tex from results/runs.json."""
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXCLUDED_MODEL_PREFIXES = ("litellm/RiVault/",)  # same exclusion as harness/collect_results.py
RUNS = [r for r in json.load(open(HERE.parent / "results" / "runs.json"))
        if not r["model"].startswith(EXCLUDED_MODEL_PREFIXES)]
OUT = HERE / "tables"
SUSPICIOUS = 1000.0  # speedups above this almost always mean the timed region was emptied


def short_model(name):
    return name.replace("litellm/", "").split("/")[-1].replace("_", r"\_")


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


def model_row(model, runs):
    ok, good = scored(runs), plausible(runs)
    return [
        short_model(model), len(runs), len(ok),
        sum(r["speedup"] > SUSPICIOUS for r in ok),
        statistics.median([r["speedup"] for r in ok]) if ok else float("nan"),
        geomean([r["speedup"] for r in good]),
        statistics.median([r["agent"]["wall_seconds"] for r in runs]) / 60,
        sum(r["agent"]["usage"].get("output_tokens") or 0 for r in runs) / 1e6,
    ]


def cell(value, column, maxima):
    text = str(value) if isinstance(value, int) else (f"{value:.1f}" if column == 7 else fmt(value))
    highlighted = column in maxima and value == maxima[column]
    return rf"\textbf{{{text}}}" if highlighted else text


HIGHLIGHT_COLUMNS = (3, 4, 5, 6, 7)  # ">1000x" and every column to its right


def model_table():
    rows = [model_row(model, runs) for model, runs in sorted(by(RUNS, "model").items())]
    maxima = {c: max(row[c] for row in rows if row[c] == row[c]) for c in HIGHLIGHT_COLUMNS}
    return "\n".join(" & ".join([row[0]] + [cell(row[c], c, maxima) for c in range(1, 8)]) + r" \\"
                     for row in rows)


def tokens(run):
    usage = run["agent"]["usage"]
    return (usage.get("input_tokens") or 0) + (usage.get("output_tokens") or 0)


def peak_row(model, runs):
    good = plausible(runs)
    peak = max(good, key=lambda r: r["speedup"]) if good else None
    return [
        short_model(model),
        peak["speedup"] if peak else float("nan"),
        peak["benchmark"].replace("_", r"\_") if peak else "--",
        tokens(peak) / 1e3 if peak else float("nan"),
        peak["agent"]["wall_seconds"] / 60 if peak else float("nan"),
        sum(tokens(r) for r in runs) / 1e6,
        sum(r["agent"]["wall_seconds"] for r in runs) / 3600,
    ]


PEAK_HEAD = r"""\begin{tabular}{l r l r r r r}
\toprule
model & peak & benchmark & \multicolumn{2}{c}{cost of the peak run} & \multicolumn{2}{c}{cost of the sweep} \\
      & speedup &         & tokens (k) & wall (min) & tokens (M) & agent-hours \\
\midrule
"""


def peak_table():
    rows = [peak_row(model, runs) for model, runs in sorted(by(RUNS, "model").items())]
    best = max(row[1] for row in rows if row[1] == row[1])
    lines = []
    for row in rows:
        peak = fmt(row[1])
        lines.append(" & ".join([row[0], rf"\textbf{{{peak}}}" if row[1] == best else peak, row[2],
                                 fmt(row[3]), fmt(row[4]), fmt(row[5]), fmt(row[6])]) + r" \\")
    return "\n".join(lines)


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


MODELS_HEAD = r"""\begin{tabular}{l r r r r r r r}
\toprule
model & runs & correct & $>$\suspiciouscap$\times$ & median & geo-mean$^\dagger$ & wall & out.\ tok. \\
      &      &         &                          & speedup & speedup & (min) & (M) \\
\midrule
"""
OUTCOMES_HEAD = r"""\begin{tabular}{l r r r r r r}
\toprule
model & correct & build failed & self-check failed & run timeout & agent error & hit 2\,h \\
\midrule
"""
TABULAR_FOOT = "\\bottomrule\n\\end{tabular}\n"
BENCH_HEAD = r"""\begin{longtable}{l r r r l r}
\toprule
benchmark & correct/runs & median & best$^\dagger$ & best model & $>$\suspiciouscap$\times$ \\
\midrule
\endfirsthead
\toprule
benchmark & correct/runs & median & best$^\dagger$ & best model & $>$\suspiciouscap$\times$ \\
\midrule
\endhead
\bottomrule
\endfoot
"""
BENCH_FOOT = r"""\caption{Per-benchmark results over all models and repetitions. $^\dagger$Best
verified speedup among runs $\le$ \suspiciouscap$\times$.}
\label{tab:benchmarks}
\end{longtable}
"""


def main():
    OUT.mkdir(exist_ok=True)
    (OUT / "models.tex").write_text(MODELS_HEAD + model_table() + "\n" + TABULAR_FOOT)
    (OUT / "outcomes.tex").write_text(OUTCOMES_HEAD + outcome_table() + "\n" + TABULAR_FOOT)
    (OUT / "peaks.tex").write_text(PEAK_HEAD + peak_table() + "\n" + TABULAR_FOOT)
    (OUT / "benchmarks.tex").write_text(BENCH_HEAD + benchmark_table() + "\n" + BENCH_FOOT)
    (OUT / "macros.tex").write_text(macros() + "\n")
    print("tables written to", OUT)


if __name__ == "__main__":
    main()
