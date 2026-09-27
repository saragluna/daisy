#!/usr/bin/env python3
"""
Process user-provided icon and generate all macOS icon sizes
"""

from PIL import Image
import argparse
import os

def create_iconset(source_path, output_dir):
    """Create all required macOS icon sizes from source image"""

    # Load source image
    img = Image.open(source_path)
    print(f"Source image: {img.size[0]}x{img.size[1]}")

    # The image is 1408x768, need to extract the square icon from center
    # Looking at the image, the icon appears to be centered
    width, height = img.size

    # Calculate crop box to get square centered on the icon
    # The icon appears to be roughly in the center, height is limiting factor
    icon_size = min(width, height)

    # Center crop
    left = (width - icon_size) // 2
    top = (height - icon_size) // 2
    right = left + icon_size
    bottom = top + icon_size

    # Crop to square
    icon = img.crop((left, top, right, bottom))
    print(f"Cropped to: {icon.size[0]}x{icon.size[1]}")

    # Now we need to find the actual icon within this crop
    # The icon has a shadow and padding, let's detect the content bounds
    # For now, let's resize to 1024 and use as-is since it looks good

    # Resize to 1024x1024 (macOS base icon size)
    icon_1024 = icon.resize((1024, 1024), Image.Resampling.LANCZOS)

    # Generate all sizes
    sizes = [
        (16, 'icon_16x16.png'),
        (32, 'icon_16x16@2x.png'),
        (32, 'icon_32x32.png'),
        (64, 'icon_32x32@2x.png'),
        (128, 'icon_128x128.png'),
        (256, 'icon_128x128@2x.png'),
        (256, 'icon_256x256.png'),
        (512, 'icon_256x256@2x.png'),
        (512, 'icon_512x512.png'),
        (1024, 'icon_512x512@2x.png'),
    ]

    iconset_dir = os.path.join(output_dir, 'AppIcon.iconset')
    os.makedirs(iconset_dir, exist_ok=True)

    for size, filename in sizes:
        resized = icon_1024.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))
        print(f'Generated: {filename}')

    # Save 1024 as main icon
    icon_1024.save(os.path.join(output_dir, 'AppIcon.png'))
    print('Generated: AppIcon.png (1024x1024)')

    return iconset_dir

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate a macOS iconset from a source image.')
    parser.add_argument('source', help='Path to the source image')
    parser.add_argument(
        '--output-dir',
        default=os.path.dirname(os.path.abspath(__file__)),
        help='Directory that will receive AppIcon.png and AppIcon.iconset',
    )
    args = parser.parse_args()
    source = os.path.abspath(args.source)
    output_dir = os.path.abspath(args.output_dir)

    print("Processing user-provided icon...")
    print()

    # Remove old iconset
    import shutil
    iconset_path = os.path.join(output_dir, 'AppIcon.iconset')
    if os.path.exists(iconset_path):
        shutil.rmtree(iconset_path)

    create_iconset(source, output_dir)

    print()
    print("Done! Now run iconutil to create .icns")
