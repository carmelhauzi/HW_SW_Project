# Third-party code

The files under `benchmarks/nbody/original/` and `benchmarks/raytrace/original/`
(and their initial, unmodified copies under `benchmarks/*/optimized/`) are taken
verbatim from the [pyperformance](https://github.com/python/pyperformance)
project ("Python Performance Benchmark Suite"):

- Source: https://github.com/python/pyperformance
- Commit: `bf9179beeb1c2ca3f212df2f0a124f6a18d1f38f` (2026-08-01)
- Paths:
  - `pyperformance/data-files/benchmarks/bm_nbody/run_benchmark.py`
  - `pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py`
- License: MIT (see below)

`nbody` is itself adapted by the pyperformance project from the
[Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/)
n-body program, contributed by Kevin Carson and modified by Tupteq,
Fredrik Johansson, and Daniel Nanz.

`raytrace` is a toy raytracer copyright Callum and Tony Garnock-Jones (2008),
originally published at http://www.lshift.net/blog/2008/10/29/toy-raytracer-in-python,
also redistributed by pyperformance under the MIT license.

The `optimized/` copies start out identical to `original/` and are the ones we
modify for this project; `original/` is kept untouched as the baseline for
correctness comparisons and performance comparisons.

## MIT License (pyperformance)

Copyright (c) 2016, Python Software Foundation and contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
