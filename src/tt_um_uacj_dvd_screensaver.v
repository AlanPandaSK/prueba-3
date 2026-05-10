/*
 * Original VGA framework: Copyright (c) 2024 Tiny Tapeout LTD (Apache-2.0)
 * Original author: Uri Shaked
 *
 * This is a MODIFIED FORK of the original Tiny Tapeout VGA example.
 *
 * Modifications and DVD screensaver implementation: Alan Sigala (2026)
 * Changes:
 *   - Custom 128x40 logo bitmap
 *   - DVD bouncing behavior with color changes only on wall hits
 *   - Different background color (color_index + 4 offset)
 *   - Reduced logo size and adjusted timing
 *   - Added cfg_invert, cfg_slow, cfg_flip control inputs
 *   - Added visual flash effect on wall collisions
 *
 * v2 additions (light features):
 *   - Background checkerboard pattern (16x16 tiles, XOR of pix_x[4] ^ pix_y[4])
 *   - Trail effect: two previous logo positions drawn at dimmed color
 *   - CRT scanline effect: every odd row darkened by halving each channel
 */

`default_nettype none

parameter LOGO_WIDTH     = 128;
parameter LOGO_HEIGHT    = 40;
parameter DISPLAY_WIDTH  = 640;
parameter DISPLAY_HEIGHT = 480;

module tt_um_uacj_dvd_screensaver (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ── VGA signals ─────────────────────────────────────────────────────────────
  wire hsync, vsync;
  reg  [1:0] R, G, B;
  wire video_active;
  wire [9:0] pix_x, pix_y;

  // ── Pin map ──────────────────────────────────────────────────────────────────
  //  ui_in[0]  cfg_tile        – bitmap as tile (debug)
  //  ui_in[1]  cfg_color       – 0=black/white  1=color palette
  //  ui_in[2]  cfg_invert      – swap logo and background colors
  //  ui_in[3]  cfg_slow        – 0=1px/frame  1=1px/2frames
  //  ui_in[4]  cfg_flip        – flip logo upside-down
  //  ui_in[5]  cfg_checker     – enable background checkerboard pattern
  //  ui_in[6]  cfg_trail       – enable logo trail
  //  ui_in[7]  cfg_scanline    – enable CRT scanline effect
  wire cfg_tile     = ui_in[0];
  wire cfg_color    = ui_in[1];
  wire cfg_invert   = ui_in[2];
  wire cfg_slow     = ui_in[3];
  wire cfg_flip     = ui_in[4];
  wire cfg_checker  = ui_in[5];
  wire cfg_trail    = ui_in[6];
  wire cfg_scanline = ui_in[7];

  // ── TinyVGA PMOD ─────────────────────────────────────────────────────────────
  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  wire _unused_ok = &{ena, uio_in};

  // ── VGA sync ─────────────────────────────────────────────────────────────────
  hvsync_generator vga_sync_gen (
      .clk       (clk),
      .reset     (~rst_n),
      .hsync     (hsync),
      .vsync     (vsync),
      .display_on(video_active),
      .hpos      (pix_x),
      .vpos      (pix_y)
  );

  // ── Logo position & direction ────────────────────────────────────────────────
  reg [9:0] logo_left, logo_top;
  reg       dir_x, dir_y;
  reg [9:0] prev_y;

  // ── Trail positions (two frames back) ───────────────────────────────────────
  reg [9:0] trail1_left, trail1_top;   // 1 frame behind
  reg [9:0] trail2_left, trail2_top;   // 2 frames behind

  // ── Speed divider ────────────────────────────────────────────────────────────
  reg slow_tick;

  // ── Bounce flash ─────────────────────────────────────────────────────────────
  reg [2:0] flash_ctr;
  wire      flashing = (flash_ctr != 3'd0);

  // ── Colors ───────────────────────────────────────────────────────────────────
  reg  [2:0] color_index;
  wire [2:0] bg_color_index      = color_index + 3'd4;
  wire [2:0] dim_color_index     = color_index + 3'd2;  // trail: shifted 2 steps
  wire [2:0] checker_color_index = color_index + 3'd5;  // checker alt tile: shifted 5 steps

  wire [5:0] logo_color_rgb;
  wire [5:0] bg_color_rgb;
  wire [5:0] dim_color_rgb;
  wire [5:0] checker_color_rgb;

  palette palette_logo (
      .color_index(cfg_color ? color_index         : 3'd7),
      .rrggbb     (logo_color_rgb)
  );

  palette palette_bg (
      .color_index(cfg_color ? bg_color_index      : 3'd0),
      .rrggbb     (bg_color_rgb)
  );

  palette palette_dim (
      .color_index(cfg_color ? dim_color_index     : 3'd0),
      .rrggbb     (dim_color_rgb)
  );

  // Checker alternate tile: a different palette entry so contrast is guaranteed
  // in both color and b&w modes. In b&w mode uses white (3'd7) vs black (3'd0).
  palette palette_checker (
      .color_index(cfg_color ? checker_color_index : 3'd7),
      .rrggbb     (checker_color_rgb)
  );

  // During flash, logo is white
  wire [5:0] fg_actual = flashing ? 6'b111111 : logo_color_rgb;

  // cfg_invert swaps fg/bg
  wire [5:0] fg_rgb = cfg_invert ? bg_color_rgb : fg_actual;
  wire [5:0] bk_rgb = cfg_invert ? fg_actual    : bg_color_rgb;

  // ── Checkerboard background — alternates between bk_rgb and checker_color_rgb
  wire checker_bit = pix_x[4] ^ pix_y[4];
  wire [5:0] bk_checker = (cfg_checker && checker_bit) ? checker_color_rgb : bk_rgb;

  // ── Pixel lookup – current logo ──────────────────────────────────────────────
  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;
  wire in_logo = cfg_tile || (x < LOGO_WIDTH && y < LOGO_HEIGHT);
  wire pixel_value;

  wire [5:0] rom_y = cfg_flip ? (LOGO_HEIGHT - 1 - y[5:0]) : y[5:0];

  bitmap_rom rom1 (
      .x    (x[6:0]),
      .y    (rom_y),
      .pixel(pixel_value)
  );

  // ── Trail pixel lookup – 1 frame behind ─────────────────────────────────────
  wire [9:0] tx1 = pix_x - trail1_left;
  wire [9:0] ty1 = pix_y - trail1_top;
  wire in_trail1 = (tx1 < LOGO_WIDTH && ty1 < LOGO_HEIGHT);
  wire trail1_pixel;

  wire [5:0] trail1_rom_y = cfg_flip ? (LOGO_HEIGHT - 1 - ty1[5:0]) : ty1[5:0];

  bitmap_rom rom_trail1 (
      .x    (tx1[6:0]),
      .y    (trail1_rom_y),
      .pixel(trail1_pixel)
  );

  // ── Trail pixel lookup – 2 frames behind ────────────────────────────────────
  wire [9:0] tx2 = pix_x - trail2_left;
  wire [9:0] ty2 = pix_y - trail2_top;
  wire in_trail2 = (tx2 < LOGO_WIDTH && ty2 < LOGO_HEIGHT);
  wire trail2_pixel;

  wire [5:0] trail2_rom_y = cfg_flip ? (LOGO_HEIGHT - 1 - ty2[5:0]) : ty2[5:0];

  bitmap_rom rom_trail2 (
      .x    (tx2[6:0]),
      .y    (trail2_rom_y),
      .pixel(trail2_pixel)
  );

  // ── CRT Scanline effect ───────────────────────────────────────────────────────
  // Every odd scanline (pix_y[0] == 1) gets its brightness halved by dropping
  // the MSB of each 2-bit channel, simulating the dark gap between CRT phosphor rows.
  wire scanline_dark = cfg_scanline && pix_y[0];

  // ── RGB output ────────────────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0; G <= 0; B <= 0;
    end else begin
      if (video_active) begin
        // ── Select pixel color ───────────────────────────────────────────
        reg [1:0] pR, pG, pB;
        if (in_logo && pixel_value) begin
          pR = fg_rgb[5:4]; pG = fg_rgb[3:2]; pB = fg_rgb[1:0];
        end else if (cfg_trail && in_trail1 && trail1_pixel) begin
          pR = dim_color_rgb[5:4]; pG = dim_color_rgb[3:2]; pB = dim_color_rgb[1:0];
        end else if (cfg_trail && in_trail2 && trail2_pixel) begin
          pR = {1'b0, dim_color_rgb[5]}; pG = {1'b0, dim_color_rgb[3]}; pB = {1'b0, dim_color_rgb[1]};
        end else begin
          pR = bk_checker[5:4]; pG = bk_checker[3:2]; pB = bk_checker[1:0];
        end
        // ── Apply scanline dimming: drop MSB on odd rows ─────────────────
        R <= scanline_dark ? {1'b0, pR[0]} : pR;
        G <= scanline_dark ? {1'b0, pG[0]} : pG;
        B <= scanline_dark ? {1'b0, pB[0]} : pB;
      end else begin
        R <= 0; G <= 0; B <= 0;
      end
    end
  end

  // ── Bouncing + color + flash + trail update — ONLY during vertical blanking ──
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left    <= 10'd200;
      logo_top     <= 10'd200;
      dir_x        <= 1'b1;
      dir_y        <= 1'b0;
      color_index  <= 3'd0;
      flash_ctr    <= 3'd0;
      slow_tick    <= 1'b0;
      prev_y       <= 10'd0;
      trail1_left  <= 10'd200;
      trail1_top   <= 10'd200;
      trail2_left  <= 10'd200;
      trail2_top   <= 10'd200;
    end else begin
      prev_y <= pix_y;

      if (pix_y == 10'd0 && prev_y != 10'd0) begin

        // ── Toggle slow_tick every frame ──────────────────────────────
        slow_tick <= ~slow_tick;

        // ── Decrement flash counter ───────────────────────────────────
        if (flash_ctr != 3'd0)
          flash_ctr <= flash_ctr - 3'd1;

        // Only move and bounce when appropriate according to cfg_slow
        if (!cfg_slow || slow_tick) begin

          // ── Shift trail positions before moving ──────────────────────
          trail2_left <= trail1_left;
          trail2_top  <= trail1_top;
          trail1_left <= logo_left;
          trail1_top  <= logo_top;

          // ── Move 1 pixel ─────────────────────────────────────────────
          logo_left <= logo_left + (dir_x ? 10'd1 : -10'd1);
          logo_top  <= logo_top  + (dir_y ? 10'd1 : -10'd1);

          // ── Horizontal bounce ────────────────────────────────────────
          if (!dir_x && logo_left <= 10'd1) begin
            dir_x        <= 1'b1;
            color_index  <= color_index + 3'd1;
            flash_ctr    <= 3'd6;
          end
          if (dir_x && logo_left + 10'd1 >= DISPLAY_WIDTH - LOGO_WIDTH) begin
            dir_x        <= 1'b0;
            color_index  <= color_index + 3'd1;
            flash_ctr    <= 3'd6;
          end

          // ── Vertical bounce ──────────────────────────────────────────
          if (!dir_y && logo_top <= 10'd1) begin
            dir_y        <= 1'b1;
            color_index  <= color_index + 3'd1;
            flash_ctr    <= 3'd6;
          end
          if (dir_y && logo_top + 10'd1 >= DISPLAY_HEIGHT - LOGO_HEIGHT) begin
            dir_y        <= 1'b0;
            color_index  <= color_index + 3'd1;
            flash_ctr    <= 3'd6;
          end

        end
      end
    end
  end

endmodule
