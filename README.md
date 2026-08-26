# HW_SW_Project

Performance-optimization project based on two benchmarks from the
[pyperformance](https://github.com/python/pyperformance) ("Python Performance
Benchmark Suite"): **nbody** and **raytrace**. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance/license info
on the copied benchmark code.

## Layout

```
benchmarks/
  manifest-original.txt   # tells the pyperformance CLI where the baseline benchmarks live
  manifest-optimized.txt  # tells the pyperformance CLI where the optimized benchmarks live
  nbody/
    original/      # untouched baseline, do not edit
    optimized/      # our modified/optimized version, starts as a copy of original
  raytrace/
    original/      # untouched baseline, do not edit
    optimized/      # our modified/optimized version, starts as a copy of original
tests/
  test_nbody.py     # asserts optimized output == original output
  test_raytrace.py  # asserts optimized output == original output
```

`original/` must stay byte-for-byte the upstream code so it always serves as
the correctness and performance baseline. All optimization work happens in
the corresponding `optimized/` folder.

## Setup

```
python -m venv .venv
.venv\Scripts\activate      # Windows
pip install -r requirements.txt
```

## Correctness: does the optimization still behave the same?

```
pytest tests/ -v
```

`test_nbody.py` runs `advance()`/`report_energy()` on both variants with the
same inputs and checks the resulting energy values match. `test_raytrace.py`
renders the same scene with both variants and checks the output pixels are
identical. If you change behavior (not just speed) in `optimized/`, these
will fail — that's the point.

## Performance: how fast is each version?

There are two ways to measure performance, depending on what you need.

### Option A: the `pyperformance` CLI (recommended, this is "running pyperformance")

`pip install -r requirements.txt` also installs the `pyperformance` package
itself. `benchmarks/manifest-original.txt` and `benchmarks/manifest-optimized.txt`
point pyperformance at our two copies of each benchmark (one manifest per
variant, since both copies declare the same benchmark names `nbody`/`raytrace`
and pyperformance won't allow duplicate names in one manifest).

**Always run these commands from the repository root** — the manifest files
use paths relative to the current directory.

```
# sanity-check the manifest resolves correctly
python -m pyperformance list --manifest benchmarks/manifest-original.txt

# run the baseline
python -m pyperformance run --manifest benchmarks/manifest-original.txt -o results_original.json

# run our optimized version
python -m pyperformance run --manifest benchmarks/manifest-optimized.txt -o results_optimized.json

# compare
python -m pyperformance compare results_original.json results_optimized.json
```

Add `-b nbody` or `-b raytrace` to run just one benchmark, `--fast` while
iterating, `--rigorous` for final numbers. Note: the first run creates an
isolated virtual environment under `venv/` (gitignored) with each benchmark's
declared dependencies (just `pyperf`) — this is normal pyperformance behavior
and is reused on subsequent runs.

### Option B: run a `run_benchmark.py` directly with pyperf

Each `run_benchmark.py` is also a self-contained [pyperf](https://pyperf.readthedocs.io/)
benchmark script and can be run/compared without going through the
`pyperformance` CLI or its manifest/venv machinery — useful for quick
iteration or profiling.

Run one version and save timing results to a JSON file:

```
python benchmarks/nbody/original/run_benchmark.py -o results_nbody_original.json
python benchmarks/nbody/optimized/run_benchmark.py -o results_nbody_optimized.json

python benchmarks/raytrace/original/run_benchmark.py -o results_raytrace_original.json
python benchmarks/raytrace/optimized/run_benchmark.py -o results_raytrace_optimized.json
```

Then compare original vs optimized:

```
python -m pyperf compare_to results_nbody_original.json results_nbody_optimized.json
python -m pyperf compare_to results_raytrace_original.json results_raytrace_optimized.json
```

(Note the results files from Option A and Option B aren't interchangeable inputs to each other's compare command — keep each option's outputs together.)

Useful flags while iterating (full runs are slow/rigorous by default):
- `--fast` — fewer samples, quick sanity check of timing
- `--rigorous` — more samples, higher-confidence result for final numbers
- `-p N` — number of worker processes
- `--iterations` (nbody) / `--width --height` (raytrace) — problem size

You can also profile a version directly with any standard tool, e.g.:

```
python -m cProfile -o nbody.prof benchmarks/nbody/optimized/run_benchmark.py --iterations 20000
```
