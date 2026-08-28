"""
N-body benchmark from the Computer Language Benchmarks Game.

This is intended to support Unladen Swallow's pyperf.py. Accordingly, it has been
modified from the Shootout version:
- Accept standard Unladen Swallow benchmark options.
- Run report_energy()/advance() in a loop.
- Reimplement itertools.combinations() to work with older Python versions.

Pulled from:
http://benchmarksgame.alioth.debian.org/u64q/program.php?test=nbody&lang=python3&id=1

Contributed by Kevin Carson.
Modified by Tupteq, Fredrik Johansson, and Daniel Nanz.

Optimized variant: bodies are still stored the same way as the original
([x, y, z] / [vx, vy, vz] lists + mass), and per-body position/velocity is
still extracted via list/tuple destructuring (CPython's UNPACK_SEQUENCE is
a single, cheap opcode - repeatedly indexing with body[0]/body[1]/body[2]
instead is measurably *slower*, since each indexed read costs its own
LOAD_FAST/LOAD_CONST/BINARY_SUBSCR opcode triplet). What changes is *how
often* that destructuring happens and how the pairwise loop runs:
- Since there are always exactly 5 bodies / 10 pairs, the pairwise force
  loop is manually unrolled, removing the FOR_ITER looping overhead.
- Each body's position/velocity is destructured once per simulation step
  and reused across all pairs it's a member of, instead of the original
  re-destructuring a body's position anew for every pair it appears in
  (each body is in 4 of the 10 pairs, so the original repeats that work
  4x per body per step).
- Velocity is accumulated in local variables across all 10 pairs and
  written back to the body's velocity list once per step, instead of a
  subscript read-modify-write (v[i] -= ...) on every pair.
"""

import pyperf

__contact__ = "collinwinter@google.com (Collin Winter)"
DEFAULT_ITERATIONS = 20000
DEFAULT_REFERENCE = 'sun'

PI = 3.14159265358979323
SOLAR_MASS = 4 * PI * PI
DAYS_PER_YEAR = 365.24

BODIES = {
    'sun': ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], SOLAR_MASS),

    'jupiter': ([4.84143144246472090e+00,
                 -1.16032004402742839e+00,
                 -1.03622044471123109e-01],
                [1.66007664274403694e-03 * DAYS_PER_YEAR,
                 7.69901118419740425e-03 * DAYS_PER_YEAR,
                 -6.90460016972063023e-05 * DAYS_PER_YEAR],
                9.54791938424326609e-04 * SOLAR_MASS),

    'saturn': ([8.34336671824457987e+00,
                4.12479856412430479e+00,
                -4.03523417114321381e-01],
               [-2.76742510726862411e-03 * DAYS_PER_YEAR,
                4.99852801234917238e-03 * DAYS_PER_YEAR,
                2.30417297573763929e-05 * DAYS_PER_YEAR],
               2.85885980666130812e-04 * SOLAR_MASS),

    'uranus': ([1.28943695621391310e+01,
                -1.51111514016986312e+01,
                -2.23307578892655734e-01],
               [2.96460137564761618e-03 * DAYS_PER_YEAR,
                2.37847173959480950e-03 * DAYS_PER_YEAR,
                -2.96589568540237556e-05 * DAYS_PER_YEAR],
               4.36624404335156298e-05 * SOLAR_MASS),

    'neptune': ([1.53796971148509165e+01,
                 -2.59193146099879641e+01,
                 1.79258772950371181e-01],
                [2.68067772490389322e-03 * DAYS_PER_YEAR,
                 1.62824170038242295e-03 * DAYS_PER_YEAR,
                 -9.51592254519715870e-05 * DAYS_PER_YEAR],
                5.15138902046611451e-05 * SOLAR_MASS)}


SYSTEM = list(BODIES.values())


def advance(dt, n, bodies=SYSTEM):
    (p0, v0, m0), (p1, v1, m1), (p2, v2, m2), (p3, v3, m3), (p4, v4, m4) = bodies
    for _ in range(n):
        x0, y0, z0 = p0
        x1, y1, z1 = p1
        x2, y2, z2 = p2
        x3, y3, z3 = p3
        x4, y4, z4 = p4
        vx0, vy0, vz0 = v0
        vx1, vy1, vz1 = v1
        vx2, vy2, vz2 = v2
        vx3, vy3, vz3 = v3
        vx4, vy4, vz4 = v4

        # pairwise force accumulation (locals only, no subscripting)
        dx = x0 - x1; dy = y0 - y1; dz = z0 - z1
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m0 * mag; b2m = m1 * mag
        vx0 -= dx * b2m; vy0 -= dy * b2m; vz0 -= dz * b2m
        vx1 += dx * b1m; vy1 += dy * b1m; vz1 += dz * b1m

        dx = x0 - x2; dy = y0 - y2; dz = z0 - z2
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m0 * mag; b2m = m2 * mag
        vx0 -= dx * b2m; vy0 -= dy * b2m; vz0 -= dz * b2m
        vx2 += dx * b1m; vy2 += dy * b1m; vz2 += dz * b1m

        dx = x0 - x3; dy = y0 - y3; dz = z0 - z3
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m0 * mag; b2m = m3 * mag
        vx0 -= dx * b2m; vy0 -= dy * b2m; vz0 -= dz * b2m
        vx3 += dx * b1m; vy3 += dy * b1m; vz3 += dz * b1m

        dx = x0 - x4; dy = y0 - y4; dz = z0 - z4
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m0 * mag; b2m = m4 * mag
        vx0 -= dx * b2m; vy0 -= dy * b2m; vz0 -= dz * b2m
        vx4 += dx * b1m; vy4 += dy * b1m; vz4 += dz * b1m

        dx = x1 - x2; dy = y1 - y2; dz = z1 - z2
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m1 * mag; b2m = m2 * mag
        vx1 -= dx * b2m; vy1 -= dy * b2m; vz1 -= dz * b2m
        vx2 += dx * b1m; vy2 += dy * b1m; vz2 += dz * b1m

        dx = x1 - x3; dy = y1 - y3; dz = z1 - z3
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m1 * mag; b2m = m3 * mag
        vx1 -= dx * b2m; vy1 -= dy * b2m; vz1 -= dz * b2m
        vx3 += dx * b1m; vy3 += dy * b1m; vz3 += dz * b1m

        dx = x1 - x4; dy = y1 - y4; dz = z1 - z4
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m1 * mag; b2m = m4 * mag
        vx1 -= dx * b2m; vy1 -= dy * b2m; vz1 -= dz * b2m
        vx4 += dx * b1m; vy4 += dy * b1m; vz4 += dz * b1m

        dx = x2 - x3; dy = y2 - y3; dz = z2 - z3
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m2 * mag; b2m = m3 * mag
        vx2 -= dx * b2m; vy2 -= dy * b2m; vz2 -= dz * b2m
        vx3 += dx * b1m; vy3 += dy * b1m; vz3 += dz * b1m

        dx = x2 - x4; dy = y2 - y4; dz = z2 - z4
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m2 * mag; b2m = m4 * mag
        vx2 -= dx * b2m; vy2 -= dy * b2m; vz2 -= dz * b2m
        vx4 += dx * b1m; vy4 += dy * b1m; vz4 += dz * b1m

        dx = x3 - x4; dy = y3 - y4; dz = z3 - z4
        mag = dt * (dx * dx + dy * dy + dz * dz) ** (-1.5)
        b1m = m3 * mag; b2m = m4 * mag
        vx3 -= dx * b2m; vy3 -= dy * b2m; vz3 -= dz * b2m
        vx4 += dx * b1m; vy4 += dy * b1m; vz4 += dz * b1m

        # write updated velocities back, then advance positions using them
        v0[0] = vx0; v0[1] = vy0; v0[2] = vz0
        v1[0] = vx1; v1[1] = vy1; v1[2] = vz1
        v2[0] = vx2; v2[1] = vy2; v2[2] = vz2
        v3[0] = vx3; v3[1] = vy3; v3[2] = vz3
        v4[0] = vx4; v4[1] = vy4; v4[2] = vz4
        p0[0] += dt * vx0; p0[1] += dt * vy0; p0[2] += dt * vz0
        p1[0] += dt * vx1; p1[1] += dt * vy1; p1[2] += dt * vz1
        p2[0] += dt * vx2; p2[1] += dt * vy2; p2[2] += dt * vz2
        p3[0] += dt * vx3; p3[1] += dt * vy3; p3[2] += dt * vz3
        p4[0] += dt * vx4; p4[1] += dt * vy4; p4[2] += dt * vz4


def report_energy(bodies=SYSTEM, e=0.0):
    (p0, v0, m0), (p1, v1, m1), (p2, v2, m2), (p3, v3, m3), (p4, v4, m4) = bodies
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    x2, y2, z2 = p2
    x3, y3, z3 = p3
    x4, y4, z4 = p4

    dx = x0 - x1; dy = y0 - y1; dz = z0 - z1
    e -= (m0 * m1) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x0 - x2; dy = y0 - y2; dz = z0 - z2
    e -= (m0 * m2) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x0 - x3; dy = y0 - y3; dz = z0 - z3
    e -= (m0 * m3) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x0 - x4; dy = y0 - y4; dz = z0 - z4
    e -= (m0 * m4) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x1 - x2; dy = y1 - y2; dz = z1 - z2
    e -= (m1 * m2) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x1 - x3; dy = y1 - y3; dz = z1 - z3
    e -= (m1 * m3) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x1 - x4; dy = y1 - y4; dz = z1 - z4
    e -= (m1 * m4) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x2 - x3; dy = y2 - y3; dz = z2 - z3
    e -= (m2 * m3) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x2 - x4; dy = y2 - y4; dz = z2 - z4
    e -= (m2 * m4) / (dx * dx + dy * dy + dz * dz) ** 0.5
    dx = x3 - x4; dy = y3 - y4; dz = z3 - z4
    e -= (m3 * m4) / (dx * dx + dy * dy + dz * dz) ** 0.5

    vx0, vy0, vz0 = v0
    vx1, vy1, vz1 = v1
    vx2, vy2, vz2 = v2
    vx3, vy3, vz3 = v3
    vx4, vy4, vz4 = v4
    e += m0 * (vx0 * vx0 + vy0 * vy0 + vz0 * vz0) / 2.
    e += m1 * (vx1 * vx1 + vy1 * vy1 + vz1 * vz1) / 2.
    e += m2 * (vx2 * vx2 + vy2 * vy2 + vz2 * vz2) / 2.
    e += m3 * (vx3 * vx3 + vy3 * vy3 + vz3 * vz3) / 2.
    e += m4 * (vx4 * vx4 + vy4 * vy4 + vz4 * vz4) / 2.
    return e


def offset_momentum(ref, bodies=SYSTEM, px=0.0, py=0.0, pz=0.0):
    for (r, [vx, vy, vz], m) in bodies:
        px -= vx * m
        py -= vy * m
        pz -= vz * m
    (r, v, m) = ref
    v[0] = px / m
    v[1] = py / m
    v[2] = pz / m


def bench_nbody(loops, reference, iterations):
    # Set up global state
    offset_momentum(BODIES[reference])

    range_it = range(loops)
    t0 = pyperf.perf_counter()

    for _ in range_it:
        report_energy()
        advance(0.01, iterations)
        report_energy()

    return pyperf.perf_counter() - t0


def add_cmdline_args(cmd, args):
    cmd.extend(("--iterations", str(args.iterations)))


if __name__ == '__main__':
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    runner.metadata['description'] = "n-body benchmark"
    runner.argparser.add_argument("--iterations",
                                  type=int, default=DEFAULT_ITERATIONS,
                                  help="Number of nbody advance() iterations "
                                       "(default: %s)" % DEFAULT_ITERATIONS)
    runner.argparser.add_argument("--reference",
                                  type=str, default=DEFAULT_REFERENCE,
                                  help="nbody reference (default: %s)"
                                       % DEFAULT_REFERENCE)

    args = runner.parse_args()
    runner.bench_time_func('nbody', bench_nbody,
                           args.reference, args.iterations)
