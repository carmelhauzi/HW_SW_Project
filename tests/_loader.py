"""Helper to import the two (original/optimized) copies of a benchmark
module under distinct names, since both files are called ``run_benchmark.py``.
"""

import importlib.util
import sys
from pathlib import Path

BENCHMARKS_DIR = Path(__file__).resolve().parent.parent / "benchmarks"


def load_variant(benchmark: str, variant: str):
    """Import benchmarks/<benchmark>/<variant>/run_benchmark.py as its own module.

    Each call returns a fresh module object with its own globals, so mutable
    module-level state (e.g. nbody's BODIES/SYSTEM) does not leak between
    the original and optimized variants, or between successive test calls.
    """
    path = BENCHMARKS_DIR / benchmark / variant / "run_benchmark.py"
    module_name = f"_bench_{benchmark}_{variant}"
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
