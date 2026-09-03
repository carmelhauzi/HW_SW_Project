// ---------------------------------------------------------------------------
// ray_sphere_accelerator.sv
//
// Top module.  Connects
//
//   sphere_storage -> sphere_intersection_pipeline -> sphere_min_reducer
//
// and runs a 3-state FSM that processes ONE ray at a time:
//
//   S_IDLE   : ready = 1.  On ray_start: latch the ray, drop the old result,
//              pulse `clear` to the reducer, go to S_STREAM.
//   S_STREAM : 7 cycles.  Feed spheres 0..6 into the pipeline, one per clock
//              (in_valid = 1, sphere_index = count).
//   S_WAIT   : wait for the reducer's result_valid, latch {hit, index, t},
//              raise the sticky output result_valid, go to S_IDLE.
//
// The pipeline drains fully between rays, so there is never cross-ray
// contamination.
//
// Software: load the 7 spheres via setup_we/addr/wdata, then for each ray
// wait for `ready`, drive ray_point_*/ray_dir_* with ray_start = 1 for one
// cycle, poll result_valid, read result_*.  The Halfspace comparison is
// done afterwards in Python.
// ---------------------------------------------------------------------------

module ray_sphere_accelerator (
  input  logic        clk,
  input  logic        rst_n,

  // software setup port -> sphere_storage
  input  logic        setup_we,
  input  logic [4:0]  setup_addr,
  input  real         setup_wdata,

  // ray input (start handshake)
  output logic        ready,          // 1 in S_IDLE: ray_start accepted this cycle
  input  logic        ray_start,
  input  real         ray_point_x,
  input  real         ray_point_y,
  input  real         ray_point_z,
  input  real         ray_dir_x,
  input  real         ray_dir_y,
  input  real         ray_dir_z,

  // result (sticky until the next accepted ray_start)
  output logic        result_valid,
  output logic        result_hit_valid,
  output logic [2:0]  result_sphere_index,
  output real         result_t
);

  typedef enum logic [1:0] { S_IDLE, S_STREAM, S_WAIT } state_e;
  state_e     state;
  logic [2:0] count;                  // sphere being fed, 0..6

  // latched ray operands
  real ray_px, ray_py, ray_pz;
  real ray_dx, ray_dy, ray_dz;

  assign ready = (state == S_IDLE);

  wire       accept      = (state == S_IDLE) && ray_start;
  wire       streaming   = (state == S_STREAM);
  wire       clear_pulse = accept;                 // arm reducer 1 cycle before streaming
  wire [2:0] sph_index   = streaming ? count : 3'd0;

  // ---- sphere_storage (combinational read of sphere `sph_index`) ----
  real rd_cx, rd_cy, rd_cz, rd_r2;

  sphere_storage u_storage (
    .clk        (clk),
    .setup_we   (setup_we),
    .setup_addr (setup_addr),
    .setup_wdata(setup_wdata),
    .rd_index   (sph_index),
    .rd_cx      (rd_cx),
    .rd_cy      (rd_cy),
    .rd_cz      (rd_cz),
    .rd_r2      (rd_r2)
  );

  // ---- sphere_intersection_pipeline ----
  logic       pipe_out_valid, pipe_hit_valid;
  logic [2:0] pipe_index_out;
  real        pipe_t;

  sphere_intersection_pipeline u_pipe (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_valid        (streaming),
    .sphere_index    (sph_index),
    .ray_point_x     (ray_px),
    .ray_point_y     (ray_py),
    .ray_point_z     (ray_pz),
    .ray_dir_x       (ray_dx),
    .ray_dir_y       (ray_dy),
    .ray_dir_z       (ray_dz),
    .sphere_cx       (rd_cx),
    .sphere_cy       (rd_cy),
    .sphere_cz       (rd_cz),
    .sphere_r2       (rd_r2),
    .out_valid       (pipe_out_valid),
    .hit_valid       (pipe_hit_valid),
    .sphere_index_out(pipe_index_out),
    .t               (pipe_t)
  );

  // ---- sphere_min_reducer ----
  logic       red_result_valid, red_best_valid;
  logic [2:0] red_best_index;
  real        red_best_t;

  sphere_min_reducer u_reducer (
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

  // ---- FSM ----
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      state        <= S_IDLE;
      count        <= 3'd0;
      result_valid <= 1'b0;
    end
    else case (state)

      S_IDLE:
        if (ray_start) begin
          ray_px <= ray_point_x; ray_py <= ray_point_y; ray_pz <= ray_point_z;
          ray_dx <= ray_dir_x;   ray_dy <= ray_dir_y;   ray_dz <= ray_dir_z;
          result_valid <= 1'b0;                 // drop the previous ray's result
          count        <= 3'd0;
          state        <= S_STREAM;
        end

      S_STREAM:
        if (count == 3'd6) state <= S_WAIT;     // sphere 6 fed this cycle
        else               count <= count + 3'd1;

      S_WAIT:
        if (red_result_valid) begin
          result_hit_valid    <= red_best_valid;
          result_sphere_index <= red_best_index;
          result_t            <= red_best_t;
          result_valid        <= 1'b1;
          state               <= S_IDLE;
        end

      default: state <= S_IDLE;

    endcase

endmodule
