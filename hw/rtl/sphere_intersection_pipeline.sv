// ---------------------------------------------------------------------------
// sphere_intersection_pipeline.sv
//
// Behavioral 5-stage pipeline that reproduces CPython's Sphere.intersectionTime
// for one (ray, sphere) pair per clock.
//
//   * All arithmetic is SystemVerilog `real` (IEEE-754 double, identical to
//     Python's float / math.sqrt).
//   * One clock per stage, pipeline registers between the stages.
//   * Initiation interval = 1: a sphere may enter every clock, so up to 5 are
//     in flight at once.  A sphere entering with in_valid = 1 on cycle T
//     produces its result on cycle T + 5 with out_valid = 1, carrying the
//     sphere_index that entered with it.
//
// Math, in the SAME operation order as the Python:
//   cp   = center - ray_point
//   v    = (cp.x*dir.x + cp.y*dir.y) + cp.z*dir.z
//   cpcp = (cp.x*cp.x + cp.y*cp.y) + cp.z*cp.z
//   disc = radius_squared - (cpcp - v*v)
//   hit  = disc >= 0                              (Python: disc < 0 -> None)
//   t    = v - sqrt(disc)
//   hit_valid = hit && (t > -EPSILON)             EPSILON = 1e-5
// ---------------------------------------------------------------------------

module sphere_intersection_pipeline (
  input  logic       clk,
  input  logic       rst_n,          // clears the valid pipe

  input  logic       in_valid,
  input  logic [2:0] sphere_index,

  // ray operands (held constant by the caller across a ray's 7 spheres)
  input  real        ray_point_x,
  input  real        ray_point_y,
  input  real        ray_point_z,
  input  real        ray_dir_x,
  input  real        ray_dir_y,
  input  real        ray_dir_z,

  // sphere operands (one per clock)
  input  real        sphere_cx,
  input  real        sphere_cy,
  input  real        sphere_cz,
  input  real        sphere_r2,

  output logic       out_valid,
  output logic       hit_valid,
  output logic [2:0] sphere_index_out,
  output real        t
);

  localparam real EPSILON = 1e-5;    // matches Python  EPSILON = 0.00001
  // latency from in_valid to out_valid = 5 clocks

  // ---- Stage 1 : cp = center - ray_point ----
  real        cpx1, cpy1, cpz1;
  real        dx1, dy1, dz1;         // ray direction, carried
  real        r2_1;                  // radius^2, carried
  logic [2:0] idx1;
  logic       vld1;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) vld1 <= 1'b0;
    else begin
      cpx1 <= sphere_cx - ray_point_x;
      cpy1 <= sphere_cy - ray_point_y;
      cpz1 <= sphere_cz - ray_point_z;
      dx1  <= ray_dir_x;
      dy1  <= ray_dir_y;
      dz1  <= ray_dir_z;
      r2_1 <= sphere_r2;
      idx1 <= sphere_index;
      vld1 <= in_valid;
    end

  // ---- Stage 2 : the six products ----
  real        pvx2, pvy2, pvz2;      // cp .* dir
  real        pcx2, pcy2, pcz2;      // cp .* cp
  real        r2_2;
  logic [2:0] idx2;
  logic       vld2;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) vld2 <= 1'b0;
    else begin
      pvx2 <= cpx1 * dx1;
      pvy2 <= cpy1 * dy1;
      pvz2 <= cpz1 * dz1;
      pcx2 <= cpx1 * cpx1;
      pcy2 <= cpy1 * cpy1;
      pcz2 <= cpz1 * cpz1;
      r2_2 <= r2_1;
      idx2 <= idx1;
      vld2 <= vld1;
    end

  // ---- Stage 3 : left-associative dot-product sums ----
  real        v3, cpcp3, r2_3;
  logic [2:0] idx3;
  logic       vld3;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) vld3 <= 1'b0;
    else begin
      v3    <= (pvx2 + pvy2) + pvz2;
      cpcp3 <= (pcx2 + pcy2) + pcz2;
      r2_3  <= r2_2;
      idx3  <= idx2;
      vld3  <= vld2;
    end

  // ---- Stage 4 : disc = radius_squared - (cpcp - v*v) ----
  real        v4, disc4;
  logic [2:0] idx4;
  logic       vld4;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) vld4 <= 1'b0;
    else begin
      v4    <= v3;
      disc4 <= r2_3 - (cpcp3 - (v3 * v3));
      idx4  <= idx3;
      vld4  <= vld3;
    end

  // ---- Stage 5 : sqrt, t = v - sqrt(disc), hit test -> registered outputs ----
  logic disc_ge0;
  real  sq5, t5;

  always_comb begin
    disc_ge0 = (disc4 >= 0.0);
    sq5      = disc_ge0 ? $sqrt(disc4) : 0.0;   // never sqrt a negative
    t5       = v4 - sq5;
  end

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      out_valid <= 1'b0;
      hit_valid <= 1'b0;
    end
    else begin
      out_valid        <= vld4;
      hit_valid        <= vld4 && disc_ge0 && (t5 > -EPSILON);
      sphere_index_out <= idx4;
      t                <= t5;
    end

endmodule
