#!/usr/bin/env bash
#
# script_pyflate.sh
#
# End-to-end performance harness for the "pyflate" benchmark. Intended to be
# run inside the QEMU environment, from the repository root:
#
#   ./script_pyflate.sh [normal|fast|rigorous]
#
# It will:
#   1. Set up the environment (venv + dependencies, apt deps incl. perf +
#      python3-dbg).
#   2. Run the ORIGINAL (baseline) benchmark via pyperformance, profiled with
#      `perf record -F 999 --call-graph dwarf -e cpu-clock -- python3-dbg ...`
#      to produce a flame graph + performance data.
#   3. Run the OPTIMIZED benchmark the same way.
#   4. Compare original vs. optimized and print/save the results.
#
# This script requires `perf`, `python3-dbg`, and the FlameGraph scripts to
# work - there is no fallback profiler. If any of those fail, the script
# stops with an error instead of silently substituting a different tool.
#
# Defaults to "normal" (no --fast/--rigorous), matching the staff's example
# command, which doesn't pass --fast either. Re-run any time after editing
# benchmarks/pyflate/optimized/run_benchmark.py to get fresh numbers.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Config
# ---------------------------------------------------------------------------
BENCH_NAME="pyflate"
MODE="${1:-normal}"         # normal | fast | rigorous
PROFILE_LOOPS="${PROFILE_LOOPS:-30}"  # loops for the cProfile/flameprof run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RESULTS_DIR="results/${BENCH_NAME}"
FLAMEGRAPH_DIR="$SCRIPT_DIR/.flamegraph-tools"
# pyperformance/pyperf refuse to overwrite an existing -o output file, so
# start each run from a clean slate rather than erroring on stale results.
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

case "$MODE" in
  fast)     PYPERFORMANCE_FLAG="--fast" ;;
  rigorous) PYPERFORMANCE_FLAG="--rigorous" ;;
  normal)   PYPERFORMANCE_FLAG="" ;;
  *) echo "Unknown mode '$MODE' (expected normal|fast|rigorous)" >&2; exit 1 ;;
esac

log() { printf '\n===> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Environment setup and dependency installation
# ---------------------------------------------------------------------------
log "Environment setup"

if command -v apt-get >/dev/null 2>&1; then
  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"
  $SUDO apt-get update -y || true
  $SUDO apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dbg build-essential git perl
  # perf package name depends on the running kernel flavor; try the common
  # ones individually so one non-existent package name doesn't block perf
  # itself from being installed via whichever candidate does exist.
  $SUDO apt-get install -y --no-install-recommends linux-tools-common || true
  $SUDO apt-get install -y --no-install-recommends linux-tools-generic || true
  $SUDO apt-get install -y --no-install-recommends "linux-tools-$(uname -r)" || true
else
  echo "apt-get not found, assuming python3/python3-dbg/perf are already available."
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required but was not found on PATH."
command -v perf >/dev/null 2>&1 || die "perf is required (course staff's flame-graph method) but was not found on PATH. Install linux-tools-\$(uname -r) (or linux-tools-generic) and re-run."
command -v python3-dbg >/dev/null 2>&1 || die "python3-dbg is required (course staff's flame-graph method) but was not found on PATH. Install the python3-dbg package and re-run."
PYTHON_DBG="python3-dbg"

if [ ! -d "$FLAMEGRAPH_DIR" ]; then
  git clone --depth 1 https://github.com/brendangregg/FlameGraph.git "$FLAMEGRAPH_DIR"
fi
[ -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" ] || die "FlameGraph script stackcollapse-perf.pl missing under $FLAMEGRAPH_DIR."
[ -x "$FLAMEGRAPH_DIR/flamegraph.pl" ] || die "FlameGraph script flamegraph.pl missing under $FLAMEGRAPH_DIR."

if python3 -m venv "$SCRIPT_DIR/.venv" >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.venv/bin/activate"
else
  echo "python3 -m venv failed; continuing with system python3 (--user installs)."
  PIP_USER_FLAG="--user"
fi
PIP_USER_FLAG="${PIP_USER_FLAG:-}"

python3 -m pip install --upgrade pip $PIP_USER_FLAG
python3 -m pip install -r requirements.txt $PIP_USER_FLAG

# ---------------------------------------------------------------------------
# Helper: `perf record` for one variant.
#
# -e cpu-clock : the QEMU guest has no working hardware PMU, so the default
#   'cycles' event records zero samples (flamegraph.pl then fails with
#   "Stack count is low (0)").
#
# --call-graph dwarf : unwind call stacks from debug info instead of frame
#   pointers, so frames resolve to real names instead of collapsing into
#   [unknown]. Heavier than -g/fp (bigger perf.data, slower `perf script`);
#   if a run stalls at flame-graph generation, drop -F 999 to e.g. -F 250 or
#   switch back to plain -g.
#
# --no-bpf-event : skip BPF image metadata perf can't fetch on this guest.
# ---------------------------------------------------------------------------
run_perf_record() {
  local out_data="$1"; shift
  perf record -F 999 --call-graph dwarf --no-bpf-event -e cpu-clock -o "$out_data" -- "$@"
}

# ---------------------------------------------------------------------------
# Helper: run one variant (original|optimized) end to end
# ---------------------------------------------------------------------------
run_variant() {
  local variant="$1"   # original | optimized
  local script_path="benchmarks/${BENCH_NAME}/${variant}/run_benchmark.py"

  log "Running ${BENCH_NAME} (${variant}) via pyperformance, profiled with perf"
  run_perf_record "${RESULTS_DIR}/perf_${variant}.data" \
      "$PYTHON_DBG" -m pyperformance run \
        --manifest "benchmarks/manifest-${variant}.txt" \
        -b "${BENCH_NAME}" \
        ${PYPERFORMANCE_FLAG} \
        -o "${RESULTS_DIR}/pyperformance_${variant}.json" \
    || die "perf record failed for ${variant}."

  log "Generating flame graph for ${variant}"
  perf script -i "${RESULTS_DIR}/perf_${variant}.data" \
      | "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" \
      | "$FLAMEGRAPH_DIR/flamegraph.pl" \
      > "${RESULTS_DIR}/flamegraph_${variant}.svg" \
    || die "failed to render the flame graph SVG for ${variant} from perf.data."

  log "Generating perf report for ${variant}"
  perf report --stdio -i "${RESULTS_DIR}/perf_${variant}.data" \
      > "${RESULTS_DIR}/perf_report_${variant}.txt" \
    || die "perf report failed for ${variant}."

  log "Generating cProfile/flameprof flame graph for ${variant}"
  python3 -c "
import cProfile, os, sys
sys.path.insert(0, 'benchmarks/${BENCH_NAME}/${variant}')
import run_benchmark as m
filename = os.path.join(os.path.dirname(m.__file__), 'data', 'interpreter.tar.bz2')
cProfile.run('m.bench_pyflake(${PROFILE_LOOPS}, filename)', '${RESULTS_DIR}/cprofile_${variant}.prof')
" || die "cProfile run failed for ${variant}."
  python3 -m flameprof "${RESULTS_DIR}/cprofile_${variant}.prof" \
      > "${RESULTS_DIR}/flameprof_${variant}.svg" \
    || die "flameprof rendering failed for ${variant}."

  # perf stat: counters (task-clock, cycles, instructions, ...), -r 3 for a
  # mean +- stddev. --worker runs pyperf in-process (no subprocess spawning);
  # --loops 1 skips auto-calibration so both variants do identical work;
  # --warmups 1 --values 20 = 1 discarded + 20 measured values.
  log "Collecting perf stat counters for ${variant}"
  perf stat -r 3 python3 "$script_path" \
      --worker --loops 1 --warmups 1 --values 20 \
      > "${RESULTS_DIR}/perfstat_${variant}.txt" 2>&1 \
    || die "perf stat failed for ${variant}."
}

# ---------------------------------------------------------------------------
# 2. Baseline (pre-optimization) run + profiling data
# ---------------------------------------------------------------------------
run_variant original

# ---------------------------------------------------------------------------
# 3. Post-optimization run + profiling data
# ---------------------------------------------------------------------------
run_variant optimized

# ---------------------------------------------------------------------------
# 4. Performance comparison
# ---------------------------------------------------------------------------
log "Comparing original vs. optimized"

python3 -m pyperformance compare \
  "${RESULTS_DIR}/pyperformance_original.json" \
  "${RESULTS_DIR}/pyperformance_optimized.json" \
  | tee "${RESULTS_DIR}/compare.txt"

log "Done. Artifacts written under ${RESULTS_DIR}/:"
echo "  pyperformance_{original,optimized}.json  - pyperformance timing results"
echo "  perf_{original,optimized}.data           - raw perf samples"
echo "  flamegraph_{original,optimized}.svg      - flame graphs (perf-based)"
echo "  perf_report_{original,optimized}.txt     - perf report --stdio (hot symbols/callers)"
echo "  cprofile_{original,optimized}.prof       - raw cProfile stats"
echo "  flameprof_{original,optimized}.svg       - flame graphs (cProfile/flameprof-based)"
echo "  perfstat_{original,optimized}.txt        - perf stat (-r 3) counters"
echo "  compare.txt                              - performance comparison"
