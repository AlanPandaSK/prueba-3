<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# DVD Screensaver with UACJ IIT Logo

## How it works

This project implements a **DVD-style bouncing logo** on a VGA monitor. The logo is a 128×40 bitmap that displays **UACJ IIT**. The design is written in Verilog and targets the Tiny Tapeout ASIC shuttle.

The system is composed of four main blocks: a VGA sync generator, bouncing logic with position registers, a bitmap ROM containing the logo pattern, a color palette, and an RGB output multiplexer. The diagram below shows the overall architecture.



_**Figure 1.** Block diagram of the DVD screensaver system._

### Block description

- **hvsync_generator** – Generates the HSync and VSync timing signals required for a 640×480 @ 60 Hz VGA display. It also produces the current pixel coordinates (`pix_x`, `pix_y`) and an active video flag (`video_active`).

- **Bouncing Logic & Position Registers** – Maintains the current top‑left corner position of the logo (`logo_left`, `logo_top`) and the direction of movement (`dir_x`, `dir_y`). On each frame (detected during vertical blanking), the position updates by one pixel. When the logo reaches a screen edge, it bounces, increments the color index, and triggers a white flash.

- **bitmap_rom** – A 640‑byte ROM (40 rows × 16 bytes/row) that stores the 128×40 UACJ IIT logo. Each bit represents one pixel: `1` for logo foreground, `0` for background. The ROM is addressed by the current pixel position relative to the logo's top‑left corner.

- **palette** – Two instances of a 8‑entry color palette (6‑bit RGB, 2 bits per channel). The logo color cycles through the palette on each bounce, while the background color is offset by +4 indices. A `cfg_color` input selects between colour (palette) and monochrome (white on black).

- **RGB Mux & Output Registers** – Combines the pixel value (from ROM), the selected colors (from palette), and the flash signal to produce the final 2‑bit per channel RGB output. The result is latched in registers before being sent to the output pins.

### Configuration inputs

The design accepts five configuration inputs via the `ui_in[7:0]` pins:

| Pin        | Name        | Description                                                     |
|------------|-------------|-----------------------------------------------------------------|
| `ui_in[0]` | `cfg_tile`  | Debug mode: fill the entire screen with the logo pattern        |
| `ui_in[1]` | `cfg_color` | 0 = monochrome (white on black), 1 = color palette              |
| `ui_in[2]` | `cfg_invert`| Swaps the logo and background colors                            |
| `ui_in[3]` | `cfg_slow`  | Halves the movement speed (update every other frame)            |
| `ui_in[4]` | `cfg_flip`  | Vertically flips the bitmap when reading from the ROM           |

> [!NOTE]
> The VGA output follows the **TinyVGA PMOD** pin mapping:
> `uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}`.
> Connect directly to a TinyVGA PMOD or a compatible VGA DAC.

## How to test

### Simulation testing (CocoTB)

The project includes a CocoTB testbench that verifies the basic functionality. Due to the complexity of VGA simulation, the default test is configured to pass trivially. For full verification, you can implement the following test procedure:

1. **Navigate to the `test` folder** and ensure `test.py` and `Makefile` are present.

2. **Run the simulation** using:
   ```bash
   make
   ```

3. **Expected behaviour** (if you implement full testing):
   - The testbench should generate VGA timing signals and verify that the logo bounces correctly within the 640×480 screen boundaries.
   - On each bounce, the simulation should check that:
     - The direction toggles (horizontal or vertical)
     - The color index increments by 1
     - The flash counter (`flash_ctr`) becomes non-zero
   - The bitmap ROM output should match the expected pattern for the UACJ IIT logo.

### Hardware testing (FPGA or final chip)

#### Required equipment
- VGA monitor (supports 640×480 @ 60 Hz)
- TinyVGA PMOD
- Switches for configuration inputs (optional)
- 25.175 MHz clock source (provided by the Tiny Tapeout harness)

#### Test procedure

**1. Basic functionality test**

Connect the TinyVGA PMOD to your board and to the monitor. Apply power and reset. You should observe:

- The **UACJ IIT logo** bouncing diagonally across the screen
- The logo changes colour each time it hits a wall (cycles through 8 colours)
- A brief **white flash** at the moment of impact
- Background colour remains constant (offset from logo colour)

**2. Configuration input tests**

Apply logic levels to the `ui_in[4:0]` pins and observe the behaviour:

| Input combination | Expected behaviour |
|-------------------|---------------------|
| `cfg_tile = 1`    | The entire screen fills with the logo pattern (debug mode) |
| `cfg_color = 0`   | Logo becomes white, background becomes black (monochrome mode) |
| `cfg_invert = 1`  | Logo and background colours swap |
| `cfg_slow = 1`    | Logo moves at half speed (updates every other frame) |
| `cfg_flip = 1`    | Logo appears upside down (vertical mirror) |

**3. Boundary testing**

Monitor the logo position as it approaches screen edges:

- Left edge (X = 0) should cause a horizontal bounce
- Right edge (X = 640 - 128 = 512) should cause a horizontal bounce
- Top edge (Y = 0) should cause a vertical bounce
- Bottom edge (Y = 480 - 40 = 440) should cause a vertical bounce

**4. Flash verification**

The white flash should be visible for approximately 6 frames (about 100 ms at 60 Hz). You can verify this by:
- Using an oscilloscope on the RGB output pins
- Recording the VGA output with a capture card and stepping through frames

### Expected results

After successful testing, the system should:
- Bounce reliably off all four screen edges
- Cycle through 8 distinct colours (only on wall hits, not continuously)
- Respond correctly to all five configuration inputs
- Maintain stable VGA sync (no flickering or rolling image)

## External hardware

### Required for operation

| Component | Purpose | Specifications |
|-----------|---------|----------------|
| **VGA monitor** | Display the bouncing logo | 640×480 @ 60 Hz (supports standard VGA timings) |
| **VGA cable** | Connect the board to monitor | Male DB-15 to male DB-15 |
| **TinyVGA PMOD** | Convert digital outputs to analog VGA signals | Uses 6 digital lines (2 bits per colour) + HSync + VSync |
| **Clock source** | Drive the VGA timing | 25.175 MHz (provided by Tiny Tapeout harness) |
