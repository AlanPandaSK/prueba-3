# @title Generate Bitmap ROM for 128x40
from google.colab import files
from PIL import Image
import numpy as np
import matplotlib.pyplot as plt

def convert_to_bitmap_rom_128x40(image_path, output_name="bitmap_rom"):
    """
    Converts a 128x40 image to bitmap_rom format
    """

    # Open image
    img = Image.open(image_path)

    # Convert to RGBA if it has transparency
    if img.mode == 'RGBA':
        img_rgb = img.convert('RGB')
        img_alpha = img.split()[3]
    else:
        img_rgb = img.convert('RGB')
        # If no transparency, create fully opaque alpha channel
        img_alpha = Image.new('L', img.size, 255)

    # Check size
    if img.size != (128, 40):
        print(f"⚠️ Image is {img.size[0]}x{img.size[1]}, resizing to 128x40...")
        img_rgb = img_rgb.resize((128, 40), Image.Resampling.LANCZOS)
        img_alpha = img_alpha.resize((128, 40), Image.Resampling.LANCZOS)

    # Convert to grayscale
    img_gray = img_rgb.convert('L')

    # Show preview
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))
    axes[0].imshow(img_rgb)
    axes[0].set_title('Original Image')
    axes[0].axis('off')

    axes[1].imshow(img_alpha, cmap='gray')
    axes[1].set_title('Alpha Channel\n(White=opaque)')
    axes[1].axis('off')

    axes[2].imshow(img_gray, cmap='gray')
    axes[2].set_title('Grayscale')
    axes[2].axis('off')
    plt.show()

    # Generate Verilog file
    output_file = f"{output_name}.v"

    with open(output_file, 'w') as f:
        f.write("module bitmap_rom (\n")
        f.write("    input wire [6:0] x,  // 7 bits for 128 pixels\n")
        f.write("    input wire [5:0] y,  // 6 bits for 40 pixels\n")
        f.write("    output wire pixel\n")
        f.write(");\n\n")
        f.write("  // 40 rows * 16 bytes = 640 bytes\n")
        f.write("  reg [7:0] mem[639:0];\n")
        f.write("  initial begin\n")

        # Generate data (40 rows, 16 bytes per row)
        bytes_per_row = 16  # 128/8 = 16
        total_pixels_drawn = 0

        for y in range(40):
            for byte_idx in range(bytes_per_row):
                byte_val = 0
                for bit in range(8):
                    x_pos = byte_idx * 8 + bit

                    if x_pos < 128:
                        # Get pixel values
                        gray_val = img_gray.getpixel((x_pos, y))
                        alpha_val = img_alpha.getpixel((x_pos, y))

                        # Decision: draw if opaque AND dark
                        draw = (alpha_val > 128) and (gray_val < 128)

                        if draw:
                            byte_val |= (1 << bit)  # LSB first
                            total_pixels_drawn += 1

                addr = y * bytes_per_row + byte_idx
                f.write(f"    mem[{addr}] = 8'h{byte_val:02x};\n")

        f.write("  end\n\n")
        f.write("  // Addressing: 6 bits Y + 4 bits X (16 groups)\n")
        f.write("  wire [9:0] addr = {y[5:0], x[6:3]};\n")
        f.write("  assign pixel = mem[addr][x&7];\n\n")
        f.write("endmodule\n")

    print(f"\n✅ File generated: {output_file}")
    print(f"\n📊 Statistics:")
    print(f"   - Dimensions: 128x40 pixels")
    print(f"   - Bytes per row: {bytes_per_row}")
    print(f"   - Total bytes: {40 * bytes_per_row}")
    print(f"   - Pixels drawn: {total_pixels_drawn}/{128*40} ({total_pixels_drawn*100/(128*40):.1f}%)")

    return output_file

# Upload image (should be 128x40)
print("📤 Upload your 128x40 image:")
print("   (can be PNG with transparency or JPG)")

uploaded = files.upload()

if uploaded:
    filename = list(uploaded.keys())[0]
    print(f"\n📸 Processing: {filename}")

    # Generate ROM
    output_file = convert_to_bitmap_rom_128x40(filename)

    # Download
    files.download(output_file)
    print("\n🎉 Done! The bitmap_rom.v file has been downloaded")
