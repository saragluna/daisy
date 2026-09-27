#!/usr/bin/env python3
"""
Generate macOS app icon for Copilot API Manager
Design: Yellow daisy on white background
Following macOS icon sizing guidelines (icon content within ~80% of canvas)
"""

import math
from PIL import Image, ImageDraw, ImageFilter
import os

# Canvas size (1024x1024 for macOS app icon)
SIZE = 1024
CENTER = SIZE // 2

# macOS icons have content within ~80% of the canvas, with rounded rect mask
CONTENT_INSET = int(SIZE * 0.10)  # 10% inset on each side
CONTENT_SIZE = SIZE - (CONTENT_INSET * 2)

def create_rounded_square_mask(size, radius):
    """Create a rounded square mask for macOS icon shape"""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=radius,
        fill=255
    )
    return mask

def draw_petal(draw, center_x, center_y, angle, length, width, color):
    """Draw a single petal as an ellipse rotated around center"""
    # Calculate petal center position
    rad = math.radians(angle)
    petal_center_x = center_x + (length * 0.5) * math.cos(rad)
    petal_center_y = center_y + (length * 0.5) * math.sin(rad)

    # Draw ellipse (we'll use polygon for rotation)
    points = []
    for i in range(36):
        t = (i / 36) * 2 * math.pi
        # Ellipse point
        x = (length / 2) * math.cos(t)
        y = (width / 2) * math.sin(t)
        # Rotate
        rx = x * math.cos(rad) - y * math.sin(rad)
        ry = x * math.sin(rad) + y * math.cos(rad)
        # Translate
        points.append((center_x + rx + (length * 0.45) * math.cos(rad),
                       center_y + ry + (length * 0.45) * math.sin(rad)))

    draw.polygon(points, fill=color)

def create_daisy_icon():
    """Create the daisy icon"""

    # Create base with white background
    icon = Image.new('RGBA', (SIZE, SIZE), (255, 255, 255, 255))
    draw = ImageDraw.Draw(icon)

    # Daisy parameters - sized to fit within the icon guidelines
    daisy_center_x = CENTER
    daisy_center_y = CENTER + 20  # Slightly lower for visual balance

    # Petal parameters
    num_petals = 16
    petal_length = 260
    petal_width = 85

    # Petal colors - gradient from golden yellow to warm yellow
    petal_color_base = (255, 210, 50)  # Warm golden yellow
    petal_color_tip = (255, 235, 100)  # Lighter yellow

    # Draw petals in layers for depth
    # Back layer (slightly darker/muted)
    for i in range(num_petals):
        angle = (360 / num_petals) * i + (180 / num_petals)  # Offset layer
        # Slightly muted yellow for back petals
        back_color = (245, 200, 45)
        draw_petal(draw, daisy_center_x, daisy_center_y, angle,
                   petal_length * 0.95, petal_width * 0.9, back_color)

    # Front layer (brighter)
    for i in range(num_petals):
        angle = (360 / num_petals) * i
        draw_petal(draw, daisy_center_x, daisy_center_y, angle,
                   petal_length, petal_width, petal_color_base)

    # Add petal highlights (lighter streaks)
    highlight_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight_layer)

    for i in range(num_petals):
        angle = (360 / num_petals) * i
        # Draw thin highlight line on each petal
        rad = math.radians(angle)
        start_dist = 80
        end_dist = petal_length * 0.85
        x1 = daisy_center_x + start_dist * math.cos(rad)
        y1 = daisy_center_y + start_dist * math.sin(rad)
        x2 = daisy_center_x + end_dist * math.cos(rad)
        y2 = daisy_center_y + end_dist * math.sin(rad)
        highlight_draw.line([(x1, y1), (x2, y2)], fill=(255, 245, 150, 180), width=12)

    # Blur highlights
    highlight_layer = highlight_layer.filter(ImageFilter.GaussianBlur(radius=8))
    icon = Image.alpha_composite(icon, highlight_layer)
    draw = ImageDraw.Draw(icon)

    # Center disc (brown/orange like real daisy)
    disc_radius = 95

    # Outer ring - darker brown
    draw.ellipse(
        [daisy_center_x - disc_radius - 5, daisy_center_y - disc_radius - 5,
         daisy_center_x + disc_radius + 5, daisy_center_y + disc_radius + 5],
        fill=(139, 90, 43)  # Darker brown border
    )

    # Main disc - warm brown/orange gradient effect
    for r in range(disc_radius, 0, -1):
        progress = r / disc_radius
        # Gradient from darker edge to lighter center
        red = int(160 + (200 - 160) * (1 - progress))
        green = int(82 + (130 - 82) * (1 - progress))
        blue = int(45 + (60 - 45) * (1 - progress))
        draw.ellipse(
            [daisy_center_x - r, daisy_center_y - r,
             daisy_center_x + r, daisy_center_y + r],
            fill=(red, green, blue)
        )

    # Add texture dots to center disc (like real daisy)
    import random
    random.seed(42)  # Consistent pattern
    for _ in range(200):
        # Random position within disc
        angle = random.uniform(0, 2 * math.pi)
        dist = random.uniform(0, disc_radius - 10)
        x = daisy_center_x + dist * math.cos(angle)
        y = daisy_center_y + dist * math.sin(angle)

        # Vary dot properties based on distance from center
        dot_size = random.uniform(2, 5)
        brightness = random.randint(80, 140)
        dot_color = (brightness + 60, brightness + 20, brightness - 20)

        draw.ellipse(
            [x - dot_size, y - dot_size, x + dot_size, y + dot_size],
            fill=dot_color
        )

    # Center highlight
    highlight_radius = 30
    highlight_x = daisy_center_x - 25
    highlight_y = daisy_center_y - 25
    for r in range(highlight_radius, 0, -1):
        alpha = int(60 * (1 - r / highlight_radius))
        draw.ellipse(
            [highlight_x - r, highlight_y - r, highlight_x + r, highlight_y + r],
            fill=(255, 220, 180, alpha)
        )

    # === APPLY ROUNDED SQUARE MASK (macOS icon shape) ===
    # macOS Big Sur+ uses ~22% corner radius (smooth corners / squircle)
    corner_radius = int(SIZE * 0.22)
    mask = create_rounded_square_mask(SIZE, corner_radius)

    # Create final icon with rounded corners
    final_icon = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    final_icon.paste(icon, (0, 0), mask)

    # Add subtle shadow/edge for depth (like other macOS icons)
    edge = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    edge_draw = ImageDraw.Draw(edge)
    # Inner shadow at top
    edge_draw.rounded_rectangle(
        [1, 1, SIZE - 2, SIZE - 2],
        radius=corner_radius,
        outline=(255, 255, 255, 100),
        width=2
    )
    # Subtle outer edge
    edge_draw.rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1],
        radius=corner_radius,
        outline=(0, 0, 0, 25),
        width=1
    )
    final_icon = Image.alpha_composite(final_icon, edge)

    return final_icon

def generate_all_sizes(base_icon, output_dir):
    """Generate all required macOS icon sizes"""
    sizes = [
        (16, '16x16'),
        (32, '16x16@2x'),
        (32, '32x32'),
        (64, '32x32@2x'),
        (128, '128x128'),
        (256, '128x128@2x'),
        (256, '256x256'),
        (512, '256x256@2x'),
        (512, '512x512'),
        (1024, '512x512@2x'),
    ]

    iconset_dir = os.path.join(output_dir, 'AppIcon.iconset')
    os.makedirs(iconset_dir, exist_ok=True)

    for size, name in sizes:
        resized = base_icon.resize((size, size), Image.Resampling.LANCZOS)
        filename = f'icon_{name}.png'
        resized.save(os.path.join(iconset_dir, filename))
        print(f'Generated: {filename}')

    # Also save the full 1024 as the main icon
    base_icon.save(os.path.join(output_dir, 'AppIcon.png'))
    print('Generated: AppIcon.png (1024x1024)')

if __name__ == '__main__':
    print("Generating Copilot API Manager icon...")
    print("Design: Yellow Daisy on White Background")
    print()

    icon = create_daisy_icon()

    output_dir = os.path.dirname(os.path.abspath(__file__))

    # Generate all sizes
    generate_all_sizes(icon, output_dir)

    # Generate .icns file
    iconset_dir = os.path.join(output_dir, 'AppIcon.iconset')
    icns_path = os.path.join(output_dir, 'AppIcon.icns')

    print()
    print("Now run: iconutil -c icns AppIcon.iconset -o AppIcon.icns")
    print()
    print("Icon generation complete!")
    print(f"Output directory: {output_dir}")
