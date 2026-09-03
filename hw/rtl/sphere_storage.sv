// ---------------------------------------------------------------------------
// sphere_storage.sv
//
// Holds the parameters of the 7 spheres for one render:
//   center_x, center_y, center_z, radius_squared   (real = IEEE-754 double)
//
// Ports:
//   * setup / write  -- software loads every field once per render, one word
//     per write.  setup_addr = sphere_index*4 + field,
//     field 0..3 = center_x, center_y, center_z, radius_squared.
//   * streaming read -- rd_index (0..6) selects a sphere; its four fields
//     appear combinationally, so the top module can push one sphere per clock
//     into sphere_intersection_pipeline.
//
// radius_squared must be radius*radius, precomputed by software.
// Load all 28 words once, before feeding any rays.
// ---------------------------------------------------------------------------

module sphere_storage (
  input  logic        clk,

  // setup / write port
  input  logic        setup_we,
  input  logic [4:0]  setup_addr,     // sphere*4 + field  (0..27)
  input  real         setup_wdata,

  // streaming read port
  input  logic [2:0]  rd_index,       // 0..6
  output real         rd_cx,
  output real         rd_cy,
  output real         rd_cz,
  output real         rd_r2
);

  real mem [0:27];                    // 7 spheres x {cx, cy, cz, r2}

  always_ff @(posedge clk)
    if (setup_we)
      mem[setup_addr] <= setup_wdata;

  always_comb begin
    rd_cx = mem[rd_index*4 + 0];
    rd_cy = mem[rd_index*4 + 1];
    rd_cz = mem[rd_index*4 + 2];
    rd_r2 = mem[rd_index*4 + 3];
  end

endmodule
