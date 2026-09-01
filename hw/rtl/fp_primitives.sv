// ---------------------------------------------------------------------------
// fp_primitives.sv
//
// Behavioral IEEE-754 binary64 (double) arithmetic leaf cells used by
// sphere_intersection_pipeline.sv.
//
//  * SIMULATION ONLY.  Each cell computes its result with SystemVerilog `real`
//    arithmetic, which is IEEE-754 double in every compliant simulator, so the
//    numbers are bit-identical to CPython's float / math.sqrt.  The result is
//    then delayed by a fixed, parameterizable number of clocks.
//  * Initiation interval is 1: a new pair of operands may be applied on every
//    clock edge.
//  * For synthesis these are meant to be replaced 1:1 by pipelined FP IP
//    (e.g. Xilinx Floating-Point Operator, or an unrolled digit-recurrence
//    square root) exposing the same ports and the same LATENCY.  Nothing above
//    these cells changes when that swap happens.
//
// Every LATENCY parameter must be >= 1.
// ---------------------------------------------------------------------------

`default_nettype none

// ---------------------------------------------------------------------------
// vdelay : plain N-cycle shift register (N >= 0).
// Used to line up an operand that is produced in an earlier pipeline stage
// than the stage that consumes it.
// ---------------------------------------------------------------------------
module vdelay #(
  parameter int WIDTH = 64,
  parameter int N     = 1
) (
  input  wire  [WIDTH-1:0] d,
  input  wire               clk,
  output wire  [WIDTH-1:0] q
);
  generate
    if (N == 0) begin : g_passthru
      assign q = d;
    end
    else begin : g_pipe
      logic [WIDTH-1:0] pipe [0:N-1];
      integer i;
      always_ff @(posedge clk) begin
        pipe[0] <= d;
        for (i = 1; i < N; i = i + 1)
          pipe[i] <= pipe[i-1];
      end
      assign q = pipe[N-1];
    end
  endgenerate
endmodule


// ---------------------------------------------------------------------------
// Two-input arithmetic cells : y = (a OP b) registered LATENCY clocks later.
// ---------------------------------------------------------------------------
module fp_add #(parameter int LATENCY = 3) (
  input  wire         clk,
  input  wire  [63:0] a,
  input  wire  [63:0] b,
  output wire  [63:0] y
);
  logic [63:0] comb;
  always_comb comb = $realtobits($bitstoreal(a) + $bitstoreal(b));
  vdelay #(.WIDTH(64), .N(LATENCY)) u_d (.d(comb), .clk(clk), .q(y));
endmodule


module fp_sub #(parameter int LATENCY = 3) (
  input  wire         clk,
  input  wire  [63:0] a,
  input  wire  [63:0] b,
  output wire  [63:0] y
);
  logic [63:0] comb;
  always_comb comb = $realtobits($bitstoreal(a) - $bitstoreal(b));
  vdelay #(.WIDTH(64), .N(LATENCY)) u_d (.d(comb), .clk(clk), .q(y));
endmodule


module fp_mul #(parameter int LATENCY = 3) (
  input  wire         clk,
  input  wire  [63:0] a,
  input  wire  [63:0] b,
  output wire  [63:0] y
);
  logic [63:0] comb;
  always_comb comb = $realtobits($bitstoreal(a) * $bitstoreal(b));
  vdelay #(.WIDTH(64), .N(LATENCY)) u_d (.d(comb), .clk(clk), .q(y));
endmodule


// ---------------------------------------------------------------------------
// fp_sqrt : y = sqrt(a) registered LATENCY clocks later.
// A negative (or -0.0) radicand is mapped to +0.0 so that no NaN can travel
// down the pipe.  Such a lane is always discarded downstream anyway, because
// disc < 0 forces hit_valid = 0.  For disc == +0.0 the result is +0.0, which
// matches CPython (math.sqrt(0.0) == 0.0).
// ---------------------------------------------------------------------------
module fp_sqrt #(parameter int LATENCY = 16) (
  input  wire         clk,
  input  wire  [63:0] a,
  output wire  [63:0] y
);
  logic [63:0] comb;
  real         ra;
  always_comb begin
    ra   = $bitstoreal(a);
    comb = (ra <= 0.0) ? 64'h0000_0000_0000_0000
                       : $realtobits($sqrt(ra));
  end
  vdelay #(.WIDTH(64), .N(LATENCY)) u_d (.d(comb), .clk(clk), .q(y));
endmodule


// ---------------------------------------------------------------------------
// Comparison cells : 1-bit result registered LATENCY clocks later.
// ---------------------------------------------------------------------------
module fp_lt #(parameter int LATENCY = 1) (
  input  wire         clk,
  input  wire  [63:0] a,
  input  wire  [63:0] b,
  output wire         y      // 1 iff a < b
);
  logic comb;
  always_comb comb = ($bitstoreal(a) < $bitstoreal(b));
  vdelay #(.WIDTH(1), .N(LATENCY)) u_d (.d(comb), .clk(clk), .q(y));
endmodule


module fp_gt #(parameter int LATENCY = 1) (
  input  wire         clk,
  input  wire  [63:0] a,
  input  wire  [63:0] b,
  output wire         y      // 1 iff a > b
);
  logic comb;
  always_comb comb = ($bitstoreal(a) > $bitstoreal(b));
  vdelay #(.WIDTH(1), .N(LATENCY)) u_d (.d(comb), .clk(clk), .q(y));
endmodule

`default_nettype wire
