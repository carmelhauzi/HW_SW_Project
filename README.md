# HW_SW_Project

Performance-optimization project based on two benchmarks from the
[pyperformance](https://github.com/python/pyperformance) suite: **raytrace**
and **pyflate**. Also includes a SystemVerilog RTL sketch of a hardware
accelerator for the raytrace benchmark's sphere-intersection math. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance/license info
on the copied benchmark code.

## Repository structure

```
benchmarks/
  manifest-original.txt    # pyperformance manifest pointing at the baseline benchmarks
  manifest-optimized.txt   # pyperformance manifest pointing at the optimized benchmarks
  raytrace/
    original/              # untouched baseline, do not edit
    optimized/              # our optimized version
  pyflate/
    original/              # untouched baseline, do not edit
    optimized/              # our optimized version

hw/rtl/                    # SystemVerilog: sphere-intersection accelerator sketch
  ray_sphere_accelerator.sv  # top module
  sphere_intersection_pipeline.sv
  sphere_min_reducer.sv
  sphere_storage.sv

tests/
  test_raytrace.py         # asserts optimized output == original output
  test_pyflate.py          # asserts optimized output == original output

script_raytrace.sh         # end-to-end perf harness (perf/flamegraph) for raytrace
script_pyflate.sh          # end-to-end perf harness (perf/flamegraph) for pyflate
requirements.txt
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

Each test runs both variants on the same inputs and checks the outputs
match byte-for-byte / value-for-value. If you change behavior (not just
speed) in `optimized/`, these will fail — that's the point.

## Performance: how fast is each version?

### Option A: `script_raytrace.sh` / `script_pyflate.sh` (recommended)

These are the full harnesses used to produce the numbers in this project.
Intended to run inside the course's QEMU environment (they need `perf`,
`python3-dbg`, and the FlameGraph scripts on `PATH`), from the repo root:

```
./script_raytrace.sh
./script_pyflate.sh
```

Each script sets up the venv, runs the baseline and optimized variants
through `pyperformance` under `perf record`, generates flame graphs
(perf-based and cProfile/flameprof-based), collects `perf stat` counters,
and writes everything to `results/<benchmark>/` (timings, raw perf data,
flame graphs, perf reports, and a `compare.txt` summary).

### Option B: the `pyperformance` CLI directly

**Always run these commands from the repository root** — the manifest files
use paths relative to the current directory.

```
python -m pyperformance run --manifest benchmarks/manifest-original.txt -o results_original.json
python -m pyperformance run --manifest benchmarks/manifest-optimized.txt -o results_optimized.json
python -m pyperformance compare results_original.json results_optimized.json
```

Add `-b raytrace` or `-b pyflate` to run just one benchmark, `--fast` while
iterating, `--rigorous` for final numbers.

### Option C: run a `run_benchmark.py` directly with pyperf

```
python benchmarks/raytrace/original/run_benchmark.py -o results_raytrace_original.json
python benchmarks/raytrace/optimized/run_benchmark.py -o results_raytrace_optimized.json
python -m pyperf compare_to results_raytrace_original.json results_raytrace_optimized.json
```

Same pattern for `benchmarks/pyflate/`. Useful flags: `--fast`,
`--rigorous`, `-p N` (worker processes), `--iterations`/`--width --height`
(problem size).

## Hardware (hw/rtl)

`hw/rtl/` contains a behavioral SystemVerilog model of a pipelined
sphere-intersection accelerator (`ray_sphere_accelerator.sv` is the top
module, wiring together `sphere_storage`, `sphere_intersection_pipeline`,
and `sphere_min_reducer`). It's a design exploration, not part of the
Python benchmark/test flow above.
