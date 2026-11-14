#!/usr/bin/env python3
"""
Create app icon: white ཨ on blue background
Generates single 1024x1024 icon for iOS (Xcode auto-generates sizes)
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Blue background color (Apple system blue)
BLUE = (0, 122, 255)
WHITE = (255, 255, 255)

def create_icon(size: int, output_path: str):
    """Create icon at the specified size."""
    # Create image with blue background
    img = Image.new('RGB', (size, size), BLUE)
    draw = ImageDraw.Draw(img)

    # Calculate font size (about 65% of icon size)
    font_size = int(size * 0.65)

    # Try to use a system font that supports Tibetan
    font = None
    tibetan_fonts = [
        '/System/Library/Fonts/Supplemental/Kailasa.ttc',
        '/Library/Fonts/Kailasa.ttc',
        '/System/Library/Fonts/Kokonor.ttf',
    ]

    for font_path in tibetan_fonts:
        if os.path.exists(font_path):
            try:
                font = ImageFont.truetype(font_path, font_size)
                break
            except:
                continue

    if font is None:
        font = ImageFont.load_default()

    # Tibetan letter "A" (ཨ)
    text = "ཨ"

    # Get text bounding box for centering
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # Center the text
    x = (size - text_width) // 2 - bbox[0]
    y = (size - text_height) // 2 - bbox[1]

    # Draw the white ཨ
    draw.text((x, y), text, font=font, fill=WHITE)

    # Save
    img.save(output_path, 'PNG')
    print(f"Created: {output_path} ({size}x{size})")

def main():
    # Output directory
    output_dir = os.path.join(
        os.path.dirname(os.path.dirname(__file__)),
        'LotsawaKeyboard', 'LotsawaKeyboard', 'Assets.xcassets', 'AppIcon.appiconset'
    )
    os.makedirs(output_dir, exist_ok=True)

    # Generate 1024x1024 icon
    create_icon(1024, os.path.join(output_dir, 'AppIcon.png'))
    print(f"\nApp icon generated in: {output_dir}")

if __name__ == '__main__':
    main()
