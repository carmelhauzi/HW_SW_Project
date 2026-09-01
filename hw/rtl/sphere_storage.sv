// ---------------------------------------------------------------------------
// sphere_storage.sv
//
// Holds the parameters of the N_SPHERES spheres for one render:
//   center_x, center_y, center_z, radius_squared   (IEEE-754 binary64 each)
//
// Two ports:
//   * setup / write  -- software loads every field once per render, one
//     64-bit word per write, memory-mapped style.
//   * streaming read -- the top module drives rd_index (0..N_SPHERES-1) and
//     gets that sphere's four fields back COMBINATIONALLY, so it can push one
//     sphere per clock into sphere_intersection_pipeline.
//
// Address map for the setup port  (setup_addr = sphere_index*4 + field):
//
//     sphere s : addr s*4 + 0 = center_x
//                addr s*4 + 1 = center_y
//                addr s*4 + 2 = center_z
//                addr s*4 + 3 = radius_squared
//
//   e.g. sphere 0 -> addr 0..3,  sphere 6 -> addr 24..27.
//   radius_squared must be radius*radius, precomputed by software.
//   Load all N_SPHERES*4 words once at the start of each render, before
//   feeding any rays.
// ---------------------------------------------------------------------------

`default_nettype none

module sphere_storage #(
  parameter int DW        = 64,             // IEEE-754 binary64
  parameter int IDX_W     = 3,              // sphere index 0..6
  parameter int N_SPHERES = 7,
  // derived -- do not override
  parameter int NWORDS    = N_SPHERES * 4,  // 28
  parameter int AW        = $clog2(N_SPHERES * 4)   // 5
) (
  input  wire               clk,
  input  wire               rst_n,

  // ---- setup / write port (software) ----
  input  wire               setup_we,
  input  wire  [AW-1:0]     setup_addr,   // sphere_index*4 + field
  input  wire  [DW-1:0]     setup_wdata,

  // ---- streaming read port (to the intersection pipeline) ----
  input  wire  [IDX_W-1:0]  rd_index,     // 0 .. N_SPHERES-1
  output wire  [DW-1:0]     rd_cx,
  output wire  [DW-1:0]     rd_cy,
  output wire  [DW-1:0]     rd_cz,
  output wire  [DW-1:0]     rd_r2
);

  // field offsets inside a sphere's 4-word block
  localparam int FIELD_CX = 0;
  localparam int FIELD_CY = 1;
  localparam int FIELD_CZ = 2;
  localparam int FIELD_R2 = 3;

  // Storage.  Reset-cleared for clean simulation; remove the reset branch if
  // you want this to map to BRAM / LUTRAM in synthesis.
  logic [DW-1:0] mem [0:NWORDS-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NWORDS; i++)
        mem[i] <= '0;
    end
    else if (setup_we) begin
      if (setup_addr < AW'(NWORDS)) begin
        mem[setup_addr] <= setup_wdata;
      end
`ifndef SYNTHESIS
      else begin
        $warning("sphere_storage: setup write to addr %0d ignored (>= %0d)",
                 setup_addr, NWORDS);
      end
`endif
    end
  end

  // Combinational read of one sphere's four fields.
  assign rd_cx = mem[rd_index*4 + FIELD_CX];
  assign rd_cy = mem[rd_index*4 + FIELD_CY];
  assign rd_cz = mem[rd_index*4 + FIELD_CZ];
  assign rd_r2 = mem[rd_index*4 + FIELD_R2];

`ifndef SYNTHESIS
  always_ff @(posedge clk)
    if (rst_n && (rd_index > IDX_W'(N_SPHERES - 1)))
      $warning("sphere_storage: rd_index %0d out of range (> %0d)",
               rd_index, N_SPHERES - 1);
`endif

endmodule

`default_nettype wire
