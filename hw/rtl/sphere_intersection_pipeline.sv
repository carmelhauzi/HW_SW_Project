// ---------------------------------------------------------------------------
// sphere_intersection_pipeline.sv
//
// Feed-forward pipeline that reproduces CPython's Sphere.intersectionTime for
// one (ray, sphere) pair per clock.  Initiation interval = 1.  The result for
// the sphere presented on cycle T (with in_valid = 1) leaves on cycle
// T + LATENCY with out_valid = 1, carrying the sphere_index that entered with
// it.  There is no FSM, no loop and no back-pressure.
//
// Math, in the SAME operation order / associativity as the Python:
//
//   cp        = center - ray_point                         // 3 subs
//   v         = (cp.x*dir.x + cp.y*dir.y) + cp.z*dir.z      // left-assoc dot
//   cpcp      = (cp.x*cp.x + cp.y*cp.y) + cp.z*cp.z         // left-assoc dot
//   disc      = radius_squared - (cpcp - v*v)               // note grouping
//   hit       = (disc >= 0)                                 // Python: disc<0 -> None
//   t         = v - sqrt(disc)                              // sqrt(0) when disc==0
//   hit_valid = hit && (t > -EPSILON)                       // EPSILON = 1e-5
//
// ray_point_* / ray_dir_* are held constant by the caller for the 7 spheres
// of a ray; this module does not track "rays".  ray_dir_* must already be
// normalized by software.  sphere_r2 is radius*radius, precomputed by software.
// ---------------------------------------------------------------------------

`default_nettype none

module sphere_intersection_pipeline #(
  parameter int DW       = 64,   // IEEE-754 binary64
  parameter int IDX_W    = 3,    // sphere index 0..6
  // Behavioral FP leaf-cell latencies.  Override to match real FP IP.
  parameter int SUB_LAT  = 3,
  parameter int ADD_LAT  = 3,
  parameter int MUL_LAT  = 3,
  parameter int SQRT_LAT = 16,
  parameter int CMP_LAT  = 1
) (
  input  wire               clk,
  input  wire               rst_n,        // sync, active-low; clears the valid pipe only

  input  wire               in_valid,     // a sphere is presented this cycle
  input  wire  [IDX_W-1:0]   sphere_index, // rides through the pipeline

  // ray operands (constant across a ray's 7 beats)
  input  wire  [DW-1:0]      ray_point_x,
  input  wire  [DW-1:0]      ray_point_y,
  input  wire  [DW-1:0]      ray_point_z,
  input  wire  [DW-1:0]      ray_dir_x,
  input  wire  [DW-1:0]      ray_dir_y,
  input  wire  [DW-1:0]      ray_dir_z,

  // sphere operands (one per clock)
  input  wire  [DW-1:0]      sphere_cx,
  input  wire  [DW-1:0]      sphere_cy,
  input  wire  [DW-1:0]      sphere_cz,
  input  wire  [DW-1:0]      sphere_r2,

  output logic              out_valid,
  output logic              hit_valid,
  output logic [IDX_W-1:0]  sphere_index_out,
  output logic [DW-1:0]     t
);

  // -----------------------------------------------------------------------
  // Constants (IEEE-754 binary64 bit patterns)
  // -----------------------------------------------------------------------
  localparam logic [63:0] NEG_EPS = 64'hBEE4F8B588E368F1;  // -1e-5
  localparam logic [63:0] F_ZERO  = 64'h0000000000000000;  // +0.0

  // -----------------------------------------------------------------------
  // Cumulative latency to the output of each stage.
  // (all *_LAT >= 1  =>  L10 >= 10)
  // -----------------------------------------------------------------------
  localparam int L1  = SUB_LAT;              // cp        ready
  localparam int L2  = L1 + MUL_LAT;         // m*/n*     ready
  localparam int L3  = L2 + ADD_LAT;         // sv/sc     ready
  localparam int L4  = L3 + ADD_LAT;         // v / cpcp  ready
  localparam int L5  = L4 + MUL_LAT;         // v2        ready
  localparam int L6  = L5 + SUB_LAT;         // inner     ready
  localparam int L7  = L6 + SUB_LAT;         // disc      ready
  localparam int L8  = L7 + SQRT_LAT;        // sqrt(disc) ready  (long pole)
  localparam int L9  = L8 + SUB_LAT;         // t_raw     ready
  localparam int L10 = L9 + CMP_LAT;         // t_gt      ready
  localparam int LATENCY = L10 + 1;          // + output register

  // =======================================================================
  // Stage 1 : cp = center - ray_point
  // =======================================================================
  logic [DW-1:0] cpx, cpy, cpz;
  fp_sub #(.LATENCY(SUB_LAT)) u_cpx (.clk(clk), .a(sphere_cx), .b(ray_point_x), .y(cpx));
  fp_sub #(.LATENCY(SUB_LAT)) u_cpy (.clk(clk), .a(sphere_cy), .b(ray_point_y), .y(cpy));
  fp_sub #(.LATENCY(SUB_LAT)) u_cpz (.clk(clk), .a(sphere_cz), .b(ray_point_z), .y(cpz));

  // =======================================================================
  // Stage 2 : the six products.  dir_* delayed L1 to meet cp.
  // =======================================================================
  logic [DW-1:0] dxd, dyd, dzd;
  vdelay #(.WIDTH(DW), .N(L1)) d_dx (.d(ray_dir_x), .clk(clk), .q(dxd));
  vdelay #(.WIDTH(DW), .N(L1)) d_dy (.d(ray_dir_y), .clk(clk), .q(dyd));
  vdelay #(.WIDTH(DW), .N(L1)) d_dz (.d(ray_dir_z), .clk(clk), .q(dzd));

  logic [DW-1:0] m0, m1, m2, n0, n1, n2;
  fp_mul #(.LATENCY(MUL_LAT)) u_m0 (.clk(clk), .a(cpx), .b(dxd), .y(m0));  // cp.x*dir.x
  fp_mul #(.LATENCY(MUL_LAT)) u_m1 (.clk(clk), .a(cpy), .b(dyd), .y(m1));  // cp.y*dir.y
  fp_mul #(.LATENCY(MUL_LAT)) u_m2 (.clk(clk), .a(cpz), .b(dzd), .y(m2));  // cp.z*dir.z
  fp_mul #(.LATENCY(MUL_LAT)) u_n0 (.clk(clk), .a(cpx), .b(cpx), .y(n0));  // cp.x*cp.x
  fp_mul #(.LATENCY(MUL_LAT)) u_n1 (.clk(clk), .a(cpy), .b(cpy), .y(n1));  // cp.y*cp.y
  fp_mul #(.LATENCY(MUL_LAT)) u_n2 (.clk(clk), .a(cpz), .b(cpz), .y(n2));  // cp.z*cp.z

  // =======================================================================
  // Stage 3 : first add of each dot product
  //   sv = m0 + m1 ,  sc = n0 + n1
  // =======================================================================
  logic [DW-1:0] sv, sc;
  fp_add #(.LATENCY(ADD_LAT)) u_sv (.clk(clk), .a(m0), .b(m1), .y(sv));
  fp_add #(.LATENCY(ADD_LAT)) u_sc (.clk(clk), .a(n0), .b(n1), .y(sc));

  // =======================================================================
  // Stage 4 : v = sv + m2 ,  cpcp = sc + n2.  m2/n2 delayed one add.
  // =======================================================================
  logic [DW-1:0] m2d, n2d;
  vdelay #(.WIDTH(DW), .N(ADD_LAT)) d_m2 (.d(m2), .clk(clk), .q(m2d));
  vdelay #(.WIDTH(DW), .N(ADD_LAT)) d_n2 (.d(n2), .clk(clk), .q(n2d));

  logic [DW-1:0] v, cpcp;
  fp_add #(.LATENCY(ADD_LAT)) u_v    (.clk(clk), .a(sv), .b(m2d), .y(v));
  fp_add #(.LATENCY(ADD_LAT)) u_cpcp (.clk(clk), .a(sc), .b(n2d), .y(cpcp));

  // =======================================================================
  // Stage 5 : v2 = v * v
  // =======================================================================
  logic [DW-1:0] v2;
  fp_mul #(.LATENCY(MUL_LAT)) u_v2 (.clk(clk), .a(v), .b(v), .y(v2));

  // =======================================================================
  // Stage 6 : inner = cpcp - v2.  cpcp delayed one mul.
  // =======================================================================
  logic [DW-1:0] cpcpd;
  vdelay #(.WIDTH(DW), .N(MUL_LAT)) d_cpcp (.d(cpcp), .clk(clk), .q(cpcpd));

  logic [DW-1:0] inner;
  fp_sub #(.LATENCY(SUB_LAT)) u_inner (.clk(clk), .a(cpcpd), .b(v2), .y(inner));

  // =======================================================================
  // Stage 7 : disc = radius_squared - inner.  r2 delayed L6.
  // =======================================================================
  logic [DW-1:0] r2d;
  vdelay #(.WIDTH(DW), .N(L6)) d_r2 (.d(sphere_r2), .clk(clk), .q(r2d));

  logic [DW-1:0] disc;
  fp_sub #(.LATENCY(SUB_LAT)) u_disc (.clk(clk), .a(r2d), .b(inner), .y(disc));

  // =======================================================================
  // Stage 8 : sqrt(disc)  ||  (disc < 0) test, in parallel
  // =======================================================================
  logic [DW-1:0] sq;
  logic          disc_lt0;
  fp_sqrt #(.LATENCY(SQRT_LAT)) u_sqrt    (.clk(clk), .a(disc),            .y(sq));
  fp_lt   #(.LATENCY(CMP_LAT))  u_disc_neg (.clk(clk), .a(disc), .b(F_ZERO), .y(disc_lt0));

  // =======================================================================
  // Stage 9 : t = v - sqrt(disc).  v delayed from L4 to L8.
  // =======================================================================
  logic [DW-1:0] vd;
  vdelay #(.WIDTH(DW), .N(L8 - L4)) d_v (.d(v), .clk(clk), .q(vd));

  logic [DW-1:0] t_raw;
  fp_sub #(.LATENCY(SUB_LAT)) u_t (.clk(clk), .a(vd), .b(sq), .y(t_raw));

  // =======================================================================
  // Stage 10 : t > -EPSILON
  // =======================================================================
  logic t_gt;
  fp_gt #(.LATENCY(CMP_LAT)) u_t_gt (.clk(clk), .a(t_raw), .b(NEG_EPS), .y(t_gt));

  // align disc_lt0 (ready at L7+CMP_LAT) and t_raw (ready at L9) to L10
  logic          disc_lt0_a;
  logic [DW-1:0] t_raw_a;
  vdelay #(.WIDTH(1),  .N(L10 - (L7 + CMP_LAT))) d_dlt0 (.d(disc_lt0), .clk(clk), .q(disc_lt0_a));
  vdelay #(.WIDTH(DW), .N(CMP_LAT))              d_traw (.d(t_raw),    .clk(clk), .q(t_raw_a));

  // =======================================================================
  // Passenger pipeline : sphere_index + in_valid, depth L10
  // =======================================================================
  logic [IDX_W-1:0] idx_a;
  vdelay #(.WIDTH(IDX_W), .N(L10)) d_idx (.d(sphere_index), .clk(clk), .q(idx_a));

  logic [L10-1:0] vpipe;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) vpipe <= '0;
    else        vpipe <= {vpipe[L10-2:0], in_valid};
  end
  wire valid_a = vpipe[L10-1];

  // =======================================================================
  // Stage 11 : registered outputs (this register is the final "+1" that
  // makes the total pipeline latency exactly LATENCY = L10 + 1)
  // =======================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid        <= 1'b0;
      hit_valid        <= 1'b0;
      sphere_index_out <= '0;
      t                <= '0;
    end
    else begin
      out_valid        <= valid_a;
      hit_valid        <= valid_a & ~disc_lt0_a & t_gt;
      sphere_index_out <= idx_a;
      t                <= t_raw_a;
    end
  end

`ifndef SYNTHESIS
  initial begin
    // Fires at elaboration if the latency arithmetic ever goes non-positive.
    if (SUB_LAT < 1 || ADD_LAT < 1 || MUL_LAT < 1 || SQRT_LAT < 1 || CMP_LAT < 1)
      $fatal(1, "sphere_intersection_pipeline: every *_LAT must be >= 1");
    $display("sphere_intersection_pipeline: LATENCY = %0d cycles", LATENCY);
  end
`endif

endmodule

`default_nettype wire
