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
 *   - Background checkerboard pattern (16x16 tiles, XOR of pix_x[4] ^ pix_y[4])
 *   - CRT scanline effect: every odd row darkened by halving each channel
 *   - GLITCH MODE: VHS corruption effect on ui_in[7] press + random auto-glitch
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
  wire cfg_tile     = ui_in[0];
  wire cfg_color    = ui_in[1];
  wire cfg_invert   = ui_in[2];
  wire cfg_slow     = ui_in[3];
  wire cfg_flip     = ui_in[4];
  wire cfg_checker  = ui_in[5];
  wire cfg_scanline = ui_in[6];
  wire cfg_glitch   = ui_in[7];

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

  // ── Speed divider ────────────────────────────────────────────────────────────
  reg slow_tick;

  // ── Bounce flash ─────────────────────────────────────────────────────────────
  reg [2:0] flash_ctr;
  wire      flashing = (flash_ctr != 3'd0);

  // ── Glitch / corruption engine ──────────────────────────────────────────────
  // 8-bit LFSR (taps at 7,5,4,3)
  reg [7:0] glitch_lfsr;
  wire [7:0] glitch_lfsr_next = {glitch_lfsr[6:0], glitch_lfsr[7] ^ glitch_lfsr[5] ^ glitch_lfsr[4] ^ glitch_lfsr[3]};
  
  reg [1:0] glitch_state;      // 0=idle, 1=corrupt, 2=recover
  reg [3:0] glitch_timer;
  reg [2:0] glitch_intensity;
  reg       glitch_prev_btn;
  
  reg [7:0] auto_glitch_counter;
  wire      auto_glitch_trigger = (auto_glitch_counter == 8'd0) && cfg_glitch;
  
  wire      glitch_active = (glitch_state != 2'd0);
  
  // Horizontal XOR scrambling (improved: uses full intensity range)
  wire [9:0] glitch_mask_x = {5'b0, glitch_lfsr[4:0]} << glitch_intensity[2:0];
  wire [9:0] glitch_x = pix_x ^ glitch_mask_x;
  
  // Vertical XOR scrambling (fixed shift amount)
  wire [9:0] glitch_mask_y = {2'b0, glitch_lfsr[7:0]} >> glitch_intensity[2:0];
  wire [9:0] glitch_y = pix_y ^ glitch_mask_y;
  
  // Horizontal tearing: offset specific rows
  wire [9:0] tear_offset = {glitch_lfsr[5:2], 6'd0};
  wire       tear_active = glitch_active && glitch_lfsr[7] && (pix_y[4:0] == glitch_lfsr[4:0]);
  wire [9:0] tear_x_raw = pix_x + tear_offset;
  wire [9:0] tear_x = (tear_x_raw < DISPLAY_WIDTH) ? tear_x_raw : (tear_x_raw - DISPLAY_WIDTH);
  
  // Combine glitch effects: tearing on selected rows, otherwise XOR scrambling
  wire [9:0] active_x = glitch_active ? (tear_active ? tear_x : glitch_x) : pix_x;
  wire [9:0] active_y = glitch_active ? glitch_y : pix_y;

  // ── Colors ───────────────────────────────────────────────────────────────────
  reg  [2:0] color_index;
  wire [2:0] bg_color_index      = color_index + 3'd4;
  wire [2:0] checker_color_index = color_index + 3'd5;

  wire [5:0] logo_color_rgb;
  wire [5:0] bg_color_rgb;
  wire [5:0] checker_color_rgb;

  palette palette_logo (
      .color_index(cfg_color ? color_index         : 3'd7),
      .rrggbb     (logo_color_rgb)
  );

  palette palette_bg (
      .color_index(cfg_color ? bg_color_index      : 3'd0),
      .rrggbb     (bg_color_rgb)
  );

  palette palette_checker (
      .color_index(cfg_color ? checker_color_index : 3'd7),
      .rrggbb     (checker_color_rgb)
  );

  wire [5:0] fg_actual = flashing ? 6'b111111 : logo_color_rgb;
  wire [5:0] fg_rgb = cfg_invert ? bg_color_rgb : fg_actual;
  wire [5:0] bk_rgb = cfg_invert ? fg_actual    : bg_color_rgb;

  // ── Checkerboard background ─────────────────────────────────────────────────
  wire checker_bit = pix_x[4] ^ pix_y[4];
  wire [5:0] bk_checker = (cfg_checker && checker_bit) ? checker_color_rgb : bk_rgb;

  // ── Pixel lookup – current logo ──────────────────────────────────────────────
  wire [9:0] x = active_x - logo_left;
  wire [9:0] y = active_y - logo_top;
  wire in_logo = cfg_tile || (x < LOGO_WIDTH && y < LOGO_HEIGHT);
  wire pixel_value;

  wire [5:0] rom_y = cfg_flip ? (LOGO_HEIGHT - 1 - y[5:0]) : y[5:0];

  bitmap_rom rom1 (
      .x    (x[6:0]),
      .y    (rom_y),
      .pixel(pixel_value)
  );

  // ── CRT Scanline effect ───────────────────────────────────────────────────────
  wire scanline_dark = cfg_scanline && pix_y[0];

  // ── RGB output ────────────────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0; G <= 0; B <= 0;
    end else begin
      if (video_active) begin
        reg [1:0] pR, pG, pB;
        reg [1:0] gR, gG, gB;
        
        if (in_logo && pixel_value) begin
          pR = fg_rgb[5:4]; pG = fg_rgb[3:2]; pB = fg_rgb[1:0];
        end else begin
          pR = bk_checker[5:4]; pG = bk_checker[3:2]; pB = bk_checker[1:0];
        end
        
        if (glitch_active) begin
          // Chromatic aberration
          gR = pR ^ glitch_lfsr[1:0];
          gG = pG ^ glitch_lfsr[3:2];
          gB = pB ^ glitch_lfsr[5:4];
          
          // Channel swapping
          if (glitch_lfsr[6]) {gR, gG} = {gG, gR};
          if (glitch_lfsr[7]) {gG, gB} = {gB, gG};
          
          // Inversion flash
          if (glitch_intensity[2] && glitch_lfsr[0]) begin
            gR = ~gR;
            gG = ~gG;
            gB = ~gB;
          end
        end else begin
          gR = pR; gG = pG; gB = pB;
        end
        
        R <= scanline_dark ? {1'b0, gR[0]} : gR;
        G <= scanline_dark ? {1'b0, gG[0]} : gG;
        B <= scanline_dark ? {1'b0, gB[0]} : gB;
      end else begin
        R <= 0; G <= 0; B <= 0;
      end
    end
  end

  // ── Bouncing + color + flash + glitch update — vblank ──
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
      
      glitch_lfsr        <= 8'hFF;
      glitch_state       <= 2'd0;
      glitch_timer       <= 4'd0;
      glitch_intensity   <= 3'd0;
      glitch_prev_btn    <= 1'b0;
      auto_glitch_counter<= 8'd100;
    end else begin
      prev_y <= pix_y;

      if (pix_y == 10'd0 && prev_y != 10'd0) begin
        slow_tick <= ~slow_tick;

        if (flash_ctr != 3'd0)
          flash_ctr <= flash_ctr - 3'd1;

        // Glitch LFSR advance
        glitch_lfsr <= glitch_lfsr_next;
        
        glitch_prev_btn <= cfg_glitch;
        
        if (cfg_glitch) begin
          auto_glitch_counter <= auto_glitch_counter - 8'd1;
        end else begin
          auto_glitch_counter <= 8'd150;
        end
        
        case (glitch_state)
          2'd0: begin
            if ((cfg_glitch && !glitch_prev_btn) || auto_glitch_trigger) begin
              glitch_state     <= 2'd1;
              glitch_timer     <= 4'd2 + glitch_lfsr_next[3:0];
              glitch_intensity <= glitch_lfsr_next[2:0];
            end
          end
          2'd1: begin
            if (glitch_timer == 4'd0) begin
              glitch_state <= 2'd2;
              glitch_timer <= 4'd1;
            end else begin
              glitch_timer <= glitch_timer - 4'd1;
              if (glitch_lfsr_next[0]) 
                glitch_intensity <= glitch_intensity ^ glitch_lfsr_next[2:0];
            end
          end
          2'd2: begin
            if (glitch_timer == 4'd0)
              glitch_state <= 2'd0;
            else
              glitch_timer <= glitch_timer - 4'd1;
          end
          default: glitch_state <= 2'd0;
        endcase

        if (!cfg_slow || slow_tick) begin
          logo_left <= logo_left + (dir_x ? 10'd1 : -10'd1);
          logo_top  <= logo_top  + (dir_y ? 10'd1 : -10'd1);

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
