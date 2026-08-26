"""Correctness regression test for the nbody benchmark.

Runs the original (baseline) and optimized implementations with identical
inputs and checks that they produce the same physical result (energy of the
system before/after advancing the simulation), so a performance change can
never silently change behavior.
"""

import pytest

from _loader import load_variant


def run_nbody(module, iterations):
    module.offset_momentum(module.BODIES[module.DEFAULT_REFERENCE])
    energy_before = module.report_energy()
    module.advance(0.01, iterations)
    energy_after = module.report_energy()
    return energy_before, energy_after


@pytest.mark.parametrize("iterations", [1, 100, 1000])
def test_nbody_optimized_matches_original(iterations):
    original = load_variant("nbody", "original")
    optimized = load_variant("nbody", "optimized")

    orig_before, orig_after = run_nbody(original, iterations)
    opt_before, opt_after = run_nbody(optimized, iterations)

    assert opt_before == pytest.approx(orig_before, rel=1e-12)
    assert opt_after == pytest.approx(orig_after, rel=1e-12)


def test_nbody_bench_function_runs():
    """Smoke test: the pyperf entry point itself still runs and returns a duration."""
    optimized = load_variant("nbody", "optimized")
    dt = optimized.bench_nbody(1, optimized.DEFAULT_REFERENCE, 50)
    assert dt >= 0
