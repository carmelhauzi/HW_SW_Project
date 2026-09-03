// ---------------------------------------------------------------------------
// sphere_min_reducer.sv
//
// Consumes the per-sphere results from sphere_intersection_pipeline (one beat
// per clock) and keeps the closest valid hit, like CPython firstIntersection:
//
//   * beats with in_hit_valid = 0 are ignored
//   * the running best is replaced only when  in_t < best_t   (STRICT '<'),
//     so a tie keeps the earlier (lower) sphere_index
//   * the first valid hit seeds the best
//
// Framing: the caller pulses `clear` to start a fresh reduction, then the
// reducer counts 7 valid beats; on the 7th it registers the answer and pulses
// result_valid for one clock, then re-arms for the next ray.
// ---------------------------------------------------------------------------

module sphere_min_reducer (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       clear,          // start a fresh reduction

  input  logic       in_valid,       // a pipeline result beat this cycle
  input  logic       in_hit_valid,   // that beat is a real hit
  input  real        in_t,
  input  logic [2:0] in_index,

  output logic       result_valid,   // 1-cycle pulse after the 7th beat
  output logic       best_valid,     // a hit was found for this ray
  output logic [2:0] best_index,
  output real        best_t
);

  logic [2:0] count;                 // valid beats seen so far, 0..6
  logic       acc_valid;
  real        acc_t;
  logic [2:0] acc_index;

  logic take, last_beat;
  always_comb begin
    // strict '<', decided in the same cycle the beat is consumed
    take      = in_valid && in_hit_valid && (!acc_valid || (in_t < acc_t));
    last_beat = in_valid && (count == 3'd6);
  end

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      count        <= 3'd0;
      acc_valid    <= 1'b0;
      result_valid <= 1'b0;
      best_valid   <= 1'b0;
    end
    else begin
      result_valid <= 1'b0;                       // default: no pulse

      if (clear) begin
        count     <= 3'd0;
        acc_valid <= 1'b0;
      end
      else if (in_valid) begin
        if (take) begin
          acc_valid <= 1'b1;
          acc_t     <= in_t;
          acc_index <= in_index;
        end
        count <= count + 3'd1;

        if (last_beat) begin
          result_valid <= 1'b1;
          best_valid   <= take ? 1'b1     : acc_valid;
          best_t       <= take ? in_t     : acc_t;
          best_index   <= take ? in_index : acc_index;
          count        <= 3'd0;
          acc_valid    <= 1'b0;
        end
      end
    end

endmodule
