"""Correctness regression test for the raytrace benchmark.

Renders the same scene (as bench_raytrace does internally) with the original
and optimized implementations and checks the resulting images are pixel-for-
pixel identical, so a performance change can never silently change the
rendered output.
"""

import pytest

from _loader import load_variant


def render_scene(module, width, height):
    """Reproduce the scene setup from bench_raytrace() and render it."""
    canvas = module.Canvas(width, height)
    s = module.Scene()
    s.addLight(module.Point(30, 30, 10))
    s.addLight(module.Point(-10, 100, 30))
    s.lookAt(module.Point(0, 3, 0))
    s.addObject(module.Sphere(module.Point(1, 3, -10), 2),
                module.SimpleSurface(baseColour=(1, 1, 0)))
    for y in range(6):
        s.addObject(module.Sphere(module.Point(-3 - y * 0.4, 2.3, -5), 0.4),
                    module.SimpleSurface(baseColour=(y / 6.0, 1 - y / 6.0, 0.5)))
    s.addObject(module.Halfspace(module.Point(0, 0, 0), module.Vector.UP),
                module.CheckerboardSurface())
    s.render(canvas)
    return bytes(canvas.bytes)


@pytest.mark.parametrize("width,height", [(20, 15), (32, 24)])
def test_raytrace_optimized_matches_original(width, height):
    original = load_variant("raytrace", "original")
    optimized = load_variant("raytrace", "optimized")

    orig_pixels = render_scene(original, width, height)
    opt_pixels = render_scene(optimized, width, height)

    assert opt_pixels == orig_pixels


def test_raytrace_bench_function_runs():
    """Smoke test: the pyperf entry point itself still runs and returns a duration."""
    optimized = load_variant("raytrace", "optimized")
    dt = optimized.bench_raytrace(1, 16, 12, None)
    assert dt >= 0
