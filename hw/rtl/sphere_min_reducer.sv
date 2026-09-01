// ---------------------------------------------------------------------------
// sphere_min_reducer.sv
//
// Consumes the per-sphere results streaming out of
// sphere_intersection_pipeline (one beat per clock) and keeps the running
// "closest hit", reproducing CPython's firstIntersection():
//
//   * beats with in_hit_valid = 0 are ignored
//   * the running best is replaced only when  new_t < best_t   (STRICT '<'),
//     so on an exact tie the earlier (lower sphere_index) sphere is kept
//     -- this matches  "if result is None or candidateT < result[1]"
//   * the first valid hit becomes the best even though there is no prior
//     best (Python's "result is None" bootstrap)
//
// Framing (one ray at a time): the caller pulses `clear` to arm a fresh
// reduction, then the reducer counts N_RESULTS valid beats; on the
// N_RESULTS-th it registers the answer and pulses `result_valid` for one
// clock, then auto-arms for the next ray.  The beats need not be contiguous.
// `clear` on the same cycle as `in_valid` takes precedence (that beat is
// dropped) -- the top never does this because it clears ~LATENCY cycles
// before the first beat can arrive.
// ---------------------------------------------------------------------------

`default_nettype none

module sphere_min_reducer #(
  parameter int DW        = 64,   // IEEE-754 binary64
  parameter int IDX_W     = 3,    // sphere index 0..6
  parameter int N_RESULTS = 7     // spheres per ray
) (
  input  wire               clk,
  input  wire               rst_n,

  input  wire               clear,         // sync: arm a fresh reduction

  input  wire               in_valid,      // a pipeline result beat this cycle
  input  wire               in_hit_valid,  // that beat is a real hit
  input  wire  [DW-1:0]     in_t,
  input  wire  [IDX_W-1:0]  in_index,

  output logic              result_valid,  // 1-cycle pulse after the N_RESULTS-th beat
  output logic              best_valid,    // a hit was found for this ray
  output logic [IDX_W-1:0]  best_index,
  output logic [DW-1:0]     best_t
);

  localparam int CW = $clog2(N_RESULTS + 1);   // count needs 0..N_RESULTS

  logic [CW-1:0]     count;
  logic              acc_valid;
  logic [DW-1:0]     acc_t;
  logic [IDX_W-1:0]  acc_index;

  // Strict less-than on IEEE-754 doubles.  Combinational: the accept/reject
  // decision for a beat must be made in the same cycle it is consumed.
  // Behavioral model; for synthesis this is a plain float comparator.
  logic t_less;
  always_comb t_less = ($bitstoreal(in_t) < $bitstoreal(acc_t));

  // Replace the running best with this beat?
  wire take = in_valid & in_hit_valid & (~acc_valid | t_less);

  // Is this in_valid beat the last (N_RESULTS-th) one for the ray?
  wire last_beat = in_valid & (count == CW'(N_RESULTS - 1));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count        <= '0;
      acc_valid    <= 1'b0;
      acc_t        <= '0;
      acc_index    <= '0;
      result_valid <= 1'b0;
      best_valid   <= 1'b0;
      best_index   <= '0;
      best_t       <= '0;
    end
    else begin
      result_valid <= 1'b0;                       // default: no pulse this cycle

      if (clear) begin
        count     <= '0;
        acc_valid <= 1'b0;                        // acc_t/acc_index are don't-care while empty
      end
      else if (in_valid) begin
        // ---- fold this beat into the running best ----
        if (take) begin
          acc_valid <= 1'b1;
          acc_t     <= in_t;
          acc_index <= in_index;
        end
        count <= count + CW'(1);

        // ---- on the final beat, publish and re-arm ----
        if (last_beat) begin
          result_valid <= 1'b1;
          best_valid   <= take ? 1'b1     : acc_valid;
          best_t       <= take ? in_t     : acc_t;
          best_index   <= take ? in_index : acc_index;
          count        <= '0;
          acc_valid    <= 1'b0;
        end
      end
    end
  end

`ifndef SYNTHESIS
  // "one ray at a time" protocol check: `clear` should only arrive between rays.
  always_ff @(posedge clk)
    if (rst_n && clear && count != CW'(0))
      $warning("sphere_min_reducer: clear asserted mid-reduction (count=%0d)", count);
`endif

endmodule

`default_nettype wire
