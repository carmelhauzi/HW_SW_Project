"""Correctness regression test for the pyflate benchmark.

Decodes the same bzip2 fixture (data/interpreter.tar.bz2) with the original
and optimized implementations and checks the decompressed bytes are
identical (and match the known-good MD5), so a performance change can never
silently change the decoded output.
"""

import hashlib
from pathlib import Path

import pytest

from _loader import load_variant

DATA_FILE = "interpreter.tar.bz2"
EXPECTED_MD5 = "afa004a630fe072901b1d9628b960974"


def decode(module, variant):
    path = Path(__file__).resolve().parent.parent / "benchmarks" / "pyflate" / variant / "data" / DATA_FILE
    with open(path, "rb") as input_fp:
        field = module.RBitfield(input_fp)
        magic = field.readbits(16)
        assert magic == 0x425a, "fixture is expected to be a BZip2 stream"
        return module.bzip2_main(field)


def test_pyflate_optimized_matches_original():
    original = load_variant("pyflate", "original")
    optimized = load_variant("pyflate", "optimized")

    orig_out = decode(original, "original")
    opt_out = decode(optimized, "optimized")

    assert hashlib.md5(orig_out).hexdigest() == EXPECTED_MD5
    assert opt_out == orig_out


def test_pyflate_bench_function_runs():
    """Smoke test: the pyperf entry point itself still runs and returns a duration."""
    optimized = load_variant("pyflate", "optimized")
    filename = Path(__file__).resolve().parent.parent / "benchmarks" / "pyflate" / "optimized" / "data" / DATA_FILE
    dt = optimized.bench_pyflake(1, str(filename))
    assert dt >= 0
