# Art and Assets

This folder contains the source files used to generate `src/bitmap_rom.v`:

- `generate_rom128x40.py` - Python script that converts an image to Verilog ROM format (designed for Google Colab)
- `128x40_image.png` - Original UACJ IIT logo image (128x40 pixels)

## How to regenerate the bitmap ROM

### Using Google Colab (recommended)

The Python script is designed to run in Google Colab:

1. Open [Google Colab](https://colab.research.google.com/)
2. Create a new notebook
3. Copy and paste the `generate_rom128x40.py` code into a code cell
4. Run the cell
5. Upload your 128x40 image when prompted
6. Download the generated `bitmap_rom.v` file
7. Replace the existing file in `src/bitmap_rom.v`

### Requirements

The script requires the following Python libraries (pre-installed in Google Colab):
- `PIL` (Pillow)
- `numpy`
- `matplotlib`

### Image specifications

| Parameter | Value |
|-----------|-------|
| Width | 128 pixels |
| Height | 40 pixels |
| Format | PNG (preferred) or JPG |
| Transparency | Supported (alpha channel) |
| Color | Converted to grayscale automatically |

### How the conversion works

The script converts each pixel to a 1-bit value:
- **Pixel drawn (1)** = opaque AND dark (alpha > 128 AND grayscale < 128)
- **Pixel not drawn (0)** = transparent OR light

The output is organized as 40 rows x 16 bytes (128 bits per row), with LSB representing the leftmost pixel in each byte.

## Notes

- The `bitmap_rom.v` file in `src/` was generated using this script
- The script is specifically designed for Google Colab (uses `google.colab` file upload/download)
- To run locally, remove the `from google.colab import files` line and replace with local file handling
