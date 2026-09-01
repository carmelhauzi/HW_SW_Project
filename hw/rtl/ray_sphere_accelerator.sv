// ---------------------------------------------------------------------------
// ray_sphere_accelerator.sv
//
// Top module of the raytrace sphere-intersection accelerator.  Connects
//
//     sphere_storage  ->  sphere_intersection_pipeline  ->  sphere_min_reducer
//
// and runs a 3-state FSM that processes ONE ray at a time:
//
//   S_IDLE   : ready = 1.  On ray_start: latch the ray, clear the previous
//              result, pulse `clear` to the reducer, go to S_STREAM.
//   S_STREAM : 7 cycles.  Feed spheres 0..6 from sphere_storage into the
//              pipeline, one per clock (in_valid = 1, sphere_index = count).
//              On the count == N_SPHERES-1 cycle, go to S_WAIT.
//   S_WAIT   : in_valid = 0.  Wait for the reducer's result_valid pulse,
//              then latch {hit_valid, sphere_index, t} and raise the sticky
//              output result_valid.  Go to S_IDLE.
//
// The pipeline drains fully between rays, so there is never cross-ray
// contamination.  Software setup writes are forwarded straight to
// sphere_storage.
//
// Software use:
//   1. load all N_SPHERES*4 words via setup_we/addr/wdata (see sphere_storage)
//   2. wait for ready, then drive ray_point_*/ray_dir_* with ray_start = 1
//      for one cycle
//   3. poll result_valid; when set, read result_hit_valid / _sphere_index / _t
//   Then the Python side compares result_t with the Halfspace t (strict <).
// ---------------------------------------------------------------------------

`default_nettype none

module ray_sphere_accelerator #(
  parameter int DW        = 64,   // IEEE-754 binary64
  parameter int IDX_W     = 3,    // sphere index 0..6
  parameter int N_SPHERES = 7,
  // FP leaf-cell latencies, forwarded to sphere_intersection_pipeline
  parameter int SUB_LAT   = 3,
  parameter int ADD_LAT   = 3,
  parameter int MUL_LAT   = 3,
  parameter int SQRT_LAT  = 16,
  parameter int CMP_LAT   = 1,
  // derived -- do not override
  parameter int AW = $clog2(N_SPHERES * 4)
) (
  input  wire               clk,
  input  wire               rst_n,

  // ---- software setup port -> sphere_storage ----
  input  wire               setup_we,
  input  wire  [AW-1:0]     setup_addr,
  input  wire  [DW-1:0]     setup_wdata,

  // ---- ray input (start handshake) ----
  output wire               ready,        // 1 in S_IDLE: ray_start accepted this cycle
  input  wire               ray_start,
  input  wire  [DW-1:0]     ray_point_x,
  input  wire  [DW-1:0]     ray_point_y,
  input  wire  [DW-1:0]     ray_point_z,
  input  wire  [DW-1:0]     ray_dir_x,
  input  wire  [DW-1:0]     ray_dir_y,
  input  wire  [DW-1:0]     ray_dir_z,

  // ---- result (sticky until the next accepted ray_start) ----
  output logic              result_valid,
  output logic              result_hit_valid,
  output logic [IDX_W-1:0]  result_sphere_index,
  output logic [DW-1:0]     result_t
);

  // -----------------------------------------------------------------------
  // FSM state + sphere counter + latched ray operands
  // -----------------------------------------------------------------------
  typedef enum logic [1:0] { S_IDLE, S_STREAM, S_WAIT } state_e;
  state_e state;

  localparam int CNT_W = $clog2(N_SPHERES);
  logic [CNT_W-1:0] count;

  logic [DW-1:0] ray_px_r, ray_py_r, ray_pz_r;
  logic [DW-1:0] ray_dx_r, ray_dy_r, ray_dz_r;

  assign ready = (state == S_IDLE);

  // -----------------------------------------------------------------------
  // Combinational control
  // -----------------------------------------------------------------------
  wire             accept      = (state == S_IDLE) && ray_start;
  wire             streaming   = (state == S_STREAM);
  wire             clear_pulse = accept;                      // arm reducer 1 cycle before streaming
  wire [IDX_W-1:0] sph_index   = streaming ? IDX_W'(count) : '0;

  // -----------------------------------------------------------------------
  // sphere_storage  (combinational read of sphere `sph_index`)
  // -----------------------------------------------------------------------
  wire [DW-1:0] rd_cx, rd_cy, rd_cz, rd_r2;

  sphere_storage #(
    .DW(DW), .IDX_W(IDX_W), .N_SPHERES(N_SPHERES)
  ) u_storage (
    .clk        (clk),
    .rst_n      (rst_n),
    .setup_we   (setup_we),
    .setup_addr (setup_addr),
    .setup_wdata(setup_wdata),
    .rd_index   (sph_index),
    .rd_cx      (rd_cx),
    .rd_cy      (rd_cy),
    .rd_cz      (rd_cz),
    .rd_r2      (rd_r2)
  );

  // -----------------------------------------------------------------------
  // sphere_intersection_pipeline
  // -----------------------------------------------------------------------
  wire             pipe_out_valid;
  wire             pipe_hit_valid;
  wire [IDX_W-1:0] pipe_index_out;
  wire [DW-1:0]    pipe_t;

  sphere_intersection_pipeline #(
    .DW(DW), .IDX_W(IDX_W),
    .SUB_LAT(SUB_LAT), .ADD_LAT(ADD_LAT), .MUL_LAT(MUL_LAT),
    .SQRT_LAT(SQRT_LAT), .CMP_LAT(CMP_LAT)
  ) u_pipe (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_valid        (streaming),
    .sphere_index    (sph_index),
    .ray_point_x     (ray_px_r),
    .ray_point_y     (ray_py_r),
    .ray_point_z     (ray_pz_r),
    .ray_dir_x       (ray_dx_r),
    .ray_dir_y       (ray_dy_r),
    .ray_dir_z       (ray_dz_r),
    .sphere_cx       (rd_cx),
    .sphere_cy       (rd_cy),
    .sphere_cz       (rd_cz),
    .sphere_r2       (rd_r2),
    .out_valid       (pipe_out_valid),
    .hit_valid       (pipe_hit_valid),
    .sphere_index_out(pipe_index_out),
    .t               (pipe_t)
  );

  // -----------------------------------------------------------------------
  // sphere_min_reducer
  // -----------------------------------------------------------------------
  wire             red_result_valid;
  wire             red_best_valid;
  wire [IDX_W-1:0] red_best_index;
  wire [DW-1:0]    red_best_t;

  sphere_min_reducer #(
    .DW(DW), .IDX_W(IDX_W), .N_RESULTS(N_SPHERES)
  ) u_reducer (
    .clk         (clk),
    .rst_n       (rst_n),
    .clear       (clear_pulse),
    .in_valid    (pipe_out_valid),
    .in_hit_valid(pipe_hit_valid),
    .in_t        (pipe_t),
    .in_index    (pipe_index_out),
    .result_valid(red_result_valid),
    .best_valid  (red_best_valid),
    .best_index  (red_best_index),
    .best_t      (red_best_t)
  );

  // -----------------------------------------------------------------------
  // FSM + datapath registers
  // -----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state               <= S_IDLE;
      count               <= '0;
      ray_px_r <= '0; ray_py_r <= '0; ray_pz_r <= '0;
      ray_dx_r <= '0; ray_dy_r <= '0; ray_dz_r <= '0;
      result_valid        <= 1'b0;
      result_hit_valid    <= 1'b0;
      result_sphere_index <= '0;
      result_t            <= '0;
    end
    else begin
      case (state)

        S_IDLE: begin
          if (ray_start) begin
            ray_px_r <= ray_point_x; ray_py_r <= ray_point_y; ray_pz_r <= ray_point_z;
            ray_dx_r <= ray_dir_x;   ray_dy_r <= ray_dir_y;   ray_dz_r <= ray_dir_z;
            result_valid <= 1'b0;          // drop the previous ray's result
            count        <= '0;
            state        <= S_STREAM;
          end
        end

        S_STREAM: begin
          // sphere `count` is being fed this cycle (in_valid = streaming)
          if (count == CNT_W'(N_SPHERES - 1))
            state <= S_WAIT;               // sphere N_SPHERES-1 fed now
          else
            count <= count + CNT_W'(1);
        end

        S_WAIT: begin
          if (red_result_valid) begin
            result_hit_valid    <= red_best_valid;
            result_sphere_index <= red_best_index;
            result_t            <= red_best_t;
            result_valid        <= 1'b1;
            state               <= S_IDLE;
          end
        end

        default: state <= S_IDLE;

      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk)
    if (rst_n && ray_start && state != S_IDLE)
      $warning("ray_sphere_accelerator: ray_start ignored, busy (state=%0d)", int'(state));
`endif

endmodule

`default_nettype wire
